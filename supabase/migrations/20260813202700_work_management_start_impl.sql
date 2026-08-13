-- Work Management — Migration C5b: Start validation/orchestration.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION private.start_work_item_atomic_impl(
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
BEGIN
  v_prepare := private.work_prepare_operation(
    p_operation_id, v_actor, 'start_work_item_atomic',
    jsonb_build_object('work_item_id', p_work_item_id, 'expected_state_version', p_expected_state_version), p_work_item_id
  );
  IF NOT COALESCE((v_prepare->>'execute')::BOOLEAN, false) THEN RETURN v_prepare->'response'; END IF;

  BEGIN
    SELECT * INTO v_item FROM public.work_items WHERE id = p_work_item_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'work item not found'; END IF;
    IF v_item.state_version <> p_expected_state_version THEN
      PERFORM private.work_fail_operation(p_operation_id, 'STATE_VERSION_CONFLICT', 'تم تعديل المهمة من جلسة أخرى؛ حدّث البيانات وحاول مجددًا', 'start', NULL);
      RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'start_work_item_atomic', 'replayed', false,
        'error', jsonb_build_object('code', 'STATE_VERSION_CONFLICT', 'message', 'تم تعديل المهمة من جلسة أخرى؛ حدّث البيانات وحاول مجددًا', 'current_state_version', v_item.state_version));
    END IF;
    IF v_item.status <> 'open'::public.work_item_status THEN RAISE EXCEPTION 'invalid start state'; END IF;
    IF NOT (v_actor = v_item.current_assignee_user_id OR private.work_user_can_manage_item(v_actor, v_item.id)) THEN RAISE EXCEPTION 'not authorised'; END IF;
    IF NOT private.work_actor_is_active(v_item.current_assignee_user_id) THEN RAISE EXCEPTION 'inactive assignee'; END IF;
    IF EXISTS (
      SELECT 1 FROM public.work_dependencies d
      WHERE d.blocked_work_item_id = v_item.id
        AND d.dependency_strength = 'hard'::public.work_dependency_strength
        AND d.resolved_at IS NULL
    ) THEN RAISE EXCEPTION 'hard dependency unresolved'; END IF;

    v_result := private.work_apply_start(p_operation_id, v_actor, v_item.id);
    PERFORM private.work_complete_operation(p_operation_id, v_item.id, v_result);
    RETURN jsonb_build_object('ok', true, 'operation_id', p_operation_id, 'operation', 'start_work_item_atomic', 'replayed', false, 'data', v_result);
  EXCEPTION WHEN OTHERS THEN
    PERFORM private.work_fail_operation(p_operation_id, CASE WHEN SQLSTATE='P0001' THEN 'DOMAIN_VALIDATION_FAILED' ELSE 'INTERNAL_ERROR' END,
      CASE WHEN SQLSTATE='P0001' THEN 'تعذر بدء المهمة في حالتها الحالية أو لوجود مانع تنفيذي' ELSE 'فشل بدء المهمة بسبب خطأ داخلي' END,
      'start', SQLERRM);
    RETURN jsonb_build_object('ok', false, 'operation_id', p_operation_id, 'operation', 'start_work_item_atomic', 'replayed', false,
      'error', jsonb_build_object('code', CASE WHEN SQLSTATE='P0001' THEN 'DOMAIN_VALIDATION_FAILED' ELSE 'INTERNAL_ERROR' END,
        'message', CASE WHEN SQLSTATE='P0001' THEN 'تعذر بدء المهمة في حالتها الحالية أو لوجود مانع تنفيذي' ELSE 'فشل بدء المهمة بسبب خطأ داخلي' END));
  END;
END;
$$;

REVOKE ALL ON FUNCTION private.start_work_item_atomic_impl(UUID, UUID, BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.start_work_item_atomic_impl(UUID, UUID, BIGINT) TO authenticated, service_role;
RESET lock_timeout;
RESET statement_timeout;
