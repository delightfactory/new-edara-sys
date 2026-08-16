-- ============================================================================
-- AI Operations Planner — Credit Snapshot Evidence Capture
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply until explicitly reviewed/approved.
-- Depends on:
--   * 20260816163504_ai_operations_foundation.sql
--   * 20260816164500_ai_operations_snapshot_case_evidence.sql
--   * 20260816165500_ai_operations_credit_case_engine.sql
--
-- Replaces only the planner-local refresh routine so each mutable current case
-- also gets an immutable per-snapshot evidence copy.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.refresh_credit_cases(
  p_snapshot_id UUID,
  p_business_date DATE,
  p_limit INTEGER DEFAULT 100
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_candidate RECORD;
  v_case_id UUID;
  v_case_status TEXT;
  v_count INTEGER := 0;
BEGIN
  SELECT * INTO v_snapshot
  FROM ai_ops.snapshots
  WHERE id = p_snapshot_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ai_ops snapshot not found: %', p_snapshot_id;
  END IF;

  FOR v_candidate IN
    SELECT *
    FROM ai_ops.credit_overdue_candidates(p_business_date, p_limit)
  LOOP
    v_count := v_count + 1;

    INSERT INTO ai_ops.cases(
      case_key,
      first_snapshot_id,
      last_snapshot_id,
      domain,
      case_type,
      entity_type,
      entity_id,
      attention_class,
      severity,
      first_seen_at,
      last_seen_at,
      source_as_of,
      facts,
      responsibility_evidence,
      trust,
      status,
      state_version,
      updated_at
    ) VALUES (
      v_candidate.case_key,
      p_snapshot_id,
      p_snapshot_id,
      'receivables',
      'overdue_invoice',
      'sales_order',
      v_candidate.order_id,
      'exception',
      v_candidate.severity,
      v_snapshot.generated_at,
      v_snapshot.generated_at,
      v_snapshot.data_as_of,
      v_candidate.facts,
      v_candidate.responsibility_evidence,
      v_candidate.trust,
      'open',
      1,
      clock_timestamp()
    )
    ON CONFLICT (case_key) DO UPDATE
    SET
      last_snapshot_id = EXCLUDED.last_snapshot_id,
      severity = EXCLUDED.severity,
      last_seen_at = EXCLUDED.last_seen_at,
      source_as_of = EXCLUDED.source_as_of,
      facts = EXCLUDED.facts,
      responsibility_evidence = EXCLUDED.responsibility_evidence,
      trust = EXCLUDED.trust,
      status = CASE
        WHEN ai_ops.cases.status IN ('resolved', 'expired') THEN 'open'
        WHEN ai_ops.cases.status = 'suppressed'
          AND ai_ops.cases.suppressed_until IS NOT NULL
          AND ai_ops.cases.suppressed_until > clock_timestamp()
          THEN 'suppressed'
        ELSE ai_ops.cases.status
      END,
      state_version = ai_ops.cases.state_version + 1,
      updated_at = clock_timestamp()
    RETURNING id, status INTO v_case_id, v_case_status;

    INSERT INTO ai_ops.snapshot_cases(
      snapshot_id,
      case_id,
      case_key,
      snapshot_rank,
      domain,
      case_type,
      entity_type,
      entity_id,
      attention_class,
      severity,
      case_status,
      source_as_of,
      facts,
      responsibility_evidence,
      trust
    ) VALUES (
      p_snapshot_id,
      v_case_id,
      v_candidate.case_key,
      v_count,
      'receivables',
      'overdue_invoice',
      'sales_order',
      v_candidate.order_id,
      'exception',
      v_candidate.severity,
      v_case_status,
      v_snapshot.data_as_of,
      v_candidate.facts,
      v_candidate.responsibility_evidence,
      v_candidate.trust
    )
    ON CONFLICT (snapshot_id, case_id) DO NOTHING;
  END LOOP;

  RETURN jsonb_build_object(
    'snapshot_id', p_snapshot_id,
    'business_date', p_business_date,
    'domain', 'receivables',
    'case_type', 'overdue_invoice',
    'candidates_upserted', v_count,
    'snapshot_evidence_rows', v_count,
    'resolution_performed', false
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.refresh_credit_cases(UUID, DATE, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION ai_ops.refresh_credit_cases(UUID, DATE, INTEGER) FROM anon;
REVOKE ALL ON FUNCTION ai_ops.refresh_credit_cases(UUID, DATE, INTEGER) FROM authenticated;

COMMENT ON FUNCTION ai_ops.refresh_credit_cases(UUID, DATE, INTEGER) IS
  'Upserts current credit cases and freezes the exact ranked evidence in ai_ops.snapshot_cases for historical replay.';

RESET lock_timeout;
RESET statement_timeout;
