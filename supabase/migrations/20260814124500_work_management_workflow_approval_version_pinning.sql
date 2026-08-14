-- Work Management — pin Approval Engine versions into published Workflow definitions.
-- A published workflow must remain reproducible even when a newer approval template version is published later.
SET lock_timeout='5s';
SET statement_timeout='60s';

ALTER TABLE public.work_workflow_step_definitions
  ADD COLUMN approval_template_version_id UUID
    REFERENCES public.work_approval_template_versions(id) ON DELETE RESTRICT,
  ADD COLUMN completion_approval_template_version_id UUID
    REFERENCES public.work_approval_template_versions(id) ON DELETE RESTRICT;

ALTER TABLE public.work_items
  ADD COLUMN completion_approval_template_version_id UUID
    REFERENCES public.work_approval_template_versions(id) ON DELETE RESTRICT;

CREATE INDEX idx_work_workflow_steps_approval_version
  ON public.work_workflow_step_definitions(approval_template_version_id)
  WHERE approval_template_version_id IS NOT NULL;

CREATE INDEX idx_work_items_completion_approval_version
  ON public.work_items(completion_approval_template_version_id)
  WHERE completion_approval_template_version_id IS NOT NULL;

CREATE OR REPLACE FUNCTION private.work_pin_workflow_approval_versions(p_workflow_version_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_step public.work_workflow_step_definitions%ROWTYPE;
  v_template_id UUID;
  v_version_id UUID;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.work_workflow_template_versions v
    WHERE v.id=p_workflow_version_id AND v.status='draft'
  ) THEN
    RAISE EXCEPTION 'only a draft workflow version can be pinned';
  END IF;

  FOR v_step IN
    SELECT *
    FROM public.work_workflow_step_definitions
    WHERE template_version_id=p_workflow_version_id
    ORDER BY sort_order,id
    FOR UPDATE
  LOOP
    IF v_step.step_kind='approval' THEN
      SELECT t.current_published_version_id
      INTO v_version_id
      FROM public.work_approval_templates t
      JOIN public.work_approval_template_versions av
        ON av.id=t.current_published_version_id
       AND av.template_id=t.id
       AND av.status='published'
      WHERE t.id=v_step.approval_template_id
        AND t.is_active=true;

      IF v_version_id IS NULL THEN
        RAISE EXCEPTION 'workflow approval step % has no published approval version',v_step.step_key;
      END IF;

      UPDATE public.work_workflow_step_definitions
      SET approval_template_version_id=v_version_id,
          completion_approval_template_version_id=NULL
      WHERE id=v_step.id;

    ELSE
      IF COALESCE(v_step.task_config->>'completion_mode','assignee_closes')='approval' THEN
        BEGIN
          v_template_id:=NULLIF(v_step.task_config->>'completion_approval_template_id','')::UUID;
        EXCEPTION WHEN OTHERS THEN
          RAISE EXCEPTION 'workflow task step % has invalid completion approval template id',v_step.step_key;
        END;

        IF v_template_id IS NULL THEN
          RAISE EXCEPTION 'workflow task step % requires completion approval template',v_step.step_key;
        END IF;

        SELECT t.current_published_version_id
        INTO v_version_id
        FROM public.work_approval_templates t
        JOIN public.work_approval_template_versions av
          ON av.id=t.current_published_version_id
         AND av.template_id=t.id
         AND av.status='published'
        WHERE t.id=v_template_id
          AND t.is_active=true;

        IF v_version_id IS NULL THEN
          RAISE EXCEPTION 'workflow task step % has no published completion approval version',v_step.step_key;
        END IF;

        UPDATE public.work_workflow_step_definitions
        SET approval_template_version_id=NULL,
            completion_approval_template_version_id=v_version_id
        WHERE id=v_step.id;
      ELSE
        UPDATE public.work_workflow_step_definitions
        SET approval_template_version_id=NULL,
            completion_approval_template_version_id=NULL
        WHERE id=v_step.id;
      END IF;
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION private.work_pin_workflow_before_publish()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
BEGIN
  IF OLD.status='draft' AND NEW.status='published' THEN
    PERFORM private.work_pin_workflow_approval_versions(OLD.id);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_work_workflow_pin_approvals_before_publish
  BEFORE UPDATE OF status ON public.work_workflow_template_versions
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION private.work_pin_workflow_before_publish();

