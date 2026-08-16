-- ============================================================================
-- AI Operations Planner — Decision Input Guard
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply until explicitly reviewed/approved.
-- Depends on:
--   * 20260816171900_ai_operations_runtime_contract_alignment.sql
--   * 20260816172000_ai_operations_worker_protocol.sql
--
-- Purpose:
--   Make the persisted decision contract at least as strict as the first Work
--   bridge. A staged CREATE_WORK must already be executable without hidden
--   routing/deadline defaults; a MONITOR must have a future review point.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.enforce_decision_insert_contract()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_now TIMESTAMPTZ := clock_timestamp();
BEGIN
  IF NEW.decision_type = 'MONITOR' THEN
    IF NEW.review_after IS NULL OR NEW.review_after <= v_now THEN
      RAISE EXCEPTION 'MONITOR decisions require a future review_after';
    END IF;
  END IF;

  IF NEW.decision_type = 'CREATE_WORK' THEN
    IF NEW.recommended_owner_user_id IS NULL
       OR NEW.recommended_assignee_user_id IS NULL
       OR NULLIF(btrim(COALESCE(NEW.expected_outcome, '')), '') IS NULL
       OR NULLIF(btrim(COALESCE(NEW.next_action_text, '')), '') IS NULL
       OR NEW.due_at IS NULL THEN
      RAISE EXCEPTION 'CREATE_WORK requires explicit owner, assignee, expected_outcome, next_action_text and due_at';
    END IF;

    IF NEW.due_at <= v_now THEN
      RAISE EXCEPTION 'CREATE_WORK due_at must be in the future';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ai_ops_decision_insert_contract ON ai_ops.decisions;
CREATE TRIGGER trg_ai_ops_decision_insert_contract
BEFORE INSERT ON ai_ops.decisions
FOR EACH ROW
EXECUTE FUNCTION ai_ops.enforce_decision_insert_contract();

REVOKE ALL ON FUNCTION ai_ops.enforce_decision_insert_contract()
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION ai_ops.enforce_decision_insert_contract() IS
  'Fail-closed insert guard keeping staged decision payloads compatible with the reviewed first-slice Work bridge; never supplies defaults.';

RESET lock_timeout;
RESET statement_timeout;
