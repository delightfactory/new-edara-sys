-- Work Management — atomic Queue / Request Type authoring.
-- Configuration writes are versioned and never performed directly by browser clients.
SET lock_timeout='5s';
SET statement_timeout='60s';

ALTER TABLE public.work_queues
  ADD COLUMN IF NOT EXISTS state_version BIGINT NOT NULL DEFAULT 1;

ALTER TABLE public.work_request_types
  ADD COLUMN IF NOT EXISTS state_version BIGINT NOT NULL DEFAULT 1;

CREATE OR REPLACE FUNCTION private.work_validate_intake_schema_definition(
  p_schema JSONB
) RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
SET search_path=''
AS $$
DECLARE
  v_field JSONB;
  v_key TEXT;
  v_type TEXT;
  v_seen TEXT[]:=ARRAY[]::TEXT[];
BEGIN
  IF jsonb_typeof(COALESCE(p_schema,'{}'::JSONB))<>'object'
     OR jsonb_typeof(p_schema->'version')<>'number'
     OR jsonb_typeof(COALESCE(p_schema->'fields','[]'::JSONB))<>'array' THEN
    RETURN jsonb_build_object('ok',false,'code','INVALID_INTAKE_SCHEMA','message','تعريف نموذج الطلب غير صالح');
  END IF;

  FOR v_field IN SELECT value FROM jsonb_array_elements(p_schema->'fields') LOOP
    IF jsonb_typeof(v_field)<>'object' THEN
      RETURN jsonb_build_object('ok',false,'code','INVALID_INTAKE_SCHEMA','message','كل حقل في نموذج الطلب يجب أن يكون كائن بيانات');
    END IF;

    v_key:=NULLIF(btrim(v_field->>'key'),'');
    v_type:=COALESCE(NULLIF(btrim(v_field->>'type'),''),'string');

    IF v_key IS NULL OR v_key !~ '^[A-Za-z][A-Za-z0-9_]{0,63}$' THEN
      RETURN jsonb_build_object('ok',false,'code','INVALID_FIELD_KEY','message','مفتاح أحد حقول الطلب غير صالح');
    END IF;
    IF v_key=ANY(v_seen) THEN
      RETURN jsonb_build_object('ok',false,'code','DUPLICATE_FIELD_KEY','message','يوجد مفتاح مكرر في نموذج الطلب','field',v_key);
    END IF;
    v_seen:=array_append(v_seen,v_key);

    IF v_type NOT IN ('string','number','boolean','array','object') THEN
      RETURN jsonb_build_object('ok',false,'code','INVALID_FIELD_TYPE','message','نوع أحد حقول الطلب غير مدعوم','field',v_key);
    END IF;

    IF v_field ? 'required' AND jsonb_typeof(v_field->'required')<>'boolean' THEN
      RETURN jsonb_build_object('ok',false,'code','INVALID_REQUIRED_FLAG','message','قيمة required يجب أن تكون منطقية','field',v_key);
    END IF;
  END LOOP;

  RETURN jsonb_build_object('ok',true);
END;
$$;