-- Exact-version Approval Engine entry point used by pinned workflows.
CREATE OR REPLACE FUNCTION private.work_start_approval_request_version(
  p_work_item_id UUID,
  p_template_version_id UUID,
  p_context_kind public.work_approval_context_kind,
  p_context_payload JSONB,
  p_requested_by_user_id UUID,
  p_operation_id UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_version public.work_approval_template_versions%ROWTYPE;
  v_template public.work_approval_templates%ROWTYPE;
  v_request public.work_approval_requests%ROWTYPE;
  v_first_order INTEGER;
BEGIN
  SELECT * INTO v_version
  FROM public.work_approval_template_versions
  WHERE id=p_template_version_id AND status='published';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'pinned approval version is not published';
  END IF;

  SELECT * INTO v_template
  FROM public.work_approval_templates
  WHERE id=v_version.template_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'approval template for pinned version is missing';
  END IF;

  SELECT min(stage_order) INTO v_first_order
  FROM public.work_approval_stages
  WHERE template_version_id=v_version.id;
  IF v_first_order IS NULL THEN
    RAISE EXCEPTION 'pinned approval version has no stages';
  END IF;

  INSERT INTO public.work_approval_requests(
    work_item_id,template_version_id,context_kind,context_payload,
    status,requested_by_user_id,requested_at,state_version
  ) VALUES (
    p_work_item_id,v_version.id,p_context_kind,COALESCE(p_context_payload,'{}'::JSONB),
    'pending',p_requested_by_user_id,clock_timestamp(),1
  ) RETURNING * INTO v_request;

  PERFORM private.work_activate_approval_stage(v_request.id,v_first_order);
  PERFORM private.work_append_user_event(
    p_work_item_id,'work.approval.requested',p_requested_by_user_id,p_operation_id,NULL,NULL,
    jsonb_build_object(
      'approval_request_id',v_request.id,
      'template_id',v_template.id,
      'template_version_id',v_version.id,
      'pinned_version',true,
      'context_kind',p_context_kind,
      'stage_order',v_first_order
    )
  );
  RETURN v_request.id;
END;
$$;

-- Replace workflow step activation so approval behavior is always tied to the workflow's pinned version.
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
  v_completion_template_id UUID;
  v_work public.work_items%ROWTYPE;
  v_approval_request UUID;
  v_approval_due TIMESTAMPTZ;
  v_requester UUID;
BEGIN
  SELECT * INTO v_instance
  FROM public.work_workflow_step_instances
  WHERE id=p_step_instance_id
  FOR UPDATE;
  IF NOT FOUND OR v_instance.status<>'pending' THEN RETURN false; END IF;

  SELECT * INTO v_run
  FROM public.work_workflow_runs
  WHERE id=v_instance.workflow_run_id
  FOR UPDATE;
  IF NOT FOUND OR v_run.status<>'running' THEN RETURN false; END IF;

  SELECT * INTO v_def
  FROM public.work_workflow_step_definitions
  WHERE id=v_instance.step_definition_id;
  IF NOT FOUND OR v_def.template_version_id<>v_run.template_version_id THEN
    RAISE EXCEPTION 'workflow step definition/version mismatch';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.work_workflow_step_dependencies d
    JOIN public.work_workflow_step_definitions pred ON pred.id=d.predecessor_step_id
    JOIN public.work_workflow_step_instances pi
      ON pi.workflow_run_id=v_run.id AND pi.step_key=pred.step_key
    WHERE d.successor_step_id=v_def.id
      AND d.template_version_id=v_run.template_version_id
      AND pi.status NOT IN ('completed','skipped')
  ) THEN RETURN false; END IF;

  IF NOT private.work_evaluate_workflow_condition(v_run.id,v_def.condition_dsl) THEN
    UPDATE public.work_workflow_step_instances
    SET status='skipped',completed_at=clock_timestamp(),state_version=state_version+1
    WHERE id=v_instance.id;
    RETURN true;
  END IF;

  v_owner:=private.work_resolve_workflow_actor(v_run.id,v_def.task_config,'owner');
  IF v_owner IS NULL THEN v_owner:=v_run.started_by_user_id; END IF;
  IF NOT private.work_actor_is_active(v_owner) THEN
    RAISE EXCEPTION 'workflow step owner could not be resolved';
  END IF;
  v_requester:=COALESCE(v_run.started_by_user_id,v_owner);

  IF v_def.step_kind='task' THEN
    v_assignee:=private.work_resolve_workflow_actor(v_run.id,v_def.task_config,'assignee');
    IF v_assignee IS NULL THEN v_assignee:=v_owner; END IF;
    IF NOT private.work_actor_is_active(v_assignee) THEN
      RAISE EXCEPTION 'workflow step assignee could not be resolved';
    END IF;

    SELECT e.branch_id,e.department_id
    INTO v_branch,v_department
    FROM public.hr_employees e
    WHERE e.user_id=v_assignee AND e.status::TEXT='active'
    LIMIT 1;

    BEGIN
      v_due_minutes:=NULLIF(v_def.task_config->>'due_minutes','')::INTEGER;
      v_priority:=COALESCE(NULLIF(v_def.task_config->>'priority','')::public.work_priority,'normal');
      v_visibility:=COALESCE(NULLIF(v_def.task_config->>'visibility','')::public.work_visibility,'standard');
      v_completion_mode:=COALESCE(NULLIF(v_def.task_config->>'completion_mode','')::public.work_completion_mode,'assignee_closes');
      v_completion_template_id:=CASE
        WHEN v_completion_mode='approval'
        THEN NULLIF(v_def.task_config->>'completion_approval_template_id','')::UUID
        ELSE NULL
      END;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'invalid workflow task runtime configuration';
    END;

    IF v_due_minutes IS NOT NULL AND v_due_minutes<=0 THEN
      RAISE EXCEPTION 'workflow due_minutes must be positive';
    END IF;
    IF v_completion_mode='approval' AND (
      v_completion_template_id IS NULL OR v_def.completion_approval_template_version_id IS NULL
    ) THEN
      RAISE EXCEPTION 'published workflow task is missing pinned completion approval version';
    END IF;
    IF v_def.completion_approval_template_version_id IS NOT NULL AND NOT EXISTS (
      SELECT 1
      FROM public.work_approval_template_versions av
      WHERE av.id=v_def.completion_approval_template_version_id
        AND av.template_id=v_completion_template_id
        AND av.status='published'
    ) THEN
      RAISE EXCEPTION 'pinned completion approval version is inconsistent';
    END IF;

    v_due_at:=CASE
      WHEN v_due_minutes IS NULL THEN NULL
      ELSE clock_timestamp()+make_interval(mins=>v_due_minutes)
    END;

    INSERT INTO public.work_items(
      kind,source_kind,source_key,title,description,expected_outcome,status,priority,visibility,
      creator_user_id,requester_user_id,accountable_owner_user_id,current_assignee_user_id,
      owning_department_id,branch_id,workflow_run_id,workflow_step_key,
      activated_at,assigned_at,due_at,first_due_at,next_action_text,next_action_at,
      completion_mode,completion_approval_template_id,completion_approval_template_version_id,
      last_meaningful_activity_at,state_version
    ) VALUES (
      'workflow_step','workflow','workflow:'||v_run.id::TEXT||':'||v_def.step_key,
      v_def.name,v_def.task_config->>'description',v_def.task_config->>'expected_outcome',
      'open',v_priority,v_visibility,
      v_requester,v_requester,v_owner,v_assignee,v_department,v_branch,v_run.id,v_def.step_key,
      clock_timestamp(),clock_timestamp(),v_due_at,v_due_at,
      COALESCE(NULLIF(v_def.task_config->>'next_action_text',''),v_def.name),NULL,
      v_completion_mode,v_completion_template_id,v_def.completion_approval_template_version_id,
      clock_timestamp(),1
    ) RETURNING * INTO v_work;

    UPDATE public.work_workflow_step_instances
    SET status='active',work_item_id=v_work.id,activated_at=clock_timestamp(),state_version=state_version+1
    WHERE id=v_instance.id;

    PERFORM private.work_append_system_event(
      v_work.id,'work.workflow_step.activated',NULL,'open',
      jsonb_build_object(
        'workflow_run_id',v_run.id,
        'step_key',v_def.step_key,
        'completion_approval_version_id',v_def.completion_approval_template_version_id
      )
    );
  ELSE
    IF v_def.approval_template_id IS NULL OR v_def.approval_template_version_id IS NULL THEN
      RAISE EXCEPTION 'published workflow approval step is missing pinned approval version';
    END IF;
    IF NOT EXISTS (
      SELECT 1
      FROM public.work_approval_template_versions av
      WHERE av.id=v_def.approval_template_version_id
        AND av.template_id=v_def.approval_template_id
        AND av.status='published'
    ) THEN
      RAISE EXCEPTION 'pinned workflow approval version is inconsistent';
    END IF;

    INSERT INTO public.work_items(
      kind,source_kind,source_key,title,expected_outcome,status,priority,visibility,
      creator_user_id,requester_user_id,accountable_owner_user_id,current_assignee_user_id,
      workflow_run_id,workflow_step_key,activated_at,next_action_text,last_meaningful_activity_at,state_version
    ) VALUES (
      'workflow_step','workflow','workflow:'||v_run.id::TEXT||':'||v_def.step_key,
      v_def.name,'اتخاذ قرار اعتماد موثق للمرحلة','pending_approval','normal','standard',
      v_requester,v_requester,v_owner,NULL,v_run.id,v_def.step_key,
      clock_timestamp(),'اتخاذ قرار الاعتماد',clock_timestamp(),1
    ) RETURNING * INTO v_work;

    v_approval_request:=private.work_start_approval_request_version(
      v_work.id,v_def.approval_template_version_id,'workflow_step',
      jsonb_build_object(
        'workflow_run_id',v_run.id,
        'workflow_step_instance_id',v_instance.id,
        'step_key',v_def.step_key
      ),
      v_requester,NULL
    );

    SELECT s.due_at INTO v_approval_due
    FROM public.work_approval_stage_instances s
    WHERE s.approval_request_id=v_approval_request AND s.status='pending'
    ORDER BY s.stage_order
    LIMIT 1;

    UPDATE public.work_items
    SET next_action_at=v_approval_due
    WHERE id=v_work.id;

    UPDATE public.work_workflow_step_instances
    SET status='active',work_item_id=v_work.id,approval_request_id=v_approval_request,
        activated_at=clock_timestamp(),state_version=state_version+1
    WHERE id=v_instance.id;

    PERFORM private.work_append_system_event(
      v_work.id,'work.workflow_approval_step.activated',NULL,'pending_approval',
      jsonb_build_object(
        'workflow_run_id',v_run.id,
        'step_key',v_def.step_key,
        'approval_request_id',v_approval_request,
        'approval_template_version_id',v_def.approval_template_version_id
      )
    );
  END IF;

  RETURN true;
