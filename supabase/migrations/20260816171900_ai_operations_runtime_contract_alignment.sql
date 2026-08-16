-- ============================================================================
-- AI Operations Planner — Runtime Contract Alignment
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply until explicitly reviewed/approved.
--
-- Purpose:
--   Align the foundation table contract with the concrete worker/validation/
--   review/commit pipeline before those functions are created. No AI Operations
--   migration has been deployed, so this migration is part of the fresh-chain
--   contract rather than a production data repair.
--
-- Must execute before:
--   20260816172000_ai_operations_worker_protocol.sql
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

ALTER TABLE ai_ops.planner_runs
  ADD COLUMN claimed_at TIMESTAMPTZ,
  ADD COLUMN prompt_version TEXT NOT NULL DEFAULT 'v1';

ALTER TABLE ai_ops.planner_runs
  ADD CONSTRAINT ai_ops_planner_runs_prompt_version_not_blank
  CHECK (btrim(prompt_version) <> '');

ALTER TABLE ai_ops.decisions
  RENAME COLUMN validation_status TO validation_state;

ALTER TABLE ai_ops.decisions
  RENAME COLUMN work_item_id TO committed_work_item_id;

ALTER TABLE ai_ops.decisions
  ADD COLUMN next_action_text TEXT,
  ADD COLUMN due_at TIMESTAMPTZ,
  ADD COLUMN linked_work_item_id UUID,
  ADD COLUMN validated_at TIMESTAMPTZ,
  ADD COLUMN validated_by_user_id UUID,
  ADD COLUMN committed_at TIMESTAMPTZ;

-- The concrete first-slice validator intentionally collapses historical design
-- variants such as valid/stale/conflict into an auditable binary gate:
-- pending -> validated OR rejected, with reason codes in validation_detail.
ALTER TABLE ai_ops.decisions
  DROP CONSTRAINT ai_ops_decisions_validation_check;

ALTER TABLE ai_ops.decisions
  ADD CONSTRAINT ai_ops_decisions_validation_check CHECK (
    validation_state IN ('pending','validated','rejected')
  );

-- Preserve the existing index name while rebuilding it on the final column.
DROP INDEX IF EXISTS ai_ops.idx_ai_ops_decisions_validation_commit;
CREATE INDEX idx_ai_ops_decisions_validation_commit
  ON ai_ops.decisions(validation_state, commit_status, decision_type);

COMMENT ON COLUMN ai_ops.planner_runs.claimed_at IS
  'Timestamp of the latest worker lease claim; attempt history remains in planner_runs/result_summary.';
COMMENT ON COLUMN ai_ops.planner_runs.prompt_version IS
  'Version identifier for the bounded planner prompt contract used by this run.';
COMMENT ON COLUMN ai_ops.decisions.validation_state IS
  'Current technical safety gate: pending, validated, or rejected. Human approval is stored separately.';
COMMENT ON COLUMN ai_ops.decisions.committed_work_item_id IS
  'Soft reference to Work created from an approved decision; kept soft to preserve bounded-context isolation.';
COMMENT ON COLUMN ai_ops.decisions.linked_work_item_id IS
  'Decision-time Work reference for recommendations such as ESCALATE; execution remains separately governed.';
COMMENT ON COLUMN ai_ops.decisions.validated_by_user_id IS
  'Soft actor reference only. Intentionally has no foreign key to public.profiles so AI migration application never locks or couples to the operational profile table.';

RESET lock_timeout;
RESET statement_timeout;
