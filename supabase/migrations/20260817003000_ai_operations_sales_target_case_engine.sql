-- ============================================================================
-- AI Operations Planner — Sales & Targets Case Engine
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply to production until explicitly
-- reviewed, isolated-tested and approved.
-- Depends on the AI Operations foundation and the existing Work engine.
--
-- Scope:
--   * read-only canonical target-gap candidate kernel
--   * exact contribution parity with the deployed target engine
--   * bounded supporting field-execution evidence
--   * explicit accountability evidence without hard routing
--   * exact active Work collision detection through public.work_links
--   * optional persistence into ai_ops.cases for an existing snapshot
--
-- Explicitly NOT included:
--   * no call to public.recalculate_target_progress
--   * no Target/Sales/Activity/Visit/HR mutation
--   * no source-table ALTER / trigger / index
--   * no Work creation
--   * no browser grant / public RPC
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

-- --------------------------------------------------------------------------
-- Exact per-target contribution evidence.
-- This intentionally mirrors the deployed public.recalculate_target_progress
-- sales_value/product_qty semantics instead of inventing a second KPI truth.
-- Only positive contributors are named; zero/bottom contributor lists are not
-- exposed because this evidence is for operational diagnosis, not scoring.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ai_ops.sales_target_contribution_evidence(
  p_target_id UUID,
  p_business_date DATE,
  p_limit INTEGER DEFAULT 5
)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH target_row AS (
    SELECT t.*
    FROM public.targets t
    WHERE t.id = p_target_id
      AND t.type_code IN ('sales_value', 'product_qty')
      AND p_business_date BETWEEN t.period_start AND t.period_end
  ),
  members AS (
    SELECT
      he.id AS employee_id,
      he.user_id,
      p.full_name::TEXT AS full_name
    FROM target_row t
    JOIN public.hr_employees he
      ON he.status = 'active'
     AND (
       (t.scope = 'individual' AND he.id = t.scope_id)
       OR (t.scope = 'department' AND he.department_id = t.scope_id)
       OR (t.scope = 'branch' AND he.branch_id = t.scope_id)
       OR t.scope = 'company'
     )
    LEFT JOIN public.profiles p ON p.id = he.user_id
  ),
  contributions AS (
    -- Ordinary sales-value targets use order-level net value.
    SELECT
      m.employee_id,
      m.user_id,
      m.full_name,
      COALESCE(SUM(GREATEST(so.total_amount - COALESCE(so.returned_amount, 0), 0)), 0)::NUMERIC AS achieved_value
    FROM target_row t
    JOIN members m ON true
    LEFT JOIN public.sales_orders so
      ON so.rep_id = m.user_id
     AND so.status::TEXT IN ('delivered', 'completed')
     AND so.delivered_at::DATE BETWEEN t.period_start AND p_business_date
    LEFT JOIN public.customers c ON c.id = so.customer_id
    WHERE t.type_code = 'sales_value'
      AND t.product_id IS NULL
      AND t.category_id IS NULL
      AND (so.id IS NULL OR (
        (t.governorate_id IS NULL OR c.governorate_id = t.governorate_id)
        AND (t.city_id IS NULL OR c.city_id = t.city_id)
        AND (t.area_id IS NULL OR c.area_id = t.area_id)
      ))
    GROUP BY m.employee_id, m.user_id, m.full_name

    UNION ALL

    -- Product/category-filtered sales-value targets use eligible line value
    -- less confirmed return-line value, matching the deployed target function.
    SELECT
      m.employee_id,
      m.user_id,
      m.full_name,
      COALESCE(SUM(
        soi.line_total - COALESCE((
          SELECT SUM(sri.line_total)
          FROM public.sales_return_items sri
          JOIN public.sales_returns sr ON sr.id = sri.return_id
          WHERE sri.order_item_id = soi.id
            AND sr.status::TEXT = 'confirmed'
        ), 0)
      ), 0)::NUMERIC AS achieved_value
    FROM target_row t
    JOIN members m ON true
    LEFT JOIN public.sales_orders so
      ON so.rep_id = m.user_id
     AND so.status::TEXT IN ('delivered', 'completed')
     AND so.delivered_at::DATE BETWEEN t.period_start AND p_business_date
    LEFT JOIN public.sales_order_items soi ON soi.order_id = so.id
    LEFT JOIN public.customers c ON c.id = so.customer_id
    LEFT JOIN public.products pr ON pr.id = soi.product_id
    WHERE t.type_code = 'sales_value'
      AND (t.product_id IS NOT NULL OR t.category_id IS NOT NULL)
      AND (so.id IS NULL OR (
        (t.product_id IS NULL OR soi.product_id = t.product_id)
        AND (t.category_id IS NULL OR pr.category_id = t.category_id)
        AND (t.governorate_id IS NULL OR c.governorate_id = t.governorate_id)
        AND (t.city_id IS NULL OR c.city_id = t.city_id)
        AND (t.area_id IS NULL OR c.area_id = t.area_id)
      ))
    GROUP BY m.employee_id, m.user_id, m.full_name

    UNION ALL

    -- Product quantity uses delivered minus returned quantity.
    SELECT
      m.employee_id,
      m.user_id,
      m.full_name,
      COALESCE(SUM(GREATEST(
        soi.delivered_quantity - COALESCE(soi.returned_quantity, 0),
        0
      )), 0)::NUMERIC AS achieved_value
    FROM target_row t
    JOIN members m ON true
    LEFT JOIN public.sales_orders so
      ON so.rep_id = m.user_id
     AND so.status::TEXT IN ('delivered', 'completed')
     AND so.delivered_at::DATE BETWEEN t.period_start AND p_business_date
    LEFT JOIN public.sales_order_items soi ON soi.order_id = so.id
    LEFT JOIN public.products pr ON pr.id = soi.product_id
    WHERE t.type_code = 'product_qty'
      AND (so.id IS NULL OR (
        (t.product_id IS NULL OR soi.product_id = t.product_id)
        AND (t.category_id IS NULL OR pr.category_id = t.category_id)
      ))
    GROUP BY m.employee_id, m.user_id, m.full_name
  ),
  canonical AS (
    SELECT
      tp.achieved_value AS official_achieved_value,
      tp.last_calc_at
    FROM public.target_progress tp
    WHERE tp.target_id = p_target_id
      AND tp.snapshot_date = p_business_date
    ORDER BY tp.last_calc_at DESC NULLS LAST, tp.id DESC
    LIMIT 1
  ),
  totals AS (
    SELECT
      COALESCE(SUM(c.achieved_value), 0)::NUMERIC AS contribution_total,
      COUNT(*)::INTEGER AS member_count,
      COUNT(*) FILTER (WHERE c.achieved_value > 0)::INTEGER AS contributing_member_count
    FROM contributions c
  ),
  top_rows AS (
    SELECT c.*
    FROM contributions c
    WHERE c.achieved_value > 0
    ORDER BY c.achieved_value DESC, c.full_name NULLS LAST, c.employee_id
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 5), 1), 20)
  )
  SELECT jsonb_build_object(
    'supported', EXISTS (SELECT 1 FROM target_row),
    'business_date', p_business_date,
    'member_count', COALESCE((SELECT member_count FROM totals), 0),
    'contributing_member_count', COALESCE((SELECT contributing_member_count FROM totals), 0),
    'contribution_total', COALESCE((SELECT contribution_total FROM totals), 0),
    'official_achieved_value', (SELECT official_achieved_value FROM canonical),
    'parity_delta', CASE
      WHEN NOT EXISTS (SELECT 1 FROM canonical) THEN NULL
      ELSE ABS(
        COALESCE((SELECT contribution_total FROM totals), 0)
        - COALESCE((SELECT official_achieved_value FROM canonical), 0)
      )
    END,
    'parity_ok', CASE
      WHEN NOT EXISTS (SELECT 1 FROM canonical) THEN false
      ELSE ABS(
        COALESCE((SELECT contribution_total FROM totals), 0)
        - COALESCE((SELECT official_achieved_value FROM canonical), 0)
      ) <= 0.01
    END,
    'official_last_calc_at', (SELECT last_calc_at FROM canonical),
    'contributors', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'employee_id', tr.employee_id,
          'user_id', tr.user_id,
          'full_name', tr.full_name,
          'achieved_value', tr.achieved_value,
          'evidence_type', 'deterministic_target_contribution',
          'routing_rule', false
        )
        ORDER BY tr.achieved_value DESC, tr.full_name NULLS LAST, tr.employee_id
      )
      FROM top_rows tr
    ), '[]'::JSONB)
  );
