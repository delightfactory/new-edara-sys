-- Work Management — Migration C2a: internal validated Task draft writer.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION private.work_insert_task_draft(
  p_operation_id UUID,
  p_actor_user_id UUID,
  p_title TEXT,
  p_description TEXT,
  p_expected_outcome TEXT,
  p_priority public.work_priority,
  p_visibility public.work_visibility,
  p_owner_user_id UUID,
  p_assignee_user_id UUID,
  p_due_at TIMESTAMPTZ,
  p_next_action_text VARCHAR(500),
  p_next_action_at TIMESTAMPTZ,
  p_acknowledgement_required BOOLEAN,
  p_completion_mode public.work_completion_mode
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_source_department_id UUID;
  v_owning_department_id UUID;
  v_branch_id UUID;
  v_new public.work_items%ROWTYPE;
BEGIN
  SELECT e.department_id
  INTO v_source_department_id
  FROM public.hr_employees e
  WHERE e.user_id = p_actor_user_id
    AND e.status::TEXT = 'active';

  SELECT e.department_id, e.branch_id
  INTO v_owning_department_id, v_branch_id
  FROM public.hr_employees e
  WHERE e.user_id = p_assignee_user_id
    AND e.status::TEXT = 'active';

  IF v_owning_department_id IS NULL THEN
    SELECT e.department_id, e.branch_id
    INTO v_owning_department_id, v_branch_id
    FROM public.hr_employees e
    WHERE e.user_id = p_owner_user_id
      AND e.status::TEXT = 'active';
  END IF;

  INSERT INTO public.work_items (
    kind, source_kind, title, description, expected_outcome,
    status, priority, visibility,
    creator_user_id, requester_user_id,
    accountable_owner_user_id, current_assignee_user_id,
    source_department_id, owning_department_id, branch_id,
    due_at, first_due_at, next_action_text, next_action_at,
    acknowledgement_required, completion_mode,
    last_meaningful_activity_at, metadata
  ) VALUES (
    'task'::public.work_item_kind,
    'manual'::public.work_source_kind,
    p_title,
    p_description,
    p_expected_outcome,
    'draft'::public.work_item_status,
    p_priority,
    p_visibility,
    p_actor_user_id,
    p_actor_user_id,
    p_owner_user_id,
    p_assignee_user_id,
    v_source_department_id,
    v_owning_department_id,
    v_branch_id,
    p_due_at,
    p_due_at,
    p_next_action_text,
    p_next_action_at,
    p_acknowledgement_required,
    p_completion_mode,
    clock_timestamp(),
    '{}'::JSONB
  ) RETURNING * INTO v_new;

  INSERT INTO public.work_events (
    work_item_id, event_type, actor_user_id, actor_kind,
    to_status, operation_id, payload, created_at
  ) VALUES (
    v_new.id,
    'work.created',
    p_actor_user_id,
    'user'::public.work_actor_kind,
    'draft'::public.work_item_status,
    p_operation_id,
    jsonb_build_object(
      'owner_user_id', p_owner_user_id,
      'assignee_user_id', p_assignee_user_id,
      'priority', p_priority,
      'visibility', p_visibility
    ),
    clock_timestamp()
  );

  RETURN jsonb_build_object(
    'work_item_id', v_new.id,
    'work_number', v_new.work_number,
    'status', v_new.status,
    'state_version', v_new.state_version
  );
END;
$$;

REVOKE ALL ON FUNCTION private.work_insert_task_draft(
  UUID, UUID, TEXT, TEXT, TEXT, public.work_priority, public.work_visibility,
  UUID, UUID, TIMESTAMPTZ, VARCHAR, TIMESTAMPTZ, BOOLEAN, public.work_completion_mode
) FROM PUBLIC, anon, authenticated, service_role;

RESET lock_timeout;
RESET statement_timeout;
