-- ============================================================================
-- AI Operations Planner — Customer Health / Re-engagement Case Engine
--
-- DESIGN-TIME MIGRATION ONLY. Production operational tables remain read-only.
--
-- Sources intentionally reused from the deployed system:
--   * public.targets / target_customers for governed reactivation policy
--   * analytics.effective_sale_date for canonical Cairo commercial dates
--   * completed + delivered sales history for legacy/current parity
--   * current customer credit fields as feasibility evidence
--   * activities / visit plans / call plans as supporting interaction evidence
--   * public.work_links for duplicate-work continuity
--
-- Case types:
--   * reactivation_gap: selected customer has not achieved the active governed
--     reactivation target's minimum value.
--   * high_value_reactivation_opportunity: top-decile repeat customer is dormant
--     by the current reactivation dormancy threshold but is outside the target.
--
-- No target recalculation, customer mutation, sales mutation, activity mutation,
-- visit mutation, call mutation or Work creation is performed here.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.customer_health_candidates(
  p_business_date DATE,
  p_limit INTEGER DEFAULT 50
)
RETURNS TABLE(
  case_key TEXT,
  case_type TEXT,
  attention_class TEXT,
  severity TEXT,
  customer_id UUID,
  customer_name TEXT,
  assigned_rep_user_id UUID,
  assigned_rep_name TEXT,
  assigned_rep_active BOOLEAN,
  target_id UUID,
  target_scope TEXT,
  target_scope_id UUID,
  target_scope_owner_user_id UUID,
  target_scope_owner_name TEXT,
  target_scope_owner_active BOOLEAN,
  facts JSONB,
  responsibility_evidence JSONB,
  trust JSONB
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
WITH
active_reactivation_targets AS (
  SELECT
    t.id,
    t.name::TEXT AS target_name,
    t.scope::TEXT AS scope,
    t.scope_id,
    t.period_start,
    t.period_end,
    t.dormancy_days,
    COALESCE(NULLIF(t.filter_criteria->>'min_reactivation_value','')::NUMERIC, 0) AS min_reactivation_value,
    t.updated_at,
    CASE t.scope::TEXT
      WHEN 'department' THEN dep.manager_id
      WHEN 'branch' THEN br.manager_id
      WHEN 'individual' THEN individual.user_id
      ELSE NULL
    END AS scope_owner_user_id
  FROM public.targets t
  LEFT JOIN public.hr_departments dep
    ON t.scope::TEXT='department' AND dep.id=t.scope_id
  LEFT JOIN public.branches br
    ON t.scope::TEXT='branch' AND br.id=t.scope_id
  LEFT JOIN public.hr_employees individual
    ON t.scope::TEXT='individual' AND individual.id=t.scope_id
  WHERE t.type_code='reactivation'
    AND t.is_active=true
    AND COALESCE(t.is_paused,false)=false
    AND p_business_date BETWEEN t.period_start AND t.period_end
),
governed_dormancy AS (
  SELECT COALESCE(MIN(dormancy_days) FILTER (WHERE dormancy_days IS NOT NULL), 90)::INTEGER AS dormancy_days
  FROM active_reactivation_targets
),
sales_history AS (
  SELECT
    so.customer_id,
    analytics.effective_sale_date(so.delivered_at,so.order_date) AS sale_date,
    GREATEST(COALESCE(so.total_amount,0)-COALESCE(so.returned_amount,0),0)::NUMERIC AS net_value
  FROM public.sales_orders so
  JOIN public.customers c ON c.id=so.customer_id AND c.is_active=true
  WHERE so.status::TEXT IN ('delivered','completed')
    AND analytics.effective_sale_date(so.delivered_at,so.order_date) <= p_business_date
),
history_agg AS (
  SELECT
    sh.customer_id,
    COUNT(*)::INTEGER AS historical_order_count,
    SUM(sh.net_value)::NUMERIC AS lifetime_net_value,
    MAX(sh.sale_date) AS last_sale_date,
    SUM(sh.net_value) FILTER (
      WHERE sh.sale_date BETWEEN p_business_date-89 AND p_business_date
    )::NUMERIC AS net_value_l90d,
    SUM(sh.net_value) FILTER (
      WHERE sh.sale_date BETWEEN p_business_date-179 AND p_business_date-90
    )::NUMERIC AS net_value_prev90d
  FROM sales_history sh
  GROUP BY sh.customer_id
),
repeat_rank AS (
  SELECT
    h.customer_id,
    percent_rank() OVER (
      ORDER BY h.lifetime_net_value
    )::NUMERIC AS value_percentile
  FROM history_agg h
  WHERE h.historical_order_count >= 2
),
reactivation_selected AS (
  SELECT
    art.*,
    tc.customer_id,
    tc.baseline_value,
    tc.baseline_category_count,
    tc.baseline_period_start,
    tc.baseline_period_end
  FROM active_reactivation_targets art
  JOIN public.target_customers tc ON tc.target_id=art.id
),
reactivation_period_sales AS (
  SELECT
    rs.id AS target_id,
    rs.customer_id,
    COALESCE(SUM(GREATEST(
      COALESCE(so.total_amount,0)-COALESCE(so.returned_amount,0),0
    )) FILTER (
      WHERE so.id IS NOT NULL
        AND (
          rs.scope='company'
          OR (rs.scope='individual' AND sale_rep.id=rs.scope_id)
          OR (rs.scope='department' AND sale_rep.department_id=rs.scope_id)
          OR (rs.scope='branch' AND sale_rep.branch_id=rs.scope_id)
        )
    ),0)::NUMERIC AS achieved_reactivation_value
  FROM reactivation_selected rs
  LEFT JOIN public.sales_orders so
    ON so.customer_id=rs.customer_id
   AND so.status::TEXT IN ('delivered','completed')
   AND analytics.effective_sale_date(so.delivered_at,so.order_date)
       BETWEEN rs.period_start AND LEAST(p_business_date,rs.period_end)
  LEFT JOIN public.hr_employees sale_rep ON sale_rep.user_id=so.rep_id
  GROUP BY rs.id,rs.customer_id
),
category_context AS (
  SELECT DISTINCT ON (tc.customer_id)
    tc.customer_id,
    t.id AS category_target_id,
    COALESCE(NULLIF(t.filter_criteria->>'required_category_count','')::INTEGER,0) AS required_category_count,
    tc.baseline_category_count,
    cardinality(COALESCE(tc.baseline_category_ids,ARRAY[]::UUID[]))::INTEGER AS baseline_category_id_count,
    COALESCE(achieved.achieved_category_count,0)::INTEGER AS achieved_new_category_count
  FROM public.targets t
  JOIN public.target_customers tc ON tc.target_id=t.id
  LEFT JOIN LATERAL (
    SELECT COUNT(DISTINCT p.category_id)::INTEGER AS achieved_category_count
    FROM public.sales_orders so
    JOIN public.sales_order_items soi ON soi.order_id=so.id
    JOIN public.products p ON p.id=soi.product_id
    JOIN public.hr_employees sale_rep ON sale_rep.user_id=so.rep_id
    WHERE so.customer_id=tc.customer_id
      AND so.status::TEXT IN ('delivered','completed')
      AND analytics.effective_sale_date(so.delivered_at,so.order_date)
          BETWEEN t.period_start AND LEAST(p_business_date,t.period_end)
      AND GREATEST(COALESCE(soi.delivered_quantity,0)-COALESCE(soi.returned_quantity,0),0)>0
      AND p.category_id IS NOT NULL
      AND NOT (p.category_id=ANY(COALESCE(tc.baseline_category_ids,ARRAY[]::UUID[])))
      AND (
        t.scope::TEXT='company'
        OR (t.scope::TEXT='individual' AND sale_rep.id=t.scope_id)
        OR (t.scope::TEXT='department' AND sale_rep.department_id=t.scope_id)
        OR (t.scope::TEXT='branch' AND sale_rep.branch_id=t.scope_id)
      )
  ) achieved ON true
  WHERE t.type_code='category_spread'
    AND t.is_active=true
    AND COALESCE(t.is_paused,false)=false
    AND p_business_date BETWEEN t.period_start AND t.period_end
  ORDER BY tc.customer_id,t.updated_at DESC,t.id
),
interaction_context AS (
  SELECT
    c.id AS customer_id,
    act.latest_activity_at,
    act.latest_activity_date,
    act.latest_outcome_type,
    COALESCE(vis.open_visit_commitments,0)::INTEGER AS open_visit_commitments,
    vis.next_visit_date,
    COALESCE(cal.open_call_commitments,0)::INTEGER AS open_call_commitments,
    cal.next_call_date
  FROM public.customers c
  LEFT JOIN LATERAL (
    SELECT
      COALESCE(a.end_time,a.start_time,a.created_at) AS latest_activity_at,
      a.activity_date AS latest_activity_date,
      a.outcome_type::TEXT AS latest_outcome_type
    FROM public.activities a
    WHERE a.customer_id=c.id AND a.deleted_at IS NULL
    ORDER BY COALESCE(a.end_time,a.start_time,a.created_at) DESC,a.id
    LIMIT 1
  ) act ON true
  LEFT JOIN LATERAL (
    SELECT
      COUNT(*)::INTEGER AS open_visit_commitments,
      MIN(vp.plan_date) AS next_visit_date
    FROM public.visit_plan_items vpi
    JOIN public.visit_plans vp ON vp.id=vpi.plan_id
    WHERE vpi.customer_id=c.id
      AND vp.plan_date>=p_business_date
      AND vpi.status NOT IN ('completed','skipped','cancelled','missed')
      AND vp.status NOT IN ('cancelled','completed')
  ) vis ON true
  LEFT JOIN LATERAL (
    SELECT
      COUNT(*)::INTEGER AS open_call_commitments,
      MIN(cp.plan_date) AS next_call_date
    FROM public.call_plan_items cpi
    JOIN public.call_plans cp ON cp.id=cpi.plan_id
    WHERE cpi.customer_id=c.id
      AND cp.plan_date>=p_business_date
      AND cpi.status NOT IN ('completed','skipped','cancelled','missed')
      AND cp.status NOT IN ('cancelled','completed')
  ) cal ON true
  WHERE c.is_active=true
),
active_work AS (
  SELECT DISTINCT ON (wl.entity_id)
    wl.entity_id AS customer_id,
    wi.id AS work_item_id,
    wi.work_number,
    wi.status::TEXT AS work_status,
    wi.title::TEXT AS work_title,
    wl.relation_type::TEXT AS relation_type
  FROM public.work_links wl
  JOIN public.work_items wi ON wi.id=wl.work_item_id
  WHERE wl.entity_type='customer'
    AND wi.status::TEXT NOT IN ('done','cancelled')
  ORDER BY wl.entity_id,wi.updated_at DESC,wi.id,wl.id
),
target_candidates AS (
  SELECT
    'customer_health:reactivation_gap:'||rs.id::TEXT||':'||rs.customer_id::TEXT AS case_key,
    'reactivation_gap'::TEXT AS case_type,
    'exception'::TEXT AS attention_class,
    CASE
      WHEN COALESCE(rr.value_percentile,0)>=0.90
       AND COALESCE(rps.achieved_reactivation_value,0)=0 THEN 'critical'
      WHEN COALESCE(rr.value_percentile,0)>=0.75
        OR COALESCE(rps.achieved_reactivation_value,0)=0 THEN 'high'
      ELSE 'medium'
    END::TEXT AS severity,
    rs.customer_id,
    rs.id AS target_id,
    rs.scope,
    rs.scope_id,
    rs.scope_owner_user_id,
    rs.target_name,
    rs.period_start,
    rs.period_end,
    rs.dormancy_days,
    rs.min_reactivation_value,
    rs.baseline_period_start,
    rs.baseline_period_end,
    COALESCE(rps.achieved_reactivation_value,0)::NUMERIC AS achieved_reactivation_value,
    COALESCE(rr.value_percentile,0)::NUMERIC AS value_percentile,
    true AS target_governed
  FROM reactivation_selected rs
  LEFT JOIN reactivation_period_sales rps
    ON rps.target_id=rs.id AND rps.customer_id=rs.customer_id
  LEFT JOIN repeat_rank rr ON rr.customer_id=rs.customer_id
  WHERE rs.baseline_period_end IS NOT NULL
    AND COALESCE(rps.achieved_reactivation_value,0) < rs.min_reactivation_value
),
opportunity_candidates AS (
  SELECT
    'customer_health:high_value_reactivation_opportunity:'||h.customer_id::TEXT AS case_key,
    'high_value_reactivation_opportunity'::TEXT AS case_type,
    'opportunity'::TEXT AS attention_class,
    CASE WHEN rr.value_percentile>=0.97 THEN 'high' ELSE 'medium' END::TEXT AS severity,
    h.customer_id,
    NULL::UUID AS target_id,
    NULL::TEXT AS scope,
    NULL::UUID AS scope_id,
    NULL::UUID AS scope_owner_user_id,
    NULL::TEXT AS target_name,
    NULL::DATE AS period_start,
    NULL::DATE AS period_end,
    gd.dormancy_days,
    NULL::NUMERIC AS min_reactivation_value,
    NULL::DATE AS baseline_period_start,
    NULL::DATE AS baseline_period_end,
    NULL::NUMERIC AS achieved_reactivation_value,
    rr.value_percentile,
    false AS target_governed
  FROM history_agg h
  JOIN repeat_rank rr ON rr.customer_id=h.customer_id
  CROSS JOIN governed_dormancy gd
  WHERE rr.value_percentile>=0.90
    AND h.last_sale_date IS NOT NULL
    AND (p_business_date-h.last_sale_date)>=gd.dormancy_days
    AND NOT EXISTS (
      SELECT 1 FROM reactivation_selected rs WHERE rs.customer_id=h.customer_id
    )
),
combined AS (
  SELECT * FROM target_candidates
  UNION ALL
  SELECT * FROM opportunity_candidates
),
enriched AS (
  SELECT
    cb.*,
    c.name::TEXT AS customer_name,
    c.code::TEXT AS customer_code,
    c.type::TEXT AS customer_type,
    c.governorate_id,c.city_id,c.area_id,
    c.assigned_rep_id,
    c.payment_terms::TEXT AS payment_terms,
    COALESCE(c.current_balance,0)::NUMERIC AS current_balance,
    COALESCE(c.credit_limit,0)::NUMERIC AS credit_limit,
    c.credit_days,
    CASE
      WHEN COALESCE(c.credit_limit,0)>0 AND COALESCE(c.current_balance,0)>COALESCE(c.credit_limit,0)
        THEN 'over_limit'
      WHEN COALESCE(c.current_balance,0)>0 THEN 'positive_balance'
      WHEN COALESCE(c.current_balance,0)<0 THEN 'customer_credit'
      ELSE 'clear'
    END::TEXT AS credit_state,
    h.historical_order_count,
    h.lifetime_net_value,
    h.last_sale_date,
    GREATEST(p_business_date-h.last_sale_date,0)::INTEGER AS recency_days,
    COALESCE(h.net_value_l90d,0)::NUMERIC AS net_value_l90d,
    COALESCE(h.net_value_prev90d,0)::NUMERIC AS net_value_prev90d,
    rep.full_name::TEXT AS assigned_rep_name,
    CASE WHEN c.assigned_rep_id IS NULL THEN false ELSE private.work_actor_is_active(c.assigned_rep_id) END AS assigned_rep_active,
    rep_employee.id AS assigned_rep_employee_id,
    rep_employee.department_id AS assigned_rep_department_id,
    rep_employee.branch_id AS assigned_rep_branch_id,
    manager_employee.user_id AS assigned_rep_manager_user_id,
    manager_profile.full_name::TEXT AS assigned_rep_manager_name,
    scope_owner.full_name::TEXT AS target_scope_owner_name,
    CASE WHEN cb.scope_owner_user_id IS NULL THEN false ELSE private.work_actor_is_active(cb.scope_owner_user_id) END AS target_scope_owner_active,
    ic.latest_activity_at,ic.latest_activity_date,ic.latest_outcome_type,
    ic.open_visit_commitments,ic.next_visit_date,
    ic.open_call_commitments,ic.next_call_date,
    aw.work_item_id,aw.work_number,aw.work_status,aw.work_title,aw.relation_type,
    cc.category_target_id,cc.required_category_count,cc.baseline_category_count,
    cc.baseline_category_id_count,cc.achieved_new_category_count
  FROM combined cb
  JOIN public.customers c ON c.id=cb.customer_id AND c.is_active=true
  LEFT JOIN history_agg h ON h.customer_id=cb.customer_id
  LEFT JOIN public.profiles rep ON rep.id=c.assigned_rep_id
  LEFT JOIN public.hr_employees rep_employee
    ON rep_employee.user_id=c.assigned_rep_id AND rep_employee.status::TEXT='active'
  LEFT JOIN public.hr_employees manager_employee
    ON manager_employee.id=rep_employee.direct_manager_id
  LEFT JOIN public.profiles manager_profile ON manager_profile.id=manager_employee.user_id
  LEFT JOIN public.profiles scope_owner ON scope_owner.id=cb.scope_owner_user_id
  LEFT JOIN interaction_context ic ON ic.customer_id=cb.customer_id
  LEFT JOIN active_work aw ON aw.customer_id=cb.customer_id
  LEFT JOIN category_context cc ON cc.customer_id=cb.customer_id
)
SELECT
  e.case_key,
  e.case_type,
  e.attention_class,
  e.severity,
  e.customer_id,
  e.customer_name,
  e.assigned_rep_id AS assigned_rep_user_id,
  e.assigned_rep_name,
  e.assigned_rep_active,
  e.target_id,
  e.scope AS target_scope,
  e.scope_id AS target_scope_id,
  e.scope_owner_user_id AS target_scope_owner_user_id,
  e.target_scope_owner_name,
  e.target_scope_owner_active,
  jsonb_build_object(
    'customer_id',e.customer_id,
    'customer_name',e.customer_name,
    'customer_code',e.customer_code,
    'customer_type',e.customer_type,
    'governorate_id',e.governorate_id,
    'city_id',e.city_id,
    'area_id',e.area_id,
    'assigned_rep_user_id',e.assigned_rep_id,
    'assigned_rep_employee_id',e.assigned_rep_employee_id,
    'assigned_rep_department_id',e.assigned_rep_department_id,
    'assigned_rep_branch_id',e.assigned_rep_branch_id,
    'historical_order_count',COALESCE(e.historical_order_count,0),
    'lifetime_net_value',COALESCE(e.lifetime_net_value,0),
    'value_percentile',e.value_percentile,
    'last_sale_date',e.last_sale_date,
    'recency_days',e.recency_days,
    'net_value_l90d',e.net_value_l90d,
    'net_value_prev90d',e.net_value_prev90d,
    'target_governed',e.target_governed,
    'target_id',e.target_id,
    'target_name',e.target_name,
    'target_scope',e.scope,
    'target_scope_id',e.scope_id,
    'target_period_start',e.period_start,
    'target_period_end',e.period_end,
    'dormancy_days',e.dormancy_days,
    'min_reactivation_value',e.min_reactivation_value,
    'achieved_reactivation_value',e.achieved_reactivation_value,
    'baseline_period_start',e.baseline_period_start,
    'baseline_period_end',e.baseline_period_end,
    'payment_terms',e.payment_terms,
    'current_balance',e.current_balance,
    'credit_limit',e.credit_limit,
    'credit_days',e.credit_days,
    'credit_state',e.credit_state,
    'category_spread',CASE WHEN e.category_target_id IS NULL THEN NULL ELSE jsonb_build_object(
      'target_id',e.category_target_id,
      'required_category_count',e.required_category_count,
      'baseline_category_count',e.baseline_category_count,
      'baseline_category_id_count',e.baseline_category_id_count,
      'achieved_new_category_count',e.achieved_new_category_count
    ) END,
    'interaction',jsonb_build_object(
      'latest_activity_at',e.latest_activity_at,
      'latest_activity_date',e.latest_activity_date,
      'latest_outcome_type',e.latest_outcome_type,
      'open_visit_commitments',e.open_visit_commitments,
      'next_visit_date',e.next_visit_date,
      'open_call_commitments',e.open_call_commitments,
      'next_call_date',e.next_call_date,
      'interpretation','supporting_only_no_causal_inference'
    ),
    'existing_active_work',CASE WHEN e.work_item_id IS NULL THEN NULL ELSE jsonb_build_object(
      'work_item_id',e.work_item_id,
      'work_number',e.work_number,
      'status',e.work_status,
      'title',e.work_title,
      'relation_type',e.relation_type
    ) END
  ) AS facts,
  jsonb_build_object(
    'assigned_rep',CASE WHEN e.assigned_rep_id IS NULL THEN NULL ELSE jsonb_build_object(
      'user_id',e.assigned_rep_id,
      'full_name',e.assigned_rep_name,
      'active_work_actor',e.assigned_rep_active,
      'evidence_type','customer_assigned_rep',
      'routing_rule',false
    ) END,
    'assigned_rep_manager',CASE WHEN e.assigned_rep_manager_user_id IS NULL THEN NULL ELSE jsonb_build_object(
      'user_id',e.assigned_rep_manager_user_id,
      'full_name',e.assigned_rep_manager_name,
      'active_work_actor',private.work_actor_is_active(e.assigned_rep_manager_user_id),
      'evidence_type','employee_direct_manager_context',
      'routing_rule',false
    ) END,
    'target_scope_accountability',CASE WHEN e.scope_owner_user_id IS NULL THEN NULL ELSE jsonb_build_object(
      'user_id',e.scope_owner_user_id,
      'full_name',e.target_scope_owner_name,
      'active_work_actor',e.target_scope_owner_active,
      'evidence_type','reactivation_target_scope_accountability',
      'routing_rule',false
    ) END,
    'existing_active_work',CASE WHEN e.work_item_id IS NULL THEN NULL ELSE jsonb_build_object(
      'work_item_id',e.work_item_id,
      'work_number',e.work_number,
      'status',e.work_status,
      'evidence_type','existing_customer_work_continuity'
    ) END
  ) AS responsibility_evidence,
  jsonb_build_object(
    'source','customers+sales_orders+targets+target_customers+field_execution+work_links',
    'business_date',p_business_date,
    'commercial_date_contract','analytics.effective_sale_date',
    'eligible_sales_statuses',jsonb_build_array('completed','delivered'),
    'target_governed',e.target_governed,
    'target_recalculation_performed',false,
    'customer_360_semantics_reused',true,
    'legacy_fixed_45_90_status_not_authoritative',true,
    'field_execution_interpretation','supporting_only_no_causal_inference',
    'credit_interpretation','feasibility_evidence_not_customer_health_cause',
    'pii_excluded_from_worker_facts',true
  ) AS trust
FROM enriched e
ORDER BY
  CASE e.case_type WHEN 'reactivation_gap' THEN 0 ELSE 1 END,
  CASE e.severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END,
  e.value_percentile DESC,
  COALESCE(e.lifetime_net_value,0) DESC,
  e.customer_id
LIMIT LEAST(GREATEST(COALESCE(p_limit,50),1),2000);
$$;

REVOKE ALL ON FUNCTION ai_ops.customer_health_candidates(DATE, INTEGER)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION ai_ops.customer_health_candidates(DATE, INTEGER) IS
  'Read-only deterministic Customer Health kernel combining governed reactivation gaps with bounded top-decile dormant opportunities and structured feasibility evidence.';

RESET lock_timeout;
RESET statement_timeout;