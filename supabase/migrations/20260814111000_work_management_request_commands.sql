-- Work Management — atomic Request / Queue runtime commands.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION private.work_validate_intake_payload(
  p_schema JSONB,
  p_payload JSONB
) RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
SET search_path=''
AS $$
DECLARE
  v_field JSONB;
  v_key TEXT;
  v_type TEXT;
  v_required BOOLEAN;
  v_value JSONB;
BEGIN
  IF jsonb_typeof(COALESCE(p_schema,'{}'::JSONB)) <> 'object'
     OR jsonb_typeof(COALESCE(p_schema->'fields','[]'::JSONB)) <> 'array' THEN
    RETURN jsonb_build_object('ok',false,'code','INVALID_INTAKE_SCHEMA','message','تعريف نموذج الطلب غير صالح');
  END IF;
  IF jsonb_typeof(COALESCE(p_payload,'{}'::JSONB)) <> 'object' THEN
    RETURN jsonb_build_object('ok',false,'code','INVALID_INTAKE_PAYLOAD','message','بيانات الطلب يجب أن تكون كائن بيانات');
  END IF;

  FOR v_field IN SELECT value FROM jsonb_array_elements(p_schema->'fields') LOOP
    v_key:=NULLIF(btrim(v_field->>'key'),'');
    v_type:=COALESCE(NULLIF(btrim(v_field->>'type'),''),'string');
    v_required:=COALESCE((v_field->>'required')::BOOLEAN,false);
    IF v_key IS NULL THEN
      RETURN jsonb_build_object('ok',false,'code','INVALID_INTAKE_SCHEMA','message','أحد حقول نموذج الطلب بلا مفتاح');
    END IF;

    IF NOT (p_payload ? v_key) OR p_payload->v_key='null'::JSONB THEN
      IF v_required THEN
        RETURN jsonb_build_object('ok',false,'code','REQUIRED_FIELD_MISSING','message','حقل مطلوب غير مستكمل','field',v_key);
      END IF;
      CONTINUE;
    END IF;

    v_value:=p_payload->v_key;
    IF v_type IN ('string','number','boolean','array','object')
       AND jsonb_typeof(v_value) <> v_type THEN
      RETURN jsonb_build_object('ok',false,'code','INVALID_FIELD_TYPE','message','نوع بيانات أحد الحقول غير صحيح','field',v_key,'expected_type',v_type);
    END IF;
  END LOOP;

  RETURN jsonb_build_object('ok',true);
EXCEPTION WHEN invalid_text_representation THEN
  RETURN jsonb_build_object('ok',false,'code','INVALID_INTAKE_SCHEMA','message','تعريف أحد حقول نموذج الطلب غير صالح');
END;
$$;

