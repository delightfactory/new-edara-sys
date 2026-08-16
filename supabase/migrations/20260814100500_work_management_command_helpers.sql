-- Work Management — shared command-engine helpers.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION private.work_actor_can_update_item(
  p_actor_user_id UUID,
  p_work_item_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_item public.work_items%ROWTYPE;
BEGIN
  IF NOT private.work_actor_is_active(p_actor_user_id) THEN
    RETURN false;
  END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id = p_work_item_id;
  IF NOT FOUND THEN RETURN false; END IF;

  IF private.work_user_can_manage_item(p_actor_user_id, p_work_item_id) THEN
    RETURN true;
  END IF;

  RETURN COALESCE(public.check_permission(p_actor_user_id, 'work.items.update_own'), false)
    AND p_actor_user_id IN (
      v_item.creator_user_id,
      v_item.requester_user_id,
      v_item.accountable_owner_user_id,
      v_item.current_assignee_user_id
    );
END;
$$;

CREATE OR REPLACE FUNCTION private.work_actor_can_comment_item(
  p_actor_user_id UUID,
  p_work_item_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_item public.work_items%ROWTYPE;
BEGIN
  IF NOT private.work_actor_is_active(p_actor_user_id)
     OR NOT COALESCE(public.check_permission(p_actor_user_id, 'work.items.comment'), false) THEN
    RETURN false;
  END IF;

  SELECT * INTO v_item FROM public.work_items WHERE id = p_work_item_id;
  IF NOT FOUND THEN RETURN false; END IF;

  RETURN private.work_user_can_view_row(
    p_actor_user_id,
    v_item.id,
    v_item.visibility,
    v_item.creator_user_id,
    v_item.requester_user_id,
    v_item.accountable_owner_user_id,
    v_item.current_assignee_user_id,
    v_item.branch_id,
    v_item.owning_department_id
  ) AND NOT EXISTS (
    SELECT 1 FROM public.work_participants p
    WHERE p.work_item_id = p_work_item_id
      AND p.user_id = p_actor_user_id
      AND p.removed_at IS NULL
      AND p.can_comment = false
  );
END;
$$;

CREATE OR REPLACE FUNCTION private.work_command_error(
  p_operation_id UUID,
  p_operation_name TEXT,
  p_code TEXT,
  p_message TEXT,
  p_subject_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_operation_id IS NOT NULL THEN
    PERFORM private.work_fail_operation(
      p_operation_id,
      p_code,
      p_message,
      p_operation_name,
      p_subject_id::TEXT
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', false,
    'operation_id', p_operation_id,
    'operation', p_operation_name,
    'replayed', false,
    'error', jsonb_build_object('code', p_code, 'message', p_message)
  );
END;
$$;

CREATE OR REPLACE FUNCTION private.work_command_success(
  p_operation_id UUID,
  p_operation_name TEXT,
  p_subject_id UUID,
  p_result JSONB
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM private.work_complete_operation(p_operation_id, p_subject_id, p_result);
  RETURN jsonb_build_object(
    'ok', true,
    'operation_id', p_operation_id,
    'operation', p_operation_name,
    'replayed', false,
    'data', COALESCE(p_result, '{}'::JSONB)
  );
END;
$$;

CREATE OR REPLACE FUNCTION private.work_append_user_event(
  p_work_item_id UUID,
  p_event_type TEXT,
  p_actor_user_id UUID,
  p_operation_id UUID,
  p_from_status public.work_item_status,
  p_to_status public.work_item_status,
  p_payload JSONB DEFAULT '{}'::JSONB,
  p_acting_for_user_id UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO public.work_events(
    work_item_id, event_type, actor_user_id, acting_for_user_id,
    actor_kind, from_status, to_status, operation_id, payload, created_at
  ) VALUES (
    p_work_item_id, p_event_type, p_actor_user_id, p_acting_for_user_id,
    'user'::public.work_actor_kind, p_from_status, p_to_status,
    p_operation_id, COALESCE(p_payload, '{}'::JSONB), clock_timestamp()
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION private.work_assert_expected_version(
  p_work_item_id UUID,
  p_expected_version BIGINT
) RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.work_items w
    WHERE w.id = p_work_item_id
      AND w.state_version = p_expected_version
  );
$$;

CREATE OR REPLACE FUNCTION private.work_completion_blockers(
  p_work_item_id UUID
) RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'required_checklist_open', EXISTS(
      SELECT 1 FROM public.work_checklist_items c
      WHERE c.work_item_id = p_work_item_id
        AND c.is_required = true
        AND c.completed_at IS NULL
    ),
    'required_child_open', EXISTS(
      SELECT 1 FROM public.work_items child
      WHERE child.parent_work_item_id = p_work_item_id
        AND child.blocks_parent_completion = true
        AND child.status NOT IN ('done'::public.work_item_status, 'cancelled'::public.work_item_status)
    ),
    'hard_dependency_open', EXISTS(
      SELECT 1 FROM public.work_dependencies d
      JOIN public.work_items blocker ON blocker.id = d.blocker_work_item_id
      WHERE d.blocked_work_item_id = p_work_item_id
        AND d.resolved_at IS NULL
        AND d.dependency_strength = 'hard'::public.work_dependency_strength
        AND blocker.status <> 'done'::public.work_item_status
    )
  );
$$;

REVOKE ALL ON FUNCTION private.work_actor_can_update_item(UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.work_actor_can_comment_item(UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.work_command_error(UUID, TEXT, TEXT, TEXT, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.work_command_success(UUID, TEXT, UUID, JSONB)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.work_append_user_event(UUID, TEXT, UUID, UUID, public.work_item_status, public.work_item_status, JSONB, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.work_assert_expected_version(UUID, BIGINT)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.work_completion_blockers(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

RESET lock_timeout;
RESET statement_timeout;