END;
$$;

-- Completion bridge: if a workflow-created task carries a pinned approval version, use it.
CREATE OR REPLACE FUNCTION public.work_complete(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_completion_summary TEXT,
  p_completion_output JSONB DEFAULT '{}'::JSONB
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_blockers JSONB;
  v_review public.work_completion_reviews%ROWTYPE;
  v_approval_request_id UUID;
  v_approval_due TIMESTAMPTZ;
  v_from public.work_item_status;
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_complete',
    jsonb_build_object(
      'work_item_id',p_work_item_id,'expected_version',p_expected_version,
      'completion_summary',p_completion_summary,
      'completion_output',COALESCE(p_completion_output,'{}'::JSONB)
    ),p_work_item_id
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_complete','NOT_FOUND','المهمة غير موجودة',p_work_item_id); END IF;
  IF v_item.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_complete','VERSION_CONFLICT','تم تعديل المهمة بواسطة مستخدم آخر',p_work_item_id); END IF;
  IF NOT private.work_actor_can_update_item(v_actor,p_work_item_id) THEN RETURN private.work_command_error(p_operation_id,'work_complete','FORBIDDEN','غير مصرح بإنهاء المهمة',p_work_item_id); END IF;
  IF v_item.status NOT IN ('open','in_progress','waiting') THEN RETURN private.work_command_error(p_operation_id,'work_complete','INVALID_STATE','لا يمكن إنهاء المهمة من حالتها الحالية',p_work_item_id); END IF;
  IF p_completion_summary IS NULL OR btrim(p_completion_summary)='' THEN RETURN private.work_command_error(p_operation_id,'work_complete','COMPLETION_SUMMARY_REQUIRED','ملخص نتيجة التنفيذ مطلوب',p_work_item_id); END IF;
  IF jsonb_typeof(COALESCE(p_completion_output,'{}'::JSONB))<>'object' THEN RETURN private.work_command_error(p_operation_id,'work_complete','INVALID_OUTPUT','ناتج التنفيذ يجب أن يكون كائن بيانات',p_work_item_id); END IF;

  v_blockers:=private.work_completion_blockers(p_work_item_id);
  IF COALESCE((v_blockers->>'required_checklist_open')::BOOLEAN,false) THEN RETURN private.work_command_error(p_operation_id,'work_complete','CHECKLIST_INCOMPLETE','توجد بنود إلزامية غير مكتملة',p_work_item_id); END IF;
  IF COALESCE((v_blockers->>'required_child_open')::BOOLEAN,false) THEN RETURN private.work_command_error(p_operation_id,'work_complete','CHILD_WORK_OPEN','توجد مهام فرعية مطلوبة لم تُغلق',p_work_item_id); END IF;
  IF COALESCE((v_blockers->>'hard_dependency_open')::BOOLEAN,false) THEN RETURN private.work_command_error(p_operation_id,'work_complete','DEPENDENCY_OPEN','توجد اعتمادات إلزامية لم تكتمل',p_work_item_id); END IF;

  v_from:=v_item.status;

  IF v_item.completion_mode='approval'::public.work_completion_mode THEN
    IF v_item.completion_approval_template_id IS NULL THEN
      RETURN private.work_command_error(p_operation_id,'work_complete','APPROVAL_TEMPLATE_REQUIRED','المهمة تتطلب اعتماد إتمام ولم يتم ربط نموذج اعتماد',p_work_item_id);
    END IF;

    BEGIN
      IF v_item.completion_approval_template_version_id IS NOT NULL THEN
        IF NOT EXISTS (
          SELECT 1
          FROM public.work_approval_template_versions av
          WHERE av.id=v_item.completion_approval_template_version_id
            AND av.template_id=v_item.completion_approval_template_id
            AND av.status='published'
        ) THEN
          RETURN private.work_command_error(p_operation_id,'work_complete','APPROVAL_VERSION_INVALID','نسخة اعتماد الإتمام المثبتة غير صالحة',p_work_item_id);
        END IF;
        v_approval_request_id:=private.work_start_approval_request_version(
          p_work_item_id,v_item.completion_approval_template_version_id,'completion',
          jsonb_build_object(
            'completion_summary',p_completion_summary,
            'completion_output',COALESCE(p_completion_output,'{}'::JSONB),
            'submitted_by_user_id',v_actor,
            'submitted_work_version',p_expected_version,
            'workflow_pinned_version',true
          ),v_actor,p_operation_id
        );
      ELSE
        v_approval_request_id:=private.work_start_approval_request(
          p_work_item_id,v_item.completion_approval_template_id,'completion',
          jsonb_build_object(
            'completion_summary',p_completion_summary,
            'completion_output',COALESCE(p_completion_output,'{}'::JSONB),
            'submitted_by_user_id',v_actor,
            'submitted_work_version',p_expected_version
          ),v_actor,p_operation_id
        );
      END IF;

      SELECT s.due_at INTO v_approval_due
      FROM public.work_approval_stage_instances s
      WHERE s.approval_request_id=v_approval_request_id AND s.status='pending'
      ORDER BY s.stage_order LIMIT 1;

      UPDATE public.work_items
      SET status='pending_approval',completion_summary=p_completion_summary,
          completion_output=COALESCE(p_completion_output,'{}'::JSONB),completed_by_user_id=v_actor,
          next_action_text='اعتماد نتيجة التنفيذ',next_action_at=v_approval_due,
          waiting_on_type=NULL,waiting_on_user_id=NULL,waiting_on_entity_type=NULL,waiting_on_entity_id=NULL,
          waiting_on_label=NULL,waiting_reason=NULL,waiting_since=NULL,
          state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
      WHERE id=p_work_item_id RETURNING * INTO v_item;

      PERFORM private.work_append_user_event(
        v_item.id,'work.completion_approval_requested',v_actor,p_operation_id,v_from,'pending_approval',
        jsonb_build_object(
          'approval_request_id',v_approval_request_id,
          'approval_due_at',v_approval_due,
          'approval_template_version_id',v_item.completion_approval_template_version_id
        )
      );

      v_result:=jsonb_build_object(
        'work_item_id',v_item.id,'status',v_item.status,'state_version',v_item.state_version,
        'approval_request_id',v_approval_request_id
      );
      RETURN private.work_command_success(p_operation_id,'work_complete',v_item.id,v_result);
    EXCEPTION WHEN OTHERS THEN
      RETURN private.work_command_error(p_operation_id,'work_complete','APPROVAL_START_FAILED','تعذر بدء اعتماد نتيجة التنفيذ',p_work_item_id);
    END;
  END IF;

  IF v_item.completion_mode='owner_review'::public.work_completion_mode
     AND v_item.accountable_owner_user_id IS DISTINCT FROM v_actor THEN
    IF v_item.accountable_owner_user_id IS NULL OR NOT private.work_actor_is_active(v_item.accountable_owner_user_id) THEN
      RETURN private.work_command_error(p_operation_id,'work_complete','OWNER_REVIEWER_UNAVAILABLE','لا يوجد مالك مسؤول نشط لمراجعة الإتمام',p_work_item_id);
    END IF;

    INSERT INTO public.work_completion_reviews(
      work_item_id,requested_by_user_id,reviewer_user_id,completion_summary,completion_output
    ) VALUES (
      p_work_item_id,v_actor,v_item.accountable_owner_user_id,p_completion_summary,COALESCE(p_completion_output,'{}'::JSONB)
    ) RETURNING * INTO v_review;

    UPDATE public.work_items
    SET status='pending_approval',completion_summary=p_completion_summary,
        completion_output=COALESCE(p_completion_output,'{}'::JSONB),completed_by_user_id=v_actor,
        next_action_text='مراجعة نتيجة التنفيذ',next_action_at=NULL,
        state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
    WHERE id=p_work_item_id RETURNING * INTO v_item;

    PERFORM private.work_append_user_event(
      v_item.id,'work.completion_review_requested',v_actor,p_operation_id,v_from,'pending_approval',
      jsonb_build_object('review_id',v_review.id,'reviewer_user_id',v_review.reviewer_user_id)
    );
    v_result:=jsonb_build_object('work_item_id',v_item.id,'status',v_item.status,'state_version',v_item.state_version,'review_id',v_review.id);
    RETURN private.work_command_success(p_operation_id,'work_complete',v_item.id,v_result);
  END IF;

  UPDATE public.work_items
  SET status='done',completion_summary=p_completion_summary,
      completion_output=COALESCE(p_completion_output,'{}'::JSONB),completed_by_user_id=v_actor,
      completed_at=clock_timestamp(),next_action_text=NULL,next_action_at=NULL,
      waiting_on_type=NULL,waiting_on_user_id=NULL,waiting_on_entity_type=NULL,waiting_on_entity_id=NULL,
      waiting_on_label=NULL,waiting_reason=NULL,waiting_since=NULL,
      state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
  WHERE id=p_work_item_id RETURNING * INTO v_item;

  PERFORM private.work_append_user_event(
    v_item.id,'work.completed',v_actor,p_operation_id,v_from,'done',
    jsonb_build_object('completion_summary',p_completion_summary)
  );
  v_result:=jsonb_build_object(
    'work_item_id',v_item.id,'status',v_item.status,'state_version',v_item.state_version,'completed_at',v_item.completed_at
  );
  RETURN private.work_command_success(p_operation_id,'work_complete',v_item.id,v_result);
END;
$$;

REVOKE ALL ON FUNCTION private.work_pin_workflow_approval_versions(UUID)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_pin_workflow_before_publish()
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_start_approval_request_version(UUID,UUID,public.work_approval_context_kind,JSONB,UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_activate_workflow_step(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

RESET lock_timeout;
RESET statement_timeout;
