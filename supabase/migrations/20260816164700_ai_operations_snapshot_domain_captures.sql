-- ============================================================================
-- AI Operations Planner — Immutable Snapshot Domain Captures
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply until explicitly reviewed/approved.
-- Depends on:
--   * 20260816163504_ai_operations_foundation.sql
--   * 20260816164500_ai_operations_snapshot_case_evidence.sql
--
-- Purpose:
--   * prove that a domain capture completed even when it produced ZERO cases
--   * make per-domain evidence counts/bytes auditable and replayable
--   * provide a safe foundation for future multi-domain snapshots
--
-- This remains fully inside ai_ops. No operational table is altered.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE TABLE ai_ops.snapshot_domain_captures (
  snapshot_id UUID NOT NULL
    REFERENCES ai_ops.snapshots(id) ON DELETE RESTRICT,
  domain VARCHAR(80) NOT NULL,
  capture_version VARCHAR(60) NOT NULL,
  source_as_of TIMESTAMPTZ NOT NULL,
  business_date DATE NOT NULL,
  case_count INTEGER NOT NULL DEFAULT 0,
  evidence_bytes BIGINT NOT NULL DEFAULT 0,
  capture_status TEXT NOT NULL DEFAULT 'completed',
  metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
  captured_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT ai_ops_snapshot_domain_captures_pkey
    PRIMARY KEY (snapshot_id, domain),
  CONSTRAINT ai_ops_snapshot_domain_captures_domain_not_blank
    CHECK (btrim(domain) <> ''),
  CONSTRAINT ai_ops_snapshot_domain_captures_version_not_blank
    CHECK (btrim(capture_version) <> ''),
  CONSTRAINT ai_ops_snapshot_domain_captures_case_count_nonnegative
    CHECK (case_count >= 0),
  CONSTRAINT ai_ops_snapshot_domain_captures_evidence_bytes_nonnegative
    CHECK (evidence_bytes >= 0),
  CONSTRAINT ai_ops_snapshot_domain_captures_status_check
    CHECK (capture_status IN ('completed','partial','blocked')),
  CONSTRAINT ai_ops_snapshot_domain_captures_metadata_object
    CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE INDEX idx_ai_ops_snapshot_domain_captures_domain_time
  ON ai_ops.snapshot_domain_captures(domain, captured_at DESC, snapshot_id);

COMMENT ON TABLE ai_ops.snapshot_domain_captures IS
  'Immutable proof that a specific domain capture completed for a snapshot, including zero-case captures and serialized evidence byte accounting.';

CREATE TRIGGER trg_ai_ops_snapshot_domain_captures_immutable
  BEFORE UPDATE OR DELETE ON ai_ops.snapshot_domain_captures
  FOR EACH ROW EXECUTE FUNCTION ai_ops.reject_snapshot_mutation();

ALTER TABLE ai_ops.snapshot_domain_captures ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE ai_ops.snapshot_domain_captures FROM PUBLIC;
REVOKE ALL ON TABLE ai_ops.snapshot_domain_captures FROM anon;
REVOKE ALL ON TABLE ai_ops.snapshot_domain_captures FROM authenticated;

RESET lock_timeout;
RESET statement_timeout;
