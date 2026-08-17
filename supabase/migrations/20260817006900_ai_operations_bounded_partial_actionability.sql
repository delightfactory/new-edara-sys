-- ============================================================================
-- AI Operations Planner — Bounded Partial Capture Actionability
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply to production until explicitly
-- reviewed, isolated-tested and approved.
--
-- A domain capture can be partial for two very different reasons:
--   1) bounded coverage: lower-ranked cases were intentionally omitted by the
--      shared snapshot budget while each selected case is fully frozen; or
--   2) evidence/source incompleteness: the snapshot itself is partial/blocked.
--
-- Consequential action may proceed only for (1), and only for capture versions
-- whose partial semantics are explicitly known here. Every ambiguous state
-- remains fail closed.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

-- Preserve the full audited domain guards as raw primitives. The wrappers below
-- add one shared capture-actionability gate without duplicating domain logic.
ALTER FUNCTION ai_ops.current_sales_target_decision_issues(UUID)
  RENAME TO current_sales_target_decision_issues_pre_bounded_v1;

ALTER FUNCTION ai_ops.current_customer_health_decision_issues(UUID)
  RENAME TO current_customer_health_decision_issues_pre_bounded_v1;

REVOKE ALL ON FUNCTION ai_ops.current_sales_target_decision_issues_pre_bounded_v1(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION ai_ops.current_customer_health_decision_issues_pre_bounded_v1(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION ai_ops.selected_case_capture_allows_action(
  p_decision_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_decision_type TEXT;
  v_run_business_date DATE;
  v_snapshot_id UUID;
  v_snapshot_status TEXT;
  v_snapshot_data_as_of TIMESTAMPTZ;
  v_domain TEXT;
  v_case_source_as_of TIMESTAMPTZ;
  v_case_payload_bytes INTEGER;
  v_capture_version TEXT;
  v_capture_status TEXT;
  v_capture_source_as_of TIMESTAMPTZ;
  v_capture_business_date DATE;
  v_capture_case_count INTEGER;
  v_capture_evidence_bytes BIGINT;
  v_metadata JSONB;
  v_frozen_domain_case_count INTEGER;
  v_frozen_domain_evidence_bytes BIGINT;
BEGIN
  SELECT
    d.decision_type::TEXT,
    r.business_date,
    s.id,
    s.snapshot_status,
    s.data_as_of,
    sc.domain,
    sc.source_as_of,
    sc.payload_bytes,
    dc.capture_version,
    dc.capture_status,
    dc.source_as_of,
    dc.business_date,
    dc.case_count,
    dc.evidence_bytes,
    dc.metadata
  INTO
    v_decision_type,
    v_run_business_date,
    v_snapshot_id,
    v_snapshot_status,
    v_snapshot_data_as_of,
    v_domain,
    v_case_source_as_of,
    v_case_payload_bytes,
    v_capture_version,
    v_capture_status,
    v_capture_source_as_of,
    v_capture_business_date,
    v_capture_case_count,
    v_capture_evidence_bytes,
    v_metadata
  FROM ai_ops.decisions d
  JOIN ai_ops.planner_runs r ON r.id = d.run_id
  JOIN ai_ops.snapshots s ON s.run_id = d.run_id
  JOIN ai_ops.snapshot_cases sc
    ON sc.snapshot_id = s.id
   AND sc.case_id = d.case_id
  JOIN ai_ops.snapshot_domain_captures dc
    ON dc.snapshot_id = s.id
   AND dc.domain = sc.domain
  WHERE d.id = p_decision_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_decision_type NOT IN ('CREATE_WORK','ESCALATE') THEN
    RETURN false;
  END IF;

  -- Only capture contracts whose partial semantics are known may use the
  -- bounded-coverage exception. Future domains/versions remain fail closed.
  IF NOT (
    (v_domain = 'sales' AND v_capture_version = 'sales-target-gap-v1')
    OR
    (v_domain = 'customer_health' AND v_capture_version = 'customer-health-v1')
  ) THEN
    RETURN false;
  END IF;

  -- A partial/blocked parent snapshot is evidence incompleteness, never merely
  -- domain budget truncation.
  IF v_snapshot_status <> 'ready' THEN
    RETURN false;
  END IF;

  IF v_capture_status NOT IN ('completed','partial') THEN
    RETURN false;
  END IF;

  IF v_capture_source_as_of IS DISTINCT FROM v_snapshot_data_as_of
     OR v_case_source_as_of IS DISTINCT FROM v_snapshot_data_as_of
     OR v_capture_business_date IS DISTINCT FROM v_run_business_date THEN
    RETURN false;
  END IF;

  -- The decision must point at real frozen evidence, and the immutable capture
  -- marker must exactly account for all frozen rows/bytes in this domain.
  IF COALESCE(v_capture_case_count, 0) <= 0
     OR COALESCE(v_capture_evidence_bytes, 0) <= 0
     OR COALESCE(v_case_payload_bytes, 0) <= 0 THEN
    RETURN false;
  END IF;

  SELECT
    COUNT(*)::INTEGER,
    COALESCE(SUM(sc.payload_bytes), 0)::BIGINT
  INTO v_frozen_domain_case_count, v_frozen_domain_evidence_bytes
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id = v_snapshot_id
    AND sc.domain = v_domain;

  IF v_frozen_domain_case_count IS DISTINCT FROM v_capture_case_count
     OR v_frozen_domain_evidence_bytes IS DISTINCT FROM v_capture_evidence_bytes THEN
    RETURN false;
  END IF;

  -- A zero-capacity marker explicitly means the domain had demand but no frozen
  -- selected case. It can never authorize action.
  IF COALESCE(v_metadata->'global_budget_exhausted', 'false'::JSONB) = 'true'::JSONB THEN
    RETURN false;
  END IF;

  IF v_capture_status = 'completed' THEN
    -- Completed known captures must not simultaneously claim omitted cases.
    RETURN COALESCE(v_metadata->'has_more', 'false'::JSONB) = 'false'::JSONB;
  END IF;

  -- For the two trusted v1 capture contracts, partial + ready parent + has_more
  -- + a positive case_limit means bounded selection only. Any missing marker is
  -- ambiguous and therefore blocked.
  RETURN
    v_capture_status = 'partial'
    AND COALESCE(v_metadata->'has_more', 'false'::JSONB) = 'true'::JSONB
    AND (v_metadata ? 'case_limit');
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.selected_case_capture_allows_action(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION ai_ops.apply_selected_case_capture_actionability(
  p_decision_id UUID,
  p_reasons JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_decision_type TEXT;
  v_reasons JSONB := COALESCE(p_reasons, '[]'::JSONB);
BEGIN
  IF jsonb_typeof(v_reasons) <> 'array' THEN
    RETURN jsonb_build_array('invalid_validation_reasons_shape');
  END IF;

  SELECT d.decision_type::TEXT
  INTO v_decision_type
  FROM ai_ops.decisions d
  WHERE d.id = p_decision_id;

  IF NOT FOUND OR v_decision_type NOT IN ('CREATE_WORK','ESCALATE') THEN
    RETURN v_reasons;
  END IF;

  IF ai_ops.selected_case_capture_allows_action(p_decision_id) THEN
    -- Remove only the coverage-level issue. Every domain-specific drift,
    -- parity, freshness, routing, collision and feasibility issue is preserved.
    SELECT COALESCE(jsonb_agg(e.value ORDER BY e.ordinality), '[]'::JSONB)
    INTO v_reasons
    FROM jsonb_array_elements(v_reasons) WITH ORDINALITY AS e(value, ordinality)
    WHERE e.value <> to_jsonb('snapshot_not_complete_for_action'::TEXT);

    RETURN v_reasons;
  END IF;

  -- The shared gate is also fail-closed for malformed/missing capture evidence:
  -- if a raw guard did not already emit the issue, add it here.
  IF NOT (v_reasons @> jsonb_build_array('snapshot_not_complete_for_action')) THEN
    v_reasons := v_reasons || jsonb_build_array('snapshot_not_complete_for_action');
  END IF;

  RETURN v_reasons;
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.apply_selected_case_capture_actionability(UUID, JSONB)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION ai_ops.current_sales_target_decision_issues(
  p_decision_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN ai_ops.apply_selected_case_capture_actionability(
    p_decision_id,
    ai_ops.current_sales_target_decision_issues_pre_bounded_v1(p_decision_id)
  );
END;
$$;

CREATE OR REPLACE FUNCTION ai_ops.current_customer_health_decision_issues(
  p_decision_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN ai_ops.apply_selected_case_capture_actionability(
    p_decision_id,
    ai_ops.current_customer_health_decision_issues_pre_bounded_v1(p_decision_id)
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.current_sales_target_decision_issues(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION ai_ops.current_customer_health_decision_issues(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

-- Rebuild the canonical dispatcher explicitly. Receivables keeps its audited
-- primitive; Sales and Customer Health both pass through the shared gate.
CREATE OR REPLACE FUNCTION ai_ops.current_decision_issues(p_decision_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_domain TEXT;
BEGIN
  SELECT sc.domain
  INTO v_domain
  FROM ai_ops.decisions d
  JOIN ai_ops.snapshots s ON s.run_id = d.run_id
  JOIN ai_ops.snapshot_cases sc
    ON sc.snapshot_id = s.id
   AND sc.case_id = d.case_id
  WHERE d.id = p_decision_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_array('frozen_case_evidence_missing');
  END IF;

  CASE v_domain
    WHEN 'receivables' THEN
      RETURN ai_ops.current_decision_issues_credit_v1(p_decision_id);
    WHEN 'sales' THEN
      RETURN ai_ops.current_sales_target_decision_issues(p_decision_id);
    WHEN 'customer_health' THEN
      RETURN ai_ops.current_customer_health_decision_issues(p_decision_id);
    ELSE
      RETURN jsonb_build_array('unsupported_validation_domain');
  END CASE;
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.current_decision_issues(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION ai_ops.selected_case_capture_allows_action(UUID) IS
  'Fail-closed shared gate separating whole-domain coverage completeness from actionability of a fully frozen selected Sales/Customer Health case.';
COMMENT ON FUNCTION ai_ops.apply_selected_case_capture_actionability(UUID, JSONB) IS
  'Preserves all current-state issues while removing only the coverage-level incomplete-snapshot issue for proven bounded-selection-only partial captures.';
COMMENT ON FUNCTION ai_ops.current_decision_issues(UUID) IS
  'Canonical Receivables/Sales/Customer Health current-state guard; Sales and Customer Health share bounded partial capture actionability semantics.';

RESET lock_timeout;
RESET statement_timeout;
