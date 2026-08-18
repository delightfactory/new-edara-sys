-- ============================================================================
-- AI Operations Planner — Cross-Domain Feasibility Hardening
--
-- Forward-only hardening. This migration changes AI Operations functions only.
-- It does not ALTER, trigger, index, update or otherwise mutate operational
-- source tables. Existing Work/HR/Visits sources remain authoritative.
--
-- Design rule:
--   * hard blockers are limited to facts that are safe to prove deterministically;
--   * workload/visit/dependency/approval context is exposed as bounded evidence,
--     not converted into an arbitrary productivity/capacity score;
--   * bounded-partial snapshot actionability established by earlier migrations
--     remains untouched.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.current_cross_domain_feasibility_evidence(
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
  v_run ai_ops.planner_runs%ROWTYPE;
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_sc ai_ops.snapshot_cases%ROWTYPE;
  v_assignee_employee_id UUID;
  v_customer_id UUID;
  v_product_id UUID;
  v_source_work_id UUID;
  v_due_local_date DATE;
  v_now TIMESTAMPTZ := clock_timestamp();
  v_today DATE := (clock_timestamp() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_blocking JSONB := '[]'::JSONB;
  v_active_work_count INTEGER := 0;
  v_overdue_work_count INTEGER := 0;
  v_urgent_overdue_work_count INTEGER := 0;
  v_next_work_due_at TIMESTAMPTZ;
  v_today_visit_plan_count INTEGER := 0;
  v_today_pending_visit_count INTEGER := 0;
  v_unresolved_hard_dependency_count INTEGER := 0;
  v_source_work_status TEXT;
  v_related_inventory_cases INTEGER := 0;
  v_related_receivables_cases INTEGER := 0;
  v_related_sales_cases INTEGER := 0;
BEGIN
  SELECT * INTO v_decision
  FROM ai_ops.decisions
  WHERE id = p_decision_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'blocking_issues', jsonb_build_array('decision_missing'),
      'evidence_complete', false
    );
  END IF;

  SELECT * INTO v_run
  FROM ai_ops.planner_runs
  WHERE id = v_decision.run_id;

  SELECT * INTO v_snapshot
  FROM ai_ops.snapshots
  WHERE run_id = v_decision.run_id;

  IF v_run.id IS NULL OR v_snapshot.id IS NULL THEN
    RETURN jsonb_build_object(
      'blocking_issues', jsonb_build_array('decision_snapshot_missing'),
      'evidence_complete', false
    );
  END IF;

  SELECT * INTO v_sc
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id = v_snapshot.id
    AND sc.case_id = v_decision.case_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'blocking_issues', jsonb_build_array('frozen_case_evidence_missing'),
      'evidence_complete', false
    );
  END IF;

  IF v_decision.decision_type NOT IN ('CREATE_WORK','ESCALATE') THEN
    RETURN jsonb_build_object(
      'blocking_issues', '[]'::JSONB,
      'evidence_complete', true,
      'consequential_action', false
    );
  END IF;

  v_due_local_date := COALESCE(
    (v_decision.due_at AT TIME ZONE 'Africa/Cairo')::DATE,
    v_run.business_date
  );

  -- Reuse the deployed Work actor semantics; never invent a parallel active-user rule.
  IF v_decision.recommended_owner_user_id IS NOT NULL
     AND NOT private.work_actor_is_active(v_decision.recommended_owner_user_id) THEN
    v_blocking := v_blocking || jsonb_build_array('recommended_owner_unavailable_now');
  END IF;

  IF v_decision.recommended_assignee_user_id IS NOT NULL
     AND NOT private.work_actor_is_active(v_decision.recommended_assignee_user_id) THEN
    v_blocking := v_blocking || jsonb_build_array('recommended_assignee_unavailable_now');
  END IF;

  -- Resolve the assignee through the current HR source of truth. Only explicit,
  -- current unavailability can become a blocker. Missing attendance never means absence.
  IF v_decision.recommended_assignee_user_id IS NOT NULL THEN
    SELECT he.id
    INTO v_assignee_employee_id
    FROM public.hr_employees he
    WHERE he.user_id = v_decision.recommended_assignee_user_id
    ORDER BY
      CASE WHEN he.status::TEXT = 'active' THEN 0 WHEN he.status::TEXT = 'on_leave' THEN 1 ELSE 2 END,
      he.updated_at DESC NULLS LAST,
      he.id
    LIMIT 1;
  END IF;

  -- A same-day/immediate action cannot be assigned through a known approved leave
  -- or explicit unavailable attendance state. Future-dated leave is evidence for
  -- planning, not a blanket blocker because the Work may be executed before due date.
  IF v_assignee_employee_id IS NOT NULL AND v_due_local_date <= v_today THEN
    IF EXISTS (
      SELECT 1
      FROM public.hr_leave_requests lr
      WHERE lr.employee_id = v_assignee_employee_id
        AND lr.status::TEXT = 'approved'
        AND v_today BETWEEN lr.start_date AND lr.end_date
    ) THEN
      v_blocking := v_blocking || jsonb_build_array('assignee_on_approved_leave_for_immediate_action');
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.hr_attendance_days ad
      WHERE ad.employee_id = v_assignee_employee_id
        AND ad.work_date = v_today
        AND ad.status::TEXT IN (
          'on_leave','absent_authorized','absent_unauthorized','weekly_off','public_holiday'
        )
    ) THEN
      v_blocking := v_blocking || jsonb_build_array('assignee_explicitly_unavailable_for_immediate_action');
    END IF;
  END IF;

  -- Preserve the original frozen HR allocation conflict contract.
  IF v_decision.recommended_assignee_user_id IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM ai_ops.snapshot_cases sc
       WHERE sc.snapshot_id = v_snapshot.id
         AND sc.domain = 'hr_availability'
         AND NULLIF(sc.facts->>'affected_user_id','')::UUID = v_decision.recommended_assignee_user_id
         AND COALESCE(NULLIF(sc.facts->>'availability_date','')::DATE, v_run.business_date) <= v_due_local_date
     ) THEN
    v_blocking := v_blocking || jsonb_build_array('assignee_has_frozen_hr_unavailability_conflict');
  END IF;

  -- Same-run duplicate operational actions must resolve deterministically before
  -- Work is created. Keep the earliest staged decision and reject later duplicates.
  IF v_decision.decision_type = 'CREATE_WORK'
     AND v_sc.entity_id IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM ai_ops.decisions d2
       JOIN ai_ops.snapshot_cases sc2
         ON sc2.snapshot_id = v_snapshot.id
        AND sc2.case_id = d2.case_id
       WHERE d2.run_id = v_decision.run_id
         AND d2.id <> v_decision.id
         AND d2.decision_type = 'CREATE_WORK'
         AND sc2.entity_type = v_sc.entity_type
         AND sc2.entity_id = v_sc.entity_id
         AND (
           d2.created_at < v_decision.created_at
           OR (d2.created_at = v_decision.created_at AND d2.id < v_decision.id)
         )
     ) THEN
    v_blocking := v_blocking || jsonb_build_array('duplicate_same_entity_create_work_in_run');
  END IF;

  IF v_decision.decision_type = 'ESCALATE'
     AND v_decision.linked_work_item_id IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM ai_ops.decisions d2
       WHERE d2.run_id = v_decision.run_id
         AND d2.id <> v_decision.id
         AND d2.decision_type = 'ESCALATE'
         AND d2.linked_work_item_id = v_decision.linked_work_item_id
         AND (
           d2.created_at < v_decision.created_at
           OR (d2.created_at = v_decision.created_at AND d2.id < v_decision.id)
         )
     ) THEN
    v_blocking := v_blocking || jsonb_build_array('duplicate_linked_work_escalation_in_run');
  END IF;

  -- Bounded workload/deadline evidence. It is intentionally advisory: the
  -- engine has no universal safe task-count threshold, so counts never become
  -- an arbitrary rejection rule.
  IF v_decision.recommended_assignee_user_id IS NOT NULL THEN
    SELECT
      COUNT(*)::INTEGER,
      COUNT(*) FILTER (WHERE wi.due_at IS NOT NULL AND wi.due_at < v_now)::INTEGER,
      COUNT(*) FILTER (
        WHERE wi.priority::TEXT IN ('urgent','critical')
          AND wi.due_at IS NOT NULL
          AND wi.due_at < v_now
      )::INTEGER,
      MIN(wi.due_at) FILTER (WHERE wi.due_at IS NOT NULL)
    INTO
      v_active_work_count,
      v_overdue_work_count,
      v_urgent_overdue_work_count,
      v_next_work_due_at
    FROM public.work_items wi
    WHERE wi.current_assignee_user_id = v_decision.recommended_assignee_user_id
      AND wi.status::TEXT IN ('open','in_progress','waiting','pending_approval')
      AND wi.visibility::TEXT = 'standard';
  END IF;

  -- Current visit commitments are also advisory unless an exact temporal
  -- collision can be proven. A plan-day presence alone must never block Work.
  IF v_assignee_employee_id IS NOT NULL THEN
    SELECT
      COUNT(DISTINCT vp.id)::INTEGER,
      COUNT(vpi.id) FILTER (WHERE vpi.status::TEXT = 'pending')::INTEGER
    INTO v_today_visit_plan_count, v_today_pending_visit_count
    FROM public.visit_plans vp
    LEFT JOIN public.visit_plan_items vpi ON vpi.plan_id = vp.id
    WHERE vp.employee_id = v_assignee_employee_id
      AND vp.plan_date = v_today
      AND vp.status::TEXT IN ('confirmed','in_progress');
  END IF;

  -- Linked/source Work dependency and approval state are captured as evidence.
  -- An unresolved dependency can be the reason an escalation is needed, so it
  -- is not blindly turned into a blocker.
  v_source_work_id := COALESCE(
    v_decision.linked_work_item_id,
    CASE WHEN v_sc.entity_type = 'work_item' THEN v_sc.entity_id ELSE NULL END,
    NULLIF(v_sc.facts->>'source_work_item_id','')::UUID
  );

  IF v_source_work_id IS NOT NULL THEN
    SELECT wi.status::TEXT
    INTO v_source_work_status
    FROM public.work_items wi
    WHERE wi.id = v_source_work_id;

    SELECT COUNT(*)::INTEGER
    INTO v_unresolved_hard_dependency_count
    FROM public.work_dependencies wd
    WHERE wd.blocked_work_item_id = v_source_work_id
      AND wd.resolved_at IS NULL
      AND wd.dependency_strength::TEXT = 'hard';
  END IF;

  -- Resolve common entity context without changing any source record.
  v_customer_id := NULLIF(v_sc.facts->>'customer_id','')::UUID;
  IF v_customer_id IS NULL AND v_sc.entity_type = 'customer' THEN
    v_customer_id := v_sc.entity_id;
  ELSIF v_customer_id IS NULL AND v_sc.entity_type = 'sales_order' THEN
    SELECT so.customer_id INTO v_customer_id
    FROM public.sales_orders so WHERE so.id = v_sc.entity_id;
  END IF;

  v_product_id := NULLIF(v_sc.facts->>'product_id','')::UUID;
  IF v_product_id IS NULL AND v_sc.entity_type = 'product' THEN
    v_product_id := v_sc.entity_id;
  END IF;

  IF v_product_id IS NOT NULL THEN
    SELECT COUNT(*)::INTEGER INTO v_related_inventory_cases
    FROM ai_ops.snapshot_cases x
    WHERE x.snapshot_id = v_snapshot.id
      AND x.domain = 'inventory'
      AND NULLIF(x.facts->>'product_id','')::UUID = v_product_id;

    SELECT COUNT(*)::INTEGER INTO v_related_sales_cases
    FROM ai_ops.snapshot_cases x
    WHERE x.snapshot_id = v_snapshot.id
      AND x.domain = 'sales'
      AND NULLIF(x.facts->>'product_id','')::UUID = v_product_id;
  END IF;

  IF v_customer_id IS NOT NULL THEN
    SELECT COUNT(*)::INTEGER INTO v_related_receivables_cases
    FROM ai_ops.snapshot_cases x
    WHERE x.snapshot_id = v_snapshot.id
      AND x.domain = 'receivables'
      AND NULLIF(x.facts->>'customer_id','')::UUID = v_customer_id;
  END IF;

  RETURN jsonb_build_object(
    'blocking_issues', v_blocking,
    'evidence_complete', true,
    'consequential_action', true,
    'business_date', v_run.business_date,
    'due_local_date', v_due_local_date,
    'assignee_employee_id', v_assignee_employee_id,
    'workload', jsonb_build_object(
      'active_standard_work_count', v_active_work_count,
      'overdue_work_count', v_overdue_work_count,
      'urgent_or_critical_overdue_work_count', v_urgent_overdue_work_count,
      'next_due_at', v_next_work_due_at,
      'arbitrary_capacity_threshold_applied', false
    ),
    'field_commitments', jsonb_build_object(
      'today_active_visit_plan_count', v_today_visit_plan_count,
      'today_pending_visit_count', v_today_pending_visit_count,
      'plan_presence_is_automatic_blocker', false
    ),
    'dependency_approval', jsonb_build_object(
      'source_work_item_id', v_source_work_id,
      'source_work_status', v_source_work_status,
      'source_work_pending_approval', v_source_work_status = 'pending_approval',
      'unresolved_hard_dependency_count', v_unresolved_hard_dependency_count,
      'dependency_presence_is_automatic_blocker', false
    ),
    'related_frozen_cases', jsonb_build_object(
      'inventory_product_cases', v_related_inventory_cases,
      'receivables_customer_cases', v_related_receivables_cases,
      'sales_product_target_cases', v_related_sales_cases
    ),
    'safety_contract', jsonb_build_object(
      'missing_attendance_never_implies_absence', true,
      'source_mutation_performed', false,
      'productivity_score_used', false,
      'soft_feasibility_context_is_advisory', true
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.current_cross_domain_feasibility_evidence(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION ai_ops.current_cross_domain_feasibility_issues(
  p_decision_id UUID
)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(
    ai_ops.current_cross_domain_feasibility_evidence(p_decision_id)->'blocking_issues',
    jsonb_build_array('cross_domain_feasibility_evidence_missing')
  );
$$;

REVOKE ALL ON FUNCTION ai_ops.current_cross_domain_feasibility_issues(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION ai_ops.current_cross_domain_feasibility_evidence(UUID) IS
  'Read-only cross-domain feasibility evidence: explicit availability blockers plus bounded Work workload/deadline, visit, dependency/approval and related frozen-domain context. No arbitrary capacity score and no source mutation.';

COMMENT ON FUNCTION ai_ops.current_cross_domain_feasibility_issues(UUID) IS
  'Hard deterministic feasibility blockers only. The canonical current_decision_issues wrapper continues to append these blockers to each domain current-state guard.';

RESET lock_timeout;
RESET statement_timeout;
