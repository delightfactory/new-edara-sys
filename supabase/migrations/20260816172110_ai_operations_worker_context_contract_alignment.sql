-- ============================================================================
-- AI Operations Planner — Worker Context Contract Alignment
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply until explicitly reviewed/approved.
-- Depends on:
--   * 20260816172000_ai_operations_worker_protocol.sql
--   * 20260816172100_ai_operations_decision_input_guard.sql
--
-- Keep the tested snapshot/context builder intact and wrap only the advertised
-- action requirements so the LLM sees the same contract enforced by DB + TS +
-- reviewed Work bridge.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

ALTER FUNCTION ai_ops.worker_get_context(UUID, TEXT)
  RENAME TO worker_get_context_v1;

CREATE OR REPLACE FUNCTION ai_ops.worker_get_context(
  p_run_id UUID,
  p_worker_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_result JSONB;
BEGIN
  v_result := ai_ops.worker_get_context_v1(p_run_id, p_worker_id);

  IF COALESCE((v_result->>'blocked')::BOOLEAN, false) THEN
    RETURN v_result;
  END IF;

  v_result := jsonb_set(
    v_result,
    '{context,decision_contract,create_work_requires}',
    to_jsonb(ARRAY[
      'recommended_owner_user_id',
      'recommended_assignee_user_id',
      'expected_outcome',
      'next_action_text',
      'due_at'
    ]::TEXT[]),
    false
  );

  v_result := jsonb_set(
    v_result,
    '{context,decision_contract,create_work_due_at_must_be_future}',
    'true'::JSONB,
    true
  );

  v_result := jsonb_set(
    v_result,
    '{context,decision_contract,monitor_review_after_must_be_future}',
    'true'::JSONB,
    true
  );

  RETURN v_result;
END;
$$;

-- Renaming preserves the original function object's revoked privileges. The
-- new public name is also internal-only until a separately reviewed broker is
-- introduced.
REVOKE ALL ON FUNCTION ai_ops.worker_get_context(UUID, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION ai_ops.worker_get_context_v1(UUID, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION ai_ops.worker_get_context(UUID, TEXT) IS
  'Internal bounded worker context. Advertises the same explicit CREATE_WORK and future-date contract enforced by the decision insert guard and reviewed Work bridge.';

RESET lock_timeout;
RESET statement_timeout;
