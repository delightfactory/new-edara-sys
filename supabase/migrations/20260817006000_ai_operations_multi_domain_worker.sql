-- ============================================================================
-- AI Operations Planner — Multi-Domain Snapshot + Worker Integration
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply to production until explicitly
-- reviewed, isolated-tested and approved.
--
-- Extends the proven Receivables worker path to include the Sales/Targets slice
-- without duplicating planner state or weakening any existing worker guards.
-- Receivables remains the legacy snapshot header creator; immutable per-domain
-- capture markers are the authoritative multi-domain coverage record.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

-- --------------------------------------------------------------------------
-- One bounded snapshot, two domain captures, one global case budget.
--
-- The budget is split evenly while both domains have demand. Unused capacity
-- from one domain spills to the other. No cross-domain severity comparison is
-- performed because severity scales are domain-specific.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ai_ops.build_operational_snapshot(
  p_run_id UUID,
  p_case_limit INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_run ai_ops.planner_runs%ROWTYPE;
  v_settings ai_ops.settings%ROWTYPE;
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_credit_capture ai_ops.snapshot_domain_captures%ROWTYPE;
  v_sales_capture ai_ops.snapshot_domain_captures%ROWTYPE;
  v_now TIMESTAMPTZ := clock_timestamp();
  v_limit INTEGER;
  v_credit_demand INTEGER := 0;
  v_sales_demand INTEGER := 0;
  v_credit_quota INTEGER := 0;
  v_sales_quota INTEGER := 0;
  v_credit_alloc INTEGER := 0;
  v_sales_alloc INTEGER := 0;
  v_remaining INTEGER := 0;
  v_credit_build JSONB;
  v_sales_build JSONB;
  v_context_bound BOOLEAN := false;
  v_sales_has_candidate BOOLEAN := false;
  v_total_cases INTEGER := 0;
  v_domain_captures JSONB := '[]'::JSONB;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('ai_ops:operational_snapshot:' || p_run_id::TEXT, 0));

  SELECT * INTO v_run
  FROM ai_ops.planner_runs
  WHERE id = p_run_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ai_ops planner run not found: %', p_run_id;
  END IF;

  SELECT * INTO v_settings
  FROM ai_ops.settings
  WHERE singleton = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI Operations settings are not initialized';
  END IF;

  v_limit := LEAST(
    GREATEST(COALESCE(p_case_limit, v_settings.max_cases_per_snapshot), 1),
    v_settings.max_cases_per_snapshot
  );

  SELECT * INTO v_snapshot
  FROM ai_ops.snapshots
  WHERE run_id = p_run_id;

  IF FOUND THEN
    SELECT * INTO v_credit_capture
    FROM ai_ops.snapshot_domain_captures dc
    WHERE dc.snapshot_id = v_snapshot.id AND dc.domain = 'receivables';

    IF NOT FOUND THEN
      RAISE EXCEPTION 'existing planner snapshot is missing receivables capture marker: %', v_snapshot.id;
    END IF;

    SELECT * INTO v_sales_capture
    FROM ai_ops.snapshot_domain_captures dc
    WHERE dc.snapshot_id = v_snapshot.id AND dc.domain = 'sales';

    IF FOUND THEN
      v_total_cases := v_credit_capture.case_count + v_sales_capture.case_count;
      IF v_total_cases > v_limit THEN
        RAISE EXCEPTION 'existing snapshot case count % exceeds global limit %', v_total_cases, v_limit;
      END IF;

      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'domain', dc.domain,
        'capture_status', dc.capture_status,
        'case_count', dc.case_count,
        'evidence_bytes', dc.evidence_bytes,
        'capture_version', dc.capture_version,
        'metadata', dc.metadata
      ) ORDER BY CASE dc.domain WHEN 'receivables' THEN 0 WHEN 'sales' THEN 1 ELSE 2 END, dc.domain), '[]'::JSONB)
      INTO v_domain_captures
      FROM ai_ops.snapshot_domain_captures dc
      WHERE dc.snapshot_id = v_snapshot.id;

      RETURN jsonb_build_object(
        'snapshot_id', v_snapshot.id,
        'run_id', p_run_id,
        'business_date', v_run.business_date,
        'global_case_limit', v_limit,
        'captured_cases', v_total_cases,
        'idempotent_reuse', true,
        'domain_captures', v_domain_captures
      );
    END IF;

    -- Historical credit-only snapshots may be augmented only before a worker
    -- context hash exists. Once reasoning was bound to a context, evidence is
    -- immutable for that run and must never be silently expanded.
    v_context_bound := NULLIF(v_run.result_summary->>'worker_context_hash', '') IS NOT NULL;
    IF v_context_bound THEN
      RAISE EXCEPTION 'existing snapshot is already bound to a worker context and cannot add a new domain';
    END IF;

    v_remaining := GREATEST(v_limit - v_credit_capture.case_count, 0);

    SELECT count(*)::INTEGER INTO v_sales_demand
    FROM ai_ops.sales_target_candidates(v_run.business_date, v_limit);

    v_sales_alloc := LEAST(v_sales_demand, v_remaining);

    IF v_sales_alloc > 0 THEN
      v_sales_build := ai_ops.refresh_sales_target_cases(v_snapshot.id, v_run.business_date, v_sales_alloc);
    ELSE
      SELECT EXISTS(
        SELECT 1 FROM ai_ops.sales_target_candidates(v_run.business_date, 1)
      ) INTO v_sales_has_candidate;

      INSERT INTO ai_ops.snapshot_domain_captures(
        snapshot_id, domain, capture_version, source_as_of, business_date,
        case_count, evidence_bytes, capture_status, metadata
      ) VALUES (
        v_snapshot.id,
        'sales',
        'sales-target-gap-v1',
        v_now,
        v_run.business_date,
        0,
        0,
        CASE WHEN v_sales_has_candidate THEN 'partial' ELSE 'completed' END,
        jsonb_build_object(
          'capture_marker_written', true,
          'case_type', 'target_trajectory_gap',
          'global_budget_exhausted', v_sales_has_candidate,
          'global_case_limit', v_limit,
          'remaining_case_budget', 0,
          'has_more', v_sales_has_candidate,
          'target_recalculation_performed', false
        )
      );
    END IF;
  ELSE
    IF v_run.status NOT IN ('pending', 'claimed', 'reasoning') THEN
      RAISE EXCEPTION 'planner run status does not allow snapshot build: %', v_run.status;
    END IF;

    -- Demand is measured only to allocate the bounded context. Operational
    -- sources remain read-only and target progress is never recalculated here.
    SELECT LEAST(count(*)::INTEGER, v_limit)
    INTO v_credit_demand
    FROM public.sales_orders so
    WHERE so.status IN (
      'delivered'::public.sales_order_status,
      'partially_delivered'::public.sales_order_status
    )
      AND so.payment_terms IN ('credit', 'mixed')
      AND so.delivered_at IS NOT NULL
      AND so.due_date IS NOT NULL
      AND so.due_date < v_run.business_date
      AND GREATEST(
        0::NUMERIC,
        COALESCE(so.total_amount, 0)
          - COALESCE(so.paid_amount, 0)
          - COALESCE(so.returned_amount, 0)
      ) > 0;

    SELECT count(*)::INTEGER INTO v_sales_demand
    FROM ai_ops.sales_target_candidates(v_run.business_date, v_limit);

    v_credit_quota := (v_limit + 1) / 2;
    v_sales_quota := v_limit / 2;
    v_credit_alloc := LEAST(v_credit_demand, v_credit_quota);
    v_sales_alloc := LEAST(v_sales_demand, v_sales_quota);
    v_remaining := v_limit - v_credit_alloc - v_sales_alloc;

    -- Spill only unused quota; no cross-domain severity/rank comparison.
    IF v_remaining > 0 AND v_credit_demand > v_credit_alloc THEN
      v_credit_alloc := v_credit_alloc + LEAST(v_remaining, v_credit_demand - v_credit_alloc);
      v_remaining := v_limit - v_credit_alloc - v_sales_alloc;
    END IF;
    IF v_remaining > 0 AND v_sales_demand > v_sales_alloc THEN
      v_sales_alloc := v_sales_alloc + LEAST(v_remaining, v_sales_demand - v_sales_alloc);
      v_remaining := v_limit - v_credit_alloc - v_sales_alloc;
    END IF;

    -- build_credit_snapshot requires a minimum argument of one. Passing one
    -- when Credit demand is zero still captures zero Credit cases and consumes
    -- no global case slot.
    v_credit_build := ai_ops.build_credit_snapshot(p_run_id, GREATEST(v_credit_alloc, 1));

    SELECT * INTO v_snapshot
    FROM ai_ops.snapshots
    WHERE run_id = p_run_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'snapshot missing after credit base build';
    END IF;

    SELECT * INTO v_credit_capture
    FROM ai_ops.snapshot_domain_captures dc
    WHERE dc.snapshot_id = v_snapshot.id AND dc.domain = 'receivables';

    IF NOT FOUND THEN
      RAISE EXCEPTION 'receivables capture missing after credit base build';
    END IF;

    -- Recalculate the remaining hard cap from what was actually captured.
    v_remaining := GREATEST(v_limit - v_credit_capture.case_count, 0);
    v_sales_alloc := LEAST(v_sales_alloc, v_remaining);

    IF v_sales_alloc > 0 THEN
      v_sales_build := ai_ops.refresh_sales_target_cases(v_snapshot.id, v_run.business_date, v_sales_alloc);
    ELSE
      v_sales_has_candidate := v_sales_demand > 0;
      INSERT INTO ai_ops.snapshot_domain_captures(
        snapshot_id, domain, capture_version, source_as_of, business_date,
        case_count, evidence_bytes, capture_status, metadata
      ) VALUES (
        v_snapshot.id,
        'sales',
        'sales-target-gap-v1',
        v_now,
        v_run.business_date,
        0,
        0,
        CASE WHEN v_sales_has_candidate THEN 'partial' ELSE 'completed' END,
        jsonb_build_object(
          'capture_marker_written', true,
          'case_type', 'target_trajectory_gap',
          'global_budget_exhausted', v_sales_has_candidate,
          'global_case_limit', v_limit,
          'allocated_case_limit', 0,
          'has_more', v_sales_has_candidate,
          'target_recalculation_performed', false
        )
      );
    END IF;
  END IF;

  SELECT * INTO v_credit_capture
  FROM ai_ops.snapshot_domain_captures dc
  WHERE dc.snapshot_id = v_snapshot.id AND dc.domain = 'receivables';
  SELECT * INTO v_sales_capture
  FROM ai_ops.snapshot_domain_captures dc
  WHERE dc.snapshot_id = v_snapshot.id AND dc.domain = 'sales';

  IF v_credit_capture.snapshot_id IS NULL OR v_sales_capture.snapshot_id IS NULL THEN
    RAISE EXCEPTION 'multi-domain snapshot did not produce both immutable domain capture markers';
  END IF;

  v_total_cases := v_credit_capture.case_count + v_sales_capture.case_count;
  IF v_total_cases > v_limit THEN
    RAISE EXCEPTION 'multi-domain snapshot case count % exceeds global limit %', v_total_cases, v_limit;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'domain', dc.domain,
    'capture_status', dc.capture_status,
    'case_count', dc.case_count,
    'evidence_bytes', dc.evidence_bytes,
    'capture_version', dc.capture_version,
    'metadata', dc.metadata
  ) ORDER BY CASE dc.domain WHEN 'receivables' THEN 0 WHEN 'sales' THEN 1 ELSE 2 END, dc.domain), '[]'::JSONB)
  INTO v_domain_captures
  FROM ai_ops.snapshot_domain_captures dc
  WHERE dc.snapshot_id = v_snapshot.id;

  RETURN jsonb_build_object(
    'snapshot_id', v_snapshot.id,
    'run_id', p_run_id,
    'business_date', v_run.business_date,
    'global_case_limit', v_limit,
    'credit_demand', v_credit_demand,
    'sales_demand', v_sales_demand,
    'credit_allocated_limit', v_credit_alloc,
    'sales_allocated_limit', v_sales_alloc,
    'captured_cases', v_total_cases,
    'idempotent_reuse', false,
    'domain_captures', v_domain_captures,
    'target_recalculation_performed', false
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.build_operational_snapshot(UUID, INTEGER)
  FROM PUBLIC, anon, authenticated, service_role;

-- Preserve the proven Credit context implementation as an internal primitive.
ALTER FUNCTION ai_ops.worker_get_context(UUID, TEXT)
  RENAME TO worker_get_context_credit_v2;

REVOKE ALL ON FUNCTION ai_ops.worker_get_context_credit_v2(UUID, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;

-- --------------------------------------------------------------------------
-- Canonical worker context now contains every frozen case and every immutable
-- domain capture from the one snapshot. The old singular receivables
-- domain_capture field remains for backward-compatible readers; domain_captures
-- is authoritative for multi-domain coverage.
-- --------------------------------------------------------------------------
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
  v_run ai_ops.planner_runs%ROWTYPE;
  v_settings ai_ops.settings%ROWTYPE;
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_credit_result JSONB;
  v_build JSONB;
  v_cases JSONB := '[]'::JSONB;
  v_domain_captures JSONB := '[]'::JSONB;
  v_coverage JSONB := '{}'::JSONB;
  v_body JSONB;
  v_hash TEXT;
  v_context_bytes INTEGER;
  v_total_cases INTEGER := 0;
  v_capture_count INTEGER := 0;
  v_any_partial BOOLEAN := false;
  v_any_blocked BOOLEAN := false;
  v_now TIMESTAMPTZ := clock_timestamp();
BEGIN
  IF p_worker_id IS NULL OR btrim(p_worker_id) = '' OR length(p_worker_id) > 120 THEN
    RAISE EXCEPTION 'invalid worker id';
  END IF;

  SELECT * INTO v_run
  FROM ai_ops.planner_runs
  WHERE id = p_run_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'planner run not found';
  END IF;

  IF v_run.claimed_by IS DISTINCT FROM p_worker_id
     OR v_run.status NOT IN ('claimed','reasoning')
     OR v_run.lease_expires_at IS NULL
     OR v_run.lease_expires_at <= v_now THEN
    RAISE EXCEPTION 'worker lease is not valid for run';
  END IF;

  SELECT * INTO v_settings
  FROM ai_ops.settings
  WHERE singleton = true;

  IF NOT FOUND OR NOT v_settings.planner_enabled THEN
    RAISE EXCEPTION 'planner disabled while run is claimed';
  END IF;

  -- Build both domains before invoking the preserved Credit context primitive;
  -- it will reuse the existing immutable snapshot rather than recapture Credit.
  v_build := ai_ops.build_operational_snapshot(p_run_id, v_settings.max_cases_per_snapshot);
  v_credit_result := ai_ops.worker_get_context_credit_v2(p_run_id, p_worker_id);

  IF COALESCE((v_credit_result->>'blocked')::BOOLEAN, false) THEN
    RETURN v_credit_result;
  END IF;

  SELECT * INTO v_snapshot
  FROM ai_ops.snapshots
  WHERE run_id = p_run_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'run snapshot missing after multi-domain build';
  END IF;

  SELECT COALESCE(jsonb_agg(case_payload ORDER BY snapshot_rank ASC), '[]'::JSONB)
  INTO v_cases
  FROM (
    SELECT
      sc.snapshot_rank,
      jsonb_build_object(
        'case_id', sc.case_id,
        'case_key', sc.case_key,
        'rank', sc.snapshot_rank,
        'domain', sc.domain,
        'case_type', sc.case_type,
        'entity_type', sc.entity_type,
        'entity_id', sc.entity_id,
        'attention_class', sc.attention_class,
        'severity', sc.severity,
        'case_status_at_snapshot', sc.case_status,
        'source_as_of', sc.source_as_of,
        'facts', sc.facts,
        'responsibility_evidence', sc.responsibility_evidence,
        'operational_context', sc.operational_context,
        'trust', sc.trust
      ) AS case_payload
    FROM ai_ops.snapshot_cases sc
    WHERE sc.snapshot_id = v_snapshot.id
    ORDER BY sc.snapshot_rank ASC
  ) q;

  SELECT
    COALESCE(jsonb_agg(jsonb_build_object(
      'domain', dc.domain,
      'capture_status', dc.capture_status,
      'case_count', dc.case_count,
      'evidence_bytes', dc.evidence_bytes,
      'capture_version', dc.capture_version,
      'business_date', dc.business_date,
      'source_as_of', dc.source_as_of,
      'metadata', dc.metadata
    ) ORDER BY CASE dc.domain WHEN 'receivables' THEN 0 WHEN 'sales' THEN 1 ELSE 2 END, dc.domain), '[]'::JSONB),
    COALESCE(sum(dc.case_count), 0)::INTEGER,
    count(*)::INTEGER,
    COALESCE(bool_or(dc.capture_status = 'partial'), false),
    COALESCE(bool_or(dc.capture_status = 'blocked'), false)
  INTO v_domain_captures, v_total_cases, v_capture_count, v_any_partial, v_any_blocked
  FROM ai_ops.snapshot_domain_captures dc
  WHERE dc.snapshot_id = v_snapshot.id;

  IF v_capture_count < 2
     OR NOT EXISTS (SELECT 1 FROM ai_ops.snapshot_domain_captures dc WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='receivables')
     OR NOT EXISTS (SELECT 1 FROM ai_ops.snapshot_domain_captures dc WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='sales') THEN
    RAISE EXCEPTION 'worker context requires immutable receivables and sales domain captures';
  END IF;

  IF v_total_cases > v_settings.max_cases_per_snapshot THEN
    RAISE EXCEPTION 'frozen case count % exceeds global planner limit %', v_total_cases, v_settings.max_cases_per_snapshot;
  END IF;

  v_coverage := jsonb_build_object(
    'global_case_limit', v_settings.max_cases_per_snapshot,
    'captured_cases', v_total_cases,
    'domain_capture_count', v_capture_count,
    'all_domain_captures_complete', NOT v_any_partial AND NOT v_any_blocked,
    'legacy_credit_header_coverage', v_snapshot.coverage
  );

  v_body := v_credit_result->'context';
  v_body := jsonb_set(v_body, '{cases}', v_cases, false);
  v_body := jsonb_set(v_body, '{snapshot,domain_captures}', v_domain_captures, true);
  v_body := jsonb_set(v_body, '{snapshot,coverage}', v_coverage, false);
  v_body := jsonb_set(
    v_body,
    '{snapshot,snapshot_status}',
    to_jsonb(CASE
      WHEN v_any_blocked THEN 'blocked'
      WHEN v_any_partial OR v_snapshot.snapshot_status <> 'ready' THEN 'partial'
      ELSE 'ready'
    END::TEXT),
    false
  );

  v_context_bytes := octet_length(convert_to(v_body::TEXT, 'UTF8'));

  IF v_context_bytes > v_settings.max_worker_context_bytes THEN
    UPDATE ai_ops.planner_runs
    SET
      status = 'partial',
      checkpoint = 'context_budget_blocked',
      heartbeat_at = v_now,
      lease_expires_at = NULL,
      error_class = 'context_budget_exceeded',
      error_message = format('multi-domain worker context %s bytes exceeds limit %s', v_context_bytes, v_settings.max_worker_context_bytes),
      result_summary = result_summary || jsonb_build_object(
        'snapshot_id', v_snapshot.id,
        'worker_context_bytes', v_context_bytes,
        'worker_context_limit_bytes', v_settings.max_worker_context_bytes,
        'worker_domain_count', v_capture_count,
        'worker_case_count', v_total_cases
      ),
      completed_at = v_now,
      updated_at = v_now
    WHERE id = p_run_id;

    RETURN jsonb_build_object(
      'blocked', true,
      'reason', 'context_budget_exceeded',
      'run_id', p_run_id,
      'snapshot_id', v_snapshot.id,
      'context_bytes', v_context_bytes,
      'context_limit_bytes', v_settings.max_worker_context_bytes
    );
  END IF;

  -- MD5 remains payload identity only, never authentication.
  v_hash := md5(v_body::TEXT);

  UPDATE ai_ops.planner_runs
  SET
    status = 'reasoning',
    checkpoint = 'context_ready',
    heartbeat_at = v_now,
    lease_expires_at = v_now + interval '20 minutes',
    cases_seen = v_total_cases,
    result_summary = result_summary || jsonb_build_object(
      'snapshot_id', v_snapshot.id,
      'worker_context_hash', v_hash,
      'worker_context_hash_algorithm', 'md5-jsonb-identity',
      'worker_context_bytes', v_context_bytes,
      'worker_context_limit_bytes', v_settings.max_worker_context_bytes,
      'worker_domain_count', v_capture_count,
      'worker_case_count', v_total_cases,
      'multi_domain_context', true
    ),
    updated_at = v_now
  WHERE id = p_run_id;

  RETURN jsonb_build_object(
    'blocked', false,
    'context_hash', v_hash,
    'context_hash_algorithm', 'md5-jsonb-identity',
    'context_bytes', v_context_bytes,
    'context_limit_bytes', v_settings.max_worker_context_bytes,
    'context', v_body
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.worker_get_context(UUID, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;

-- --------------------------------------------------------------------------
-- Replace the staging cardinality assumption: one decision is required for
-- every frozen case across every captured domain, not receivables only.
-- All original bounded payload, idempotency and no-execution guarantees remain.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ai_ops.worker_stage_decisions(
  p_run_id UUID,
  p_worker_id TEXT,
  p_context_hash TEXT,
  p_decisions JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_run ai_ops.planner_runs%ROWTYPE;
  v_settings ai_ops.settings%ROWTYPE;
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_now TIMESTAMPTZ := clock_timestamp();
  v_expected_case_count INTEGER := 0;
  v_decision_count INTEGER;
  v_distinct_case_count INTEGER;
  v_action_count INTEGER;
  v_submission_hash TEXT;
  v_existing_count INTEGER;
  v_existing_hashes INTEGER;
  v_item JSONB;
  v_case_id UUID;
  v_decision_type TEXT;
  v_owner UUID;
  v_assignee UUID;
  v_linked_work UUID;
BEGIN
  IF jsonb_typeof(p_decisions) <> 'array' THEN
    RAISE EXCEPTION 'decisions payload must be a JSON array';
  END IF;

  SELECT * INTO v_run
  FROM ai_ops.planner_runs
  WHERE id = p_run_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'planner run not found'; END IF;
  IF v_run.claimed_by IS DISTINCT FROM p_worker_id
     OR v_run.status <> 'reasoning'
     OR v_run.lease_expires_at IS NULL
     OR v_run.lease_expires_at <= v_now THEN
    RAISE EXCEPTION 'worker lease is not valid for staging';
  END IF;

  IF NULLIF(p_context_hash, '') IS NULL
     OR v_run.result_summary->>'worker_context_hash' IS DISTINCT FROM p_context_hash THEN
    RAISE EXCEPTION 'worker context hash does not match the run context';
  END IF;

  SELECT * INTO v_settings FROM ai_ops.settings WHERE singleton = true;
  SELECT * INTO v_snapshot FROM ai_ops.snapshots WHERE run_id = p_run_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'run snapshot not found'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM ai_ops.snapshot_domain_captures dc
    WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='receivables'
  ) OR NOT EXISTS (
    SELECT 1 FROM ai_ops.snapshot_domain_captures dc
    WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='sales'
  ) THEN
    RAISE EXCEPTION 'run multi-domain capture markers are incomplete';
  END IF;

  SELECT count(*)::INTEGER INTO v_expected_case_count
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id = v_snapshot.id;

  IF v_expected_case_count > v_settings.max_cases_per_snapshot THEN
    RAISE EXCEPTION 'frozen case count exceeds global planner limit';
  END IF;

  v_decision_count := jsonb_array_length(p_decisions);
  IF v_decision_count <> v_expected_case_count THEN
    RAISE EXCEPTION 'one decision is required for every frozen case: expected %, received %', v_expected_case_count, v_decision_count;
  END IF;

  SELECT count(DISTINCT (item->>'case_id'))::INTEGER
  INTO v_distinct_case_count
  FROM jsonb_array_elements(p_decisions) item;

  IF v_distinct_case_count <> v_decision_count THEN
    RAISE EXCEPTION 'duplicate case decisions are not allowed';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_decisions) item
    WHERE NOT EXISTS (
      SELECT 1 FROM ai_ops.snapshot_cases sc
      WHERE sc.snapshot_id = v_snapshot.id
        AND sc.case_id = (item->>'case_id')::UUID
    )
  ) THEN
    RAISE EXCEPTION 'decision payload references a case outside the frozen run snapshot';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM ai_ops.snapshot_cases sc
    WHERE sc.snapshot_id = v_snapshot.id
      AND NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_decisions) item
        WHERE (item->>'case_id')::UUID = sc.case_id
      )
  ) THEN
    RAISE EXCEPTION 'decision payload omitted a frozen case';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_decisions) item,
         LATERAL jsonb_object_keys(item) field_name
    WHERE field_name NOT IN (
      'case_id','decision_type','concise_rationale','confidence',
      'recommended_owner_user_id','recommended_assignee_user_id',
      'responsibility_summary','why_this_owner','why_now',
      'expected_outcome','next_action_text','due_at','review_after'
    )
  ) THEN
    RAISE EXCEPTION 'decision payload contains unsupported fields';
  END IF;

  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_decisions) item
    WHERE item->>'decision_type' NOT IN ('IGNORE','MONITOR','INVESTIGATE','INFORM','CREATE_WORK','ESCALATE')
       OR length(btrim(COALESCE(item->>'concise_rationale',''))) NOT BETWEEN 1 AND 1200
       OR COALESCE((item->>'confidence')::NUMERIC, -1) < 0
       OR COALESCE((item->>'confidence')::NUMERIC, -1) > 1
  ) THEN
    RAISE EXCEPTION 'decision payload failed type/rationale/confidence validation';
  END IF;

  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_decisions) item
    WHERE length(COALESCE(item->>'responsibility_summary','')) > 800
       OR length(COALESCE(item->>'why_this_owner','')) > 800
       OR length(COALESCE(item->>'why_now','')) > 800
       OR length(COALESCE(item->>'expected_outcome','')) > 1000
       OR length(COALESCE(item->>'next_action_text','')) > 500
  ) THEN
    RAISE EXCEPTION 'decision payload failed bounded text validation';
  END IF;

  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_decisions) item
    WHERE item->>'decision_type' = 'MONITOR'
      AND (
        NULLIF(item->>'review_after','') IS NULL
        OR (item->>'review_after')::TIMESTAMPTZ <= v_now
      )
  ) THEN
    RAISE EXCEPTION 'MONITOR decisions require a future review_after';
  END IF;

  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_decisions) item
    WHERE item->>'decision_type' = 'CREATE_WORK'
      AND (
        NULLIF(item->>'recommended_owner_user_id','') IS NULL
        OR NULLIF(item->>'recommended_assignee_user_id','') IS NULL
        OR NULLIF(btrim(item->>'expected_outcome'),'') IS NULL
        OR NULLIF(btrim(item->>'next_action_text'),'') IS NULL
        OR NULLIF(item->>'due_at','') IS NULL
        OR (item->>'due_at')::TIMESTAMPTZ <= v_now
      )
  ) THEN
    RAISE EXCEPTION 'CREATE_WORK requires explicit owner, assignee, expected_outcome, next_action_text and future due_at';
  END IF;

  SELECT count(*)::INTEGER INTO v_action_count
  FROM jsonb_array_elements(p_decisions) item
  WHERE item->>'decision_type' IN ('CREATE_WORK','ESCALATE');

  IF v_action_count > v_settings.max_actions_per_run THEN
    RAISE EXCEPTION 'action decision count % exceeds max %', v_action_count, v_settings.max_actions_per_run;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_decisions)
  LOOP
    v_case_id := (v_item->>'case_id')::UUID;
    v_decision_type := v_item->>'decision_type';
    v_owner := NULLIF(v_item->>'recommended_owner_user_id','')::UUID;
    v_assignee := NULLIF(v_item->>'recommended_assignee_user_id','')::UUID;

    IF v_decision_type = 'CREATE_WORK' THEN
      IF NOT private.work_actor_is_active(v_owner) THEN
        RAISE EXCEPTION 'recommended owner is not an active Work actor for case %', v_case_id;
      END IF;
      IF NOT private.work_actor_is_active(v_assignee) THEN
        RAISE EXCEPTION 'recommended assignee is not an active Work actor for case %', v_case_id;
      END IF;
    END IF;

    IF v_decision_type = 'ESCALATE' THEN
      SELECT NULLIF(sc.facts->'existing_active_work'->>'work_item_id','')::UUID
      INTO v_linked_work
      FROM ai_ops.snapshot_cases sc
      WHERE sc.snapshot_id = v_snapshot.id AND sc.case_id = v_case_id;

      IF v_linked_work IS NULL THEN
        RAISE EXCEPTION 'ESCALATE requires frozen existing Work evidence for case %', v_case_id;
      END IF;
    ELSE
      v_linked_work := NULL;
    END IF;
  END LOOP;

  v_submission_hash := md5(p_decisions::TEXT);

  SELECT count(*)::INTEGER,
         count(DISTINCT d.management_only_metadata->>'worker_submission_hash')::INTEGER
  INTO v_existing_count, v_existing_hashes
  FROM ai_ops.decisions d
  WHERE d.run_id = p_run_id;

  IF v_existing_count > 0 THEN
    IF v_existing_count = v_decision_count
       AND v_existing_hashes = 1
       AND EXISTS (
         SELECT 1 FROM ai_ops.decisions d
         WHERE d.run_id = p_run_id
           AND d.management_only_metadata->>'worker_submission_hash' = v_submission_hash
       ) THEN
      UPDATE ai_ops.planner_runs
      SET status='staged', checkpoint='decisions_staged', heartbeat_at=v_now,
          lease_expires_at=NULL, decisions_count=v_decision_count,
          result_summary=result_summary || jsonb_build_object('worker_submission_hash',v_submission_hash,'action_decisions',v_action_count),
          updated_at=v_now
      WHERE id=p_run_id;
      RETURN jsonb_build_object('staged',true,'idempotent_reuse',true,'decision_count',v_decision_count,'action_count',v_action_count,'submission_hash',v_submission_hash);
    END IF;
    RAISE EXCEPTION 'run already contains a different staged decision submission';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_decisions)
  LOOP
    v_case_id := (v_item->>'case_id')::UUID;
    v_decision_type := v_item->>'decision_type';
    v_owner := NULLIF(v_item->>'recommended_owner_user_id','')::UUID;
    v_assignee := NULLIF(v_item->>'recommended_assignee_user_id','')::UUID;

    IF v_decision_type = 'ESCALATE' THEN
      SELECT NULLIF(sc.facts->'existing_active_work'->>'work_item_id','')::UUID
      INTO v_linked_work
      FROM ai_ops.snapshot_cases sc
      WHERE sc.snapshot_id = v_snapshot.id AND sc.case_id = v_case_id;
    ELSE
      v_linked_work := NULL;
    END IF;

    INSERT INTO ai_ops.decisions(
      run_id, case_id, revision, decision_type, recommended_owner_user_id,
      recommended_assignee_user_id, responsibility_basis, concise_rationale,
      confidence, expected_outcome, next_action_text, due_at, review_after,
      linked_work_item_id, validation_state, validation_detail,
      management_only_metadata
    ) VALUES (
      p_run_id,
      v_case_id,
      1,
      v_decision_type,
      v_owner,
      v_assignee,
      jsonb_build_object(
        'summary', COALESCE(v_item->>'responsibility_summary',''),
        'why_this_owner', COALESCE(v_item->>'why_this_owner',''),
        'why_now', COALESCE(v_item->>'why_now','')
      ),
      btrim(v_item->>'concise_rationale'),
      (v_item->>'confidence')::NUMERIC,
      NULLIF(COALESCE(v_item->>'expected_outcome',''), ''),
      NULLIF(COALESCE(v_item->>'next_action_text',''), ''),
      NULLIF(v_item->>'due_at','')::TIMESTAMPTZ,
      NULLIF(v_item->>'review_after','')::TIMESTAMPTZ,
      v_linked_work,
      'pending',
      jsonb_build_object('requires_human_review',true,'stage_only',true),
      jsonb_build_object(
        'worker_id',p_worker_id,
        'worker_context_hash',p_context_hash,
        'worker_submission_hash',v_submission_hash,
        'chain_of_thought_stored',false
      )
    );
  END LOOP;

  UPDATE ai_ops.planner_runs
  SET
    status='staged', checkpoint='decisions_staged', heartbeat_at=v_now,
    lease_expires_at=NULL, decisions_count=v_decision_count,
    cases_investigated=v_decision_count,
    result_summary=result_summary || jsonb_build_object(
      'worker_submission_hash',v_submission_hash,
      'action_decisions',v_action_count,
      'zero_action_run',v_action_count=0,
      'multi_domain_staging',true
    ),
    updated_at=v_now
  WHERE id=p_run_id;

  RETURN jsonb_build_object(
    'staged',true,
    'idempotent_reuse',false,
    'decision_count',v_decision_count,
    'action_count',v_action_count,
    'zero_action_run',v_action_count=0,
    'submission_hash',v_submission_hash
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions(UUID, TEXT, TEXT, JSONB)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION ai_ops.build_operational_snapshot(UUID, INTEGER) IS
  'Planner-internal two-domain snapshot orchestrator. Shares one global case budget between immutable Receivables and Sales captures without cross-domain severity ranking.';
COMMENT ON FUNCTION ai_ops.worker_get_context(UUID, TEXT) IS
  'Internal multi-domain worker context over immutable snapshot evidence. Includes Receivables and Sales domain captures and preserves strict context budget/hash semantics.';
COMMENT ON FUNCTION ai_ops.worker_stage_decisions(UUID, TEXT, TEXT, JSONB) IS
  'Stages exactly one bounded decision for every frozen case across all captured domains; no operational execution.';

RESET lock_timeout;
RESET statement_timeout;
