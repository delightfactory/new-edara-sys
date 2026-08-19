-- ============================================================================
-- AI Operations — cross-domain planning evidence without fake capacity scores
--
-- HR explicit unavailability remains a hard feasibility blocker in the existing
-- current_cross_domain_feasibility_issues(). Work/Field pressure is useful but
-- is not sufficient evidence to declare a person incapable of more work because
-- EDARA has no trusted effort estimate for all Work items. This migration freezes
-- those constraints as planning evidence instead of inventing thresholds.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.build_actor_feasibility_evidence(p_snapshot_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
WITH actors AS (
  SELECT DISTINCT user_id
  FROM (
    SELECT NULLIF(sc.responsibility_evidence->>'owner_user_id','')::UUID AS user_id
    FROM ai_ops.snapshot_cases sc WHERE sc.snapshot_id=p_snapshot_id AND sc.domain='work_health'
    UNION ALL
    SELECT NULLIF(sc.responsibility_evidence->>'assignee_user_id','')::UUID
    FROM ai_ops.snapshot_cases sc WHERE sc.snapshot_id=p_snapshot_id AND sc.domain='work_health'
    UNION ALL
    SELECT NULLIF(sc.responsibility_evidence->>'rep_user_id','')::UUID
    FROM ai_ops.snapshot_cases sc WHERE sc.snapshot_id=p_snapshot_id AND sc.domain='field_execution'
    UNION ALL
    SELECT NULLIF(sc.responsibility_evidence->>'manager_user_id','')::UUID
    FROM ai_ops.snapshot_cases sc WHERE sc.snapshot_id=p_snapshot_id AND sc.domain='field_execution'
    UNION ALL
    SELECT NULLIF(sc.facts->>'affected_user_id','')::UUID
    FROM ai_ops.snapshot_cases sc WHERE sc.snapshot_id=p_snapshot_id AND sc.domain='hr_availability'
    UNION ALL
    SELECT NULLIF(sc.responsibility_evidence->>'coverage_owner_user_id','')::UUID
    FROM ai_ops.snapshot_cases sc WHERE sc.snapshot_id=p_snapshot_id AND sc.domain='hr_availability'
    UNION ALL
    SELECT NULLIF(sc.facts->>'assigned_rep_user_id','')::UUID
    FROM ai_ops.snapshot_cases sc WHERE sc.snapshot_id=p_snapshot_id AND sc.domain='customer_health'
    UNION ALL
    SELECT NULLIF(sc.responsibility_evidence->'scope_accountability'->>'user_id','')::UUID
    FROM ai_ops.snapshot_cases sc WHERE sc.snapshot_id=p_snapshot_id AND sc.domain='sales'
    UNION ALL
    SELECT NULLIF(sc.responsibility_evidence->>'responsible_user_id','')::UUID
    FROM ai_ops.snapshot_cases sc WHERE sc.snapshot_id=p_snapshot_id AND sc.domain='inventory'
  ) x
  WHERE user_id IS NOT NULL
), evidence AS (
  SELECT
    a.user_id,
    p.full_name::TEXT AS user_label,
    private.work_actor_is_active(a.user_id) AS active_work_actor,
    (SELECT count(*)::INTEGER FROM ai_ops.snapshot_cases sc
      WHERE sc.snapshot_id=p_snapshot_id AND sc.domain='hr_availability'
        AND NULLIF(sc.facts->>'affected_user_id','')::UUID=a.user_id) AS hard_unavailability_cases,
    (SELECT count(*)::INTEGER FROM ai_ops.snapshot_cases sc
      WHERE sc.snapshot_id=p_snapshot_id AND sc.domain='work_health'
        AND NULLIF(sc.responsibility_evidence->>'owner_user_id','')::UUID=a.user_id) AS unhealthy_owned_work_cases,
    (SELECT count(*)::INTEGER FROM ai_ops.snapshot_cases sc
      WHERE sc.snapshot_id=p_snapshot_id AND sc.domain='work_health'
        AND NULLIF(sc.responsibility_evidence->>'assignee_user_id','')::UUID=a.user_id) AS unhealthy_assigned_work_cases,
    (SELECT count(*)::INTEGER FROM ai_ops.snapshot_cases sc
      WHERE sc.snapshot_id=p_snapshot_id AND sc.domain='field_execution'
        AND NULLIF(sc.responsibility_evidence->>'rep_user_id','')::UUID=a.user_id) AS overdue_field_plan_cases,
    (SELECT count(*)::INTEGER FROM ai_ops.snapshot_cases sc
      WHERE sc.snapshot_id=p_snapshot_id AND sc.domain='customer_health'
        AND NULLIF(sc.facts->>'assigned_rep_user_id','')::UUID=a.user_id) AS customer_relationship_cases,
    (SELECT count(*)::INTEGER FROM ai_ops.snapshot_cases sc
      WHERE sc.snapshot_id=p_snapshot_id AND sc.domain='sales'
        AND NULLIF(sc.responsibility_evidence->'scope_accountability'->>'user_id','')::UUID=a.user_id) AS sales_accountability_cases,
    (SELECT count(*)::INTEGER FROM ai_ops.snapshot_cases sc
      WHERE sc.snapshot_id=p_snapshot_id AND sc.domain='inventory'
        AND NULLIF(sc.responsibility_evidence->>'responsible_user_id','')::UUID=a.user_id) AS inventory_responsibility_cases
  FROM actors a
  LEFT JOIN public.profiles p ON p.id=a.user_id
)
SELECT COALESCE(jsonb_agg(jsonb_build_object(
  'user_id',e.user_id,
  'user_label',e.user_label,
  'active_work_actor',e.active_work_actor,
  'hard_unavailability_cases',e.hard_unavailability_cases,
  'unhealthy_owned_work_cases',e.unhealthy_owned_work_cases,
  'unhealthy_assigned_work_cases',e.unhealthy_assigned_work_cases,
  'overdue_field_plan_cases',e.overdue_field_plan_cases,
  'customer_relationship_cases',e.customer_relationship_cases,
  'sales_accountability_cases',e.sales_accountability_cases,
  'inventory_responsibility_cases',e.inventory_responsibility_cases,
  'hard_block_from_this_summary',e.hard_unavailability_cases>0 OR NOT e.active_work_actor,
  'work_field_counts_are_pressure_evidence_only',true,
  'capacity_score',NULL,
  'capacity_score_prohibited_without_effort_model',true
) ORDER BY
  (e.hard_unavailability_cases>0 OR NOT e.active_work_actor) DESC,
  (e.unhealthy_owned_work_cases+e.unhealthy_assigned_work_cases+e.overdue_field_plan_cases) DESC,
  e.user_label NULLS LAST,e.user_id),'[]'::JSONB)
FROM evidence e;
$$;
REVOKE ALL ON FUNCTION ai_ops.build_actor_feasibility_evidence(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.build_cross_domain_entity_links(p_snapshot_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
WITH customer_rows AS (
  SELECT
    NULLIF(sc.facts->>'customer_id','')::UUID AS entity_id,
    sc.case_id,sc.domain,sc.case_type,sc.severity
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id=p_snapshot_id
    AND NULLIF(sc.facts->>'customer_id','') IS NOT NULL
), customer_links AS (
  SELECT entity_id,
    jsonb_agg(jsonb_build_object(
      'case_id',case_id,'domain',domain,'case_type',case_type,'severity',severity
    ) ORDER BY domain,case_id) AS cases,
    count(DISTINCT domain)::INTEGER AS domain_count
  FROM customer_rows GROUP BY entity_id HAVING count(DISTINCT domain)>1
), product_rows AS (
  SELECT
    NULLIF(sc.facts->>'product_id','')::UUID AS entity_id,
    sc.case_id,sc.domain,sc.case_type,sc.severity
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id=p_snapshot_id
    AND NULLIF(sc.facts->>'product_id','') IS NOT NULL
), product_links AS (
  SELECT entity_id,
    jsonb_agg(jsonb_build_object(
      'case_id',case_id,'domain',domain,'case_type',case_type,'severity',severity
    ) ORDER BY domain,case_id) AS cases,
    count(DISTINCT domain)::INTEGER AS domain_count
  FROM product_rows GROUP BY entity_id HAVING count(DISTINCT domain)>1
)
SELECT jsonb_build_object(
  'customers',COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'customer_id',entity_id,'domain_count',domain_count,'cases',cases,
    'interpretation','shared_entity_evidence_not_automatic_conflict'
  ) ORDER BY entity_id) FROM customer_links),'[]'::JSONB),
  'products',COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'product_id',entity_id,'domain_count',domain_count,'cases',cases,
    'interpretation','sales_inventory_link_requires_case_specific_reasoning'
  ) ORDER BY entity_id) FROM product_links),'[]'::JSONB),
  'automatic_priority_from_link',false
);
$$;
REVOKE ALL ON FUNCTION ai_ops.build_cross_domain_entity_links(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

-- Enrich the frozen global context builder used by capture_global_operational_context.
ALTER FUNCTION ai_ops.build_global_operational_context(UUID,UUID)
  RENAME TO build_global_operational_context_pre_feasibility_evidence_v1;
REVOKE ALL ON FUNCTION ai_ops.build_global_operational_context_pre_feasibility_evidence_v1(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.build_global_operational_context(
  p_snapshot_id UUID,
  p_run_id UUID
)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    ai_ops.build_global_operational_context_pre_feasibility_evidence_v1(p_snapshot_id,p_run_id)
    || jsonb_build_object(
      'actor_feasibility',ai_ops.build_actor_feasibility_evidence(p_snapshot_id),
      'cross_domain_entity_links',ai_ops.build_cross_domain_entity_links(p_snapshot_id),
      'feasibility_semantics',jsonb_build_object(
        'explicit_hr_unavailability_is_hard',true,
        'inactive_work_actor_is_hard',true,
        'work_health_pressure_is_not_capacity_proof',true,
        'field_execution_pressure_is_not_capacity_proof',true,
        'inventory_and_credit_links_require_case_specific_reasoning',true,
        'arbitrary_tasks_per_day_threshold',false,
        'employee_performance_score',false
      )
    );
$$;
REVOKE ALL ON FUNCTION ai_ops.build_global_operational_context(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.build_actor_feasibility_evidence(UUID) IS
  'Frozen actor feasibility evidence across HR/Work/Field/Customer/Sales/Inventory. Explicit unavailability is hard; Work/Field counts are pressure context only and never a productivity/capacity score.';
COMMENT ON FUNCTION ai_ops.build_cross_domain_entity_links(UUID) IS
  'Exact same-entity links between frozen customer/product Cases so the planner can reason about cross-domain credit/customer and sales/inventory interactions without automatic severity merging.';

RESET lock_timeout;
RESET statement_timeout;