CREATE OR REPLACE FUNCTION public.work_resolve_assignment_route(
  p_target_user_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_branch UUID;
  v_department UUID;
  v_types JSONB;
BEGIN
  IF NOT private.work_actor_is_active(v_actor) OR NOT private.work_actor_is_active(p_target_user_id) THEN
    RETURN jsonb_build_object('direct_allowed',false,'request_required',true,'reason','inactive_actor_or_target','request_types','[]'::JSONB);
  END IF;

  SELECT e.branch_id,e.department_id INTO v_branch,v_department
  FROM public.hr_employees e
  WHERE e.user_id=p_target_user_id AND e.status::TEXT='active'
  LIMIT 1;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'request_type_id',rt.id,'code',rt.code,'name',rt.name,'queue_id',rt.target_queue_id
  ) ORDER BY rt.name),'[]'::JSONB)
  INTO v_types
  FROM public.work_request_types rt
  JOIN public.work_queues q ON q.id=rt.target_queue_id
  WHERE rt.is_active=true AND q.is_active=true
    AND (rt.target_department_id IS NULL OR rt.target_department_id=v_department);

  RETURN jsonb_build_object(
    'direct_allowed',private.work_user_can_assign_target(v_actor,p_target_user_id),
    'request_required',NOT private.work_user_can_assign_target(v_actor,p_target_user_id),
    'target_branch_id',v_branch,
    'target_department_id',v_department,
    'request_types',COALESCE(v_types,'[]'::JSONB)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.work_submit_request(
  p_operation_id UUID,
  p_request_type_id UUID,
  p_title TEXT,
  p_description TEXT DEFAULT NULL,
  p_expected_outcome TEXT DEFAULT NULL,
  p_intake_payload JSONB DEFAULT '{}'::JSONB,
  p_priority public.work_priority DEFAULT NULL,
  p_visibility public.work_visibility DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_type public.work_request_types%ROWTYPE;
  v_queue public.work_queues%ROWTYPE;
  v_validation JSONB;
  v_item public.work_items%ROWTYPE;
  v_source_branch UUID;
  v_source_department UUID;
  v_now TIMESTAMPTZ:=clock_timestamp();
  v_triage_minutes INTEGER;
  v_resolution_minutes INTEGER;
  v_triage_due TIMESTAMPTZ;
  v_due_at TIMESTAMPTZ;
  v_outcome TEXT;
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_submit_request',
    jsonb_build_object(
      'request_type_id',p_request_type_id,'title',p_title,'description',p_description,
      'expected_outcome',p_expected_outcome,'intake_payload',COALESCE(p_intake_payload,'{}'::JSONB),
      'priority',p_priority,'visibility',p_visibility
    ),NULL
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  IF NOT COALESCE(public.check_permission(v_actor,'work.requests.create'),false) THEN
    RETURN private.work_command_error(p_operation_id,'work_submit_request','FORBIDDEN','لا تملك صلاحية إرسال طلب');
  END IF;
  IF p_title IS NULL OR btrim(p_title)='' THEN
    RETURN private.work_command_error(p_operation_id,'work_submit_request','VALIDATION_ERROR','عنوان الطلب مطلوب');
  END IF;

  SELECT * INTO v_type FROM public.work_request_types WHERE id=p_request_type_id;
  IF NOT FOUND OR NOT v_type.is_active THEN
    RETURN private.work_command_error(p_operation_id,'work_submit_request','REQUEST_TYPE_UNAVAILABLE','نوع الطلب غير متاح');
  END IF;
  SELECT * INTO v_queue FROM public.work_queues WHERE id=v_type.target_queue_id;
  IF NOT FOUND OR NOT v_queue.is_active THEN
    RETURN private.work_command_error(p_operation_id,'work_submit_request','QUEUE_UNAVAILABLE','جهة استقبال الطلب غير متاحة');
  END IF;
  IF NOT private.work_actor_is_active(v_queue.manager_user_id) THEN
    RETURN private.work_command_error(p_operation_id,'work_submit_request','QUEUE_MANAGER_UNAVAILABLE','لا يوجد مسؤول نشط لجهة استقبال الطلب');
  END IF;

  v_validation:=private.work_validate_intake_payload(v_type.intake_schema,COALESCE(p_intake_payload,'{}'::JSONB));
  IF NOT COALESCE((v_validation->>'ok')::BOOLEAN,false) THEN
    RETURN private.work_command_error(
      p_operation_id,'work_submit_request',COALESCE(v_validation->>'code','INVALID_INTAKE_PAYLOAD'),
      COALESCE(v_validation->>'message','بيانات الطلب غير صالحة') ||
      CASE WHEN v_validation ? 'field' THEN ' ('||(v_validation->>'field')||')' ELSE '' END
    );
  END IF;

  SELECT e.branch_id,e.department_id INTO v_source_branch,v_source_department
  FROM public.hr_employees e
  WHERE e.user_id=v_actor AND e.status::TEXT='active'
  LIMIT 1;

  v_triage_minutes:=COALESCE(v_type.triage_sla_minutes,v_queue.default_triage_sla_minutes);
  v_resolution_minutes:=COALESCE(v_type.default_resolution_sla_minutes,v_queue.default_resolution_sla_minutes);
  v_triage_due:=v_now + make_interval(mins=>v_triage_minutes);
  v_due_at:=CASE WHEN v_resolution_minutes IS NULL THEN NULL ELSE v_now+make_interval(mins=>v_resolution_minutes) END;
  v_outcome:=COALESCE(NULLIF(btrim(p_expected_outcome),''),v_type.expected_outcome_template);

  BEGIN
    INSERT INTO public.work_items(
      kind,source_kind,title,description,expected_outcome,status,priority,visibility,
      creator_user_id,requester_user_id,accountable_owner_user_id,current_assignee_user_id,
      source_department_id,owning_department_id,branch_id,queue_id,request_type_id,
      activated_at,due_at,first_due_at,next_action_text,next_action_at,
      completion_mode,last_meaningful_activity_at,state_version
    ) VALUES (
      'request','request_intake',p_title,p_description,v_outcome,'open',
      COALESCE(p_priority,v_type.default_priority,v_queue.default_priority),
      COALESCE(p_visibility,v_type.default_visibility),
      v_actor,v_actor,v_queue.manager_user_id,NULL,
      v_source_department,COALESCE(v_type.target_department_id,v_queue.department_id),v_queue.branch_id,
      v_queue.id,v_type.id,v_now,v_due_at,v_due_at,
      'فرز الطلب وتحديد المسؤول',v_triage_due,'assignee_closes',v_now,1
    ) RETURNING * INTO v_item;

    INSERT INTO public.work_requests(
      work_item_id,request_type_id,queue_id,intake_payload,submitted_at,triage_due_at
    ) VALUES (
      v_item.id,v_type.id,v_queue.id,COALESCE(p_intake_payload,'{}'::JSONB),v_now,v_triage_due
    );

    PERFORM private.work_append_user_event(
      v_item.id,'work.request.submitted',v_actor,p_operation_id,NULL,'open'::public.work_item_status,
      jsonb_build_object('request_type_id',v_type.id,'queue_id',v_queue.id,'triage_due_at',v_triage_due)
    );

    v_result:=jsonb_build_object(
      'work_item_id',v_item.id,'work_number',v_item.work_number,'status',v_item.status,
      'state_version',v_item.state_version,'queue_id',v_queue.id,'request_type_id',v_type.id,
      'triage_due_at',v_triage_due,'due_at',v_due_at
    );
    RETURN private.work_command_success(p_operation_id,'work_submit_request',v_item.id,v_result);
  EXCEPTION WHEN OTHERS THEN
    RETURN private.work_command_error(p_operation_id,'work_submit_request','INTERNAL_ERROR','تعذر إرسال الطلب');
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.work_triage_request(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_decision TEXT,
  p_assignee_user_id UUID DEFAULT NULL,
  p_owner_user_id UUID DEFAULT NULL,
  p_due_at TIMESTAMPTZ DEFAULT NULL,
  p_next_action_text VARCHAR(500) DEFAULT NULL,
  p_follow_up_at TIMESTAMPTZ DEFAULT NULL,
  p_note TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_request public.work_requests%ROWTYPE;
  v_queue public.work_queues%ROWTYPE;
  v_owner UUID;
  v_now TIMESTAMPTZ:=clock_timestamp();
  v_from public.work_item_status;
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_triage_request',
    jsonb_build_object(
      'work_item_id',p_work_item_id,'expected_version',p_expected_version,'decision',p_decision,
      'assignee_user_id',p_assignee_user_id,'owner_user_id',p_owner_user_id,'due_at',p_due_at,
      'next_action_text',p_next_action_text,'follow_up_at',p_follow_up_at,'note',p_note
    ),p_work_item_id
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id FOR UPDATE;
  IF NOT FOUND OR v_item.kind<>'request'::public.work_item_kind THEN
    RETURN private.work_command_error(p_operation_id,'work_triage_request','NOT_FOUND','الطلب غير موجود',p_work_item_id);
  END IF;
  SELECT * INTO v_request FROM public.work_requests WHERE work_item_id=p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN private.work_command_error(p_operation_id,'work_triage_request','REQUEST_RUNTIME_MISSING','بيانات تشغيل الطلب غير موجودة',p_work_item_id);
  END IF;
  SELECT * INTO v_queue FROM public.work_queues WHERE id=v_request.queue_id;

  IF v_item.state_version<>p_expected_version THEN
    RETURN private.work_command_error(p_operation_id,'work_triage_request','VERSION_CONFLICT','تم تعديل الطلب بواسطة مستخدم آخر',p_work_item_id);
  END IF;
  IF NOT private.work_user_can_triage_queue(v_actor,v_request.queue_id) THEN
    RETURN private.work_command_error(p_operation_id,'work_triage_request','FORBIDDEN','غير مصرح لك بفرز هذا الطلب',p_work_item_id);
  END IF;
  IF v_request.triaged_at IS NOT NULL THEN
    RETURN private.work_command_error(p_operation_id,'work_triage_request','ALREADY_TRIAGED','تم فرز هذا الطلب بالفعل',p_work_item_id);
  END IF;
  IF p_decision NOT IN ('accept','needs_information','reject') THEN
    RETURN private.work_command_error(p_operation_id,'work_triage_request','INVALID_DECISION','قرار الفرز غير صحيح',p_work_item_id);
  END IF;

  v_from:=v_item.status;
  UPDATE public.work_requests
  SET first_responded_at=COALESCE(first_responded_at,v_now)
  WHERE work_item_id=p_work_item_id
  RETURNING * INTO v_request;

  IF p_decision='needs_information' THEN
    IF p_note IS NULL OR btrim(p_note)='' OR p_follow_up_at IS NULL THEN
      RETURN private.work_command_error(p_operation_id,'work_triage_request','FOLLOW_UP_REQUIRED','وضح المعلومات المطلوبة وحدد موعد المتابعة',p_work_item_id);
    END IF;
    IF NOT private.work_actor_is_active(v_item.requester_user_id) THEN
      RETURN private.work_command_error(p_operation_id,'work_triage_request','REQUESTER_UNAVAILABLE','مقدم الطلب غير نشط',p_work_item_id);
    END IF;

    UPDATE public.work_requests
    SET information_request_note=p_note
    WHERE work_item_id=p_work_item_id;

    UPDATE public.work_items
    SET status='waiting',waiting_on_type='user',waiting_on_user_id=requester_user_id,
        waiting_on_label='مقدم الطلب',waiting_reason=p_note,waiting_since=v_now,
        next_action_text=left('استكمال المعلومات المطلوبة: '||p_note,500),next_action_at=p_follow_up_at,
        state_version=state_version+1,last_meaningful_activity_at=v_now
    WHERE id=p_work_item_id RETURNING * INTO v_item;

    PERFORM private.work_append_user_event(
      v_item.id,'work.request.information_required',v_actor,p_operation_id,v_from,'waiting'::public.work_item_status,
      jsonb_build_object('note',p_note,'follow_up_at',p_follow_up_at)
    );

  ELSIF p_decision='reject' THEN
    IF p_note IS NULL OR btrim(p_note)='' THEN
      RETURN private.work_command_error(p_operation_id,'work_triage_request','REJECTION_REASON_REQUIRED','سبب رفض الطلب مطلوب',p_work_item_id);
    END IF;

    UPDATE public.work_requests
    SET triaged_at=v_now,triaged_by_user_id=v_actor,triage_outcome='rejected',rejection_reason=p_note
    WHERE work_item_id=p_work_item_id;

    UPDATE public.work_items
    SET status='cancelled',cancelled_at=v_now,next_action_text=NULL,next_action_at=NULL,
        waiting_on_type=NULL,waiting_on_user_id=NULL,waiting_on_label=NULL,waiting_reason=NULL,waiting_since=NULL,
        state_version=state_version+1,last_meaningful_activity_at=v_now
    WHERE id=p_work_item_id RETURNING * INTO v_item;

    PERFORM private.work_append_user_event(
      v_item.id,'work.request.rejected',v_actor,p_operation_id,v_from,'cancelled'::public.work_item_status,
      jsonb_build_object('reason',p_note)
    );

  ELSE
    IF p_assignee_user_id IS NULL OR p_next_action_text IS NULL OR btrim(p_next_action_text)='' THEN
      RETURN private.work_command_error(p_operation_id,'work_triage_request','ASSIGNMENT_REQUIRED','حدد المسؤول والإجراء التالي لقبول الطلب',p_work_item_id);
    END IF;
    IF NOT private.work_user_can_assign_queue(v_actor,v_request.queue_id) THEN
      RETURN private.work_command_error(p_operation_id,'work_triage_request','QUEUE_ASSIGN_DENIED','لا تملك صلاحية الإسناد داخل جهة الاستقبال',p_work_item_id);
    END IF;
    IF NOT private.work_queue_assignment_target_allowed(v_request.queue_id,p_assignee_user_id) THEN
      RETURN private.work_command_error(p_operation_id,'work_triage_request','INVALID_QUEUE_ASSIGNEE','المستخدم المحدد ليس مسؤولاً نشطًا داخل جهة الاستقبال',p_work_item_id);
    END IF;
    v_owner:=COALESCE(p_owner_user_id,v_queue.manager_user_id);
    IF NOT private.work_actor_is_active(v_owner) THEN
      RETURN private.work_command_error(p_operation_id,'work_triage_request','OWNER_UNAVAILABLE','المالك المسؤول غير نشط',p_work_item_id);
    END IF;
    IF v_owner<>v_queue.manager_user_id AND NOT private.work_queue_assignment_target_allowed(v_request.queue_id,v_owner) THEN
      RETURN private.work_command_error(p_operation_id,'work_triage_request','INVALID_QUEUE_OWNER','المالك المحدد خارج جهة الاستقبال',p_work_item_id);
    END IF;

    UPDATE public.work_requests
    SET triaged_at=v_now,triaged_by_user_id=v_actor,triage_outcome='accepted',information_request_note=NULL
    WHERE work_item_id=p_work_item_id;

    UPDATE public.work_items
    SET status='open',accountable_owner_user_id=v_owner,current_assignee_user_id=p_assignee_user_id,
        assigned_at=v_now,due_at=COALESCE(p_due_at,due_at),first_due_at=COALESCE(first_due_at,p_due_at),
        next_action_text=p_next_action_text,next_action_at=p_follow_up_at,
        waiting_on_type=NULL,waiting_on_user_id=NULL,waiting_on_entity_type=NULL,waiting_on_entity_id=NULL,
        waiting_on_label=NULL,waiting_reason=NULL,waiting_since=NULL,
        state_version=state_version+1,last_meaningful_activity_at=v_now
    WHERE id=p_work_item_id RETURNING * INTO v_item;

    PERFORM private.work_append_user_event(
      v_item.id,'work.request.accepted',v_actor,p_operation_id,v_from,'open'::public.work_item_status,
      jsonb_build_object('assignee_user_id',p_assignee_user_id,'owner_user_id',v_owner,'due_at',v_item.due_at)
    );
  END IF;

  v_result:=jsonb_build_object(
    'work_item_id',v_item.id,'status',v_item.status,'state_version',v_item.state_version,
    'decision',p_decision,'first_responded_at',v_request.first_responded_at,
    'triaged_at',(SELECT triaged_at FROM public.work_requests WHERE work_item_id=p_work_item_id)
  );
  RETURN private.work_command_success(p_operation_id,'work_triage_request',v_item.id,v_result);
END;
$$;

CREATE OR REPLACE FUNCTION public.work_cancel_own_request(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_version BIGINT,
  p_reason TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_request public.work_requests%ROWTYPE;
  v_type public.work_request_types%ROWTYPE;
  v_from public.work_item_status;
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_cancel_own_request',
    jsonb_build_object('work_item_id',p_work_item_id,'expected_version',p_expected_version,'reason',p_reason),p_work_item_id
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id=p_work_item_id FOR UPDATE;
  SELECT * INTO v_request FROM public.work_requests WHERE work_item_id=p_work_item_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_cancel_own_request','NOT_FOUND','الطلب غير موجود',p_work_item_id); END IF;
  SELECT * INTO v_type FROM public.work_request_types WHERE id=v_request.request_type_id;

  IF v_item.state_version<>p_expected_version THEN RETURN private.work_command_error(p_operation_id,'work_cancel_own_request','VERSION_CONFLICT','تم تعديل الطلب بواسطة مستخدم آخر',p_work_item_id); END IF;
  IF v_item.requester_user_id<>v_actor THEN RETURN private.work_command_error(p_operation_id,'work_cancel_own_request','FORBIDDEN','لا يمكنك إلغاء طلب مستخدم آخر',p_work_item_id); END IF;
  IF NOT v_type.allow_requester_cancel THEN RETURN private.work_command_error(p_operation_id,'work_cancel_own_request','CANCELLATION_NOT_ALLOWED','نوع الطلب لا يسمح بالإلغاء الذاتي',p_work_item_id); END IF;
  IF v_request.triaged_at IS NOT NULL OR v_item.status IN ('done','cancelled') THEN RETURN private.work_command_error(p_operation_id,'work_cancel_own_request','INVALID_STATE','لا يمكن إلغاء الطلب بعد اعتماده للتنفيذ أو إغلاقه',p_work_item_id); END IF;
  IF p_reason IS NULL OR btrim(p_reason)='' THEN RETURN private.work_command_error(p_operation_id,'work_cancel_own_request','REASON_REQUIRED','سبب الإلغاء مطلوب',p_work_item_id); END IF;

  v_from:=v_item.status;
  UPDATE public.work_items
  SET status='cancelled',cancelled_at=clock_timestamp(),next_action_text=NULL,next_action_at=NULL,
      state_version=state_version+1,last_meaningful_activity_at=clock_timestamp()
  WHERE id=p_work_item_id RETURNING * INTO v_item;

  PERFORM private.work_append_user_event(
    v_item.id,'work.request.cancelled_by_requester',v_actor,p_operation_id,v_from,'cancelled'::public.work_item_status,
    jsonb_build_object('reason',p_reason)
  );
  v_result:=jsonb_build_object('work_item_id',v_item.id,'status',v_item.status,'state_version',v_item.state_version);
  RETURN private.work_command_success(p_operation_id,'work_cancel_own_request',v_item.id,v_result);
END;
$$;

REVOKE ALL ON FUNCTION private.work_validate_intake_payload(JSONB,JSONB) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.work_resolve_assignment_route(UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_submit_request(UUID,UUID,TEXT,TEXT,TEXT,JSONB,public.work_priority,public.work_visibility) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_triage_request(UUID,UUID,BIGINT,TEXT,UUID,UUID,TIMESTAMPTZ,VARCHAR,TIMESTAMPTZ,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_cancel_own_request(UUID,UUID,BIGINT,TEXT) FROM PUBLIC,anon;

GRANT EXECUTE ON FUNCTION public.work_resolve_assignment_route(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_submit_request(UUID,UUID,TEXT,TEXT,TEXT,JSONB,public.work_priority,public.work_visibility) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_triage_request(UUID,UUID,BIGINT,TEXT,UUID,UUID,TIMESTAMPTZ,VARCHAR,TIMESTAMPTZ,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_cancel_own_request(UUID,UUID,BIGINT,TEXT) TO authenticated;

RESET lock_timeout;
RESET statement_timeout;