CREATE OR REPLACE FUNCTION public.work_create_queue(
  p_operation_id UUID,
  p_code TEXT,
  p_name TEXT,
  p_description TEXT,
  p_manager_user_id UUID,
  p_branch_id UUID DEFAULT NULL,
  p_department_id UUID DEFAULT NULL,
  p_default_priority public.work_priority DEFAULT 'normal',
  p_default_triage_sla_minutes INTEGER DEFAULT 240,
  p_default_resolution_sla_minutes INTEGER DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_queue public.work_queues%ROWTYPE;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_create_queue',
    jsonb_build_object(
      'code',p_code,'name',p_name,'description',p_description,'manager_user_id',p_manager_user_id,
      'branch_id',p_branch_id,'department_id',p_department_id,'default_priority',p_default_priority,
      'default_triage_sla_minutes',p_default_triage_sla_minutes,
      'default_resolution_sla_minutes',p_default_resolution_sla_minutes
    ),NULL
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  IF NOT private.work_actor_is_active(v_actor)
     OR NOT COALESCE(public.check_permission(v_actor,'work.queues.manage'),false) THEN
    RETURN private.work_command_error(p_operation_id,'work_create_queue','FORBIDDEN','لا تملك صلاحية إدارة طوابير العمل');
  END IF;
  IF p_code IS NULL OR btrim(p_code) !~ '^[A-Za-z0-9][A-Za-z0-9._-]{1,49}$' THEN
    RETURN private.work_command_error(p_operation_id,'work_create_queue','INVALID_CODE','كود الطابور غير صالح');
  END IF;
  IF p_name IS NULL OR btrim(p_name)='' THEN
    RETURN private.work_command_error(p_operation_id,'work_create_queue','NAME_REQUIRED','اسم الطابور مطلوب');
  END IF;
  IF NOT private.work_actor_is_active(p_manager_user_id) THEN
    RETURN private.work_command_error(p_operation_id,'work_create_queue','INVALID_MANAGER','مسؤول الطابور يجب أن يكون مستخدمًا نشطًا');
  END IF;
  IF p_default_triage_sla_minutes IS NULL OR p_default_triage_sla_minutes<=0
     OR (p_default_resolution_sla_minutes IS NOT NULL AND p_default_resolution_sla_minutes<=0) THEN
    RETURN private.work_command_error(p_operation_id,'work_create_queue','INVALID_SLA','قيم SLA يجب أن تكون موجبة');
  END IF;

  BEGIN
    INSERT INTO public.work_queues(
      code,name,description,branch_id,department_id,manager_user_id,default_priority,
      default_triage_sla_minutes,default_resolution_sla_minutes,is_active,created_by_user_id,state_version
    ) VALUES (
      lower(btrim(p_code)),btrim(p_name),NULLIF(btrim(COALESCE(p_description,'')),''),
      p_branch_id,p_department_id,p_manager_user_id,COALESCE(p_default_priority,'normal'),
      p_default_triage_sla_minutes,p_default_resolution_sla_minutes,true,v_actor,1
    ) RETURNING * INTO v_queue;

    RETURN private.work_command_success(
      p_operation_id,'work_create_queue',NULL,
      jsonb_build_object('queue_id',v_queue.id,'code',v_queue.code,'state_version',v_queue.state_version)
    );
  EXCEPTION WHEN foreign_key_violation THEN
    RETURN private.work_command_error(p_operation_id,'work_create_queue','INVALID_SCOPE','الفرع أو الإدارة المحددة غير موجودة');
  WHEN unique_violation THEN
    RETURN private.work_command_error(p_operation_id,'work_create_queue','DUPLICATE_CODE','كود الطابور مستخدم بالفعل');
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.work_update_queue(
  p_operation_id UUID,
  p_queue_id UUID,
  p_expected_version BIGINT,
  p_name TEXT,
  p_description TEXT,
  p_manager_user_id UUID,
  p_branch_id UUID DEFAULT NULL,
  p_department_id UUID DEFAULT NULL,
  p_default_priority public.work_priority DEFAULT 'normal',
  p_default_triage_sla_minutes INTEGER DEFAULT 240,
  p_default_resolution_sla_minutes INTEGER DEFAULT NULL,
  p_is_active BOOLEAN DEFAULT true
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_queue public.work_queues%ROWTYPE;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_update_queue',
    jsonb_build_object(
      'queue_id',p_queue_id,'expected_version',p_expected_version,'name',p_name,'description',p_description,
      'manager_user_id',p_manager_user_id,'branch_id',p_branch_id,'department_id',p_department_id,
      'default_priority',p_default_priority,'default_triage_sla_minutes',p_default_triage_sla_minutes,
      'default_resolution_sla_minutes',p_default_resolution_sla_minutes,'is_active',p_is_active
    ),NULL
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  IF NOT private.work_actor_is_active(v_actor)
     OR NOT COALESCE(public.check_permission(v_actor,'work.queues.manage'),false) THEN
    RETURN private.work_command_error(p_operation_id,'work_update_queue','FORBIDDEN','لا تملك صلاحية إدارة طوابير العمل');
  END IF;

  SELECT * INTO v_queue FROM public.work_queues WHERE id=p_queue_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_update_queue','NOT_FOUND','طابور العمل غير موجود'); END IF;
  IF v_queue.state_version<>p_expected_version THEN
    RETURN private.work_command_error(p_operation_id,'work_update_queue','VERSION_CONFLICT','تم تعديل الطابور بواسطة مستخدم آخر');
  END IF;
  IF p_name IS NULL OR btrim(p_name)='' THEN
    RETURN private.work_command_error(p_operation_id,'work_update_queue','NAME_REQUIRED','اسم الطابور مطلوب');
  END IF;
  IF NOT private.work_actor_is_active(p_manager_user_id) THEN
    RETURN private.work_command_error(p_operation_id,'work_update_queue','INVALID_MANAGER','مسؤول الطابور يجب أن يكون مستخدمًا نشطًا');
  END IF;
  IF p_default_triage_sla_minutes IS NULL OR p_default_triage_sla_minutes<=0
     OR (p_default_resolution_sla_minutes IS NOT NULL AND p_default_resolution_sla_minutes<=0) THEN
    RETURN private.work_command_error(p_operation_id,'work_update_queue','INVALID_SLA','قيم SLA يجب أن تكون موجبة');
  END IF;

  BEGIN
    UPDATE public.work_queues
    SET name=btrim(p_name),
        description=NULLIF(btrim(COALESCE(p_description,'')),''),
        manager_user_id=p_manager_user_id,
        branch_id=p_branch_id,
        department_id=p_department_id,
        default_priority=COALESCE(p_default_priority,'normal'),
        default_triage_sla_minutes=p_default_triage_sla_minutes,
        default_resolution_sla_minutes=p_default_resolution_sla_minutes,
        is_active=COALESCE(p_is_active,true),
        state_version=state_version+1
    WHERE id=v_queue.id
    RETURNING * INTO v_queue;

    RETURN private.work_command_success(
      p_operation_id,'work_update_queue',NULL,
      jsonb_build_object('queue_id',v_queue.id,'state_version',v_queue.state_version,'is_active',v_queue.is_active)
    );
  EXCEPTION WHEN foreign_key_violation THEN
    RETURN private.work_command_error(p_operation_id,'work_update_queue','INVALID_SCOPE','الفرع أو الإدارة المحددة غير موجودة');
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.work_set_queue_member(
  p_operation_id UUID,
  p_queue_id UUID,
  p_user_id UUID,
  p_member_role public.work_queue_member_role DEFAULT 'member',
  p_can_triage BOOLEAN DEFAULT false,
  p_can_assign BOOLEAN DEFAULT false,
  p_is_active BOOLEAN DEFAULT true
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_queue public.work_queues%ROWTYPE;
  v_existing public.work_queue_members%ROWTYPE;
  v_member public.work_queue_members%ROWTYPE;
  v_now TIMESTAMPTZ:=clock_timestamp();
  v_same BOOLEAN:=false;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_set_queue_member',
    jsonb_build_object('queue_id',p_queue_id,'user_id',p_user_id,'member_role',p_member_role,'can_triage',p_can_triage,'can_assign',p_can_assign,'is_active',p_is_active),NULL
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  IF NOT private.work_actor_is_active(v_actor)
     OR NOT COALESCE(public.check_permission(v_actor,'work.queues.manage'),false) THEN
    RETURN private.work_command_error(p_operation_id,'work_set_queue_member','FORBIDDEN','لا تملك صلاحية إدارة أعضاء الطوابير');
  END IF;
  SELECT * INTO v_queue FROM public.work_queues WHERE id=p_queue_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_set_queue_member','NOT_FOUND','طابور العمل غير موجود'); END IF;
  IF p_is_active AND NOT private.work_actor_is_active(p_user_id) THEN
    RETURN private.work_command_error(p_operation_id,'work_set_queue_member','INVALID_MEMBER','عضو الطابور يجب أن يكون مستخدمًا نشطًا');
  END IF;

  SELECT * INTO v_existing
  FROM public.work_queue_members
  WHERE queue_id=p_queue_id AND user_id=p_user_id AND active_until IS NULL
  ORDER BY active_from DESC
  LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    v_same:=v_existing.member_role=p_member_role
      AND v_existing.can_triage=COALESCE(p_can_triage,false)
      AND v_existing.can_assign=COALESCE(p_can_assign,false);
  END IF;

  IF NOT p_is_active THEN
    IF FOUND THEN
      UPDATE public.work_queue_members SET active_until=v_now WHERE id=v_existing.id;
    END IF;
    RETURN private.work_command_success(
      p_operation_id,'work_set_queue_member',NULL,
      jsonb_build_object('queue_id',p_queue_id,'user_id',p_user_id,'active',false)
    );
  END IF;

  IF FOUND AND v_same THEN
    RETURN private.work_command_success(
      p_operation_id,'work_set_queue_member',NULL,
      jsonb_build_object('queue_id',p_queue_id,'user_id',p_user_id,'membership_id',v_existing.id,'active',true,'unchanged',true)
    );
  END IF;

  IF FOUND THEN
    UPDATE public.work_queue_members SET active_until=v_now WHERE id=v_existing.id;
  END IF;

  INSERT INTO public.work_queue_members(
    queue_id,user_id,member_role,can_triage,can_assign,active_from,added_by_user_id
  ) VALUES (
    p_queue_id,p_user_id,p_member_role,COALESCE(p_can_triage,false),COALESCE(p_can_assign,false),v_now,v_actor
  ) RETURNING * INTO v_member;

  RETURN private.work_command_success(
    p_operation_id,'work_set_queue_member',NULL,
    jsonb_build_object('queue_id',p_queue_id,'user_id',p_user_id,'membership_id',v_member.id,'active',true,'unchanged',false)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.work_create_request_type(
  p_operation_id UUID,
  p_code TEXT,
  p_name TEXT,
  p_description TEXT,
  p_target_queue_id UUID,
  p_expected_outcome_template TEXT,
  p_intake_schema JSONB DEFAULT '{"version":1,"fields":[]}'::JSONB,
  p_target_department_id UUID DEFAULT NULL,
  p_default_priority public.work_priority DEFAULT NULL,
  p_default_visibility public.work_visibility DEFAULT 'standard',
  p_triage_sla_minutes INTEGER DEFAULT NULL,
  p_default_resolution_sla_minutes INTEGER DEFAULT NULL,
  p_allow_requester_cancel BOOLEAN DEFAULT true
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_queue public.work_queues%ROWTYPE;
  v_type public.work_request_types%ROWTYPE;
  v_validation JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_create_request_type',
    jsonb_build_object(
      'code',p_code,'name',p_name,'description',p_description,'target_queue_id',p_target_queue_id,
      'expected_outcome_template',p_expected_outcome_template,'intake_schema',p_intake_schema,
      'target_department_id',p_target_department_id,'default_priority',p_default_priority,
      'default_visibility',p_default_visibility,'triage_sla_minutes',p_triage_sla_minutes,
      'default_resolution_sla_minutes',p_default_resolution_sla_minutes,'allow_requester_cancel',p_allow_requester_cancel
    ),NULL
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  IF NOT private.work_actor_is_active(v_actor)
     OR NOT COALESCE(public.check_permission(v_actor,'work.queues.manage'),false) THEN
    RETURN private.work_command_error(p_operation_id,'work_create_request_type','FORBIDDEN','لا تملك صلاحية إدارة أنواع الطلبات');
  END IF;
  IF p_code IS NULL OR btrim(p_code) !~ '^[A-Za-z0-9][A-Za-z0-9._-]{1,79}$' THEN
    RETURN private.work_command_error(p_operation_id,'work_create_request_type','INVALID_CODE','كود نوع الطلب غير صالح');
  END IF;
  IF p_name IS NULL OR btrim(p_name)='' OR p_expected_outcome_template IS NULL OR btrim(p_expected_outcome_template)='' THEN
    RETURN private.work_command_error(p_operation_id,'work_create_request_type','VALIDATION_ERROR','اسم نوع الطلب والنتيجة المتوقعة مطلوبان');
  END IF;

  SELECT * INTO v_queue FROM public.work_queues WHERE id=p_target_queue_id;
  IF NOT FOUND OR NOT v_queue.is_active THEN
    RETURN private.work_command_error(p_operation_id,'work_create_request_type','QUEUE_UNAVAILABLE','طابور الاستقبال غير متاح');
  END IF;
  IF v_queue.department_id IS NOT NULL AND p_target_department_id IS NOT NULL AND v_queue.department_id<>p_target_department_id THEN
    RETURN private.work_command_error(p_operation_id,'work_create_request_type','DEPARTMENT_MISMATCH','إدارة نوع الطلب لا تطابق إدارة طابور الاستقبال');
  END IF;
  IF p_triage_sla_minutes IS NOT NULL AND p_triage_sla_minutes<=0
     OR p_default_resolution_sla_minutes IS NOT NULL AND p_default_resolution_sla_minutes<=0 THEN
    RETURN private.work_command_error(p_operation_id,'work_create_request_type','INVALID_SLA','قيم SLA يجب أن تكون موجبة');
  END IF;

  v_validation:=private.work_validate_intake_schema_definition(COALESCE(p_intake_schema,'{"version":1,"fields":[]}'::JSONB));
  IF NOT COALESCE((v_validation->>'ok')::BOOLEAN,false) THEN
    RETURN private.work_command_error(
      p_operation_id,'work_create_request_type',COALESCE(v_validation->>'code','INVALID_INTAKE_SCHEMA'),COALESCE(v_validation->>'message','تعريف نموذج الطلب غير صالح')
    );
  END IF;

  BEGIN
    INSERT INTO public.work_request_types(
      code,name,description,target_queue_id,target_department_id,intake_schema,expected_outcome_template,
      default_priority,default_visibility,triage_sla_minutes,default_resolution_sla_minutes,
      allow_requester_cancel,is_active,created_by_user_id,state_version
    ) VALUES (
      lower(btrim(p_code)),btrim(p_name),NULLIF(btrim(COALESCE(p_description,'')),''),p_target_queue_id,p_target_department_id,
      COALESCE(p_intake_schema,'{"version":1,"fields":[]}'::JSONB),btrim(p_expected_outcome_template),p_default_priority,
      COALESCE(p_default_visibility,'standard'),p_triage_sla_minutes,p_default_resolution_sla_minutes,
      COALESCE(p_allow_requester_cancel,true),true,v_actor,1
    ) RETURNING * INTO v_type;

    RETURN private.work_command_success(
      p_operation_id,'work_create_request_type',NULL,
      jsonb_build_object('request_type_id',v_type.id,'code',v_type.code,'state_version',v_type.state_version)
    );
  EXCEPTION WHEN foreign_key_violation THEN
    RETURN private.work_command_error(p_operation_id,'work_create_request_type','INVALID_SCOPE','الإدارة المحددة غير موجودة');
  WHEN unique_violation THEN
    RETURN private.work_command_error(p_operation_id,'work_create_request_type','DUPLICATE_CODE','كود نوع الطلب مستخدم بالفعل');
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.work_update_request_type(
  p_operation_id UUID,
  p_request_type_id UUID,
  p_expected_version BIGINT,
  p_name TEXT,
  p_description TEXT,
  p_target_queue_id UUID,
  p_expected_outcome_template TEXT,
  p_intake_schema JSONB,
  p_target_department_id UUID DEFAULT NULL,
  p_default_priority public.work_priority DEFAULT NULL,
  p_default_visibility public.work_visibility DEFAULT 'standard',
  p_triage_sla_minutes INTEGER DEFAULT NULL,
  p_default_resolution_sla_minutes INTEGER DEFAULT NULL,
  p_allow_requester_cancel BOOLEAN DEFAULT true,
  p_is_active BOOLEAN DEFAULT true
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_queue public.work_queues%ROWTYPE;
  v_type public.work_request_types%ROWTYPE;
  v_validation JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_update_request_type',
    jsonb_build_object(
      'request_type_id',p_request_type_id,'expected_version',p_expected_version,'name',p_name,'description',p_description,
      'target_queue_id',p_target_queue_id,'expected_outcome_template',p_expected_outcome_template,'intake_schema',p_intake_schema,
      'target_department_id',p_target_department_id,'default_priority',p_default_priority,'default_visibility',p_default_visibility,
      'triage_sla_minutes',p_triage_sla_minutes,'default_resolution_sla_minutes',p_default_resolution_sla_minutes,
      'allow_requester_cancel',p_allow_requester_cancel,'is_active',p_is_active
    ),NULL
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;

  IF NOT private.work_actor_is_active(v_actor)
     OR NOT COALESCE(public.check_permission(v_actor,'work.queues.manage'),false) THEN
    RETURN private.work_command_error(p_operation_id,'work_update_request_type','FORBIDDEN','لا تملك صلاحية إدارة أنواع الطلبات');
  END IF;

  SELECT * INTO v_type FROM public.work_request_types WHERE id=p_request_type_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_update_request_type','NOT_FOUND','نوع الطلب غير موجود'); END IF;
  IF v_type.state_version<>p_expected_version THEN
    RETURN private.work_command_error(p_operation_id,'work_update_request_type','VERSION_CONFLICT','تم تعديل نوع الطلب بواسطة مستخدم آخر');
  END IF;
  IF p_name IS NULL OR btrim(p_name)='' OR p_expected_outcome_template IS NULL OR btrim(p_expected_outcome_template)='' THEN
    RETURN private.work_command_error(p_operation_id,'work_update_request_type','VALIDATION_ERROR','اسم نوع الطلب والنتيجة المتوقعة مطلوبان');
  END IF;

  SELECT * INTO v_queue FROM public.work_queues WHERE id=p_target_queue_id;
  IF NOT FOUND OR (COALESCE(p_is_active,true) AND NOT v_queue.is_active) THEN
    RETURN private.work_command_error(p_operation_id,'work_update_request_type','QUEUE_UNAVAILABLE','طابور الاستقبال غير متاح');
  END IF;
  IF v_queue.department_id IS NOT NULL AND p_target_department_id IS NOT NULL AND v_queue.department_id<>p_target_department_id THEN
    RETURN private.work_command_error(p_operation_id,'work_update_request_type','DEPARTMENT_MISMATCH','إدارة نوع الطلب لا تطابق إدارة طابور الاستقبال');
  END IF;
  IF p_triage_sla_minutes IS NOT NULL AND p_triage_sla_minutes<=0
     OR p_default_resolution_sla_minutes IS NOT NULL AND p_default_resolution_sla_minutes<=0 THEN
    RETURN private.work_command_error(p_operation_id,'work_update_request_type','INVALID_SLA','قيم SLA يجب أن تكون موجبة');
  END IF;

  v_validation:=private.work_validate_intake_schema_definition(p_intake_schema);
  IF NOT COALESCE((v_validation->>'ok')::BOOLEAN,false) THEN
    RETURN private.work_command_error(
      p_operation_id,'work_update_request_type',COALESCE(v_validation->>'code','INVALID_INTAKE_SCHEMA'),COALESCE(v_validation->>'message','تعريف نموذج الطلب غير صالح')
    );
  END IF;

  BEGIN
    UPDATE public.work_request_types
    SET name=btrim(p_name),
        description=NULLIF(btrim(COALESCE(p_description,'')),''),
        target_queue_id=p_target_queue_id,
        target_department_id=p_target_department_id,
        intake_schema=p_intake_schema,
        expected_outcome_template=btrim(p_expected_outcome_template),
        default_priority=p_default_priority,
        default_visibility=COALESCE(p_default_visibility,'standard'),
        triage_sla_minutes=p_triage_sla_minutes,
        default_resolution_sla_minutes=p_default_resolution_sla_minutes,
        allow_requester_cancel=COALESCE(p_allow_requester_cancel,true),
        is_active=COALESCE(p_is_active,true),
        state_version=state_version+1
    WHERE id=v_type.id
    RETURNING * INTO v_type;

    RETURN private.work_command_success(
      p_operation_id,'work_update_request_type',NULL,
      jsonb_build_object('request_type_id',v_type.id,'state_version',v_type.state_version,'is_active',v_type.is_active)
    );
  EXCEPTION WHEN foreign_key_violation THEN
    RETURN private.work_command_error(p_operation_id,'work_update_request_type','INVALID_SCOPE','الإدارة المحددة غير موجودة');
  END;
END;
$$;

REVOKE ALL ON FUNCTION private.work_validate_intake_schema_definition(JSONB) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.work_create_queue(UUID,TEXT,TEXT,TEXT,UUID,UUID,UUID,public.work_priority,INTEGER,INTEGER) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_update_queue(UUID,UUID,BIGINT,TEXT,TEXT,UUID,UUID,UUID,public.work_priority,INTEGER,INTEGER,BOOLEAN) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_set_queue_member(UUID,UUID,UUID,public.work_queue_member_role,BOOLEAN,BOOLEAN,BOOLEAN) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_create_request_type(UUID,TEXT,TEXT,TEXT,UUID,TEXT,JSONB,UUID,public.work_priority,public.work_visibility,INTEGER,INTEGER,BOOLEAN) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_update_request_type(UUID,UUID,BIGINT,TEXT,TEXT,UUID,TEXT,JSONB,UUID,public.work_priority,public.work_visibility,INTEGER,INTEGER,BOOLEAN,BOOLEAN) FROM PUBLIC,anon;

GRANT EXECUTE ON FUNCTION public.work_create_queue(UUID,TEXT,TEXT,TEXT,UUID,UUID,UUID,public.work_priority,INTEGER,INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_update_queue(UUID,UUID,BIGINT,TEXT,TEXT,UUID,UUID,UUID,public.work_priority,INTEGER,INTEGER,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_set_queue_member(UUID,UUID,UUID,public.work_queue_member_role,BOOLEAN,BOOLEAN,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_create_request_type(UUID,TEXT,TEXT,TEXT,UUID,TEXT,JSONB,UUID,public.work_priority,public.work_visibility,INTEGER,INTEGER,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_update_request_type(UUID,UUID,BIGINT,TEXT,TEXT,UUID,TEXT,JSONB,UUID,public.work_priority,public.work_visibility,INTEGER,INTEGER,BOOLEAN,BOOLEAN) TO authenticated;

RESET lock_timeout;
RESET statement_timeout;
