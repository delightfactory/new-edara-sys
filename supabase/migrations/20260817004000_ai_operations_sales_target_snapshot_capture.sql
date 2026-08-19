-- ============================================================================
-- AI Operations Planner — Sales & Targets Snapshot Evidence Capture
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply to production until explicitly
-- reviewed, isolated-tested and approved.
-- Depends on:
--   * 20260816163504_ai_operations_foundation.sql
--   * 20260816164500_ai_operations_snapshot_case_evidence.sql
--   * 20260816164700_ai_operations_snapshot_domain_captures.sql
--   * 20260817003000_ai_operations_sales_target_case_engine.sql
--
-- Freezes the exact Sales/Targets case facts, responsibility evidence,
-- supporting execution evidence and governed operational context that a
-- planner run is allowed to see.
--
-- No operational Target/Sales/Activity/Visit/HR/Work table is mutated.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.refresh_sales_target_cases(
  p_snapshot_id UUID,
  p_business_date DATE,
  p_limit INTEGER DEFAULT 50
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
  v_context_total INTEGER;
  v_context_captured INTEGER;
  v_context JSONB;
  v_count INTEGER := 0;
  v_evidence_bytes BIGINT := 0;
  v_context_rows INTEGER := 0;
  v_context_truncated_cases INTEGER := 0;
  v_parity_failed_cases INTEGER := 0;
  v_capture_status TEXT := 'completed';
  v_has_more BOOLEAN := false;
  v_rank_offset INTEGER := 0;
  v_effective_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
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
      AND dc.domain = 'sales'
  ) THEN
    RAISE EXCEPTION 'ai_ops sales domain already captured: %', p_snapshot_id;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM ai_ops.snapshot_cases sc
    WHERE sc.snapshot_id = p_snapshot_id
      AND sc.domain = 'sales'
  ) THEN
    RAISE EXCEPTION 'ai_ops sales evidence exists without capture marker: %', p_snapshot_id;
  END IF;

  SELECT COALESCE(MAX(sc.snapshot_rank), 0)
  INTO v_rank_offset
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id = p_snapshot_id;

  SELECT COUNT(*) > v_effective_limit
  INTO v_has_more
  FROM ai_ops.sales_target_candidates(
    p_business_date,
    LEAST(v_effective_limit + 1, 100)
  );

  IF v_snapshot.snapshot_status = 'blocked' THEN
    v_capture_status := 'blocked';
  ELSIF v_snapshot.snapshot_status = 'partial' OR v_has_more THEN
    v_capture_status := 'partial';
  END IF;

  FOR v_candidate IN
    SELECT *
    FROM ai_ops.sales_target_candidates(p_business_date, v_effective_limit)
  LOOP
    v_count := v_count + 1;

    IF NOT COALESCE((v_candidate.contribution_evidence->>'parity_ok')::BOOLEAN, false) THEN
      v_parity_failed_cases := v_parity_failed_cases + 1;
    END IF;

    INSERT INTO ai_ops.cases(
      case_key, first_snapshot_id, last_snapshot_id, domain, case_type,
      entity_type, entity_id, attention_class, severity, first_seen_at,
      last_seen_at, source_as_of, facts, responsibility_evidence, trust,
      status, state_version, updated_at
    ) VALUES (
      v_candidate.case_key, p_snapshot_id, p_snapshot_id, 'sales',
      'target_trajectory_gap', 'target', v_candidate.target_id, 'exception',
      v_candidate.severity, v_snapshot.generated_at, v_snapshot.generated_at,
      v_snapshot.data_as_of, v_candidate.facts, v_candidate.responsibility_evidence,
      v_candidate.trust, 'open', 1, clock_timestamp()
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

    -- Freeze only governed context valid at snapshot time. Text remains bounded
    -- and explicitly marked as data. Context can explain a target/product/scope
    -- situation but can never alter planner policy or tool contracts.
    SELECT count(*)::INTEGER
    INTO v_context_total
    FROM ai_ops.operational_context oc
    WHERE oc.status = 'active'
      AND oc.valid_from <= v_snapshot.data_as_of
      AND (oc.valid_until IS NULL OR oc.valid_until > v_snapshot.data_as_of)
      AND oc.visibility IN ('management', 'standard')
      AND (oc.confidence_class <> 'ai_inference' OR oc.approved_by_user_id IS NOT NULL)
      AND (
        (oc.subject_type = 'target' AND oc.subject_id = v_candidate.target_id)
        OR (
          oc.subject_type = 'product'
          AND NULLIF(v_candidate.facts->>'product_id', '') IS NOT NULL
          AND oc.subject_id = (v_candidate.facts->>'product_id')::UUID
        )
        OR (
          oc.subject_type = 'product_category'
          AND NULLIF(v_candidate.facts->>'category_id', '') IS NOT NULL
          AND oc.subject_id = (v_candidate.facts->>'category_id')::UUID
        )
        OR (
          oc.subject_type = 'department'
          AND v_candidate.target_scope = 'department'
          AND oc.subject_id = v_candidate.target_scope_id
        )
        OR (
          oc.subject_type = 'branch'
          AND v_candidate.target_scope = 'branch'
          AND oc.subject_id = v_candidate.target_scope_id
        )
        OR (
          oc.subject_type = 'employee'
          AND v_candidate.target_scope = 'individual'
          AND oc.subject_id = v_candidate.target_scope_id
        )
      );

    SELECT COALESCE(
      jsonb_agg(context_item ORDER BY priority_rank, updated_at DESC, context_id),
      '[]'::JSONB
    )
    INTO v_context
    FROM (
      SELECT
        oc.id AS context_id,
        oc.updated_at,
        CASE oc.confidence_class
          WHEN 'hard_policy' THEN 1
          WHEN 'approved_human' THEN 2
          WHEN 'explicit_human' THEN 3
          WHEN 'system_record' THEN 4
          WHEN 'system_inference' THEN 5
          ELSE 6
        END AS priority_rank,
        jsonb_build_object(
          'id', oc.id,
          'subject_type', oc.subject_type,
          'subject_id', oc.subject_id,
          'context_type', oc.context_type,
          'summary', left(COALESCE(NULLIF(oc.context_payload->>'summary', ''), oc.context_type), 500),
          'owner_user_id', oc.owner_user_id,
          'owner_label', owner_profile.full_name,
          'source_type', oc.source_type,
          'confidence_class', oc.confidence_class,
          'lifecycle_type', oc.lifecycle_type,
          'valid_from', oc.valid_from,
          'valid_until', oc.valid_until,
          'review_on', oc.review_on,
          'visibility', oc.visibility,
          'content_trust', 'governed_untrusted_text'
        ) AS context_item
      FROM ai_ops.operational_context oc
      LEFT JOIN public.profiles owner_profile ON owner_profile.id = oc.owner_user_id
      WHERE oc.status = 'active'
        AND oc.valid_from <= v_snapshot.data_as_of
        AND (oc.valid_until IS NULL OR oc.valid_until > v_snapshot.data_as_of)
        AND oc.visibility IN ('management', 'standard')
        AND (oc.confidence_class <> 'ai_inference' OR oc.approved_by_user_id IS NOT NULL)
        AND (
          (oc.subject_type = 'target' AND oc.subject_id = v_candidate.target_id)
          OR (
            oc.subject_type = 'product'
            AND NULLIF(v_candidate.facts->>'product_id', '') IS NOT NULL
            AND oc.subject_id = (v_candidate.facts->>'product_id')::UUID
          )
          OR (
            oc.subject_type = 'product_category'
            AND NULLIF(v_candidate.facts->>'category_id', '') IS NOT NULL
            AND oc.subject_id = (v_candidate.facts->>'category_id')::UUID
          )
          OR (
            oc.subject_type = 'department'
            AND v_candidate.target_scope = 'department'
            AND oc.subject_id = v_candidate.target_scope_id
          )
          OR (
            oc.subject_type = 'branch'
            AND v_candidate.target_scope = 'branch'
            AND oc.subject_id = v_candidate.target_scope_id
          )
          OR (
            oc.subject_type = 'employee'
            AND v_candidate.target_scope = 'individual'
            AND oc.subject_id = v_candidate.target_scope_id
          )
        )
      ORDER BY priority_rank, oc.updated_at DESC, oc.id
      LIMIT 5
    ) bounded_context;

    v_context_captured := jsonb_array_length(v_context);
    v_context_rows := v_context_rows + v_context_captured;
    IF v_context_total > v_context_captured THEN
      v_context_truncated_cases := v_context_truncated_cases + 1;
    END IF;

    v_context := jsonb_build_object(
      'items', v_context,
      'total', v_context_total,
      'captured', v_context_captured,
      'truncated', v_context_total > v_context_captured,
      'max_per_case', 5
    );

    v_case_payload_bytes := octet_length(convert_to(
      jsonb_build_object(
        'case_key', v_candidate.case_key,
        'domain', 'sales',
        'case_type', 'target_trajectory_gap',
        'severity', v_candidate.severity,
        'facts', v_candidate.facts,
        'responsibility_evidence', v_candidate.responsibility_evidence,
        'operational_context', v_context,
        'trust', v_candidate.trust
      )::TEXT,
      'UTF8'
    ));

    INSERT INTO ai_ops.snapshot_cases(
      snapshot_id, case_id, case_key, snapshot_rank, domain, case_type,
      entity_type, entity_id, attention_class, severity, case_status,
      source_as_of, facts, responsibility_evidence, operational_context,
      trust, payload_bytes
    ) VALUES (
      p_snapshot_id, v_case_id, v_candidate.case_key,
      v_rank_offset + v_count, 'sales', 'target_trajectory_gap', 'target',
      v_candidate.target_id, 'exception', v_candidate.severity, v_case_status,
      v_snapshot.data_as_of, v_candidate.facts,
      v_candidate.responsibility_evidence, v_context,
      v_candidate.trust, v_case_payload_bytes
    );

    v_evidence_bytes := v_evidence_bytes + v_case_payload_bytes;
  END LOOP;

  INSERT INTO ai_ops.snapshot_domain_captures(
    snapshot_id, domain, capture_version, source_as_of, business_date,
    case_count, evidence_bytes, capture_status, metadata
  ) VALUES (
    p_snapshot_id, 'sales', 'sales-target-gap-v1', v_snapshot.data_as_of,
    p_business_date, v_count, v_evidence_bytes, v_capture_status,
    jsonb_build_object(
      'case_type', 'target_trajectory_gap',
      'supported_target_types', jsonb_build_array('sales_value', 'product_qty'),
      'case_limit', v_effective_limit,
      'has_more', v_has_more,
      'context_rows_captured', v_context_rows,
      'context_truncated_cases', v_context_truncated_cases,
      'contribution_parity_failed_cases', v_parity_failed_cases,
      'field_execution_interpretation', 'supporting_only_no_uniform_activity_baseline',
      'max_context_per_case', 5,
      'target_recalculation_performed', false,
      'resolution_performed', false
    )
  );

  RETURN jsonb_build_object(
    'snapshot_id', p_snapshot_id,
    'business_date', p_business_date,
    'domain', 'sales',
    'case_type', 'target_trajectory_gap',
    'capture_status', v_capture_status,
    'candidates_upserted', v_count,
    'snapshot_evidence_rows', v_count,
    'snapshot_evidence_bytes', v_evidence_bytes,
    'context_rows_captured', v_context_rows,
    'context_truncated_cases', v_context_truncated_cases,
    'contribution_parity_failed_cases', v_parity_failed_cases,
    'has_more', v_has_more,
    'capture_marker_written', true,
    'target_recalculation_performed', false,
    'resolution_performed', false
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.refresh_sales_target_cases(UUID, DATE, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION ai_ops.refresh_sales_target_cases(UUID, DATE, INTEGER) FROM anon;
REVOKE ALL ON FUNCTION ai_ops.refresh_sales_target_cases(UUID, DATE, INTEGER) FROM authenticated;
REVOKE ALL ON FUNCTION ai_ops.refresh_sales_target_cases(UUID, DATE, INTEGER) FROM service_role;

COMMENT ON FUNCTION ai_ops.refresh_sales_target_cases(UUID, DATE, INTEGER) IS
  'Single-shot Sales/Targets capture: updates current target-gap cases and freezes exact facts, responsibility evidence, governed context and bytes without mutating operational targets or sales.';

RESET lock_timeout;
RESET statement_timeout;
