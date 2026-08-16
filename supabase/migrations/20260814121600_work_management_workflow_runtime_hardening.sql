-- Work Management — workflow runtime hardening.
-- Replaces the step activator before any runtime command is used, correcting
-- the approval-step activity column and tightening runtime configuration checks.
SET lock_timeout='5s';
SET statement_timeout='60s';

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
  v_completion_approval_template_id UUID;
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
  ) THEN
    RETURN false;
  END IF;

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
      v_completion_approval_template_id:=CASE
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
    IF v_completion_mode='approval' AND v_completion_approval_template_id IS NULL THEN
      RAISE EXCEPTION 'workflow approval-completion task requires completion approval template';
    END IF;
    IF v_completion_approval_template_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.work_approval_templates t
      WHERE t.id=v_completion_approval_template_id
        AND t.is_active=true
        AND t.current_published_version_id IS NOT NULL
    ) THEN
      RAISE EXCEPTION 'workflow completion approval template is unavailable';
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
      completion_mode,completion_approval_template_id,last_meaningful_activity_at,state_version
    ) VALUES (
      'workflow_step','workflow','workflow:'||v_run.id::TEXT||':'||v_def.step_key,
      v_def.name,v_def.task_config->>'description',v_def.task_config->>'expected_outcome',
      'open',v_priority,v_visibility,
      v_requester,v_requester,v_owner,v_assignee,v_department,v_branch,v_run.id,v_def.step_key,
      clock_timestamp(),clock_timestamp(),v_due_at,v_due_at,
      COALESCE(NULLIF(v_def.task_config->>'next_action_text',''),v_def.name),NULL,
      v_completion_mode,v_completion_approval_template_id,clock_timestamp(),1
    ) RETURNING * INTO v_work;

    UPDATE public.work_workflow_step_instances
    SET status='active',work_item_id=v_work.id,activated_at=clock_timestamp(),state_version=state_version+1
    WHERE id=v_instance.id;

    PERFORM private.work_append_system_event(
      v_work.id,'work.workflow_step.activated',NULL,'open',
      jsonb_build_object('workflow_run_id',v_run.id,'step_key',v_def.step_key)
    );
  ELSE
    IF v_def.approval_template_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM public.work_approval_templates t
      WHERE t.id=v_def.approval_template_id
        AND t.is_active=true
        AND t.current_published_version_id IS NOT NULL
    ) THEN
      RAISE EXCEPTION 'workflow approval step template is unavailable';
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

    v_approval_request:=private.work_start_approval_request(
      v_work.id,v_def.approval_template_id,'workflow_step',
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
        'approval_request_id',v_approval_request
      )
    );
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION private.work_activate_workflow_step(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

RESET lock_timeout;
RESET statement_timeout;
