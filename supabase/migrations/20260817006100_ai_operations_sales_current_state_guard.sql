-- ============================================================================
-- AI Operations Planner — Sales/Targets Current-State Guard
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply to production until explicitly
-- reviewed, isolated-tested and approved.
--
-- Keeps the proven Receivables guard intact and makes the canonical guard
-- domain-aware. Sales action decisions fail closed on target/progress/context
-- drift, stale progress, contribution parity failure or Work collisions.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

-- Preserve the audited Credit implementation byte-for-byte as the Credit
-- primitive. validate_staged_run() continues to call the canonical name below.
ALTER FUNCTION ai_ops.current_decision_issues(UUID)
  RENAME TO current_decision_issues_credit_v1;

REVOKE ALL ON FUNCTION ai_ops.current_decision_issues_credit_v1(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION ai_ops.current_sales_target_decision_issues(p_decision_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_decision ai_ops.decisions%ROWTYPE;
  v_run ai_ops.planner_runs%ROWTYPE;
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_domain_capture ai_ops.snapshot_domain_captures%ROWTYPE;
  v_sc ai_ops.snapshot_cases%ROWTYPE;
  v_now TIMESTAMPTZ := clock_timestamp();
  v_business_date DATE := (clock_timestamp() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_reasons JSONB := '[]'::JSONB;
  v_target RECORD;
  v_progress RECORD;
  v_target_id UUID;
  v_frozen_progress_date DATE;
  v_frozen_achieved NUMERIC;
  v_frozen_achievement_pct NUMERIC;
  v_frozen_progress_last_calc TIMESTAMPTZ;
  v_active_collision UUID;
BEGIN
  SELECT * INTO v_decision
  FROM ai_ops.decisions
  WHERE id = p_decision_id;

  IF NOT FOUND THEN RETURN jsonb_build_array('decision_missing'); END IF;

  SELECT * INTO v_run
  FROM ai_ops.planner_runs
  WHERE id = v_decision.run_id;
  IF NOT FOUND THEN RETURN jsonb_build_array('decision_run_missing'); END IF;

  SELECT * INTO v_snapshot
  FROM ai_ops.snapshots
  WHERE run_id = v_run.id;
  IF NOT FOUND THEN RETURN jsonb_build_array('run_snapshot_missing'); END IF;

  SELECT * INTO v_domain_capture
  FROM ai_ops.snapshot_domain_captures dc
  WHERE dc.snapshot_id = v_snapshot.id AND dc.domain = 'sales';
  IF NOT FOUND THEN RETURN jsonb_build_array('sales_capture_missing'); END IF;

  SELECT * INTO v_sc
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id = v_snapshot.id AND sc.case_id = v_decision.case_id;
  IF NOT FOUND THEN RETURN jsonb_build_array('frozen_case_evidence_missing'); END IF;

  IF v_sc.domain <> 'sales' OR v_sc.case_type <> 'target_trajectory_gap' THEN
    RETURN jsonb_build_array('unsupported_sales_validation_case');
  END IF;

  v_target_id := COALESCE(v_sc.entity_id, NULLIF(v_sc.facts->>'target_id','')::UUID);
  IF v_target_id IS NULL THEN
    RETURN jsonb_build_array('target_identity_missing');
  END IF;

  SELECT
    t.id,
    t.name::TEXT AS name,
    t.type_code::TEXT AS type_code,
    t.scope::TEXT AS scope,
    t.scope_id,
    t.target_value,
    t.min_value,
    t.stretch_value,
    t.product_id,
    t.category_id,
    t.governorate_id,
    t.city_id,
    t.area_id,
    t.period_start,
    t.period_end,
    t.is_active,
    COALESCE(t.is_paused,false) AS is_paused
  INTO v_target
  FROM public.targets t
  WHERE t.id = v_target_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_array('target_missing');
  END IF;

  IF NOT v_target.is_active
     OR v_target.is_paused
     OR v_target.type_code NOT IN ('sales_value','product_qty')
     OR v_business_date NOT BETWEEN v_target.period_start AND v_target.period_end THEN
    v_reasons := v_reasons || jsonb_build_array('target_no_longer_actionable');
  END IF;

  IF v_target.name IS DISTINCT FROM v_sc.facts->>'target_name'
     OR v_target.type_code IS DISTINCT FROM v_sc.facts->>'target_type_code'
     OR v_target.scope IS DISTINCT FROM v_sc.facts->>'scope'
     OR v_target.scope_id IS DISTINCT FROM NULLIF(v_sc.facts->>'scope_id','')::UUID
     OR v_target.target_value IS DISTINCT FROM NULLIF(v_sc.facts->>'target_value','')::NUMERIC
     OR v_target.min_value IS DISTINCT FROM NULLIF(v_sc.facts->>'min_value','')::NUMERIC
     OR v_target.stretch_value IS DISTINCT FROM NULLIF(v_sc.facts->>'stretch_value','')::NUMERIC
     OR v_target.product_id IS DISTINCT FROM NULLIF(v_sc.facts->>'product_id','')::UUID
     OR v_target.category_id IS DISTINCT FROM NULLIF(v_sc.facts->>'category_id','')::UUID
     OR v_target.governorate_id IS DISTINCT FROM NULLIF(v_sc.facts->>'governorate_id','')::UUID
     OR v_target.city_id IS DISTINCT FROM NULLIF(v_sc.facts->>'city_id','')::UUID
     OR v_target.area_id IS DISTINCT FROM NULLIF(v_sc.facts->>'area_id','')::UUID
     OR v_target.period_start::TEXT IS DISTINCT FROM v_sc.facts->>'period_start'
     OR v_target.period_end::TEXT IS DISTINCT FROM v_sc.facts->>'period_end' THEN
    v_reasons := v_reasons || jsonb_build_array('target_definition_changed_after_snapshot');
  END IF;

  SELECT
    tp.snapshot_date,
    tp.achieved_value,
    tp.achievement_pct,
    tp.trend::TEXT AS trend,
    tp.last_calc_at
  INTO v_progress
  FROM public.target_progress tp
  WHERE tp.target_id = v_target_id
    AND tp.snapshot_date <= v_business_date
  ORDER BY tp.snapshot_date DESC, tp.last_calc_at DESC NULLS LAST, tp.id DESC
  LIMIT 1;

  IF NOT FOUND THEN
    v_reasons := v_reasons || jsonb_build_array('target_progress_missing_now');
  ELSE
    v_frozen_progress_date := NULLIF(v_sc.facts->>'progress_snapshot_date','')::DATE;
    v_frozen_achieved := NULLIF(v_sc.facts->>'achieved_value','')::NUMERIC;
    v_frozen_achievement_pct := NULLIF(v_sc.facts->>'achievement_pct','')::NUMERIC;
    v_frozen_progress_last_calc := NULLIF(v_sc.facts->>'progress_last_calc_at','')::TIMESTAMPTZ;

    IF v_progress.snapshot_date IS DISTINCT FROM v_frozen_progress_date
       OR v_progress.achieved_value IS DISTINCT FROM v_frozen_achieved
       OR v_progress.achievement_pct IS DISTINCT FROM v_frozen_achievement_pct
       OR v_progress.last_calc_at IS DISTINCT FROM v_frozen_progress_last_calc THEN
      v_reasons := v_reasons || jsonb_build_array('target_progress_changed_after_snapshot');
    END IF;

    IF v_progress.trend NOT IN ('behind','at_risk') THEN
      v_reasons := v_reasons || jsonb_build_array('target_no_longer_gap_candidate');
    END IF;
  END IF;

  -- Frozen Sales cases explicitly declare whether current-state actionability
  -- is permitted. Staleness never increases severity and cannot authorize Work.
  IF v_decision.decision_type IN ('CREATE_WORK','ESCALATE')
     AND COALESCE((v_sc.trust->>'requires_progress_refresh_for_current_action')::BOOLEAN, true) THEN
    v_reasons := v_reasons || jsonb_build_array('sales_progress_stale_for_action');
  END IF;

  -- A parity failure is useful evidence for INVESTIGATE/MONITOR. It blocks only
  -- consequential action; otherwise the planner could not explicitly surface
  -- the integrity problem for human review.
  IF v_decision.decision_type IN ('CREATE_WORK','ESCALATE')
     AND COALESCE((v_sc.trust->>'contribution_parity_ok')::BOOLEAN, false) = false THEN
    v_reasons := v_reasons || jsonb_build_array('sales_contribution_parity_failed');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM ai_ops.operational_context oc
    WHERE oc.status = 'active'
      AND oc.updated_at > v_sc.created_at
      AND oc.visibility IN ('management','standard')
      AND (oc.confidence_class <> 'ai_inference' OR oc.approved_by_user_id IS NOT NULL)
      AND (oc.valid_until IS NULL OR oc.valid_until > v_now)
      AND (
        (oc.subject_type = 'target' AND oc.subject_id = v_target_id)
        OR (oc.subject_type = 'product' AND oc.subject_id = v_target.product_id)
        OR (oc.subject_type = 'product_category' AND oc.subject_id = v_target.category_id)
        OR (v_target.scope = 'department' AND oc.subject_type = 'department' AND oc.subject_id = v_target.scope_id)
      )
  ) THEN
    v_reasons := v_reasons || jsonb_build_array('new_governed_context_after_snapshot');
  END IF;

  IF v_decision.decision_type = 'CREATE_WORK' THEN
    IF v_decision.recommended_owner_user_id IS NULL
       OR NOT private.work_actor_is_active(v_decision.recommended_owner_user_id) THEN
      v_reasons := v_reasons || jsonb_build_array('recommended_owner_unavailable');
    END IF;

    IF v_decision.recommended_assignee_user_id IS NULL
       OR NOT private.work_actor_is_active(v_decision.recommended_assignee_user_id) THEN
      v_reasons := v_reasons || jsonb_build_array('recommended_assignee_unavailable');
    END IF;

    SELECT wi.id INTO v_active_collision
    FROM public.work_links wl
    JOIN public.work_items wi ON wi.id = wl.work_item_id
    WHERE wl.entity_type = 'target'
      AND wl.entity_id = v_target_id
      AND wi.status NOT IN ('done'::public.work_item_status,'cancelled'::public.work_item_status)
    ORDER BY wi.updated_at DESC, wi.id
    LIMIT 1;

    IF v_active_collision IS NOT NULL THEN
      v_reasons := v_reasons || jsonb_build_array('active_work_collision_now');
    END IF;
  ELSIF v_decision.decision_type = 'ESCALATE' THEN
    IF v_decision.linked_work_item_id IS NULL THEN
      v_reasons := v_reasons || jsonb_build_array('escalation_has_no_linked_work');
    ELSIF NOT EXISTS (
      SELECT 1
      FROM public.work_links wl
      JOIN public.work_items wi ON wi.id = wl.work_item_id
      WHERE wi.id = v_decision.linked_work_item_id
        AND wl.entity_type = 'target'
        AND wl.entity_id = v_target_id
        AND wi.status NOT IN ('done'::public.work_item_status,'cancelled'::public.work_item_status)
    ) THEN
      v_reasons := v_reasons || jsonb_build_array('linked_work_no_longer_active');
    END IF;
  END IF;

  IF v_decision.decision_type IN ('CREATE_WORK','ESCALATE')
     AND v_domain_capture.capture_status <> 'completed' THEN
    v_reasons := v_reasons || jsonb_build_array('snapshot_not_complete_for_action');
  END IF;

  RETURN v_reasons;
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.current_sales_target_decision_issues(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

-- Canonical dispatch surface used by both staged validation and commit-time
-- revalidation. Unknown domains fail closed rather than falling through.
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
  SELECT sc.domain INTO v_domain
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
    ELSE
      RETURN jsonb_build_array('unsupported_validation_domain');
  END CASE;
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.current_decision_issues(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION ai_ops.current_sales_target_decision_issues(UUID) IS
  'Read-only Sales/Targets current-state safety guard. Rejects stale target/progress/context/Work reality and never mutates operational sources.';
COMMENT ON FUNCTION ai_ops.current_decision_issues(UUID) IS
  'Canonical domain-aware current-state guard dispatcher for Receivables and Sales decisions.';

RESET lock_timeout;
RESET statement_timeout;
