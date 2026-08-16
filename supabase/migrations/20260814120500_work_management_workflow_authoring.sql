-- Work Management — workflow authoring, safe condition DSL and cycle validation.
SET lock_timeout='5s';
SET statement_timeout='60s';

CREATE OR REPLACE FUNCTION private.work_user_can_view_workflow_run(
  p_user_id UUID,
  p_run_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_run public.work_workflow_runs%ROWTYPE;
BEGIN
  IF NOT private.work_actor_is_active(p_user_id) THEN RETURN false; END IF;
  IF COALESCE(public.check_permission(p_user_id,'work.workflows.manage'),false) THEN RETURN true; END IF;
  SELECT * INTO v_run FROM public.work_workflow_runs WHERE id=p_run_id;
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_run.started_by_user_id=p_user_id THEN RETURN true; END IF;
  IF v_run.parent_work_item_id IS NOT NULL AND private.work_user_can_view_row(
    p_user_id,
    v_run.parent_work_item_id,
    (SELECT w.visibility FROM public.work_items w WHERE w.id=v_run.parent_work_item_id),
    (SELECT w.creator_user_id FROM public.work_items w WHERE w.id=v_run.parent_work_item_id),
    (SELECT w.requester_user_id FROM public.work_items w WHERE w.id=v_run.parent_work_item_id),
    (SELECT w.accountable_owner_user_id FROM public.work_items w WHERE w.id=v_run.parent_work_item_id),
    (SELECT w.current_assignee_user_id FROM public.work_items w WHERE w.id=v_run.parent_work_item_id),
    (SELECT w.branch_id FROM public.work_items w WHERE w.id=v_run.parent_work_item_id),
    (SELECT w.owning_department_id FROM public.work_items w WHERE w.id=v_run.parent_work_item_id)
  ) THEN RETURN true; END IF;
  RETURN EXISTS (
    SELECT 1
    FROM public.work_workflow_step_instances si
    JOIN public.work_items w ON w.id=si.work_item_id
    WHERE si.workflow_run_id=p_run_id
      AND private.work_user_can_view_row(
        p_user_id,w.id,w.visibility,w.creator_user_id,w.requester_user_id,
        w.accountable_owner_user_id,w.current_assignee_user_id,w.branch_id,w.owning_department_id
      )
  );
END;
$$;

DROP POLICY IF EXISTS work_workflow_runs_select ON public.work_workflow_runs;
DROP POLICY IF EXISTS work_workflow_step_instances_select ON public.work_workflow_step_instances;
CREATE POLICY work_workflow_runs_select
ON public.work_workflow_runs FOR SELECT TO authenticated
USING (private.work_user_can_view_workflow_run(auth.uid(),id));
CREATE POLICY work_workflow_step_instances_select
ON public.work_workflow_step_instances FOR SELECT TO authenticated
USING (private.work_user_can_view_workflow_run(auth.uid(),workflow_run_id));

CREATE OR REPLACE FUNCTION private.work_validate_workflow_condition_dsl(p_condition JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SET search_path=''
AS $$
DECLARE
  v_op TEXT;
  v_child JSONB;
  v_path TEXT;
BEGIN
  IF jsonb_typeof(COALESCE(p_condition,'{}'::JSONB))<>'object' THEN RETURN false; END IF;
  v_op:=p_condition->>'op';
  IF v_op='always' THEN RETURN true; END IF;
  IF v_op IN ('eq','ne','exists','in') THEN
    v_path:=p_condition->>'path';
    IF v_path IS NULL OR v_path !~ '^(input|steps\.[A-Za-z0-9_-]+\.output)(\.[A-Za-z0-9_-]+)*$' THEN RETURN false; END IF;
    IF v_op IN ('eq','ne') AND NOT (p_condition ? 'value') THEN RETURN false; END IF;
    IF v_op='in' AND jsonb_typeof(p_condition->'values')<>'array' THEN RETURN false; END IF;
    RETURN true;
  END IF;
  IF v_op IN ('all','any') THEN
    IF jsonb_typeof(p_condition->'conditions')<>'array' OR jsonb_array_length(p_condition->'conditions')=0 THEN RETURN false; END IF;
    FOR v_child IN SELECT value FROM jsonb_array_elements(p_condition->'conditions') LOOP
      IF NOT private.work_validate_workflow_condition_dsl(v_child) THEN RETURN false; END IF;
    END LOOP;
    RETURN true;
  END IF;
  IF v_op='not' THEN RETURN private.work_validate_workflow_condition_dsl(p_condition->'condition'); END IF;
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION private.work_workflow_version_has_cycle(p_version_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  WITH RECURSIVE walk AS (
    SELECT
      d.predecessor_step_id AS start_id,
      d.successor_step_id AS current_id,
      ARRAY[d.predecessor_step_id,d.successor_step_id]::UUID[] AS path,
      false AS cycle
    FROM public.work_workflow_step_dependencies d
    WHERE d.template_version_id=p_version_id
    UNION ALL
    SELECT
      w.start_id,
      d.successor_step_id,
      w.path||d.successor_step_id,
      d.successor_step_id=ANY(w.path)
    FROM walk w
    JOIN public.work_workflow_step_dependencies d
      ON d.template_version_id=p_version_id AND d.predecessor_step_id=w.current_id
    WHERE NOT w.cycle
  )
  SELECT EXISTS(SELECT 1 FROM walk WHERE cycle);
$$;

CREATE OR REPLACE FUNCTION private.work_insert_workflow_version_from_definition(
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
  v_step JSONB;
  v_step_order BIGINT;
  v_step_id UUID;
  v_kind public.work_workflow_step_kind;
  v_key TEXT;
  v_dep TEXT;
  v_pred_id UUID;
BEGIN
  IF jsonb_typeof(COALESCE(p_definition,'{}'::JSONB))<>'object'
     OR jsonb_typeof(COALESCE(p_definition->'steps','[]'::JSONB))<>'array'
     OR jsonb_array_length(COALESCE(p_definition->'steps','[]'::JSONB))=0 THEN
    RAISE EXCEPTION 'workflow definition must contain steps';
  END IF;

  PERFORM 1 FROM public.work_workflow_templates t WHERE t.id=p_template_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'workflow template not found'; END IF;
  SELECT COALESCE(max(version_number),0)+1 INTO v_version_number
  FROM public.work_workflow_template_versions WHERE template_id=p_template_id;

  INSERT INTO public.work_workflow_template_versions(
    template_id,version_number,status,metadata,created_by_user_id
  ) VALUES (
    p_template_id,v_version_number,'draft',COALESCE(p_definition->'metadata','{}'::JSONB),p_actor_user_id
  ) RETURNING id INTO v_version_id;

  FOR v_step,v_step_order IN
    SELECT value,ordinality FROM jsonb_array_elements(p_definition->'steps') WITH ORDINALITY
  LOOP
    v_key:=NULLIF(btrim(v_step->>'key'),'');
    IF v_key IS NULL OR v_key !~ '^[A-Za-z0-9_-]+$' THEN RAISE EXCEPTION 'invalid workflow step key'; END IF;
    IF NULLIF(btrim(v_step->>'name'),'') IS NULL THEN RAISE EXCEPTION 'workflow step name required'; END IF;
    BEGIN v_kind:=(v_step->>'kind')::public.work_workflow_step_kind;
    EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'invalid workflow step kind'; END;
    IF NOT private.work_validate_workflow_condition_dsl(COALESCE(v_step->'condition','{"op":"always"}'::JSONB)) THEN
      RAISE EXCEPTION 'invalid workflow condition DSL';
    END IF;
    IF jsonb_typeof(COALESCE(v_step->'output_schema','{"version":1,"fields":[]}'::JSONB))<>'object' THEN
      RAISE EXCEPTION 'invalid workflow output schema';
    END IF;
    IF v_kind='task' AND NULLIF(btrim(COALESCE(v_step->'task'->>'expected_outcome','')),'') IS NULL THEN
      RAISE EXCEPTION 'task workflow step requires expected outcome';
    END IF;
    IF v_kind='approval' AND NULLIF(v_step->>'approval_template_id','') IS NULL THEN
      RAISE EXCEPTION 'approval workflow step requires approval template';
    END IF;

    INSERT INTO public.work_workflow_step_definitions(
      template_version_id,step_key,name,step_kind,sort_order,condition_dsl,task_config,
      approval_template_id,output_schema
    ) VALUES (
      v_version_id,v_key,btrim(v_step->>'name'),v_kind,v_step_order::INTEGER,
      COALESCE(v_step->'condition','{"op":"always"}'::JSONB),
      CASE WHEN v_kind='task' THEN COALESCE(v_step->'task','{}'::JSONB) ELSE '{}'::JSONB END,
      CASE WHEN v_kind='approval' THEN (v_step->>'approval_template_id')::UUID ELSE NULL END,
      COALESCE(v_step->'output_schema','{"version":1,"fields":[]}'::JSONB)
    ) RETURNING id INTO v_step_id;
  END LOOP;

  FOR v_step IN SELECT value FROM jsonb_array_elements(p_definition->'steps') LOOP
    v_key:=btrim(v_step->>'key');
    SELECT id INTO v_step_id FROM public.work_workflow_step_definitions
      WHERE template_version_id=v_version_id AND step_key=v_key;
    IF jsonb_typeof(COALESCE(v_step->'depends_on','[]'::JSONB))<>'array' THEN RAISE EXCEPTION 'depends_on must be an array'; END IF;
    FOR v_dep IN SELECT value#>>'{}' FROM jsonb_array_elements(COALESCE(v_step->'depends_on','[]'::JSONB)) LOOP
      SELECT id INTO v_pred_id FROM public.work_workflow_step_definitions
      WHERE template_version_id=v_version_id AND step_key=v_dep;
      IF v_pred_id IS NULL THEN RAISE EXCEPTION 'workflow dependency references unknown step'; END IF;
      INSERT INTO public.work_workflow_step_dependencies(
        template_version_id,predecessor_step_id,successor_step_id
      ) VALUES (v_version_id,v_pred_id,v_step_id);
    END LOOP;
  END LOOP;

  IF private.work_workflow_version_has_cycle(v_version_id) THEN RAISE EXCEPTION 'workflow contains a dependency cycle'; END IF;
  RETURN v_version_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.work_create_workflow_template(
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
  v_actor UUID:=auth.uid(); v_prepare JSONB; v_template public.work_workflow_templates%ROWTYPE;
  v_version_id UUID; v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(p_operation_id,v_actor,'work_create_workflow_template',jsonb_build_object('code',p_code,'name',p_name,'description',p_description,'definition',p_definition,'publish',p_publish),NULL);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  IF NOT COALESCE(public.check_permission(v_actor,'work.workflows.manage'),false) THEN RETURN private.work_command_error(p_operation_id,'work_create_workflow_template','FORBIDDEN','لا تملك صلاحية إدارة مسارات العمل'); END IF;
  IF NULLIF(btrim(p_code),'') IS NULL OR NULLIF(btrim(p_name),'') IS NULL THEN RETURN private.work_command_error(p_operation_id,'work_create_workflow_template','VALIDATION_ERROR','كود واسم مسار العمل مطلوبان'); END IF;

  BEGIN
    INSERT INTO public.work_workflow_templates(code,name,description,created_by_user_id)
    VALUES(lower(btrim(p_code)),btrim(p_name),p_description,v_actor) RETURNING * INTO v_template;
    v_version_id:=private.work_insert_workflow_version_from_definition(v_template.id,p_definition,v_actor);
    IF p_publish THEN
      UPDATE public.work_workflow_template_versions SET status='published',published_at=clock_timestamp(),published_by_user_id=v_actor WHERE id=v_version_id;
      UPDATE public.work_workflow_templates SET current_published_version_id=v_version_id WHERE id=v_template.id;
    END IF;
    v_result:=jsonb_build_object('template_id',v_template.id,'version_id',v_version_id,'published',p_publish);
    RETURN private.work_command_success(p_operation_id,'work_create_workflow_template',NULL,v_result);
  EXCEPTION WHEN unique_violation THEN
    RETURN private.work_command_error(p_operation_id,'work_create_workflow_template','DUPLICATE_CODE','كود مسار العمل مستخدم بالفعل');
  WHEN OTHERS THEN
    RETURN private.work_command_error(p_operation_id,'work_create_workflow_template','INVALID_DEFINITION','تعريف مسار العمل غير صالح');
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.work_create_workflow_template_version(
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
  v_actor UUID:=auth.uid(); v_prepare JSONB; v_version_id UUID; v_version_number INTEGER; v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(p_operation_id,v_actor,'work_create_workflow_template_version',jsonb_build_object('template_id',p_template_id,'definition',p_definition,'publish',p_publish),NULL);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  IF NOT COALESCE(public.check_permission(v_actor,'work.workflows.manage'),false) THEN RETURN private.work_command_error(p_operation_id,'work_create_workflow_template_version','FORBIDDEN','لا تملك صلاحية إدارة مسارات العمل'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.work_workflow_templates WHERE id=p_template_id) THEN RETURN private.work_command_error(p_operation_id,'work_create_workflow_template_version','NOT_FOUND','مسار العمل غير موجود'); END IF;
  BEGIN
    v_version_id:=private.work_insert_workflow_version_from_definition(p_template_id,p_definition,v_actor);
    SELECT version_number INTO v_version_number FROM public.work_workflow_template_versions WHERE id=v_version_id;
    IF p_publish THEN
      UPDATE public.work_workflow_template_versions SET status='published',published_at=clock_timestamp(),published_by_user_id=v_actor WHERE id=v_version_id;
      UPDATE public.work_workflow_templates SET current_published_version_id=v_version_id WHERE id=p_template_id;
    END IF;
    v_result:=jsonb_build_object('template_id',p_template_id,'version_id',v_version_id,'version_number',v_version_number,'published',p_publish);
    RETURN private.work_command_success(p_operation_id,'work_create_workflow_template_version',NULL,v_result);
  EXCEPTION WHEN OTHERS THEN
    RETURN private.work_command_error(p_operation_id,'work_create_workflow_template_version','INVALID_DEFINITION','تعريف نسخة مسار العمل غير صالح');
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.work_publish_workflow_template_version(
  p_operation_id UUID,
  p_version_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_actor UUID:=auth.uid(); v_prepare JSONB; v_version public.work_workflow_template_versions%ROWTYPE; v_result JSONB;
BEGIN
  v_prepare:=private.work_prepare_operation(p_operation_id,v_actor,'work_publish_workflow_template_version',jsonb_build_object('version_id',p_version_id),NULL);
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN,false) THEN RETURN v_prepare->'response'; END IF;
  IF NOT COALESCE(public.check_permission(v_actor,'work.workflows.manage'),false) THEN RETURN private.work_command_error(p_operation_id,'work_publish_workflow_template_version','FORBIDDEN','لا تملك صلاحية نشر مسارات العمل'); END IF;
  SELECT * INTO v_version FROM public.work_workflow_template_versions WHERE id=p_version_id FOR UPDATE;
  IF NOT FOUND THEN RETURN private.work_command_error(p_operation_id,'work_publish_workflow_template_version','NOT_FOUND','نسخة مسار العمل غير موجودة'); END IF;
  IF v_version.status='published' THEN RETURN private.work_command_error(p_operation_id,'work_publish_workflow_template_version','ALREADY_PUBLISHED','النسخة منشورة بالفعل'); END IF;
  IF private.work_workflow_version_has_cycle(v_version.id) THEN RETURN private.work_command_error(p_operation_id,'work_publish_workflow_template_version','WORKFLOW_CYCLE','لا يمكن نشر مسار يحتوي دورة اعتماد'); END IF;
  UPDATE public.work_workflow_template_versions SET status='published',published_at=clock_timestamp(),published_by_user_id=v_actor WHERE id=v_version.id;
  UPDATE public.work_workflow_templates SET current_published_version_id=v_version.id,is_active=true WHERE id=v_version.template_id;
  v_result:=jsonb_build_object('template_id',v_version.template_id,'version_id',v_version.id,'version_number',v_version.version_number,'published',true);
  RETURN private.work_command_success(p_operation_id,'work_publish_workflow_template_version',NULL,v_result);
END;
$$;

REVOKE ALL ON FUNCTION private.work_user_can_view_workflow_run(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_validate_workflow_condition_dsl(JSONB) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_workflow_version_has_cycle(UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.work_insert_workflow_version_from_definition(UUID,JSONB,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.work_create_workflow_template(UUID,TEXT,TEXT,TEXT,JSONB,BOOLEAN) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_create_workflow_template_version(UUID,UUID,JSONB,BOOLEAN) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_publish_workflow_template_version(UUID,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.work_create_workflow_template(UUID,TEXT,TEXT,TEXT,JSONB,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_create_workflow_template_version(UUID,UUID,JSONB,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_publish_workflow_template_version(UUID,UUID) TO authenticated;

RESET lock_timeout;
RESET statement_timeout;