$$;

REVOKE ALL ON FUNCTION ai_ops.sales_target_contribution_evidence(UUID, DATE, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION ai_ops.sales_target_contribution_evidence(UUID, DATE, INTEGER) FROM anon;
REVOKE ALL ON FUNCTION ai_ops.sales_target_contribution_evidence(UUID, DATE, INTEGER) FROM authenticated;
REVOKE ALL ON FUNCTION ai_ops.sales_target_contribution_evidence(UUID, DATE, INTEGER) FROM service_role;

COMMENT ON FUNCTION ai_ops.sales_target_contribution_evidence(UUID, DATE, INTEGER) IS
  'Read-only bounded contribution evidence for sales_value/product_qty targets, with parity against canonical target_progress.';

-- --------------------------------------------------------------------------
-- Sales target trajectory candidates.
-- Requires an exact canonical target_progress row for p_business_date.
-- The function never calls the target recalculation RPC because capture is a
-- read-only source operation by design.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ai_ops.sales_target_candidates(
  p_business_date DATE,
  p_limit INTEGER DEFAULT 50
)
RETURNS TABLE(
  case_key TEXT,
  severity TEXT,
  target_id UUID,
  target_name TEXT,
  target_type_code TEXT,
  target_unit TEXT,
  target_scope TEXT,
  target_scope_id UUID,
  target_value NUMERIC,
  min_value NUMERIC,
  stretch_value NUMERIC,
  achieved_value NUMERIC,
  achievement_pct NUMERIC,
  expected_pct NUMERIC,
  trajectory_gap_pct NUMERIC,
  remaining_value NUMERIC,
  elapsed_days INTEGER,
  remaining_days INTEGER,
  actual_daily_pace NUMERIC,
  required_daily_pace NUMERIC,
  required_pace_multiplier NUMERIC,
  projected_value NUMERIC,
  progress_last_calc_at TIMESTAMPTZ,
  scope_owner_user_id UUID,
  scope_owner_name TEXT,
  scope_owner_active BOOLEAN,
  target_assigner_user_id UUID,
  target_assigner_name TEXT,
  target_assigner_active BOOLEAN,
  linked_work_item_id UUID,
  linked_work_number BIGINT,
  linked_work_status TEXT,
  linked_work_title TEXT,
  linked_work_relation_type TEXT,
  contribution_evidence JSONB,
  field_execution JSONB,
  facts JSONB,
  responsibility_evidence JSONB,
  trust JSONB
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH eligible AS (
    SELECT
      t.*,
      tt.unit::TEXT AS target_unit,
      tp.achieved_value,
      tp.achievement_pct,
      tp.trend::TEXT AS trend,
      tp.last_calc_at,
      COALESCE(NULLIF(tp.calc_details->>'expected_pct', '')::NUMERIC, 0) AS expected_pct,
      COALESCE(NULLIF(tp.calc_details->>'days_elapsed', '')::INTEGER, p_business_date - t.period_start + 1) AS elapsed_days,
      COALESCE(NULLIF(tp.calc_details->>'total_days', '')::INTEGER, t.period_end - t.period_start + 1) AS total_days
    FROM public.targets t
    JOIN public.target_progress tp
      ON tp.target_id = t.id
     AND tp.snapshot_date = p_business_date
    LEFT JOIN public.target_types tt ON tt.code = t.type_code
    WHERE t.is_active = true
      AND COALESCE(t.is_paused, false) = false
      AND p_business_date BETWEEN t.period_start AND t.period_end
      AND t.type_code IN ('sales_value', 'product_qty')
      AND tp.trend::TEXT IN ('behind', 'at_risk')
  ),
  bounded AS (
    SELECT
      e.*,
      GREATEST(e.target_value - COALESCE(e.achieved_value, 0), 0)::NUMERIC AS remaining_value,
      GREATEST(e.period_end - p_business_date, 0)::INTEGER AS remaining_days,
      CASE
        WHEN e.elapsed_days > 0 THEN COALESCE(e.achieved_value, 0) / e.elapsed_days
        ELSE 0
      END::NUMERIC AS actual_daily_pace,
      CASE
        WHEN (e.period_end - p_business_date) > 0
          THEN GREATEST(e.target_value - COALESCE(e.achieved_value, 0), 0) / (e.period_end - p_business_date)
        ELSE GREATEST(e.target_value - COALESCE(e.achieved_value, 0), 0)
      END::NUMERIC AS required_daily_pace,
      CASE
        WHEN e.elapsed_days > 0
          THEN (COALESCE(e.achieved_value, 0) / e.elapsed_days) * e.total_days
        ELSE 0
      END::NUMERIC AS projected_value,
      GREATEST(e.expected_pct - COALESCE(e.achievement_pct, 0), 0)::NUMERIC AS trajectory_gap_pct
    FROM eligible e
    ORDER BY
      CASE e.trend WHEN 'behind' THEN 0 ELSE 1 END,
      GREATEST(e.expected_pct - COALESCE(e.achievement_pct, 0), 0) DESC,
      e.target_value DESC,
      e.id
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100)
  )
  SELECT
    'sales:target_trajectory_gap:' || b.id::TEXT AS case_key,
    CASE
      WHEN b.trend = 'behind'
        AND (100.0 * b.elapsed_days / GREATEST(b.total_days, 1)) >= 75
        AND (
          (b.min_value IS NOT NULL AND b.projected_value < b.min_value)
          OR (b.min_value IS NULL AND b.projected_value < (b.target_value * 0.5))
        ) THEN 'critical'
      WHEN b.trend = 'behind' THEN 'high'
      ELSE 'medium'
    END::TEXT AS severity,
    b.id AS target_id,
    b.name::TEXT AS target_name,
    b.type_code::TEXT AS target_type_code,
    b.target_unit,
    b.scope::TEXT AS target_scope,
    b.scope_id AS target_scope_id,
    b.target_value,
    b.min_value,
    b.stretch_value,
    COALESCE(b.achieved_value, 0)::NUMERIC,
    COALESCE(b.achievement_pct, 0)::NUMERIC,
    b.expected_pct,
    b.trajectory_gap_pct,
    b.remaining_value,
    b.elapsed_days,
    b.remaining_days,
    b.actual_daily_pace,
    b.required_daily_pace,
    CASE
      WHEN b.actual_daily_pace > 0 THEN b.required_daily_pace / b.actual_daily_pace
      ELSE NULL
    END::NUMERIC AS required_pace_multiplier,
    b.projected_value,
    b.last_calc_at AS progress_last_calc_at,
    scope_owner.user_id AS scope_owner_user_id,
    scope_owner.full_name AS scope_owner_name,
    CASE
      WHEN scope_owner.user_id IS NULL THEN false
      ELSE private.work_actor_is_active(scope_owner.user_id)
    END AS scope_owner_active,
    b.assigned_by AS target_assigner_user_id,
    assigner.full_name::TEXT AS target_assigner_name,
    CASE
      WHEN b.assigned_by IS NULL THEN false
      ELSE private.work_actor_is_active(b.assigned_by)
    END AS target_assigner_active,
    linked.work_item_id,
    linked.work_number,
    linked.status,
    linked.title,
    linked.relation_type,
    contrib.evidence AS contribution_evidence,
    field_exec.evidence AS field_execution,
    jsonb_build_object(
      'target_id', b.id,
      'target_name', b.name,
      'target_type_code', b.type_code,
      'target_unit', b.target_unit,
      'scope', b.scope,
      'scope_id', b.scope_id,
      'period_start', b.period_start,
      'period_end', b.period_end,
      'target_value', b.target_value,
      'min_value', b.min_value,
      'stretch_value', b.stretch_value,
      'achieved_value', COALESCE(b.achieved_value, 0),
      'achievement_pct', COALESCE(b.achievement_pct, 0),
      'expected_pct', b.expected_pct,
      'trajectory_gap_pct', b.trajectory_gap_pct,
      'remaining_value', b.remaining_value,
      'elapsed_days', b.elapsed_days,
      'remaining_days', b.remaining_days,
      'actual_daily_pace', b.actual_daily_pace,
      'required_daily_pace', b.required_daily_pace,
      'required_pace_multiplier', CASE
        WHEN b.actual_daily_pace > 0 THEN b.required_daily_pace / b.actual_daily_pace
        ELSE NULL
      END,
      'projected_value', b.projected_value,
      'product_id', b.product_id,
      'product_name', product.name,
      'category_id', b.category_id,
      'category_name', category.name,
      'governorate_id', b.governorate_id,
      'city_id', b.city_id,
      'area_id', b.area_id,
      'progress_last_calc_at', b.last_calc_at,
      'contribution_evidence', contrib.evidence,
      'field_execution', field_exec.evidence,
      'existing_active_work', CASE
        WHEN linked.work_item_id IS NULL THEN NULL
        ELSE jsonb_build_object(
          'work_item_id', linked.work_item_id,
          'work_number', linked.work_number,
          'status', linked.status,
          'title', linked.title,
          'relation_type', linked.relation_type
        )
      END
    ) AS facts,
    jsonb_build_object(
      'scope_accountability', CASE
        WHEN scope_owner.user_id IS NULL THEN NULL
        ELSE jsonb_build_object(
          'user_id', scope_owner.user_id,
          'full_name', scope_owner.full_name,
          'active_work_actor', private.work_actor_is_active(scope_owner.user_id),
          'evidence_type', scope_owner.evidence_type,
          'routing_rule', false
        )
      END,
      'target_assigner', CASE
        WHEN b.assigned_by IS NULL THEN NULL
        ELSE jsonb_build_object(
          'user_id', b.assigned_by,
          'full_name', assigner.full_name,
          'active_work_actor', private.work_actor_is_active(b.assigned_by),
          'evidence_type', 'target_assigner_context_only',
          'routing_rule', false
        )
      END,
      'top_contributors', COALESCE(contrib.evidence->'contributors', '[]'::JSONB),
      'existing_active_work', CASE
        WHEN linked.work_item_id IS NULL THEN NULL
        ELSE jsonb_build_object(
          'work_item_id', linked.work_item_id,
          'work_number', linked.work_number,
          'status', linked.status,
          'evidence_type', 'existing_work_continuity'
        )
      END
    ) AS responsibility_evidence,
    jsonb_build_object(
      'source', 'targets+target_progress',
      'confidence', 'canonical_system_progress',
      'business_date', p_business_date,
      'progress_snapshot_exact_business_date', true,
      'progress_last_calc_at', b.last_calc_at,
      'contribution_parity_ok', COALESCE((contrib.evidence->>'parity_ok')::BOOLEAN, false),
      'contribution_parity_delta', contrib.evidence->'parity_delta',
      'field_execution_interpretation', 'supporting_only_no_uniform_activity_baseline',
      'causal_inference_allowed_without_reasoning', false,
      'target_recalculation_performed', false
    ) AS trust
  FROM bounded b
  LEFT JOIN public.products product ON product.id = b.product_id
  LEFT JOIN public.product_categories category ON category.id = b.category_id
  LEFT JOIN public.profiles assigner ON assigner.id = b.assigned_by
  LEFT JOIN LATERAL (
    SELECT
      CASE
        WHEN b.scope = 'individual' THEN he.user_id
        WHEN b.scope = 'department' THEN dep.manager_id
        WHEN b.scope = 'branch' THEN br.manager_id
        ELSE NULL
      END AS user_id,
      CASE
        WHEN b.scope = 'individual' THEN individual_profile.full_name::TEXT
        WHEN b.scope = 'department' THEN dep_profile.full_name::TEXT
        WHEN b.scope = 'branch' THEN branch_profile.full_name::TEXT
        ELSE NULL
      END AS full_name,
      CASE
        WHEN b.scope = 'individual' THEN 'target_individual_scope'
        WHEN b.scope = 'department' THEN 'department_manager_accountability'
        WHEN b.scope = 'branch' THEN 'branch_manager_accountability'
        ELSE 'no_explicit_scope_owner'
      END AS evidence_type
    FROM (SELECT 1) seed
    LEFT JOIN public.hr_employees he ON b.scope = 'individual' AND he.id = b.scope_id
    LEFT JOIN public.profiles individual_profile ON individual_profile.id = he.user_id
    LEFT JOIN public.hr_departments dep ON b.scope = 'department' AND dep.id = b.scope_id
    LEFT JOIN public.profiles dep_profile ON dep_profile.id = dep.manager_id
    LEFT JOIN public.branches br ON b.scope = 'branch' AND br.id = b.scope_id
    LEFT JOIN public.profiles branch_profile ON branch_profile.id = br.manager_id
  ) scope_owner ON true
  LEFT JOIN LATERAL (
    SELECT ai_ops.sales_target_contribution_evidence(b.id, p_business_date, 5) AS evidence
  ) contrib ON true
  LEFT JOIN LATERAL (
    WITH member_ids AS (
      SELECT he.id
      FROM public.hr_employees he
      WHERE he.status = 'active'
        AND (
          (b.scope = 'individual' AND he.id = b.scope_id)
          OR (b.scope = 'department' AND he.department_id = b.scope_id)
          OR (b.scope = 'branch' AND he.branch_id = b.scope_id)
          OR b.scope = 'company'
        )
    ), activity_counts AS (
      SELECT
        COUNT(*) FILTER (WHERE at.category = 'visit')::INTEGER AS visits_recorded,
        COUNT(*) FILTER (WHERE at.category = 'call')::INTEGER AS calls_recorded
      FROM public.activities a
      JOIN public.activity_types at ON at.id = a.type_id
      WHERE a.employee_id IN (SELECT id FROM member_ids)
        AND a.deleted_at IS NULL
        AND a.activity_date BETWEEN b.period_start AND p_business_date
    ), visit_plan_counts AS (
      SELECT
        COUNT(*)::INTEGER AS plan_days,
        COALESCE(SUM(vp.total_customers), 0)::INTEGER AS planned_visits,
        COALESCE(SUM(vp.completed_count), 0)::INTEGER AS completed_visits,
        COALESCE(SUM(vp.skipped_count), 0)::INTEGER AS skipped_visits,
        COALESCE(SUM(vp.missed_count), 0)::INTEGER AS missed_visits
      FROM public.visit_plans vp
      WHERE vp.employee_id IN (SELECT id FROM member_ids)
        AND vp.plan_date BETWEEN b.period_start AND p_business_date
    )
    SELECT jsonb_build_object(
      'activity_window_start', b.period_start,
      'activity_window_end', p_business_date,
      'visits_recorded', COALESCE(ac.visits_recorded, 0),
      'calls_recorded', COALESCE(ac.calls_recorded, 0),
      'visit_plan_days', COALESCE(vp.plan_days, 0),
      'planned_visits', COALESCE(vp.planned_visits, 0),
      'completed_planned_visits', COALESCE(vp.completed_visits, 0),
      'skipped_planned_visits', COALESCE(vp.skipped_visits, 0),
      'missed_planned_visits', COALESCE(vp.missed_visits, 0),
      'coverage_quality', CASE
        WHEN COALESCE(vp.plan_days, 0) = 0 AND COALESCE(ac.visits_recorded, 0) = 0 AND COALESCE(ac.calls_recorded, 0) = 0 THEN 'no_governed_activity_evidence'
        ELSE 'partial_supporting_evidence'
      END,
      'causal_label', NULL,
      'interpretation', 'supporting_only_no_uniform_activity_baseline'
    ) AS evidence
    FROM activity_counts ac CROSS JOIN visit_plan_counts vp
  ) field_exec ON true
  LEFT JOIN LATERAL (
    SELECT
      wi.id AS work_item_id,
      wi.work_number,
      wi.status::TEXT AS status,
      wi.title::TEXT AS title,
      wl.relation_type::TEXT AS relation_type
    FROM public.work_links wl
    JOIN public.work_items wi ON wi.id = wl.work_item_id
    WHERE wl.entity_type = 'target'
      AND wl.entity_id = b.id
      AND wi.status::TEXT NOT IN ('done', 'cancelled')
    ORDER BY wi.updated_at DESC, wi.id, wl.id
    LIMIT 1
  ) linked ON true;
$$;

REVOKE ALL ON FUNCTION ai_ops.sales_target_candidates(DATE, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION ai_ops.sales_target_candidates(DATE, INTEGER) FROM anon;
REVOKE ALL ON FUNCTION ai_ops.sales_target_candidates(DATE, INTEGER) FROM authenticated;
REVOKE ALL ON FUNCTION ai_ops.sales_target_candidates(DATE, INTEGER) FROM service_role;

COMMENT ON FUNCTION ai_ops.sales_target_candidates(DATE, INTEGER) IS
  'Internal read-only bounded Sales/Targets trajectory-gap kernel using canonical target_progress and exact source evidence.';

-- --------------------------------------------------------------------------
-- Persist candidates into the planner-local attention-case ledger only.
-- Operational Target/Sales/Work/Activity tables remain read-only.
-- --------------------------------------------------------------------------
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
    FROM ai_ops.sales_target_candidates(p_business_date, p_limit)
  LOOP
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
      'sales',
      'target_trajectory_gap',
      'target',
      v_candidate.target_id,
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
      updated_at = clock_timestamp();

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'snapshot_id', p_snapshot_id,
    'business_date', p_business_date,
    'domain', 'sales',
    'case_type', 'target_trajectory_gap',
    'candidates_upserted', v_count,
    'resolution_performed', false
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.refresh_sales_target_cases(UUID, DATE, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION ai_ops.refresh_sales_target_cases(UUID, DATE, INTEGER) FROM anon;
REVOKE ALL ON FUNCTION ai_ops.refresh_sales_target_cases(UUID, DATE, INTEGER) FROM authenticated;
REVOKE ALL ON FUNCTION ai_ops.refresh_sales_target_cases(UUID, DATE, INTEGER) FROM service_role;

COMMENT ON FUNCTION ai_ops.refresh_sales_target_cases(UUID, DATE, INTEGER) IS
  'Persists bounded Sales target trajectory cases into ai_ops only; never recalculates or mutates operational targets, sales, activities or Work.';

RESET lock_timeout;
RESET statement_timeout;
