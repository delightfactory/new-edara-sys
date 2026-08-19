-- ============================================================================
-- AI Operations Planner — Reviewed Commit Runtime Safety Wrapper
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply until explicitly reviewed/approved.
-- Depends on: 20260816173500_ai_operations_reviewed_work_bridge.sql
--
-- Adds two fail-closed guarantees without duplicating the reviewed Work builder:
--   1) planner_enabled + non-shadow mode are hard kill switches for NEW Work.
--   2) an unexplained existing source_key is a collision, not a recovery path
--      that can bypass approval/current-state validation.
--
-- Exact idempotent retry after a successful commit remains readable even if a
-- kill switch is later enabled because it performs no new operational mutation.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

ALTER FUNCTION private.work_create_ai_reviewed_task(UUID, UUID)
  RENAME TO work_create_ai_reviewed_task_v1;

CREATE OR REPLACE FUNCTION private.work_create_ai_reviewed_task(
  p_decision_id UUID,
  p_approved_execution_by UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_settings ai_ops.settings%ROWTYPE;
  v_decision ai_ops.decisions%ROWTYPE;
  v_existing_work public.work_items%ROWTYPE;
  v_source_key TEXT;
BEGIN
  -- Same transaction-level lock as the underlying builder. PostgreSQL advisory
  -- xact locks are re-entrant for the same session, so the v1 call remains safe.
  PERFORM pg_advisory_xact_lock(hashtextextended('ai_ops:commit:' || p_decision_id::TEXT, 0));

  SELECT * INTO v_decision
  FROM ai_ops.decisions
  WHERE id = p_decision_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI Operations decision not found';
  END IF;

  -- Exact retry after a completed commit is an idempotent read, not new work.
  IF v_decision.committed_work_item_id IS NOT NULL THEN
    RETURN private.work_create_ai_reviewed_task_v1(
      p_decision_id,
      p_approved_execution_by
    );
  END IF;

  SELECT * INTO v_settings
  FROM ai_ops.settings
  WHERE singleton = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI Operations settings are not initialized';
  END IF;

  IF NOT v_settings.planner_enabled THEN
    RETURN jsonb_build_object(
      'committed', false,
      'blocked', true,
      'reason', 'planner_disabled_kill_switch'
    );
  END IF;

  IF v_settings.shadow_mode THEN
    RETURN jsonb_build_object(
      'committed', false,
      'blocked', true,
      'reason', 'shadow_mode_blocks_operational_commit'
    );
  END IF;

  v_source_key := 'ai_ops:decision:' || p_decision_id::TEXT;

  SELECT * INTO v_existing_work
  FROM public.work_items wi
  WHERE wi.source_kind = 'system'::public.work_source_kind
    AND wi.source_key = v_source_key
  ORDER BY wi.created_at ASC, wi.id ASC
  LIMIT 1;

  -- The reviewed bridge is one transaction. If Work exists but the decision
  -- does not point to it, that is not a legitimate partial commit to adopt.
  IF FOUND THEN
    RETURN jsonb_build_object(
      'committed', false,
      'blocked', true,
      'reason', 'unexpected_source_key_collision',
      'work_item_id', v_existing_work.id,
      'work_number', v_existing_work.work_number
    );
  END IF;

  RETURN private.work_create_ai_reviewed_task_v1(
    p_decision_id,
    p_approved_execution_by
  );
END;
$$;

REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_task(UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_task_v1(UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION private.work_create_ai_reviewed_task(UUID, UUID) IS
  'Runtime safety wrapper for reviewed AI Work commit: exact retry allowed, new commits require planner enabled + non-shadow mode, and unexplained source-key collisions fail closed.';

RESET lock_timeout;
RESET statement_timeout;
