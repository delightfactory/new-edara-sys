-- Work Management — Workflow Engine runtime activation and reconciliation.
SET lock_timeout='5s';
SET statement_timeout='60s';

CREATE OR REPLACE FUNCTION private.work_append_system_event(
  p_work_item_id UUID,
  p_event_type TEXT,
  p_from_status public.work_item_status DEFAULT NULL,
  p_to_status public.work_item_status DEFAULT NULL,
  p_payload JSONB DEFAULT '{}'::JSONB
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE v_id UUID;
BEGIN
  INSERT INTO public.work_events(
    work_item_id,event_type,actor_user_id,actor_kind,from_status,to_status,payload,created_at
  ) VALUES (
    p_work_item_id,p_event_type,NULL,'system',p_from_status,p_to_status,COALESCE(p_payload,'{}'::JSONB),clock_timestamp()
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION private.work_workflow_context_value(
  p_run_id UUID,
  p_path TEXT
) RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_run public.work_workflow_runs%ROWTYPE;
  v_step_key TEXT;
  v_output JSONB;
  v_tail TEXT;
BEGIN
  SELECT * INTO v_run FROM public.work_workflow_runs WHERE id=p_run_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF p_path='input' THEN RETURN v_run.input_data; END IF;
  IF p_path LIKE 'input.%' THEN
    RETURN v_run.input_data #> string_to_array(substr(p_path,7),'.');
  END IF;
  IF p_path LIKE 'steps.%.output%' THEN
    v_step_key:=split_part(p_path,'.',2);
    SELECT si.output_data INTO v_output FROM public.work_workflow_step_instances si
    WHERE si.workflow_run_id=p_run_id AND si.step_key=v_step_key;
    IF NOT FOUND THEN RETURN NULL; END IF;
    IF p_path='steps.'||v_step_key||'.output' THEN RETURN v_output; END IF;
    v_tail:=substr(p_path,length('steps.'||v_step_key||'.output.')+1);
    RETURN v_output #> string_to_array(v_tail,'.');
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION private.work_evaluate_workflow_condition(
  p_run_id UUID,
  p_condition JSONB
) RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_op TEXT:=p_condition->>'op';
  v_value JSONB;
  v_child JSONB;
  v_match BOOLEAN;
BEGIN
  IF NOT private.work_validate_workflow_condition_dsl(p_condition) THEN RETURN false; END IF;
  IF v_op='always' THEN RETURN true; END IF;
  IF v_op='exists' THEN
    v_value:=private.work_workflow_context_value(p_run_id,p_condition->>'path');
    RETURN v_value IS NOT NULL AND v_value<>'null'::JSONB;
  END IF;
  IF v_op IN ('eq','ne','in') THEN
    v_value:=private.work_workflow_context_value(p_run_id,p_condition->>'path');
    IF v_op='eq' THEN RETURN v_value=p_condition->'value'; END IF;
    IF v_op='ne' THEN RETURN v_value IS DISTINCT FROM p_condition->'value'; END IF;
    RETURN EXISTS(SELECT 1 FROM jsonb_array_elements(p_condition->'values') e WHERE e=v_value);
  END IF;
  IF v_op='not' THEN RETURN NOT private.work_evaluate_workflow_condition(p_run_id,p_condition->'condition'); END IF;
  IF v_op='all' THEN
    FOR v_child IN SELECT value FROM jsonb_array_elements(p_condition->'conditions') LOOP
      IF NOT private.work_evaluate_workflow_condition(p_run_id,v_child) THEN RETURN false; END IF;
    END LOOP;
    RETURN true;
  END IF;
  IF v_op='any' THEN
    v_match:=false;
    FOR v_child IN SELECT value FROM jsonb_array_elements(p_condition->'conditions') LOOP
      IF private.work_evaluate_workflow_condition(p_run_id,v_child) THEN v_match:=true; EXIT; END IF;
    END LOOP;
    RETURN v_match;
  END IF;
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION private.work_resolve_workflow_actor(
  p_run_id UUID,
  p_config JSONB,
  p_prefix TEXT
) RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_run public.work_workflow_runs%ROWTYPE;
  v_selector TEXT;
  v_user UUID;
BEGIN
  SELECT * INTO v_run FROM public.work_workflow_runs WHERE id=p_run_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  v_selector:=COALESCE(NULLIF(p_config->>(p_prefix||'_selector'),''),'starter');
  CASE v_selector
    WHEN 'starter' THEN v_user:=v_run.started_by_user_id;
    WHEN 'parent_owner' THEN SELECT accountable_owner_user_id INTO v_user FROM public.work_items WHERE id=v_run.parent_work_item_id;
    WHEN 'parent_assignee' THEN SELECT current_assignee_user_id INTO v_user FROM public.work_items WHERE id=v_run.parent_work_item_id;
    WHEN 'user' THEN BEGIN v_user:=(p_config->>(p_prefix||'_user_id'))::UUID; EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
    ELSE RETURN NULL;
  END CASE;
  IF NOT private.work_actor_is_active(v_user) THEN RETURN NULL; END IF;
  RETURN v_user;
END;
$$;

CREATE OR REPLACE FUNCTION private.work_activate_workflow_step(p_step_instance_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_instance public.work_workflow_step_instances%ROWTYPE;
  v_run public.work_workflow_runs%ROWTYPE;
  v_def public.work_workflow_step_definitions%ROWTYPE;
  v_owner UUID;
  v_assignee UUID;
  v_branch UUID;
  v_department UUID;
  v_due_minutes INTEGER;
  v_due_at TIMESTAMPTZ;
  v_priority public.work_priority;
  v_visibility public.work_visibility;
  v_completion_mode public.work_completion_mode;
  v_work public.work_items%ROWTYPE;
  v_approval_request UUID;
  v_approval_due TIMESTAMPTZ;
  v_requester UUID;
BEGIN
  SELECT * INTO v_instance FROM public.work_workflow_step_instances WHERE id=p_step_instance_id FOR UPDATE;
  IF NOT FOUND OR v_instance.status<>'pending' THEN RETURN false; END IF;
  SELECT * INTO v_run FROM public.work_workflow_runs WHERE id=v_instance.workflow_run_id FOR UPDATE;
  IF v_run.status<>'running' THEN RETURN false; END IF;
  SELECT * INTO v_def FROM public.work_workflow_step_definitions WHERE id=v_instance.step_definition_id;

  IF EXISTS (
    SELECT 1
    FROM public.work_workflow_step_dependencies d
    JOIN public.work_workflow_step_definitions pred ON pred.id=d.predecessor_step_id
    JOIN public.work_workflow_step_instances pi ON pi.workflow_run_id=v_run.id AND pi.step_key=pred.step_key
    WHERE d.successor_step_id=v_def.id AND pi.status NOT IN ('completed','skipped')
  ) THEN RETURN false; END IF;

  IF NOT private.work_evaluate_workflow_condition(v_run.id,v_def.condition_dsl) THEN
    UPDATE public.work_workflow_step_instances
    SET status='skipped',completed_at=clock_timestamp(),state_version=state_version+1
    WHERE id=v_instance.id;
    RETURN true;
  END IF;

  v_owner:=private.work_resolve_workflow_actor(v_run.id,v_def.task_config,'owner');
  IF v_owner IS NULL THEN v_owner:=v_run.started_by_user_id; END IF;
  IF NOT private.work_actor_is_active(v_owner) THEN RAISE EXCEPTION 'workflow step owner could not be resolved'; END IF;
  v_requester:=COALESCE(v_run.started_by_user_id,v_owner);

  IF v_def.step_kind='task' THEN
    v_assignee:=private.work_resolve_workflow_actor(v_run.id,v_def.task_config,'assignee');
    IF v_assignee IS NULL THEN v_assignee:=v_owner; END IF;
    IF NOT private.work_actor_is_active(v_assignee) THEN RAISE EXCEPTION 'workflow step assignee could not be resolved'; END IF;
    SELECT e.branch_id,e.department_id INTO v_branch,v_department
    FROM public.hr_employees e WHERE e.user_id=v_assignee AND e.status::TEXT='active' LIMIT 1;
    BEGIN
      v_due_minutes:=NULLIF(v_def.task_config->>'due_minutes','')::INTEGER;
      v_priority:=COALESCE(NULLIF(v_def.task_config->>'priority','')::public.work_priority,'normal');
      v_visibility:=COALESCE(NULLIF(v_def.task_config->>'visibility','')::public.work_visibility,'standard');
      v_completion_mode:=COALESCE(NULLIF(v_def.task_config->>'completion_mode','')::public.work_completion_mode,'assignee_closes');
    EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'invalid workflow task runtime configuration'; END;
    IF v_due_minutes IS NOT NULL AND v_due_minutes<=0 THEN RAISE EXCEPTION 'workflow due_minutes must be positive'; END IF;
    v_due_at:=CASE WHEN v_due_minutes IS NULL THEN NULL ELSE clock_timestamp()+make_interval(mins=>v_due_minutes) END;

    INSERT INTO public.work_items(
      kind,source_kind,source_key,title,description,expected_outcome,status,priority,visibility,
      creator_user_id,requester_user_id,accountable_owner_user_id,current_assignee_user_id,
      owning_department_id,branch_id,workflow_run_id,workflow_step_key,
      activated_at,assigned_at,due_at,first_due_at,next_action_text,next_action_at,
      completion_mode,completion_approval_template_id,last_meaningful_activity_at,state_version
    ) VALUES (
      'workflow_step','workflow','workflow:'||v_run.id::TEXT||':'||v_def.step_key,
      v_def.name,v_def.task_config->>'description',v_def.task_config->>'expected_outcome','open',v_priority,v_visibility,
      v_requester,v_requester,v_owner,v_assignee,v_department,v_branch,v_run.id,v_def.step_key,
      clock_timestamp(),clock_timestamp(),v_due_at,v_due_at,
      COALESCE(NULLIF(v_def.task_config->>'next_action_text',''),v_def.name),NULL,
      v_completion_mode,
      CASE WHEN v_completion_mode='approval' THEN NULLIF(v_def.task_config->>'completion_approval_template_id','')::UUID ELSE NULL END,
      clock_timestamp(),1
    ) RETURNING * INTO v_work;

    UPDATE public.work_workflow_step_instances
    SET status='active',work_item_id=v_work.id,activated_at=clock_timestamp(),state_version=state_version+1
    WHERE id=v_instance.id;
    PERFORM private.work_append_system_event(v_work.id,'work.workflow_step.activated',NULL,'open',jsonb_build_object('workflow_run_id',v_run.id,'step_key',v_def.step_key));
  ELSE
    INSERT INTO public.work_items(
      kind,source_kind,source_key,title,expected_outcome,status,priority,visibility,
      creator_user_id,requester_user_id,accountable_owner_user_id,current_assignee_user_id,
      workflow_run_id,workflow_step_key,activated_at,next_action_text,last_meaning_activity_at,state_version
    ) VALUES (
      'workflow_step','workflow','workflow:'||v_run.id::TEXT||':'||v_def.step_key,
      v_def.name,'اتخاذ قرار اعتماد موثق للمرحلة','pending_approval','normal','standard',
      v_requester,v_requester,v_owner,NULL,v_run.id,v_def.step_key,clock_timestamp(),'اتخاذ قرار الاعتماد',clock_timestamp(),1
    ) RETURNING * INTO v_work;

    v_approval_request:=private.work_start_approval_request(
      v_work.id,v_def.approval_template_id,'workflow_step',
      jsonb_build_object('workflow_run_id',v_run.id,'workflow_step_instance_id',v_instance.id,'step_key',v_def.step_key),
      v_requester,NULL
    );
    SELECT s.due_at INTO v_approval_due
    FROM public.work_approval_stage_instances s
    WHERE s.approval_request_id=v_approval_request AND s.status='pending'
    ORDER BY s.stage_order LIMIT 1;
    UPDATE public.work_items SET next_action_at=v_approval_due WHERE id=v_work.id;
    UPDATE public.work_workflow_step_instances
    SET status='active',work_item_id=v_work.id,approval_request_id=v_approval_request,
        activated_at=clock_timestamp(),state_version=state_version+1
    WHERE id=v_instance.id;
    PERFORM private.work_append_system_event(v_work.id,'work.workflow_approval_step.activated',NULL,'pending_approval',jsonb_build_object('workflow_run_id',v_run.id,'step_key',v_def.step_key,'approval_request_id',v_approval_request));
  END IF;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION private.work_advance_workflow_run(p_run_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_run public.work_workflow_runs%ROWTYPE;
  v_instance public.work_workflow_step_instances%ROWTYPE;
  v_def public.work_workflow_step_definitions%ROWTYPE;
  v_work public.work_items%ROWTYPE;
  v_approval public.work_approval_requests%ROWTYPE;
  v_validation JSONB;
  v_changed BOOLEAN:=false;
  v_activated BOOLEAN;
  v_output JSONB;
BEGIN
  SELECT * INTO v_run FROM public.work_workflow_runs WHERE id=p_run_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','not_found'); END IF;
  IF v_run.status<>'running' THEN RETURN jsonb_build_object('status',v_run.status,'state_version',v_run.state_version); END IF;

  FOR v_instance IN
    SELECT * FROM public.work_workflow_step_instances WHERE workflow_run_id=p_run_id AND status='active' ORDER BY id FOR UPDATE
  LOOP
    SELECT * INTO v_def FROM public.work_workflow_step_definitions WHERE id=v_instance.step_definition_id;
    IF v_def.step_kind='task' THEN
      SELECT * INTO v_work FROM public.work_items WHERE id=v_instance.work_item_id;
      IF v_work.status='done' THEN
        v_validation:=private.work_validate_intake_payload(v_def.output_schema,COALESCE(v_work.completion_output,'{}'::JSONB));
        IF NOT COALESCE((v_validation->>'ok')::BOOLEAN,false) THEN
          UPDATE public.work_workflow_step_instances
          SET status='failed',failure_reason='structured output contract failed',state_version=state_version+1
          WHERE id=v_instance.id;
          UPDATE public.work_workflow_runs SET status='failed',completed_at=clock_timestamp(),state_version=state_version+1 WHERE id=p_run_id RETURNING * INTO v_run;
          RETURN jsonb_build_object('status','failed','state_version',v_run.state_version,'failed_step_key',v_instance.step_key,'reason','structured_output_invalid');
        END IF;
        UPDATE public.work_workflow_step_instances
        SET status='completed',output_data=COALESCE(v_work.completion_output,'{}'::JSONB),completed_at=clock_timestamp(),state_version=state_version+1
        WHERE id=v_instance.id;
        v_changed:=true;
      ELSIF v_work.status='cancelled' THEN
        UPDATE public.work_workflow_step_instances SET status='failed',failure_reason='linked work item cancelled',state_version=state_version+1 WHERE id=v_instance.id;
        UPDATE public.work_workflow_runs SET status='failed',completed_at=clock_timestamp(),state_version=state_version+1 WHERE id=p_run_id RETURNING * INTO v_run;
        RETURN jsonb_build_object('status','failed','state_version',v_run.state_version,'failed_step_key',v_instance.step_key,'reason','work_item_cancelled');
      END IF;
    ELSE
      SELECT * INTO v_approval FROM public.work_approval_requests WHERE id=v_instance.approval_request_id;
      IF v_approval.status IN ('approved','rejected','changes_required','cancelled') THEN
        v_output:=jsonb_build_object('decision',v_approval.status,'approval_request_id',v_approval.id);
        UPDATE public.work_workflow_step_instances
        SET status='completed',output_data=v_output,completed_at=clock_timestamp(),state_version=state_version+1
        WHERE id=v_instance.id;
        UPDATE public.work_items
        SET status='done',completion_summary='اكتمل قرار الاعتماد: '||v_approval.status::TEXT,
            completion_output=v_output,completed_at=clock_timestamp(),next_action_text=NULL,next_action_at=NULL,
            state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
        WHERE id=v_instance.work_item_id AND status='pending_approval';
        PERFORM private.work_append_system_event(v_instance.work_item_id,'work.workflow_approval_step.completed','pending_approval','done',v_output);
        v_changed:=true;
      END IF;
    END IF;
  END LOOP;

  LOOP
    v_activated:=false;
    FOR v_instance IN
      SELECT si.*
      FROM public.work_workflow_step_instances si
      JOIN public.work_workflow_step_definitions sd ON sd.id=si.step_definition_id
      WHERE si.workflow_run_id=p_run_id AND si.status='pending'
        AND NOT EXISTS (
          SELECT 1
          FROM public.work_workflow_step_dependencies d
          JOIN public.work_workflow_step_definitions pred ON pred.id=d.predecessor_step_id
          JOIN public.work_workflow_step_instances pi ON pi.workflow_run_id=p_run_id AND pi.step_key=pred.step_key
          WHERE d.successor_step_id=sd.id AND pi.status NOT IN ('completed','skipped')
        )
      ORDER BY sd.sort_order,sd.step_key
    LOOP
      IF private.work_activate_workflow_step(v_instance.id) THEN
        v_activated:=true; v_changed:=true;
      END IF;
    END LOOP;
    EXIT WHEN NOT v_activated OR NOT EXISTS(
      SELECT 1 FROM public.work_workflow_step_instances WHERE workflow_run_id=p_run_id AND status='pending'
    );
    -- Iterate only to allow chains of conditionally skipped steps to collapse immediately.
    EXIT WHEN EXISTS(
      SELECT 1 FROM public.work_workflow_step_instances WHERE workflow_run_id=p_run_id AND status='active'
    );
  END LOOP;

  IF NOT EXISTS(
    SELECT 1 FROM public.work_workflow_step_instances WHERE workflow_run_id=p_run_id AND status IN ('pending','active')
  ) THEN
    SELECT COALESCE(jsonb_object_agg(step_key,output_data),'{}'::JSONB) INTO v_output
    FROM public.work_workflow_step_instances WHERE workflow_run_id=p_run_id;
    UPDATE public.work_workflow_runs
    SET status='completed',output_data=COALESCE(v_output,'{}'::JSONB),completed_at=clock_timestamp(),state_version=state_version+1
    WHERE id=p_run_id RETURNING * INTO v_run;
  ELSIF v_changed THEN
    UPDATE public.work_workflow_runs SET state_version=state_version+1 WHERE id=p_run_id RETURNING * INTO v_run;
  ELSE
    SELECT * INTO v_run FROM public.work_workflow_runs WHERE id=p_run_id;
  END IF;

  RETURN jsonb_build_object('status',v_run.status,'state_version',v_run.state_version,'output_data',v_run.output_data);
END;
$$;

CREATE OR REPLACE FUNCTION public.work_start_workflow(
  p_operation_id UUID,
  p_template_id UUID,
  p_input_data JSONB DEFAULT '{}'::JSONB,
  p_parent_work_item_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid(); v_prepare JSONB; v_template public.work_workflow_templates%ROWTYPE;
  v_version public.work_workflow_template_versions%ROWTYPE; v_run public.work_workflow_runs%ROWTYPE; v_advance JSONB; v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(p_operation_id,v_actor,'work_start_workflow',jsonb_build_object('template_id',p_template_id,'input_data',COALESCE(p_input_data,'{}'::JSONB),'parent_work_item_id',p_parent_work_item_id),p_parent_work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  IF NOT COALESCE(public.check_permission(v_actor,'work.items.create'),false) THEN RETURN private.work_command_error(p_operation_id,'work_start_workflow','FORBIDDEN','لا تملك صلاحية بدء مسار عمل',p_parent_work_item_id); END IF;
  IF jsonb_typeof(COALESCE(p_input_data,'{}'::JSONB))<>'object' THEN RETURN private.work_command_error(p_operation_id,'work_start_workflow','INVALID_INPUT','مدخلات مسار العمل يجب أن تكون كائن بيانات',p_parent_work_item_id); END IF;
  IF p_parent_work_item_id IS NOT NULL AND NOT private.work_actor_can_update_item(v_actor,p_parent_work_item_id) THEN RETURN private.work_command_error(p_operation_id,'work_start_workflow','PARENT_FORBIDDEN','غير مصرح بربط مسار العمل بهذا العنصر',p_parent_work_item_id); END IF;

  SELECT * INTO v_template FROM public.work_workflow_templates WHERE id=p_template_id;
  IF NOT FOUND OR NOT v_template.is_active OR v_template.current_published_version_id IS NULL THEN RETURN private.work_command_error(p_operation_id,'work_start_workflow','WORKFLOW_UNAVAILABLE','مسار العمل غير منشور أو غير متاح',p_parent_work_item_id); END IF;
  SELECT * INTO v_version FROM public.work_workflow_template_versions WHERE id=v_template.current_published_version_id AND status='published';
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_start_workflow','WORKFLOW_VERSION_MISSING','نسخة مسار العمل المنشورة غير موجودة',p_parent_work_item_id); END IF;

  BEGIN
    INSERT INTO public.work_workflow_runs(template_version_id,parent_work_item_id,status,input_data,started_by_user_id)
    VALUES(v_version.id,p_parent_work_item_id,'running',COALESCE(p_input_data,'{}'::JSONB),v_actor) RETURNING * INTO v_run;
    INSERT INTO public.work_workflow_step_instances(workflow_run_id,step_definition_id,step_key,status)
    SELECT v_run.id,s.id,s.step_key,'pending' FROM public.work_workflow_step_definitions s
    WHERE s.template_version_id=v_version.id ORDER BY s.sort_order,s.step_key;
    v_advance:=private.work_advance_workflow_run(v_run.id);
    SELECT * INTO v_run FROM public.work_workflow_runs WHERE id=v_run.id;
    v_result:=jsonb_build_object('workflow_run_id',v_run.id,'template_version_id',v_version.id,'status',v_run.status,'state_version',v_run.state_version,'advance',v_advance);
    RETURN private.work_command_success(p_operation_id,'work_start_workflow',p_parent_work_item_id,v_result);
  EXCEPTION WHEN OTHERS THEN
    RETURN private.work_command_error(p_operation_id,'work_start_workflow','WORKFLOW_START_FAILED','تعذر بدء مسار العمل',p_parent_work_item_id);
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.work_refresh_workflow(
  p_operation_id UUID,
  p_run_id UUID,
  p_expected_version BIGINT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid(); v_prepare JSONB; v_run public.work_workflow_runs%ROWTYPE; v_advance JSONB; v_result JSONB;
BEGIN
  SELECT * INTO v_run FROM public.work_workflow_runs WHERE id=p_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'operation_id',p_operation_id,'operation','work_refresh_workflow','replayed',false,'error',jsonb_build_object('code','NOT_FOUND','message','تشغيل مسار العمل غير موجود')); END IF;
  v_prepare:=private.work_prepare_operation(p_operation_id,v_actor,'work_refresh_workflow',jsonb_build_object('run_id',p_run_id,'expected_version',p_expected_version),v_run.parent_work_item_id);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  SELECT * INTO v_run FROM public.work_workflow_runs WHERE id=p_run_id FOR UPDATE;
  IF v_run.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_refresh_workflow','VERSION_CONFLICT','تم تحديث مسار العمل بواسطة عملية أخرى',v_run.parent_work_item_id); END IF;
  IF NOT private.work_user_can_view_workflow_run(v_actor,p_run_id) THEN RETURN private.work_command_error(p_operation_id,'work_refresh_workflow','FORBIDDEN','غير مصرح بعرض أو تحديث هذا المسار',v_run.parent_work_item_id); END IF;
  v_advance:=private.work_advance_workflow_run(p_run_id);
  SELECT * INTO v_run FROM public.work_workflow_runs WHERE id=p_run_id;
  v_result:=jsonb_build_object('workflow_run_id',v_run.id,'status',v_run.status,'state_version',v_run.state_version,'output_data',v_run.output_data,'advance',v_advance);
  RETURN private.work_command_success(p_operation_id,'work_refresh_workflow',v_run.parent_work_item_id,v_result);
END;
$$;

CREATE OR REPLACE FUNCTION private.work_validate_workflow_completion_transition()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_schema JSONB;
  v_validation JSONB;
BEGIN
  IF NEW.status='done' AND OLD.status IS DISTINCT FROM NEW.status AND NEW.workflow_run_id IS NOT NULL THEN
    SELECT sd.output_schema INTO v_schema
    FROM public.work_workflow_step_instances si
    JOIN public.work_workflow_step_definitions sd ON sd.id=si.step_definition_id
    WHERE si.work_item_id=NEW.id;
    IF v_schema IS NOT NULL THEN
      v_validation:=private.work_validate_intake_payload(v_schema,COALESCE(NEW.completion_output,'{}'::JSONB));
      IF NOT COALESCE((v_validation->>'ok')::BOOLEAN,false) THEN
        RAISE EXCEPTION 'workflow structured output contract failed: %',COALESCE(v_validation->>'field',v_validation->>'code');
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_work_validate_workflow_completion
  BEFORE UPDATE OF status,completion_output ON public.work_items
  FOR EACH ROW EXECUTE FUNCTION private.work_validate_workflow_completion_transition();

REVOKE ALL ON FUNCTION private.work_append_system_event(UUID,TEXT,public.work_item_status,public.work_item_status,JSONB) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_workflow_context_value(UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_evaluate_workflow_condition(UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_resolve_workflow_actor(UUID,JSONB,TEXT) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_activate_workflow_step(UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_advance_workflow_run(UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_validate_workflow_completion_transition() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.work_start_workflow(UUID,UUID,JSONB,UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_refresh_workflow(UUID,UUID,BIGINT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.work_start_workflow(UUID,UUID,JSONB,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_refresh_workflow(UUID,UUID,BIGINT) TO authenticated;

RESET lock_timeout;
RESET statement_timeout;
