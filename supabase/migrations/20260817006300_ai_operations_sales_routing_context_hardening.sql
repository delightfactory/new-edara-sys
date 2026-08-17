-- ============================================================================
-- AI Operations Planner — Sales Routing + Scope Context Hardening
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply to production until explicitly
-- reviewed and accepted with the complete engine migration chain.
--
-- Review findings closed here:
--   * detect accountable scope-owner drift after the frozen snapshot
--   * detect new governed branch/employee context for branch/individual targets
--   * keep the existing Receivables/Sales current-state guards unchanged
--   * remain read-only against operational business tables
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.sales_target_routing_context_issues(p_decision_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_decision ai_ops.decisions%ROWTYPE;
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_sc ai_ops.snapshot_cases%ROWTYPE;
  v_target RECORD;
  v_target_id UUID;
  v_frozen_scope_owner UUID;
  v_current_scope_owner UUID;
  v_now TIMESTAMPTZ := clock_timestamp();
  v_reasons JSONB := '[]'::JSONB;
BEGIN
  SELECT * INTO v_decision
  FROM ai_ops.decisions
  WHERE id = p_decision_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_array('decision_missing');
  END IF;

  SELECT * INTO v_snapshot
  FROM ai_ops.snapshots
  WHERE run_id = v_decision.run_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_array('run_snapshot_missing');
  END IF;

  SELECT * INTO v_sc
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id = v_snapshot.id
    AND sc.case_id = v_decision.case_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_array('frozen_case_evidence_missing');
  END IF;

  IF v_sc.domain <> 'sales' OR v_sc.case_type <> 'target_trajectory_gap' THEN
    RETURN '[]'::JSONB;
  END IF;

  v_target_id := COALESCE(v_sc.entity_id, NULLIF(v_sc.facts->>'target_id','')::UUID);
  IF v_target_id IS NULL THEN
    RETURN jsonb_build_array('target_identity_missing');
  END IF;

  SELECT
    t.id,
    t.scope::TEXT AS scope,
    t.scope_id,
    t.product_id,
    t.category_id
  INTO v_target
  FROM public.targets t
  WHERE t.id = v_target_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_array('target_missing');
  END IF;

  v_frozen_scope_owner := NULLIF(
    v_sc.responsibility_evidence->'scope_accountability'->>'user_id',
    ''
  )::UUID;

  v_current_scope_owner := CASE v_target.scope
    WHEN 'individual' THEN (
      SELECT he.user_id
      FROM public.hr_employees he
      WHERE he.id = v_target.scope_id
      LIMIT 1
    )
    WHEN 'department' THEN (
      SELECT dep.manager_id
      FROM public.hr_departments dep
      WHERE dep.id = v_target.scope_id
      LIMIT 1
    )
    WHEN 'branch' THEN (
      SELECT br.manager_id
      FROM public.branches br
      WHERE br.id = v_target.scope_id
      LIMIT 1
    )
    ELSE NULL
  END;

  -- A change in the accountable person is operationally material even if the
  -- previously recommended user is still an active account. The frozen routing
  -- evidence must never silently authorize yesterday's manager/owner.
  IF v_current_scope_owner IS DISTINCT FROM v_frozen_scope_owner THEN
    v_reasons := v_reasons || jsonb_build_array(
      'target_scope_accountability_changed_after_snapshot'
    );
  END IF;

  -- The base Sales guard already checks target/product/category/department
  -- context. Snapshot capture also freezes branch and employee context; close
  -- that symmetry gap here so all captured scope-context families are watched.
  IF EXISTS (
    SELECT 1
    FROM ai_ops.operational_context oc
    WHERE oc.status = 'active'
      AND oc.updated_at > v_sc.created_at
      AND oc.valid_from <= v_now
      AND (oc.valid_until IS NULL OR oc.valid_until > v_now)
      AND oc.visibility IN ('management','standard')
      AND (oc.confidence_class <> 'ai_inference' OR oc.approved_by_user_id IS NOT NULL)
      AND (
        (v_target.scope = 'branch'
          AND oc.subject_type = 'branch'
          AND oc.subject_id = v_target.scope_id)
        OR
        (v_target.scope = 'individual'
          AND oc.subject_type = 'employee'
          AND oc.subject_id = v_target.scope_id)
      )
  ) THEN
    v_reasons := v_reasons || jsonb_build_array(
      'new_scope_governed_context_after_snapshot'
    );
  END IF;

  RETURN v_reasons;
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.sales_target_routing_context_issues(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

-- Preserve the reviewed two-domain dispatcher and add the extra Sales-only
-- review findings without rewriting either underlying domain guard.
ALTER FUNCTION ai_ops.current_decision_issues(UUID)
  RENAME TO current_decision_issues_multidomain_v3;

REVOKE ALL ON FUNCTION ai_ops.current_decision_issues_multidomain_v3(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION ai_ops.current_decision_issues(p_decision_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_domain TEXT;
  v_base JSONB;
  v_sales_extra JSONB := '[]'::JSONB;
BEGIN
  v_base := ai_ops.current_decision_issues_multidomain_v3(p_decision_id);

  SELECT sc.domain INTO v_domain
  FROM ai_ops.decisions d
  JOIN ai_ops.snapshots s ON s.run_id = d.run_id
  JOIN ai_ops.snapshot_cases sc
    ON sc.snapshot_id = s.id
   AND sc.case_id = d.case_id
  WHERE d.id = p_decision_id;

  IF NOT FOUND OR v_domain <> 'sales' THEN
    RETURN v_base;
  END IF;

  v_sales_extra := ai_ops.sales_target_routing_context_issues(p_decision_id);
  RETURN COALESCE(v_base, '[]'::JSONB) || COALESCE(v_sales_extra, '[]'::JSONB);
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.current_decision_issues(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION ai_ops.sales_target_routing_context_issues(UUID) IS
  'Read-only Sales review hardening: detects current scope-accountability drift and new branch/employee governed context after the frozen case snapshot.';
COMMENT ON FUNCTION ai_ops.current_decision_issues(UUID) IS
  'Canonical current-state guard with Receivables/Sales domain validation plus Sales scope-accountability and scope-context drift hardening.';

RESET lock_timeout;
RESET statement_timeout;
