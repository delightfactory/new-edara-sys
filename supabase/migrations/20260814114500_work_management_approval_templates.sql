-- Work Management — atomic approval-template authoring and publication.
SET lock_timeout='5s';
SET statement_timeout='60s';

CREATE OR REPLACE FUNCTION private.work_insert_approval_version_from_definition(
  p_template_id UUID,
  p_definition JSONB,
  p_actor_user_id UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_version_id UUID;
  v_version_number INTEGER;
  v_stage JSONB;
  v_stage_order BIGINT;
  v_stage_id UUID;
  v_approver JSONB;
  v_selector public.work_approval_selector_kind;
  v_user_id UUID;
  v_mode public.work_approval_stage_mode;
  v_deadline INTEGER;
BEGIN
  IF jsonb_typeof(COALESCE(p_definition,'{}'::JSONB))<>'object'
     OR jsonb_typeof(COALESCE(p_definition->'stages','[]'::JSONB))<>'array'
     OR jsonb_array_length(COALESCE(p_definition->'stages','[]'::JSONB))=0 THEN
    RAISE EXCEPTION 'approval definition must contain stages';
  END IF;

  PERFORM 1 FROM public.work_approval_templates t WHERE t.id=p_template_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'approval template not found'; END IF;

  SELECT COALESCE(max(version_number),0)+1 INTO v_version_number
  FROM public.work_approval_template_versions WHERE template_id=p_template_id;

  INSERT INTO public.work_approval_template_versions(
    template_id,version_number,status,metadata,created_by_user_id
  ) VALUES (
    p_template_id,v_version_number,'draft',COALESCE(p_definition->'metadata','{}'::JSONB),p_actor_user_id
  ) RETURNING id INTO v_version_id;

  FOR v_stage,v_stage_order IN
    SELECT value,ordinality
    FROM jsonb_array_elements(p_definition->'stages') WITH ORDINALITY
  LOOP
    IF NULLIF(btrim(v_stage->>'name'),'') IS NULL THEN RAISE EXCEPTION 'approval stage name required'; END IF;
    BEGIN
      v_mode:=COALESCE(NULLIF(v_stage->>'mode','')::public.work_approval_stage_mode,'all');
      v_deadline:=NULLIF(v_stage->>'deadline_minutes','')::INTEGER;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'invalid approval stage configuration';
    END;
    IF v_deadline IS NOT NULL AND v_deadline<=0 THEN RAISE EXCEPTION 'approval deadline must be positive'; END IF;
    IF jsonb_typeof(COALESCE(v_stage->'approvers','[]'::JSONB))<>'array'
       OR jsonb_array_length(COALESCE(v_stage->'approvers','[]'::JSONB))=0 THEN
      RAISE EXCEPTION 'approval stage must contain approvers';
    END IF;

    INSERT INTO public.work_approval_stages(
      template_version_id,stage_order,name,decision_mode,deadline_minutes,allow_changes_required
    ) VALUES (
      v_version_id,v_stage_order::INTEGER,btrim(v_stage->>'name'),v_mode,v_deadline,
      COALESCE((v_stage->>'allow_changes_required')::BOOLEAN,true)
    ) RETURNING id INTO v_stage_id;

    FOR v_approver IN SELECT value FROM jsonb_array_elements(v_stage->'approvers') LOOP
      BEGIN
        v_selector:=(v_approver->>'selector_kind')::public.work_approval_selector_kind;
        v_user_id:=CASE WHEN v_selector='user' THEN (v_approver->>'user_id')::UUID ELSE NULL END;
      EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'invalid approval selector';
      END;
      IF v_selector='user' AND NOT private.work_actor_is_active(v_user_id) THEN
        RAISE EXCEPTION 'configured user approver must be active';
      END IF;
      INSERT INTO public.work_approval_stage_approvers(
        stage_id,selector_kind,selector_user_id,sort_order
      ) VALUES (
        v_stage_id,v_selector,v_user_id,
        COALESCE(NULLIF(v_approver->>'sort_order','')::INTEGER,0)
      );
    END LOOP;
  END LOOP;

  RETURN v_version_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.work_create_approval_template(
  p_operation_id UUID,
  p_code TEXT,
  p_name TEXT,
  p_description TEXT,
  p_definition JSONB,
  p_publish BOOLEAN DEFAULT false
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_template public.work_approval_templates%ROWTYPE;
  v_version_id UUID;
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_create_approval_template',
    jsonb_build_object('code',p_code,'name',p_name,'description',p_description,'definition',p_definition,'publish',p_publish),NULL
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  IF NOT COALESCE(public.check_permission(v_actor,'work.templates.manage'),false) THEN
    RETURN private.work_command_error(p_operation_id,'work_create_approval_template','FORBIDDEN','لا تملك صلاحية إدارة قوالب الاعتماد');
  END IF;
  IF p_code IS NULL OR btrim(p_code)='' OR p_name IS NULL OR btrim(p_name)='' THEN
    RETURN private.work_command_error(p_operation_id,'work_create_approval_template','VALIDATION_ERROR','كود واسم نموذج الاعتماد مطلوبان');
  END IF;

  BEGIN
    INSERT INTO public.work_approval_templates(code,name,description,created_by_user_id)
    VALUES (lower(btrim(p_code)),btrim(p_name),p_description,v_actor)
    RETURNING * INTO v_template;
    v_version_id:=private.work_insert_approval_version_from_definition(v_template.id,p_definition,v_actor);

    IF p_publish THEN
      UPDATE public.work_approval_template_versions
      SET status='published',published_at=clock_timestamp(),published_by_user_id=v_actor
      WHERE id=v_version_id;
      UPDATE public.work_approval_templates SET current_published_version_id=v_version_id WHERE id=v_template.id;
    END IF;

    v_result:=jsonb_build_object('template_id',v_template.id,'version_id',v_version_id,'published',p_publish);
    RETURN private.work_command_success(p_operation_id,'work_create_approval_template',NULL,v_result);
  EXCEPTION WHEN unique_violation THEN
    RETURN private.work_command_error(p_operation_id,'work_create_approval_template','DUPLICATE_CODE','كود نموذج الاعتماد مستخدم بالفعل');
  WHEN OTHERS THEN
    RETURN private.work_command_error(p_operation_id,'work_create_approval_template','INVALID_DEFINITION','تعريف نموذج الاعتماد غير صالح');
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.work_create_approval_template_version(
  p_operation_id UUID,
  p_template_id UUID,
  p_definition JSONB,
  p_publish BOOLEAN DEFAULT false
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_template public.work_approval_templates%ROWTYPE;
  v_version_id UUID;
  v_version_number INTEGER;
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_create_approval_template_version',
    jsonb_build_object('template_id',p_template_id,'definition',p_definition,'publish',p_publish),NULL
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  IF NOT COALESCE(public.check_permission(v_actor,'work.templates.manage'),false) THEN
    RETURN private.work_command_error(p_operation_id,'work_create_approval_template_version','FORBIDDEN','لا تملك صلاحية إدارة قوالب الاعتماد');
  END IF;
  SELECT * INTO v_template FROM public.work_approval_templates WHERE id=p_template_id;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_create_approval_template_version','NOT_FOUND','نموذج الاعتماد غير موجود'); END IF;

  BEGIN
    v_version_id:=private.work_insert_approval_version_from_definition(p_template_id,p_definition,v_actor);
    SELECT version_number INTO v_version_number FROM public.work_approval_template_versions WHERE id=v_version_id;
    IF p_publish THEN
      UPDATE public.work_approval_template_versions
      SET status='published',published_at=clock_timestamp(),published_by_user_id=v_actor
      WHERE id=v_version_id;
      UPDATE public.work_approval_templates SET current_published_version_id=v_version_id WHERE id=p_template_id;
    END IF;
    v_result:=jsonb_build_object('template_id',p_template_id,'version_id',v_version_id,'version_number',v_version_number,'published',p_publish);
    RETURN private.work_command_success(p_operation_id,'work_create_approval_template_version',NULL,v_result);
  EXCEPTION WHEN OTHERS THEN
    RETURN private.work_command_error(p_operation_id,'work_create_approval_template_version','INVALID_DEFINITION','تعريف نسخة الاعتماد غير صالح');
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.work_publish_approval_template_version(
  p_operation_id UUID,
  p_version_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_version public.work_approval_template_versions%ROWTYPE;
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(
    p_operation_id,v_actor,'work_publish_approval_template_version',jsonb_build_object('version_id',p_version_id),NULL
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  IF NOT COALESCE(public.check_permission(v_actor,'work.templates.manage'),false) THEN
    RETURN private.work_command_error(p_operation_id,'work_publish_approval_template_version','FORBIDDEN','لا تملك صلاحية نشر قوالب الاعتماد');
  END IF;

  SELECT * INTO v_version FROM public.work_approval_template_versions WHERE id=p_version_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_publish_approval_template_version','NOT_FOUND','نسخة الاعتماد غير موجودة'); END IF;
  IF v_version.status='published' THEN RETURN private.work_command_error(p_operation_id,'work_publish_approval_template_version','ALREADY_PUBLISHED','نسخة الاعتماد منشورة بالفعل'); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.work_approval_stages WHERE template_version_id=v_version.id) THEN
    RETURN private.work_command_error(p_operation_id,'work_publish_approval_template_version','EMPTY_TEMPLATE','لا يمكن نشر نموذج بلا مراحل');
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.work_approval_stages s
    WHERE s.template_version_id=v_version.id
      AND NOT EXISTS (SELECT 1 FROM public.work_approval_stage_approvers a WHERE a.stage_id=s.id)
  ) THEN
    RETURN private.work_command_error(p_operation_id,'work_publish_approval_template_version','EMPTY_STAGE','توجد مرحلة بلا معتمدين');
  END IF;

  UPDATE public.work_approval_template_versions
  SET status='published',published_at=clock_timestamp(),published_by_user_id=v_actor
  WHERE id=v_version.id;
  UPDATE public.work_approval_templates
  SET current_published_version_id=v_version.id,is_active=true
  WHERE id=v_version.template_id;

  v_result:=jsonb_build_object('template_id',v_version.template_id,'version_id',v_version.id,'version_number',v_version.version_number,'published',true);
  RETURN private.work_command_success(p_operation_id,'work_publish_approval_template_version',NULL,v_result);
END;
$$;

CREATE OR REPLACE FUNCTION public.work_revoke_approval_delegation(
  p_operation_id UUID,
  p_delegation_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_prepare JSONB;
  v_delegation public.work_approval_delegations%ROWTYPE;
  v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(p_operation_id,v_actor,'work_revoke_approval_delegation',jsonb_build_object('delegation_id',p_delegation_id),NULL);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  SELECT * INTO v_delegation FROM public.work_approval_delegations WHERE id=p_delegation_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_revoke_approval_delegation','NOT_FOUND','التفويض غير موجود'); END IF;
  IF v_delegation.delegator_user_id<>v_actor AND NOT COALESCE(public.check_permission(v_actor,'work.templates.manage'),false) THEN
    RETURN private.work_command_error(p_operation_id,'work_revoke_approval_delegation','FORBIDDEN','لا تملك صلاحية إلغاء هذا التفويض');
  END IF;
  IF v_delegation.revoked_at IS NULL THEN
    UPDATE public.work_approval_delegations SET revoked_at=clock_timestamp(),revoked_by_user_id=v_actor WHERE id=p_delegation_id;
  END IF;
  v_result:=jsonb_build_object('delegation_id',p_delegation_id,'revoked',true);
  RETURN private.work_command_success(p_operation_id,'work_revoke_approval_delegation',NULL,v_result);
END;
$$;

REVOKE ALL ON FUNCTION private.work_insert_approval_version_from_definition(UUID,JSONB,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.work_create_approval_template(UUID,TEXT,TEXT,TEXT,JSONB,BOOLEAN) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_create_approval_template_version(UUID,UUID,JSONB,BOOLEAN) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_publish_approval_template_version(UUID,UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_revoke_approval_delegation(UUID,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.work_create_approval_template(UUID,TEXT,TEXT,TEXT,JSONB,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_create_approval_template_version(UUID,UUID,JSONB,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_publish_approval_template_version(UUID,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_revoke_approval_delegation(UUID,UUID) TO authenticated;

RESET lock_timeout;
RESET statement_timeout;
