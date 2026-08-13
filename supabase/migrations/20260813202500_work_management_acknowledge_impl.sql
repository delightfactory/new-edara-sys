-- Work Management — Migration C4a: assignment acknowledgement implementation.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION private.acknowledge_work_assignment_atomic_impl(
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
    p_operation_id, v_actor, 'acknowledge_work_assignment_atomic',
    jsonb_build_object('work_item_id', p_work_item_id, 'expected_state_version', p_expected_state_version), p_work_item_id
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN, false) THEN RETURN v_prepare->'response'; END IF;

  BEGIN
    SELECT * INTO v_item FROM public.work_items WHERE id = p_work_item_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'work item not found'; END IF;

    IF v_item.state_version <> p_expected_state_version THEN
      PERFORM private.work_fail_operation(p_operation_id, 'STATE_VERSION_CONFLICT', 'تم تعديل المهمة من جلسة أخرى؛ حدّث البيانات وحاول مجددًا', 'acknowledge', NULL);
      RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'acknowledge_work_assignment_atomic', 'replayed', false,
        'error', jsonb_build_object('code', 'STATE_VERSION_CONFLICT', 'message', 'تم تعديل المهمة من جلسة أخرى؛ حدّث البيانات وحاول مجددًا', 'current_state_version', v_item.state_version));
    END IF;

    IF v_item.status IN ('draft'::public.work_item_status, 'done'::public.work_item_status, 'cancelled'::public.work_item_status) THEN
      RAISE EXCEPTION 'invalid acknowledgement state';
    END IF;
    IF v_actor IS DISTINCT FROM v_item.current_assignee_user_id THEN RAISE EXCEPTION 'only current assignee may acknowledge'; END IF;
    IF NOT private.work_actor_is_active(v_actor) THEN RAISE EXCEPTION 'inactive actor'; END IF;

    UPDATE public.work_items
    SET first_viewed_at = COALESCE(first_viewed_at, clock_timestamp()),
        acknowledged_at = COALESCE(acknowledged_at, clock_timestamp()),
        state_version = state_version + 1
    WHERE id = v_item.id
    RETURNING * INTO v_item;

    INSERT INTO public.work_events(work_item_id, event_type, actor_user_id, actor_kind, operation_id, payload, created_at)
    VALUES(v_item.id, 'work.acknowledged', v_actor, 'user'::public.work_actor_kind, p_operation_id,
      jsonb_build_object('assigned_at', v_item.assigned_at, 'acknowledged_at', v_item.acknowledged_at), clock_timestamp());

    v_result := jsonb_build_object('work_item_id', v_item.id, 'status', v_item.status, 'state_version', v_item.state_version,
      'first_viewed_at', v_item.first_viewed_at, 'acknowledged_at', v_item.acknowledged_at);
    PERFORM private.work_complete_operation(p_operation_id, v_item.id, v_result);
    RETURN jsonb_build_object('ok', true, 'operation_id', p_operation_id, 'operation', 'acknowledge_work_assignment_atomic', 'replayed', false, 'data', v_result);
  EXCEPTION WHEN OTHERS THEN
    v_safe_code := CASE WHEN SQLSTATE = 'P0001' THEN 'DOMAIN_VALIDATION_FAILED' ELSE 'INTERNAL_ERROR' END;
    v_safe_message := CASE WHEN SQLSTATE = 'P0001' THEN 'تعذر تأكيد استلام المهمة في حالتها الحالية' ELSE 'فشل تأكيد استلام المهمة بسبب خطأ داخلي' END;
    PERFORM private.work_fail_operation(p_operation_id, v_safe_code, v_safe_message, 'acknowledge', SQLERRM);
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'acknowledge_work_assignment_atomic', 'replayed', false,
      'error', jsonb_build_object('code', v_safe_code, 'message', v_safe_message));
  END;
END;
$$;

REVOKE ALL ON FUNCTION private.acknowledge_work_assignment_atomic_impl(UUID, UUID, BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.acknowledge_work_assignment_atomic_impl(UUID, UUID, BIGINT) TO authenticated, service_role;
RESET lock_timeout;
RESET statement_timeout;
