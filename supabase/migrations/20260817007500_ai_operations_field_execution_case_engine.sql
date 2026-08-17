-- ============================================================================
-- AI Operations Planner — Field Execution Case Engine
--
-- DESIGN-TIME MIGRATION ONLY. Visit/Activity records remain read-only.
-- Production-backed v1 case:
--   * overdue_visit_day: a confirmed/in-progress visit day is before the
--     business date and still contains pending visit commitments.
--
-- The case is deliberately plan-level. Native Visit Plan operations already
-- resolve the day atomically; emitting one AI Case per pending customer would
-- create duplicate operational work and distort accountability.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.field_execution_candidates(
  p_business_date DATE,
  p_limit INTEGER DEFAULT 50
)
RETURNS TABLE(
  case_key TEXT,
  case_type TEXT,
  attention_class TEXT,
  severity TEXT,
  entity_type TEXT,
  entity_id UUID,
  visit_plan_id UUID,
  plan_date DATE,
  rep_employee_id UUID,
  rep_user_id UUID,
  rep_name TEXT,
  rep_active BOOLEAN,
  manager_user_id UUID,
  manager_name TEXT,
  manager_active BOOLEAN,
  responsibility_unambiguous BOOLEAN,
  facts JSONB,
  responsibility_evidence JSONB,
  trust JSONB
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
WITH plan_rollup AS (
  SELECT
    vp.id AS visit_plan_id,
    vp.employee_id AS rep_employee_id,
    vp.plan_date,
    vp.plan_type::TEXT AS plan_type,
    vp.status::TEXT AS plan_status,
    vp.organizational_branch_id AS branch_id,
    vp.confirmed_at,
    vp.started_at,
    vp.created_at,
    vp.updated_at,
    COUNT(vpi.id)::INTEGER AS total_count,
    COUNT(vpi.id) FILTER (WHERE vpi.status='pending')::INTEGER AS pending_count,
    COUNT(vpi.id) FILTER (WHERE vpi.status='completed')::INTEGER AS completed_count,
    COUNT(vpi.id) FILTER (WHERE vpi.status='skipped')::INTEGER AS skipped_count,
    COUNT(vpi.id) FILTER (WHERE vpi.status='missed')::INTEGER AS missed_count,
    COUNT(vpi.id) FILTER (WHERE vpi.status='rescheduled')::INTEGER AS rescheduled_count
  FROM public.visit_plans vp
  JOIN public.visit_plan_items vpi ON vpi.plan_id=vp.id
  WHERE vp.plan_date<p_business_date
    AND vp.status IN ('confirmed','in_progress')
  GROUP BY vp.id,vp.employee_id,vp.plan_date,vp.plan_type,vp.status,
           vp.organizational_branch_id,vp.confirmed_at,vp.started_at,
           vp.created_at,vp.updated_at
  HAVING COUNT(vpi.id) FILTER (WHERE vpi.status='pending')>0
),
enriched AS (
  SELECT
    pr.*,
    GREATEST(p_business_date-pr.plan_date,1)::INTEGER AS overdue_days,
    ROUND((pr.pending_count::NUMERIC/NULLIF(pr.total_count,0))*100,2) AS pending_pct,
    rep.user_id AS rep_user_id,
    rep.direct_manager_id,
    rep_profile.full_name::TEXT AS rep_name,
    mgr.user_id AS manager_user_id,
    mgr_profile.full_name::TEXT AS manager_name,
    CASE WHEN rep.user_id IS NULL THEN false ELSE private.work_actor_is_active(rep.user_id) END AS rep_active,
    CASE WHEN mgr.user_id IS NULL THEN false ELSE private.work_actor_is_active(mgr.user_id) END AS manager_active,
    pending.pending_items,
    latest_activity.latest_activity_at,
    latest_activity.latest_activity_type,
    active_work.work_item_id AS active_work_item_id,
    active_work.work_number AS active_work_number,
    active_work.work_status AS active_work_status
  FROM plan_rollup pr
  LEFT JOIN public.hr_employees rep
    ON rep.id=pr.rep_employee_id AND rep.status::TEXT='active'
  LEFT JOIN public.profiles rep_profile ON rep_profile.id=rep.user_id
  LEFT JOIN public.hr_employees mgr
    ON mgr.id=rep.direct_manager_id AND mgr.status::TEXT='active'
  LEFT JOIN public.profiles mgr_profile ON mgr_profile.id=mgr.user_id
  LEFT JOIN LATERAL (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'visit_plan_item_id',x.id,
      'customer_id',x.customer_id,
      'customer_name',x.customer_name,
      'customer_code',x.customer_code,
      'sequence',x.sequence,
      'planned_time',x.planned_time,
      'priority',x.priority,
      'purpose_type',x.purpose_type
    ) ORDER BY x.sequence,x.id),'[]'::JSONB) AS pending_items
    FROM (
      SELECT vpi.id,vpi.customer_id,c.name::TEXT AS customer_name,c.code::TEXT AS customer_code,
             vpi.sequence,vpi.planned_time,vpi.priority::TEXT,vpi.purpose_type::TEXT
      FROM public.visit_plan_items vpi
      LEFT JOIN public.customers c ON c.id=vpi.customer_id
      WHERE vpi.plan_id=pr.visit_plan_id AND vpi.status='pending'
      ORDER BY vpi.sequence,vpi.id
      LIMIT 10
    ) x
  ) pending ON true
  LEFT JOIN LATERAL (
    SELECT COALESCE(a.end_time,a.start_time,a.created_at) AS latest_activity_at,
           a.type::TEXT AS latest_activity_type
    FROM public.activities a
    JOIN public.visit_plan_items vpi ON vpi.id=a.visit_plan_item_id
    WHERE vpi.plan_id=pr.visit_plan_id AND a.deleted_at IS NULL
    ORDER BY COALESCE(a.end_time,a.start_time,a.created_at) DESC,a.id
    LIMIT 1
  ) latest_activity ON true
  LEFT JOIN LATERAL (
    SELECT wi.id AS work_item_id,wi.work_number,wi.status::TEXT AS work_status
    FROM public.work_links wl
    JOIN public.work_items wi ON wi.id=wl.work_item_id
    WHERE wl.entity_type='visit_plan' AND wl.entity_id=pr.visit_plan_id
      AND wi.status::TEXT NOT IN ('done','cancelled')
    ORDER BY wi.updated_at DESC,wi.id
    LIMIT 1
  ) active_work ON true
)
SELECT
  'field_execution:overdue_visit_day:'||e.visit_plan_id::TEXT AS case_key,
  'overdue_visit_day'::TEXT AS case_type,
  'exception'::TEXT AS attention_class,
  CASE
    WHEN e.overdue_days>=14 THEN 'critical'
    WHEN e.overdue_days>=7 THEN 'high'
    ELSE 'medium'
  END::TEXT AS severity,
  'visit_plan'::TEXT AS entity_type,
  e.visit_plan_id AS entity_id,
  e.visit_plan_id,
  e.plan_date,
  e.rep_employee_id,
  e.rep_user_id,
  e.rep_name,
  e.rep_active,
  e.manager_user_id,
  e.manager_name,
  e.manager_active,
  (
    e.rep_user_id IS NOT NULL AND e.manager_user_id IS NOT NULL
    AND e.rep_active AND e.manager_active
  ) AS responsibility_unambiguous,
  jsonb_build_object(
    'visit_plan_id',e.visit_plan_id,
    'plan_date',e.plan_date,
    'plan_type',e.plan_type,
    'plan_status',e.plan_status,
    'branch_id',e.branch_id,
    'confirmed_at',e.confirmed_at,
    'started_at',e.started_at,
    'overdue_days',e.overdue_days,
    'total_count',e.total_count,
    'pending_count',e.pending_count,
    'completed_count',e.completed_count,
    'skipped_count',e.skipped_count,
    'missed_count',e.missed_count,
    'rescheduled_count',e.rescheduled_count,
    'pending_pct',e.pending_pct,
    'pending_items',e.pending_items,
    'pending_items_captured',jsonb_array_length(e.pending_items),
    'pending_items_truncated',e.pending_count>jsonb_array_length(e.pending_items),
    'latest_linked_activity_at',e.latest_activity_at,
    'latest_linked_activity_type',e.latest_activity_type,
    'existing_active_work_item_id',e.active_work_item_id,
    'existing_active_work_number',e.active_work_number,
    'existing_active_work_status',e.active_work_status,
    'native_resolution_contract','visit_plan_atomic_operations',
    'location_evidence_in_worker_facts',false
  ) AS facts,
  jsonb_build_object(
    'routing_rule','plan_rep_executes_direct_manager_accountable',
    'responsibility_unambiguous',(
      e.rep_user_id IS NOT NULL AND e.manager_user_id IS NOT NULL
      AND e.rep_active AND e.manager_active
    ),
    'rep_employee_id',e.rep_employee_id,
    'rep_user_id',e.rep_user_id,
    'rep_name',e.rep_name,
    'rep_active',e.rep_active,
    'manager_user_id',e.manager_user_id,
    'manager_name',e.manager_name,
    'manager_active',e.manager_active
  ) AS responsibility_evidence,
  jsonb_build_object(
    'source_contract','field-execution-v1',
    'deterministic',true,
    'business_date',p_business_date,
    'operational_plan_states',jsonb_build_array('confirmed','in_progress'),
    'candidate_condition','past_plan_with_pending_commitments',
    'legacy_submitted_state_authoritative',false,
    'severity_age_bands_are_triage_not_sla',true,
    'gps_coordinates_excluded',true,
    'miss_reason_inferred',false,
    'visit_mutation_performed',false
  ) AS trust
FROM enriched e
ORDER BY
  CASE WHEN e.overdue_days>=14 THEN 0 WHEN e.overdue_days>=7 THEN 1 ELSE 2 END,
  e.overdue_days DESC,e.pending_count DESC,e.visit_plan_id
LIMIT LEAST(GREATEST(COALESCE(p_limit,50),1),2000);
$$;

REVOKE ALL ON FUNCTION ai_ops.field_execution_candidates(DATE,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.field_execution_candidates(DATE,INTEGER) IS
  'Read-only deterministic Field Execution candidates at visit-day level for operational confirmed/in-progress plans that are past date with pending commitments; exact GPS and inferred miss causes are excluded.';

RESET lock_timeout;
RESET statement_timeout;
