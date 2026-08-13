-- Work Management — Migration C3a: Activate Work Item implementation.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION private.activate_work_item_atomic_impl(
  p_operation_id UUID,
  p_work_item_id UUID,
  p_expected_state_version BIGINT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_prepare JSONB;
  v_item public.work_items%ROWTYPE;
  v_result JSONB;
  v_safe_code TEXT;
  v_safe_message TEXT;
BEGIN
  v_prepare := private.work_prepare_operation(
    p_operation_id,
    v_actor,
    'activate_work_item_atomic',
    jsonb_build_object('work_item_id', p_work_item_id, 'expected_state_version', p_expected_state_version),
    p_work_item_id
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN, false) THEN RETURN v_prepare->'response'; END IF;

  BEGIN
    SELECT * INTO v_item
    FROM public.work_items
    WHERE id = p_work_item_id
    FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'work item not found'; END IF;
    IF v_item.state_version <> p_expected_state_version THEN
      PERFORM private.work_fail_operation(p_operation_id, 'STATE_VERSION_CONFLICT', 'تم تعديل المهمة من جلسة أخرى؛ حدّث البيانات وحاول مجددًا', 'activate', NULL);
      RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'activate_work_item_atomic', 'replayed', false,
        'error', jsonb_build_object('code', 'STATE_VERSION_CONFLICT', 'message', 'تم تعديل المهمة من جلسة أخرى؛ حدّث البيانات وحاول مجددًا', 'current_state_version', v_item.state_version));
    END IF;

    IF v_item.status <> 'draft'::public.work_item_status THEN RAISE EXCEPTION 'invalid state'; END IF;
    IF NOT (v_actor = v_item.creator_user_id OR v_actor = v_item.accountable_owner_user_id OR private.work_user_can_manage_item(v_actor, v_item.id)) THEN
      RAISE EXCEPTION 'not authorised to activate';
    END IF;
    IF v_item.accountable_owner_user_id IS NULL OR v_item.current_assignee_user_id IS NULL THEN RAISE EXCEPTION 'owner and assignee required'; END IF;
    IF NOT private.work_actor_is_active(v_item.accountable_owner_user_id) OR NOT private.work_actor_is_active(v_item.current_assignee_user_id) THEN RAISE EXCEPTION 'inactive responsibility actor'; END IF;
    IF v_item.expected_outcome IS NULL OR btrim(v_item.expected_outcome) = '' THEN RAISE EXCEPTION 'expected outcome required'; END IF;
    IF v_item.next_action_text IS NULL OR btrim(v_item.next_action_text) = '' THEN RAISE EXCEPTION 'next action required'; END IF;
    IF v_item.next_action_at IS NULL AND v_item.due_at IS NULL THEN RAISE EXCEPTION 'operational clock required'; END IF;

    UPDATE public.work_items
    SET status = 'open'::public.work_item_status,
        activated_at = clock_timestamp(),
        assigned_at = COALESCE(assigned_at, clock_timestamp()),
        last_meaningful_activity_at = clock_timestamp(),
        state_version = state_version + 1
    WHERE id = v_item.id
    RETURNING * INTO v_item;

    INSERT INTO public.work_events(work_item_id, event_type, actor_user_id, actor_kind, from_status, to_status, operation_id, payload, created_at)
    VALUES(v_item.id, 'work.activated', v_actor, 'user'::public.work_actor_kind, 'draft'::public.work_item_status, 'open'::public.work_item_status,
      p_operation_id, jsonb_build_object('assignee_user_id', v_item.current_assignee_user_id, 'owner_user_id', v_item.accountable_owner_user_id), clock_timestamp());

    v_result := jsonb_build_object('work_item_id', v_item.id, 'status', v_item.status, 'state_version', v_item.state_version);
    PERFORM private.work_complete_operation(p_operation_id, v_item.id, v_result);
    RETURN jsonb_build_object('ok', true, 'operation_id', p_operation_id, 'operation', 'activate_work_item_atomic', 'replayed', false, 'data', v_result);
  EXCEPTION WHEN OTHERS THEN
    v_safe_code := CASE WHEN SQLSTATE = 'P0001' THEN 'DOMAIN_VALIDATION_FAILED' ELSE 'INTERNAL_ERROR' END;
    v_safe_message := CASE WHEN SQLSTATE = 'P0001' THEN 'تعذر تفعيل المهمة لعدم استيفاء شروط التفعيل أو الصلاحية' ELSE 'فشل تفعيل المهمة بسبب خطأ داخلي' END;
    PERFORM private.work_fail_operation(p_operation_id, v_safe_code, v_safe_message, 'activate', SQLERRM);
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'activate_work_item_atomic', 'replayed', false,
      'error', jsonb_build_object('code', v_safe_code, 'message', v_safe_message));
  END;
END;
$$;

REVOKE ALL ON FUNCTION private.activate_work_item_atomic_impl(UUID, UUID, BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.activate_work_item_atomic_impl(UUID, UUID, BIGINT) TO authenticated, service_role;
RESET lock_timeout;
RESET statement_timeout;
