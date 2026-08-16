-- ============================================================================
-- AI Operations Planner — Credit Snapshot Evidence Capture
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply until explicitly reviewed/approved.
-- Depends on:
--   * 20260816163504_ai_operations_foundation.sql
--   * 20260816164500_ai_operations_snapshot_case_evidence.sql
--   * 20260816164700_ai_operations_snapshot_domain_captures.sql
--   * 20260816165500_ai_operations_credit_case_engine.sql
--
-- Replaces only the planner-local refresh routine so each mutable current case
-- also gets an immutable per-snapshot evidence copy.
--
-- Capture is intentionally single-shot per snapshot/domain. A durable domain
-- marker proves completion even when the bounded result contains zero cases.
-- Idempotent retry belongs at build_credit_snapshot(), which reuses an existing
-- completed capture before rereading any operational data.
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
  v_case_payload_bytes INTEGER;
  v_count INTEGER := 0;
  v_evidence_bytes BIGINT := 0;
  v_capture_status TEXT := 'completed';
  v_has_more BOOLEAN := false;
BEGIN
  SELECT * INTO v_snapshot
  FROM ai_ops.snapshots
  WHERE id = p_snapshot_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ai_ops snapshot not found: %', p_snapshot_id;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM ai_ops.snapshot_domain_captures dc
    WHERE dc.snapshot_id = p_snapshot_id
      AND dc.domain = 'receivables'
  ) THEN
    RAISE EXCEPTION 'ai_ops receivables domain already captured: %', p_snapshot_id;
  END IF;

  -- A snapshot_cases row without its immutable domain completion marker is an
  -- inconsistent partial capture. Fail closed rather than silently recapturing.
  IF EXISTS (
    SELECT 1
    FROM ai_ops.snapshot_cases sc
    WHERE sc.snapshot_id = p_snapshot_id
      AND sc.domain = 'receivables'
  ) THEN
    RAISE EXCEPTION 'ai_ops receivables evidence exists without capture marker: %', p_snapshot_id;
  END IF;

  v_has_more := COALESCE((v_snapshot.coverage->>'has_more')::BOOLEAN, false);
  IF v_snapshot.snapshot_status <> 'ready' OR v_has_more THEN
    v_capture_status := 'partial';
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

    v_case_payload_bytes := octet_length(convert_to(
      jsonb_build_object(
        'case_key', v_candidate.case_key,
        'domain', 'receivables',
        'case_type', 'overdue_invoice',
        'severity', v_candidate.severity,
        'facts', v_candidate.facts,
        'responsibility_evidence', v_candidate.responsibility_evidence,
        'trust', v_candidate.trust
      )::TEXT,
      'UTF8'
    ));

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
      trust,
      payload_bytes
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
      v_candidate.trust,
      v_case_payload_bytes
    );

    v_evidence_bytes := v_evidence_bytes + v_case_payload_bytes;
  END LOOP;

  -- This row is the completion proof. It is written even when v_count = 0.
  INSERT INTO ai_ops.snapshot_domain_captures(
    snapshot_id,
    domain,
    capture_version,
    source_as_of,
    business_date,
    case_count,
    evidence_bytes,
    capture_status,
    metadata
  ) VALUES (
    p_snapshot_id,
    'receivables',
    'credit-overdue-v1',
    v_snapshot.data_as_of,
    p_business_date,
    v_count,
    v_evidence_bytes,
    v_capture_status,
    jsonb_build_object(
      'case_type', 'overdue_invoice',
      'case_limit', LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500),
      'has_more', v_has_more,
      'resolution_performed', false
    )
  );

  RETURN jsonb_build_object(
    'snapshot_id', p_snapshot_id,
    'business_date', p_business_date,
    'domain', 'receivables',
    'case_type', 'overdue_invoice',
    'capture_status', v_capture_status,
    'candidates_upserted', v_count,
    'snapshot_evidence_rows', v_count,
    'snapshot_evidence_bytes', v_evidence_bytes,
    'capture_marker_written', true,
    'resolution_performed', false
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.refresh_credit_cases(UUID, DATE, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION ai_ops.refresh_credit_cases(UUID, DATE, INTEGER) FROM anon;
REVOKE ALL ON FUNCTION ai_ops.refresh_credit_cases(UUID, DATE, INTEGER) FROM authenticated;

COMMENT ON FUNCTION ai_ops.refresh_credit_cases(UUID, DATE, INTEGER) IS
  'Single-shot receivables capture: updates current cases, freezes exact evidence/bytes, and writes an immutable domain completion marker even for zero cases. Retry through build_credit_snapshot().';

RESET lock_timeout;
RESET statement_timeout;
