-- Work Management — recurring Task / Workflow runtime and lifecycle commands.
SET lock_timeout='5s';
SET statement_timeout='60s';

ALTER TABLE public.work_recurrence_definitions
  ADD COLUMN workflow_input JSONB NOT NULL DEFAULT '{}'::JSONB,
  ADD COLUMN workflow_starter_user_id UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  ADD CONSTRAINT work_recurrence_workflow_input_object CHECK (jsonb_typeof(workflow_input)='object');

CREATE OR REPLACE FUNCTION private.work_start_workflow_version_from_recurrence(
  p_version_id UUID,
  p_input_data JSONB,
  p_occurrence_id UUID,
  p_starter_user_id UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_version public.work_workflow_template_versions%ROWTYPE;
  v_run public.work_workflow_runs%ROWTYPE;
BEGIN
  SELECT * INTO v_version
  FROM public.work_workflow_template_versions
  WHERE id=p_version_id AND status='published';
  IF NOT FOUND THEN RAISE EXCEPTION 'recurrence workflow version is unavailable'; END IF;
  IF NOT private.work_actor_is_active(p_starter_user_id) THEN
    RAISE EXCEPTION 'recurrence workflow starter is inactive';
  END IF;
  IF jsonb_typeof(COALESCE(p_input_data,'{}'::JSONB))<>'object' THEN
    RAISE EXCEPTION 'recurrence workflow input must be an object';
  END IF;

  INSERT INTO public.work_workflow_runs(
    template_version_id,recurrence_occurrence_id,status,input_data,started_by_user_id,started_at
  ) VALUES (
    v_version.id,p_occurrence_id,'running',COALESCE(p_input_data,'{}'::JSONB),p_starter_user_id,clock_timestamp()
  ) RETURNING * INTO v_run;

  INSERT INTO public.work_workflow_step_instances(
    workflow_run_id,step_definition_id,step_key,status
  )
  SELECT v_run.id,s.id,s.step_key,'pending'
  FROM public.work_workflow_step_definitions s
  WHERE s.template_version_id=v_version.id
  ORDER BY s.sort_order,s.step_key;

  PERFORM private.work_advance_workflow_run(v_run.id);
  RETURN v_run.id;
END;
$$;

CREATE OR REPLACE FUNCTION private.work_validate_recurrence_task_config(
  p_actor_user_id UUID,
  p_config JSONB
) RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_owner UUID;
  v_assignee UUID;
  v_priority public.work_priority;
  v_visibility public.work_visibility;
  v_completion_mode public.work_completion_mode;
  v_due_minutes INTEGER;
  v_next_minutes INTEGER;
  v_approval_template UUID;
BEGIN
  IF jsonb_typeof(COALESCE(p_config,'{}'::JSONB))<>'object' THEN
    RETURN jsonb_build_object('ok',false,'code','INVALID_TASK_CONFIG','message','إعداد المهمة الدورية غير صالح');
  END IF;
  IF NULLIF(btrim(p_config->>'title'),'') IS NULL
     OR NULLIF(btrim(p_config->>'expected_outcome'),'') IS NULL
     OR NULLIF(btrim(p_config->>'next_action_text'),'') IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','TASK_FIELDS_REQUIRED','message','العنوان والنتيجة المتوقعة والإجراء التالي مطلوبة للمهمة الدورية');
  END IF;

  BEGIN
    v_owner:=COALESCE(NULLIF(p_config->>'owner_user_id','')::UUID,p_actor_user_id);
    v_assignee:=COALESCE(NULLIF(p_config->>'assignee_user_id','')::UUID,v_owner);
    v_priority:=COALESCE(NULLIF(p_config->>'priority','')::public.work_priority,'normal');
    v_visibility:=COALESCE(NULLIF(p_config->>'visibility','')::public.work_visibility,'standard');
    v_completion_mode:=COALESCE(NULLIF(p_config->>'completion_mode','')::public.work_completion_mode,'assignee_closes');
    v_due_minutes:=NULLIF(p_config->>'due_after_minutes','')::INTEGER;
    v_next_minutes:=NULLIF(p_config->>'next_action_after_minutes','')::INTEGER;
    v_approval_template:=NULLIF(p_config->>'completion_approval_template_id','')::UUID;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok',false,'code','INVALID_TASK_CONFIG','message','إحدى قيم إعداد المهمة الدورية غير صحيحة');
  END;

  IF NOT private.work_user_can_assign_target(p_actor_user_id,v_owner)
     OR NOT private.work_user_can_assign_target(p_actor_user_id,v_assignee) THEN
    RETURN jsonb_build_object('ok',false,'code','ASSIGNMENT_SCOPE_DENIED','message','مسؤول أو منفذ المهمة الدورية خارج نطاق الإسناد');
  END IF;
  IF v_due_minutes IS NOT NULL AND v_due_minutes<=0 THEN
    RETURN jsonb_build_object('ok',false,'code','INVALID_DUE_OFFSET','message','مهلة إنجاز المهمة الدورية يجب أن تكون موجبة');
  END IF;
  IF v_next_minutes IS NOT NULL AND v_next_minutes<0 THEN
    RETURN jsonb_build_object('ok',false,'code','INVALID_NEXT_ACTION_OFFSET','message','مهلة الإجراء التالي غير صحيحة');
  END IF;
  IF v_completion_mode='approval' AND v_approval_template IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','APPROVAL_TEMPLATE_REQUIRED','message','نموذج اعتماد الإتمام مطلوب للمهمة الدورية');
  END IF;
  IF v_approval_template IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.work_approval_templates t
    WHERE t.id=v_approval_template AND t.is_active=true AND t.current_published_version_id IS NOT NULL
  ) THEN
    RETURN jsonb_build_object('ok',false,'code','APPROVAL_TEMPLATE_UNAVAILABLE','message','نموذج اعتماد الإتمام غير متاح');
  END IF;

  RETURN jsonb_build_object(
    'ok',true,'owner_user_id',v_owner,'assignee_user_id',v_assignee,
    'priority',v_priority,'visibility',v_visibility,'completion_mode',v_completion_mode,
    'due_after_minutes',v_due_minutes,'next_action_after_minutes',v_next_minutes,
    'completion_approval_template_id',v_approval_template
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.work_create_recurrence(
  p_operation_id UUID,
  p_name TEXT,
  p_description TEXT,
  p_target_kind public.work_recurrence_target_kind,
  p_frequency public.work_recurrence_frequency,
  p_interval_count INTEGER,
  p_local_time TIME,
  p_timezone TEXT,
  p_starts_on DATE,
  p_ends_on DATE DEFAULT NULL,
  p_weekdays SMALLINT[] DEFAULT NULL,
  p_day_of_month SMALLINT DEFAULT NULL,
  p_monthly_policy public.work_recurrence_monthly_policy DEFAULT NULL,
  p_overlap_policy public.work_recurrence_overlap_policy DEFAULT 'strict',
  p_task_config JSONB DEFAULT '{}'::JSONB,
  p_workflow_template_id UUID DEFAULT NULL,
  p_workflow_version_policy public.work_recurrence_workflow_version_policy DEFAULT NULL,
  p_workflow_input JSONB DEFAULT '{}'::JSONB,
  p_workflow_starter_user_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_validation JSONB;
  v_next TIMESTAMPTZ;
  v_definition public.work_recurrence_definitions%ROWTYPE;
  v_pinned_version UUID;
  v_starter UUID;
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_create_recurrence',
    jsonb_build_object(
      'name',p_name,'description',p_description,'target_kind',p_target_kind,'frequency',p_frequency,
      'interval_count',p_interval_count,'local_time',p_local_time,'timezone',p_timezone,'starts_on',p_starts_on,
      'ends_on',p_ends_on,'weekdays',p_weekdays,'day_of_month',p_day_of_month,'monthly_policy',p_monthly_policy,
      'overlap_policy',p_overlap_policy,'task_config',COALESCE(p_task_config,'{}'::JSONB),
      'workflow_template_id',p_workflow_template_id,'workflow_version_policy',p_workflow_version_policy,
      'workflow_input',COALESCE(p_workflow_input,'{}'::JSONB),'workflow_starter_user_id',p_workflow_starter_user_id
    ),NULL
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  IF NOT COALESCE(public.check_permission(v_actor,'work.recurrence.manage'),false) THEN
    RETURN private.work_command_error(p_operation_id,'work_create_recurrence','FORBIDDEN','لا تملك صلاحية إدارة الأعمال الدورية');
  END IF;
  IF NULLIF(btrim(p_name),'') IS NULL OR p_interval_count IS NULL OR p_interval_count<=0 THEN
    RETURN private.work_command_error(p_operation_id,'work_create_recurrence','VALIDATION_ERROR','اسم وجدول التكرار مطلوبان');
  END IF;
  IF p_starts_on IS NULL OR (p_ends_on IS NOT NULL AND p_ends_on<p_starts_on) THEN
    RETURN private.work_command_error(p_operation_id,'work_create_recurrence','INVALID_DATE_WINDOW','فترة التكرار غير صحيحة');
  END IF;
  IF private.work_recurrence_local_timestamp(p_starts_on,COALESCE(p_local_time,'09:00'),p_timezone) IS NULL THEN
    RETURN private.work_command_error(p_operation_id,'work_create_recurrence','INVALID_TIMEZONE','المنطقة الزمنية غير صحيحة');
  END IF;
  IF p_frequency='weekly' AND (p_weekdays IS NULL OR cardinality(p_weekdays)=0 OR NOT p_weekdays <@ ARRAY[1,2,3,4,5,6,7]::SMALLINT[]) THEN
    RETURN private.work_command_error(p_operation_id,'work_create_recurrence','INVALID_WEEKDAYS','حدد أيام الأسبوع بقيم من 1 إلى 7');
  END IF;
  IF p_frequency<>'weekly' AND p_weekdays IS NOT NULL THEN
    RETURN private.work_command_error(p_operation_id,'work_create_recurrence','INVALID_WEEKDAYS','أيام الأسبوع تستخدم مع التكرار الأسبوعي فقط');
  END IF;
  IF p_frequency='monthly' THEN
    IF p_monthly_policy IS NULL
       OR (p_monthly_policy='exact_day' AND (p_day_of_month IS NULL OR p_day_of_month NOT BETWEEN 1 AND 31))
       OR (p_monthly_policy='last_day' AND p_day_of_month IS NOT NULL) THEN
      RETURN private.work_command_error(p_operation_id,'work_create_recurrence','INVALID_MONTHLY_RULE','قاعدة التكرار الشهري غير صحيحة');
    END IF;
  ELSIF p_monthly_policy IS NOT NULL OR p_day_of_month IS NOT NULL THEN
    RETURN private.work_command_error(p_operation_id,'work_create_recurrence','INVALID_MONTHLY_RULE','قاعدة الشهر تستخدم مع التكرار الشهري فقط');
  END IF;

  IF p_target_kind='task' THEN
    v_validation:=private.work_validate_recurrence_task_config(v_actor,COALESCE(p_task_config,'{}'::JSONB));
    IF NOT COALESCE((v_validation->>'ok')::BOOLEAN,false) THEN
      RETURN private.work_command_error(
        p_operation_id,'work_create_recurrence',COALESCE(v_validation->>'code','INVALID_TASK_CONFIG'),
        COALESCE(v_validation->>'message','إعداد المهمة الدورية غير صالح')
      );
    END IF;
    IF p_workflow_template_id IS NOT NULL OR p_workflow_version_policy IS NOT NULL OR p_workflow_starter_user_id IS NOT NULL THEN
      RETURN private.work_command_error(p_operation_id,'work_create_recurrence','TARGET_CONFIG_CONFLICT','لا تخلط إعداد المهمة مع إعداد مسار العمل');
    END IF;
  ELSE
    IF p_workflow_template_id IS NULL OR p_workflow_version_policy IS NULL THEN
      RETURN private.work_command_error(p_operation_id,'work_create_recurrence','WORKFLOW_CONFIG_REQUIRED','حدد مسار العمل وسياسة النسخة');
    END IF;
    IF jsonb_typeof(COALESCE(p_workflow_input,'{}'::JSONB))<>'object' THEN
      RETURN private.work_command_error(p_operation_id,'work_create_recurrence','INVALID_WORKFLOW_INPUT','مدخلات مسار العمل يجب أن تكون كائن بيانات');
    END IF;
    v_starter:=COALESCE(p_workflow_starter_user_id,v_actor);
    IF NOT private.work_actor_is_active(v_starter) THEN
      RETURN private.work_command_error(p_operation_id,'work_create_recurrence','WORKFLOW_STARTER_UNAVAILABLE','مستخدم تشغيل المسار الدوري غير نشط');
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.work_workflow_templates t
      WHERE t.id=p_workflow_template_id AND t.is_active=true AND t.current_published_version_id IS NOT NULL
    ) THEN
      RETURN private.work_command_error(p_operation_id,'work_create_recurrence','WORKFLOW_UNAVAILABLE','مسار العمل غير منشور أو غير متاح');
    END IF;
    IF p_workflow_version_policy='pinned' THEN
      SELECT current_published_version_id INTO v_pinned_version
      FROM public.work_workflow_templates WHERE id=p_workflow_template_id;
    END IF;
  END IF;

  v_next:=private.work_recurrence_next_occurrence_at(
    p_frequency,p_interval_count,p_starts_on,p_ends_on,
    p_weekdays,p_day_of_month,p_monthly_policy,COALESCE(p_local_time,'09:00'),p_timezone,
    clock_timestamp()-interval '1 millisecond'
  );
  IF v_next IS NULL THEN
    RETURN private.work_command_error(p_operation_id,'work_create_recurrence','NO_FUTURE_OCCURRENCE','لا يوجد موعد تكرار قادم ضمن الفترة المحددة');
  END IF;

  INSERT INTO public.work_recurrence_definitions(
    name,description,target_kind,frequency,interval_count,weekdays,day_of_month,monthly_policy,
    local_time,timezone,starts_on,ends_on,overlap_policy,status,next_occurrence_at,
    task_config,workflow_template_id,workflow_version_policy,pinned_workflow_version_id,
    workflow_input,workflow_starter_user_id,created_by_user_id
  ) VALUES (
    btrim(p_name),p_description,p_target_kind,p_frequency,p_interval_count,
    CASE WHEN p_frequency='weekly' THEN p_weekdays ELSE NULL END,
    CASE WHEN p_frequency='monthly' AND p_monthly_policy='exact_day' THEN p_day_of_month ELSE NULL END,
    CASE WHEN p_frequency='monthly' THEN p_monthly_policy ELSE NULL END,
    COALESCE(p_local_time,'09:00'),p_timezone,p_starts_on,p_ends_on,p_overlap_policy,'active',v_next,
    CASE WHEN p_target_kind='task' THEN p_task_config ELSE '{}'::JSONB END,
    CASE WHEN p_target_kind='workflow' THEN p_workflow_template_id ELSE NULL END,
    CASE WHEN p_target_kind='workflow' THEN p_workflow_version_policy ELSE NULL END,
    v_pinned_version,
    CASE WHEN p_target_kind='workflow' THEN COALESCE(p_workflow_input,'{}'::JSONB) ELSE '{}'::JSONB END,
    CASE WHEN p_target_kind='workflow' THEN v_starter ELSE NULL END,
    v_actor
  ) RETURNING * INTO v_definition;

  v_result:=jsonb_build_object(
    'recurrence_definition_id',v_definition.id,'status',v_definition.status,
    'next_occurrence_at',v_definition.next_occurrence_at,'state_version',v_definition.state_version,
    'workflow_version_policy',v_definition.workflow_version_policy,
    'pinned_workflow_version_id',v_definition.pinned_workflow_version_id
  );
  RETURN private.work_command_success(p_operation_id,'work_create_recurrence',NULL,v_result);
END;
$$;

CREATE OR REPLACE FUNCTION private.work_generate_recurrence_occurrence(
  p_definition_id UUID,
  p_scheduled_for TIMESTAMPTZ
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_definition public.work_recurrence_definitions%ROWTYPE;
  v_occurrence public.work_recurrence_occurrences%ROWTYPE;
  v_existing_work public.work_items%ROWTYPE;
  v_existing_run public.work_workflow_runs%ROWTYPE;
  v_validation JSONB;
  v_owner UUID;
  v_assignee UUID;
  v_priority public.work_priority;
  v_visibility public.work_visibility;
  v_completion_mode public.work_completion_mode;
  v_due_minutes INTEGER;
  v_next_minutes INTEGER;
  v_ack BOOLEAN;
  v_approval_template UUID;
  v_due_at TIMESTAMPTZ;
  v_next_action_at TIMESTAMPTZ;
  v_branch UUID;
  v_department UUID;
  v_item public.work_items%ROWTYPE;
  v_workflow_version UUID;
  v_run_id UUID;
BEGIN
  SELECT * INTO v_definition
  FROM public.work_recurrence_definitions
  WHERE id=p_definition_id
  FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','definition_not_found'); END IF;

  INSERT INTO public.work_recurrence_occurrences(
    recurrence_definition_id,scheduled_for,status
  ) VALUES (v_definition.id,p_scheduled_for,'pending')
  ON CONFLICT (recurrence_definition_id,scheduled_for) DO NOTHING;

  SELECT * INTO v_occurrence
  FROM public.work_recurrence_occurrences
  WHERE recurrence_definition_id=v_definition.id AND scheduled_for=p_scheduled_for
  FOR UPDATE;

  IF v_occurrence.status IN ('generated','overlap','cancelled') THEN
    RETURN jsonb_build_object('status',v_occurrence.status,'occurrence_id',v_occurrence.id,'replayed',true);
  END IF;

  IF v_definition.overlap_policy='single_open' THEN
    IF v_definition.target_kind='task' THEN
      SELECT * INTO v_existing_work
      FROM public.work_items w
      WHERE w.recurrence_definition_id=v_definition.id
        AND w.status NOT IN ('done','cancelled')
      ORDER BY w.created_at,w.id
      LIMIT 1;
      IF FOUND THEN
        UPDATE public.work_recurrence_occurrences
        SET status='overlap',overlap_work_item_id=v_existing_work.id,generated_at=clock_timestamp(),
            error_code=NULL,error_detail=NULL
        WHERE id=v_occurrence.id;
        RETURN jsonb_build_object('status','overlap','occurrence_id',v_occurrence.id,'overlap_work_item_id',v_existing_work.id);
      END IF;
    ELSE
      SELECT r.* INTO v_existing_run
      FROM public.work_workflow_runs r
      JOIN public.work_recurrence_occurrences o ON o.id=r.recurrence_occurrence_id
      WHERE o.recurrence_definition_id=v_definition.id AND r.status='running'
      ORDER BY r.started_at,r.id
      LIMIT 1;
      IF FOUND THEN
        UPDATE public.work_recurrence_occurrences
        SET status='overlap',overlap_workflow_run_id=v_existing_run.id,generated_at=clock_timestamp(),
            error_code=NULL,error_detail=NULL
        WHERE id=v_occurrence.id;
        RETURN jsonb_build_object('status','overlap','occurrence_id',v_occurrence.id,'overlap_workflow_run_id',v_existing_run.id);
      END IF;
    END IF;
  END IF;

  BEGIN
    IF v_definition.target_kind='task' THEN
      v_validation:=private.work_validate_recurrence_task_config(v_definition.created_by_user_id,v_definition.task_config);
      IF NOT COALESCE((v_validation->>'ok')::BOOLEAN,false) THEN
        RAISE EXCEPTION 'invalid recurrence task config: %',COALESCE(v_validation->>'code','invalid');
      END IF;
      v_owner:=(v_validation->>'owner_user_id')::UUID;
      v_assignee:=(v_validation->>'assignee_user_id')::UUID;
      v_priority:=(v_validation->>'priority')::public.work_priority;
      v_visibility:=(v_validation->>'visibility')::public.work_visibility;
      v_completion_mode:=(v_validation->>'completion_mode')::public.work_completion_mode;
      v_due_minutes:=NULLIF(v_validation->>'due_after_minutes','')::INTEGER;
      v_next_minutes:=NULLIF(v_validation->>'next_action_after_minutes','')::INTEGER;
      v_approval_template:=NULLIF(v_validation->>'completion_approval_template_id','')::UUID;
      v_ack:=COALESCE((v_definition.task_config->>'acknowledgement_required')::BOOLEAN,false);
      v_due_at:=CASE WHEN v_due_minutes IS NULL THEN NULL ELSE p_scheduled_for+make_interval(mins=>v_due_minutes) END;
      v_next_action_at:=CASE WHEN v_next_minutes IS NULL THEN NULL ELSE p_scheduled_for+make_interval(mins=>v_next_minutes) END;

      SELECT e.branch_id,e.department_id INTO v_branch,v_department
      FROM public.hr_employees e
      WHERE e.user_id=v_assignee AND e.status::TEXT='active'
      LIMIT 1;

      INSERT INTO public.work_items(
        kind,source_kind,source_key,title,description,expected_outcome,status,priority,visibility,
        creator_user_id,requester_user_id,accountable_owner_user_id,current_assignee_user_id,
        owning_department_id,branch_id,recurrence_definition_id,recurrence_occurrence_id,
        activated_at,assigned_at,due_at,first_due_at,next_action_text,next_action_at,
        acknowledgement_required,completion_mode,completion_approval_template_id,
        last_meaningful_activity_at,state_version
      ) VALUES (
        'task','recurrence','recurrence:'||v_definition.id::TEXT||':'||p_scheduled_for::TEXT,
        v_definition.task_config->>'title',v_definition.task_config->>'description',v_definition.task_config->>'expected_outcome',
        'open',v_priority,v_visibility,v_definition.created_by_user_id,v_definition.created_by_user_id,
        v_owner,v_assignee,v_department,v_branch,v_definition.id,v_occurrence.id,
        clock_timestamp(),clock_timestamp(),v_due_at,v_due_at,v_definition.task_config->>'next_action_text',v_next_action_at,
        v_ack,v_completion_mode,v_approval_template,clock_timestamp(),1
      ) RETURNING * INTO v_item;

      UPDATE public.work_recurrence_occurrences
      SET status='generated',work_item_id=v_item.id,generated_at=clock_timestamp(),error_code=NULL,error_detail=NULL
      WHERE id=v_occurrence.id;
      PERFORM private.work_append_system_event(
        v_item.id,'work.recurrence.generated',NULL,'open',
        jsonb_build_object('recurrence_definition_id',v_definition.id,'occurrence_id',v_occurrence.id,'scheduled_for',p_scheduled_for)
      );
      RETURN jsonb_build_object('status','generated','occurrence_id',v_occurrence.id,'work_item_id',v_item.id);
    END IF;

    IF v_definition.workflow_version_policy='pinned' THEN
      v_workflow_version:=v_definition.pinned_workflow_version_id;
    ELSE
      SELECT current_published_version_id INTO v_workflow_version
      FROM public.work_workflow_templates
      WHERE id=v_definition.workflow_template_id AND is_active=true;
    END IF;
    IF v_workflow_version IS NULL THEN RAISE EXCEPTION 'recurrence workflow version unavailable'; END IF;

    v_run_id:=private.work_start_workflow_version_from_recurrence(
      v_workflow_version,v_definition.workflow_input,v_occurrence.id,v_definition.workflow_starter_user_id
    );
    UPDATE public.work_recurrence_occurrences
    SET status='generated',workflow_run_id=v_run_id,generated_at=clock_timestamp(),error_code=NULL,error_detail=NULL
    WHERE id=v_occurrence.id;
    RETURN jsonb_build_object('status','generated','occurrence_id',v_occurrence.id,'workflow_run_id',v_run_id,'workflow_version_id',v_workflow_version);
  EXCEPTION WHEN OTHERS THEN
    UPDATE public.work_recurrence_occurrences
    SET status='failed',generated_at=clock_timestamp(),error_code='GENERATION_FAILED',error_detail=left(SQLERRM,2000)
    WHERE id=v_occurrence.id;
    RETURN jsonb_build_object('status','failed','occurrence_id',v_occurrence.id,'error_code','GENERATION_FAILED');
  END;
END;
$$;

CREATE OR REPLACE FUNCTION private.work_generate_due_recurrences(
  p_now TIMESTAMPTZ DEFAULT now(),
  p_max_occurrences INTEGER DEFAULT 200
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_definition public.work_recurrence_definitions%ROWTYPE;
  v_scheduled TIMESTAMPTZ;
  v_next TIMESTAMPTZ;
  v_result JSONB;
  v_generated INTEGER:=0;
  v_overlaps INTEGER:=0;
  v_failed INTEGER:=0;
  v_processed INTEGER:=0;
BEGIN
  IF p_max_occurrences<1 OR p_max_occurrences>1000 THEN p_max_occurrences:=200; END IF;

  LOOP
    EXIT WHEN v_processed>=p_max_occurrences;
    SELECT * INTO v_definition
    FROM public.work_recurrence_definitions
    WHERE status='active' AND next_occurrence_at<=p_now
    ORDER BY next_occurrence_at,id
    FOR UPDATE SKIP LOCKED
    LIMIT 1;
    EXIT WHEN NOT FOUND;

    v_scheduled:=v_definition.next_occurrence_at;
    v_result:=private.work_generate_recurrence_occurrence(v_definition.id,v_scheduled);
    v_processed:=v_processed+1;
    IF v_result->>'status'='generated' THEN v_generated:=v_generated+1;
    ELSIF v_result->>'status'='overlap' THEN v_overlaps:=v_overlaps+1;
    ELSIF v_result->>'status'='failed' THEN v_failed:=v_failed+1;
    END IF;

    v_next:=private.work_recurrence_next_occurrence_at(
      v_definition.frequency,v_definition.interval_count,v_definition.starts_on,v_definition.ends_on,
      v_definition.weekdays,v_definition.day_of_month,v_definition.monthly_policy,
      v_definition.local_time,v_definition.timezone,v_scheduled
    );

    IF v_next IS NULL THEN
      UPDATE public.work_recurrence_definitions
      SET status='stopped',stopped_at=clock_timestamp(),next_occurrence_at=v_scheduled,
          state_version=state_version+1
      WHERE id=v_definition.id;
    ELSE
      UPDATE public.work_recurrence_definitions
      SET next_occurrence_at=v_next,state_version=state_version+1
      WHERE id=v_definition.id;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'processed',v_processed,'generated',v_generated,'overlaps',v_overlaps,'failed',v_failed
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.work_set_recurrence_state(
  p_operation_id UUID,
  p_definition_id UUID,
  p_expected_version BIGINT,
  p_action TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_definition public.work_recurrence_definitions%ROWTYPE;
  v_next TIMESTAMPTZ;
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_set_recurrence_state',
    jsonb_build_object('definition_id',p_definition_id,'expected_version',p_expected_version,'action',p_action),NULL
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  IF NOT COALESCE(public.check_permission(v_actor,'work.recurrence.manage'),false) THEN
    RETURN private.work_command_error(p_operation_id,'work_set_recurrence_state','FORBIDDEN','لا تملك صلاحية إدارة الأعمال الدورية');
  END IF;

  SELECT * INTO v_definition
  FROM public.work_recurrence_definitions
  WHERE id=p_definition_id
  FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_set_recurrence_state','NOT_FOUND','تعريف التكرار غير موجود'); END IF;
  IF v_definition.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_set_recurrence_state','VERSION_CONFLICT','تم تعديل تعريف التكرار بواسطة مستخدم آخر'); END IF;
  IF p_action NOT IN ('pause','resume','stop') THEN RETURN private.work_command_error(p_operation_id,'work_set_recurrence_state','INVALID_ACTION','إجراء التكرار غير صحيح'); END IF;

  IF p_action='pause' THEN
    IF v_definition.status<>'active' THEN RETURN private.work_command_error(p_operation_id,'work_set_recurrence_state','INVALID_STATE','يمكن إيقاف تعريف نشط مؤقتًا فقط'); END IF;
    UPDATE public.work_recurrence_definitions
    SET status='paused',paused_at=clock_timestamp(),paused_by_user_id=v_actor,state_version=state_version+1
    WHERE id=p_definition_id RETURNING * INTO v_definition;
  ELSIF p_action='resume' THEN
    IF v_definition.status<>'paused' THEN RETURN private.work_command_error(p_operation_id,'work_set_recurrence_state','INVALID_STATE','يمكن استئناف تعريف موقوف مؤقتًا فقط'); END IF;
    v_next:=private.work_recurrence_next_occurrence_at(
      v_definition.frequency,v_definition.interval_count,v_definition.starts_on,v_definition.ends_on,
      v_definition.weekdays,v_definition.day_of_month,v_definition.monthly_policy,
      v_definition.local_time,v_definition.timezone,clock_timestamp()-interval '1 millisecond'
    );
    IF v_next IS NULL THEN RETURN private.work_command_error(p_operation_id,'work_set_recurrence_state','NO_FUTURE_OCCURRENCE','لا يوجد موعد قادم ضمن فترة التكرار'); END IF;
    UPDATE public.work_recurrence_definitions
    SET status='active',next_occurrence_at=v_next,paused_at=NULL,paused_by_user_id=NULL,state_version=state_version+1
    WHERE id=p_definition_id RETURNING * INTO v_definition;
  ELSE
    IF v_definition.status='stopped' THEN RETURN private.work_command_error(p_operation_id,'work_set_recurrence_state','INVALID_STATE','تعريف التكرار متوقف بالفعل'); END IF;
    UPDATE public.work_recurrence_definitions
    SET status='stopped',stopped_at=clock_timestamp(),stopped_by_user_id=v_actor,state_version=state_version+1
    WHERE id=p_definition_id RETURNING * INTO v_definition;
  END IF;

  v_result:=jsonb_build_object(
    'recurrence_definition_id',v_definition.id,'status',v_definition.status,
    'next_occurrence_at',v_definition.next_occurrence_at,'state_version',v_definition.state_version
  );
  RETURN private.work_command_success(p_operation_id,'work_set_recurrence_state',NULL,v_result);
END;
$$;

CREATE OR REPLACE VIEW public.work_recurrence_compliance
WITH (security_invoker=true)
AS
SELECT
  d.id AS recurrence_definition_id,
  d.name,
  d.target_kind,
  d.frequency,
  d.overlap_policy,
  d.status,
  d.next_occurrence_at,
  count(o.id) AS occurrence_count,
  count(o.id) FILTER (WHERE o.status='generated') AS generated_count,
  count(o.id) FILTER (WHERE o.status='overlap') AS overlap_count,
  count(o.id) FILTER (WHERE o.status='failed') AS failed_count,
  max(o.scheduled_for) AS last_scheduled_for,
  max(o.generated_at) AS last_generated_at
FROM public.work_recurrence_definitions d
LEFT JOIN public.work_recurrence_occurrences o ON o.recurrence_definition_id=d.id
GROUP BY d.id,d.name,d.target_kind,d.frequency,d.overlap_policy,d.status,d.next_occurrence_at;
GRANT SELECT ON public.work_recurrence_compliance TO authenticated;

REVOKE ALL ON FUNCTION private.work_start_workflow_version_from_recurrence(UUID,JSONB,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_validate_recurrence_task_config(UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_generate_recurrence_occurrence(UUID,TIMESTAMPTZ) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_generate_due_recurrences(TIMESTAMPTZ,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.work_create_recurrence(UUID,TEXT,TEXT,public.work_recurrence_target_kind,public.work_recurrence_frequency,INTEGER,TIME,TEXT,DATE,DATE,SMALLINT[],SMALLINT,public.work_recurrence_monthly_policy,public.work_recurrence_overlap_policy,JSONB,UUID,public.work_recurrence_workflow_version_policy,JSONB,UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_set_recurrence_state(UUID,UUID,BIGINT,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.work_create_recurrence(UUID,TEXT,TEXT,public.work_recurrence_target_kind,public.work_recurrence_frequency,INTEGER,TIME,TEXT,DATE,DATE,SMALLINT[],SMALLINT,public.work_recurrence_monthly_policy,public.work_recurrence_overlap_policy,JSONB,UUID,public.work_recurrence_workflow_version_policy,JSONB,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_set_recurrence_state(UUID,UUID,BIGINT,TEXT) TO authenticated;

RESET lock_timeout;
RESET statement_timeout;
