-- ============================================================================
-- AI Operations Planner — Immutable Snapshot Case Evidence
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply until explicitly reviewed/approved.
-- Depends on: 20260816163504_ai_operations_foundation.sql
--
-- Why this exists:
--   ai_ops.cases is the CURRENT materialized case state and is intentionally
--   updated across planner runs. It cannot by itself prove what evidence an AI
--   run saw historically. This table freezes the exact bounded case evidence
--   attached to each immutable snapshot.
--
-- Resource accounting:
--   snapshots.payload_bytes measures the compact snapshot/header envelope.
--   snapshot_cases.payload_bytes measures each frozen case evidence envelope.
--   Their sum provides a cheap conservative serialized-context budget before
--   a planner worker requests the snapshot.
--
-- This remains fully inside ai_ops. No operational table is altered.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE TABLE ai_ops.snapshot_cases (
  snapshot_id UUID NOT NULL
    REFERENCES ai_ops.snapshots(id) ON DELETE RESTRICT,
  case_id UUID NOT NULL
    REFERENCES ai_ops.cases(id) ON DELETE RESTRICT,
  case_key TEXT NOT NULL,
  snapshot_rank INTEGER NOT NULL,
  domain VARCHAR(80) NOT NULL,
  case_type VARCHAR(100) NOT NULL,
  entity_type VARCHAR(80),
  entity_id UUID,
  attention_class TEXT NOT NULL,
  severity TEXT NOT NULL,
  case_status TEXT NOT NULL,
  source_as_of TIMESTAMPTZ NOT NULL,
  facts JSONB NOT NULL DEFAULT '{}'::JSONB,
  responsibility_evidence JSONB NOT NULL DEFAULT '{}'::JSONB,
  trust JSONB NOT NULL DEFAULT '{}'::JSONB,
  payload_bytes INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT ai_ops_snapshot_cases_pkey PRIMARY KEY (snapshot_id, case_id),
  CONSTRAINT ai_ops_snapshot_cases_key_uniq UNIQUE (snapshot_id, case_key),
  CONSTRAINT ai_ops_snapshot_cases_rank_uniq UNIQUE (snapshot_id, snapshot_rank),
  CONSTRAINT ai_ops_snapshot_cases_rank_positive CHECK (snapshot_rank > 0),
  CONSTRAINT ai_ops_snapshot_cases_payload_bytes_nonnegative CHECK (payload_bytes >= 0),
  CONSTRAINT ai_ops_snapshot_cases_key_not_blank CHECK (btrim(case_key) <> ''),
  CONSTRAINT ai_ops_snapshot_cases_entity_pair CHECK (
    (entity_type IS NULL AND entity_id IS NULL)
    OR (entity_type IS NOT NULL AND entity_id IS NOT NULL)
  ),
  CONSTRAINT ai_ops_snapshot_cases_attention_class_check
    CHECK (attention_class IN ('exception','opportunity','integrity','continuity')),
  CONSTRAINT ai_ops_snapshot_cases_severity_check
    CHECK (severity IN ('low','medium','high','critical')),
  CONSTRAINT ai_ops_snapshot_cases_status_check
    CHECK (case_status IN ('open','monitored','actioned','resolved','suppressed','expired')),
  CONSTRAINT ai_ops_snapshot_cases_json_objects CHECK (
    jsonb_typeof(facts) = 'object'
    AND jsonb_typeof(responsibility_evidence) = 'object'
    AND jsonb_typeof(trust) = 'object'
  )
);

CREATE INDEX idx_ai_ops_snapshot_cases_domain_rank
  ON ai_ops.snapshot_cases(snapshot_id, domain, snapshot_rank);

COMMENT ON TABLE ai_ops.snapshot_cases IS
  'Immutable per-snapshot copy of the exact bounded case evidence seen by the planner. payload_bytes supports preflight AI context budgeting; ai_ops.cases remains current mutable case state.';

-- Reuse the foundation immutability guard for the evidence rows.
CREATE TRIGGER trg_ai_ops_snapshot_cases_immutable
  BEFORE UPDATE OR DELETE ON ai_ops.snapshot_cases
  FOR EACH ROW EXECUTE FUNCTION ai_ops.reject_snapshot_mutation();

ALTER TABLE ai_ops.snapshot_cases ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE ai_ops.snapshot_cases FROM PUBLIC;
REVOKE ALL ON TABLE ai_ops.snapshot_cases FROM anon;
REVOKE ALL ON TABLE ai_ops.snapshot_cases FROM authenticated;

RESET lock_timeout;
RESET statement_timeout;
