-- ============================================================================
-- AI Operations Planner — Cross-Domain Runtime Hardening
--
-- DESIGN-TIME MIGRATION ONLY.
-- Repairs runtime/schema drift found during post-implementation review:
--   * Field Execution resolves activity type through activities.type_id -> activity_types.code.
--   * Field Execution freezes a full pending-set fingerprint while keeping only 10 bounded items.
--   * Field Execution and Inventory expose the same frozen existing_active_work evidence contract.
--   * Worker context/staging validate the full canonical required-domain set through one helper.
-- No production operational source table is mutated by this migration.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

-- --------------------------------------------------------------------------
-- Field Execution candidate kernel — schema-compatible + full pending-set parity
-- --------------------------------------------------------------------------
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
    COUNT(vpi.id) FILTER (WHERE vpi.status='rescheduled')::INTEGER AS rescheduled_count,
    md5(COALESCE(
      string_agg(
        concat_ws(
          ':',
          vpi.id::TEXT,
          vpi.status::TEXT,
          COALESCE(vpi.sequence::TEXT,''),
          COALESCE(vpi.planned_time::TEXT,'')
        ),
        '|' ORDER BY vpi.id::TEXT
      ) FILTER (WHERE vpi.status='pending'),
      ''
    )) AS pending_set_fingerprint
  FROM public.visit_plans vp
  JOIN public.visit_plan_items vpi ON vpi.plan_id=vp.id
  WHERE vp.plan_date<p_business_date
    AND vp.status IN ('confirmed','in_progress')
  GROUP BY
    vp.id,vp.employee_id,vp.plan_date,vp.plan_type,vp.status,
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
      SELECT
        vpi.id,vpi.customer_id,c.name::TEXT AS customer_name,c.code::TEXT AS customer_code,
        vpi.sequence,vpi.planned_time,vpi.priority::TEXT,vpi.purpose_type::TEXT
      FROM public.visit_plan_items vpi
      LEFT JOIN public.customers c ON c.id=vpi.customer_id
      WHERE vpi.plan_id=pr.visit_plan_id AND vpi.status='pending'
      ORDER BY vpi.sequence,vpi.id
      LIMIT 10
    ) x
  ) pending ON true
  LEFT JOIN LATERAL (
    SELECT
      COALESCE(a.end_time,a.start_time,a.created_at) AS latest_activity_at,
      COALESCE(at.code::TEXT,a.subject_type::TEXT,'activity') AS latest_activity_type
    FROM public.activities a
    JOIN public.visit_plan_items vpi ON vpi.id=a.visit_plan_item_id
    LEFT JOIN public.activity_types at ON at.id=a.type_id
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
    'pending_set_fingerprint',e.pending_set_fingerprint,
    'latest_linked_activity_at',e.latest_activity_at,
    'latest_linked_activity_type',e.latest_activity_type,
    'existing_active_work',
      CASE WHEN e.active_work_item_id IS NULL THEN NULL
           ELSE jsonb_build_object(
             'work_item_id',e.active_work_item_id,
             'work_number',e.active_work_number,
             'status',e.active_work_status
           ) END,
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
    'source_contract','field-execution-v2-runtime-hardened',
    'deterministic',true,
    'business_date',p_business_date,
    'operational_plan_states',jsonb_build_array('confirmed','in_progress'),
    'candidate_condition','past_plan_with_pending_commitments',
    'legacy_submitted_state_authoritative',false,
    'severity_age_bands_are_triage_not_sla',true,
    'gps_coordinates_excluded',true,
    'miss_reason_inferred',false,
    'pending_set_fingerprint_algorithm','md5-stable-identity',
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

-- --------------------------------------------------------------------------
-- Inventory candidate wrapper — add exact frozen active Work evidence.
-- The original deterministic business kernel is preserved unchanged.
-- --------------------------------------------------------------------------
ALTER FUNCTION ai_ops.inventory_candidates(DATE,INTEGER)
  RENAME TO inventory_candidates_pre_active_work_v1;

REVOKE ALL ON FUNCTION ai_ops.inventory_candidates_pre_active_work_v1(DATE,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.inventory_candidates(
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
  warehouse_id UUID,
  warehouse_name TEXT,
  product_id UUID,
  product_name TEXT,
  transfer_id UUID,
  responsible_user_id UUID,
  responsible_user_name TEXT,
  responsible_user_active BOOLEAN,
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
SELECT
  b.case_key,b.case_type,b.attention_class,b.severity,b.entity_type,b.entity_id,
  b.warehouse_id,b.warehouse_name,b.product_id,b.product_name,b.transfer_id,
  b.responsible_user_id,b.responsible_user_name,b.responsible_user_active,
  b.responsibility_unambiguous,
  b.facts || jsonb_build_object(
    'existing_active_work',
      CASE WHEN aw.work_item_id IS NULL THEN NULL
           ELSE jsonb_build_object(
             'work_item_id',aw.work_item_id,
             'work_number',aw.work_number,
             'status',aw.work_status
           ) END
  ) AS facts,
  b.responsibility_evidence,
  b.trust || jsonb_build_object('active_work_evidence_frozen',true) AS trust
FROM ai_ops.inventory_candidates_pre_active_work_v1(p_business_date,p_limit) b
LEFT JOIN LATERAL (
  SELECT wi.id AS work_item_id,wi.work_number,wi.status::TEXT AS work_status
  FROM public.work_items wi
  WHERE wi.status::TEXT NOT IN ('done','cancelled')
    AND (
      (
        b.case_type='local_shortage'
        AND b.product_id IS NOT NULL
        AND b.warehouse_id IS NOT NULL
        AND EXISTS(
          SELECT 1 FROM public.work_links wp
          WHERE wp.work_item_id=wi.id
            AND wp.entity_type='product'
            AND wp.entity_id=b.product_id
        )
        AND EXISTS(
          SELECT 1 FROM public.work_links ww
          WHERE ww.work_item_id=wi.id
            AND ww.entity_type='warehouse'
            AND ww.entity_id=b.warehouse_id
        )
      )
      OR
      (
        b.case_type='stalled_transfer'
        AND b.transfer_id IS NOT NULL
        AND EXISTS(
          SELECT 1 FROM public.work_links wt
          WHERE wt.work_item_id=wi.id
            AND wt.entity_type='stock_transfer'
            AND wt.entity_id=b.transfer_id
        )
      )
    )
  ORDER BY wi.updated_at DESC,wi.id
  LIMIT 1
) aw ON true;
$$;

REVOKE ALL ON FUNCTION ai_ops.inventory_candidates(DATE,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

-- --------------------------------------------------------------------------
-- Full pending-set drift helper. Bounded display remains at 10 items, while
-- consequential actions compare a stable identity over every pending item.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ai_ops.field_execution_pending_set_drift(
  p_decision_id UUID
)
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
  v_business_date DATE;
  v_current RECORD;
  v_frozen_fingerprint TEXT;
  v_current_fingerprint TEXT;
BEGIN
  SELECT * INTO v_decision FROM ai_ops.decisions WHERE id=p_decision_id;
  IF NOT FOUND OR v_decision.decision_type NOT IN ('CREATE_WORK','ESCALATE') THEN
    RETURN '[]'::JSONB;
  END IF;

  SELECT * INTO v_snapshot FROM ai_ops.snapshots WHERE run_id=v_decision.run_id;
  IF NOT FOUND THEN RETURN '[]'::JSONB; END IF;

  SELECT * INTO v_sc
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id=v_snapshot.id AND sc.case_id=v_decision.case_id;
  IF NOT FOUND OR v_sc.domain<>'field_execution' THEN RETURN '[]'::JSONB; END IF;

  SELECT r.business_date INTO v_business_date
  FROM ai_ops.planner_runs r WHERE r.id=v_decision.run_id;

  SELECT * INTO v_current
  FROM ai_ops.field_execution_candidates(v_business_date,2000) c
  WHERE c.case_key=v_sc.case_key
  LIMIT 1;
  IF NOT FOUND THEN RETURN '[]'::JSONB; END IF;

  v_frozen_fingerprint:=NULLIF(v_sc.facts->>'pending_set_fingerprint','');
  v_current_fingerprint:=NULLIF(v_current.facts->>'pending_set_fingerprint','');

  IF v_frozen_fingerprint IS NULL OR v_current_fingerprint IS NULL THEN
    RETURN jsonb_build_array('visit_day_pending_set_fingerprint_missing');
  END IF;

  IF v_frozen_fingerprint IS DISTINCT FROM v_current_fingerprint THEN
    RETURN jsonb_build_array('visit_day_pending_set_changed_after_snapshot');
  END IF;

  RETURN '[]'::JSONB;
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.field_execution_pending_set_drift(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.current_field_execution_decision_issues(p_decision_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_reasons JSONB;
BEGIN
  v_reasons :=
    ai_ops.current_field_execution_decision_issues_pre_bounded_v1(p_decision_id)
    || ai_ops.field_execution_pending_set_drift(p_decision_id);

  RETURN ai_ops.apply_selected_case_capture_actionability(
    p_decision_id,
    v_reasons
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.current_field_execution_decision_issues(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

-- --------------------------------------------------------------------------
-- One canonical required-domain contract for worker context and staging.
-- Future domain migrations only need to replace required_operational_domains().
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ai_ops.required_operational_domains()
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT ARRAY[
    'receivables',
    'sales',
    'customer_health',
    'inventory',
    'field_execution'
  ]::TEXT[];
$$;

REVOKE ALL ON FUNCTION ai_ops.required_operational_domains()
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.snapshot_has_required_domain_captures(
  p_snapshot_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    p_snapshot_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM unnest(ai_ops.required_operational_domains()) AS required(domain)
      WHERE NOT EXISTS (
        SELECT 1
        FROM ai_ops.snapshot_domain_captures dc
        WHERE dc.snapshot_id=p_snapshot_id
          AND dc.domain=required.domain
      )
    );
$$;

REVOKE ALL ON FUNCTION ai_ops.snapshot_has_required_domain_captures(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

ALTER FUNCTION ai_ops.worker_get_context(UUID,TEXT)
  RENAME TO worker_get_context_pre_required_domains_v1;

REVOKE ALL ON FUNCTION ai_ops.worker_get_context_pre_required_domains_v1(UUID,TEXT)
  FROM PUBLIC,anon,authenticated,service_role;

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
  v_result JSONB;
  v_snapshot_id UUID;
BEGIN
  v_result:=ai_ops.worker_get_context_pre_required_domains_v1(p_run_id,p_worker_id);

  IF COALESCE((v_result->>'blocked')::BOOLEAN,false) THEN
    RETURN v_result;
  END IF;

  SELECT s.id INTO v_snapshot_id
  FROM ai_ops.snapshots s
  WHERE s.run_id=p_run_id;

  IF v_snapshot_id IS NULL
     OR NOT ai_ops.snapshot_has_required_domain_captures(v_snapshot_id) THEN
    RAISE EXCEPTION 'worker context is missing one or more required operational domain captures';
  END IF;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.worker_get_context(UUID,TEXT)
  FROM PUBLIC,anon,authenticated,service_role;

ALTER FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB)
  RENAME TO worker_stage_decisions_pre_required_domains_v1;

REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions_pre_required_domains_v1(UUID,TEXT,TEXT,JSONB)
  FROM PUBLIC,anon,authenticated,service_role;

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
  v_snapshot_id UUID;
BEGIN
  SELECT s.id INTO v_snapshot_id
  FROM ai_ops.snapshots s
  WHERE s.run_id=p_run_id;

  IF v_snapshot_id IS NULL
     OR NOT ai_ops.snapshot_has_required_domain_captures(v_snapshot_id) THEN
    RAISE EXCEPTION 'decision staging is missing one or more required operational domain captures';
  END IF;

  RETURN ai_ops.worker_stage_decisions_pre_required_domains_v1(
    p_run_id,p_worker_id,p_context_hash,p_decisions
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.field_execution_candidates(DATE,INTEGER) IS
  'Runtime-hardened Field Execution candidate kernel using activities.type_id -> activity_types.code, full pending-set fingerprint and normalized frozen active Work evidence.';
COMMENT ON FUNCTION ai_ops.inventory_candidates(DATE,INTEGER) IS
  'Inventory candidate wrapper preserving deterministic business logic while freezing normalized exact-scope existing_active_work evidence for safe ESCALATE staging.';
COMMENT ON FUNCTION ai_ops.required_operational_domains() IS
  'Single canonical list of operational domains that must be present before worker context or decision staging.';
COMMENT ON FUNCTION ai_ops.snapshot_has_required_domain_captures(UUID) IS
  'Fail-closed required-domain capture completeness check used by worker context and staging.';
COMMENT ON FUNCTION ai_ops.current_field_execution_decision_issues(UUID) IS
  'Field Execution current-state guard including full pending-set fingerprint parity plus the shared bounded-partial actionability gate.';

RESET lock_timeout;
RESET statement_timeout;
