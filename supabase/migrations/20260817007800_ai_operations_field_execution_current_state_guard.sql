-- ============================================================================
-- AI Operations Planner — Field Execution Current-State Guard
--
-- DESIGN-TIME MIGRATION ONLY. Field sources are re-read but never mutated.
-- Consequential action fails closed when the overdue visit day is no longer
-- current, execution/accountability changed, plan evidence drifted, Work now
-- collides, actors are unavailable, governed context changed, or frozen evidence
-- is not actionable under the shared bounded-partial contract.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.current_field_execution_decision_issues_pre_bounded_v1(
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
  v_capture ai_ops.snapshot_domain_captures%ROWTYPE;
  v_current RECORD;
  v_business_date DATE;
  v_visit_plan_id UUID;
  v_rep_employee_id UUID;
  v_frozen_rep_user_id UUID;
  v_frozen_manager_user_id UUID;
  v_now TIMESTAMPTZ:=clock_timestamp();
  v_reasons JSONB:='[]'::JSONB;
BEGIN
  SELECT * INTO v_decision FROM ai_ops.decisions WHERE id=p_decision_id;
  IF NOT FOUND THEN RETURN jsonb_build_array('decision_missing'); END IF;

  SELECT * INTO v_snapshot FROM ai_ops.snapshots WHERE run_id=v_decision.run_id;
  IF NOT FOUND THEN RETURN jsonb_build_array('run_snapshot_missing'); END IF;

  SELECT r.business_date INTO v_business_date
  FROM ai_ops.planner_runs r WHERE r.id=v_decision.run_id;

  SELECT * INTO v_sc
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id=v_snapshot.id AND sc.case_id=v_decision.case_id;
  IF NOT FOUND THEN RETURN jsonb_build_array('frozen_case_evidence_missing'); END IF;

  IF v_sc.domain<>'field_execution' OR v_sc.case_type<>'overdue_visit_day' THEN
    RETURN jsonb_build_array('unsupported_field_execution_case_type');
  END IF;

  v_visit_plan_id:=COALESCE(v_sc.entity_id,NULLIF(v_sc.facts->>'visit_plan_id','')::UUID);
  v_rep_employee_id:=NULLIF(v_sc.responsibility_evidence->>'rep_employee_id','')::UUID;
  v_frozen_rep_user_id:=NULLIF(v_sc.responsibility_evidence->>'rep_user_id','')::UUID;
  v_frozen_manager_user_id:=NULLIF(v_sc.responsibility_evidence->>'manager_user_id','')::UUID;

  IF v_visit_plan_id IS NULL THEN
    RETURN jsonb_build_array('visit_plan_identity_missing');
  END IF;

  IF NOT EXISTS(SELECT 1 FROM public.visit_plans vp WHERE vp.id=v_visit_plan_id) THEN
    RETURN jsonb_build_array('visit_plan_missing');
  END IF;

  -- Re-run the exact deterministic kernel against current visit-plan state.
  SELECT * INTO v_current
  FROM ai_ops.field_execution_candidates(v_business_date,2000) c
  WHERE c.case_key=v_sc.case_key
  LIMIT 1;

  IF NOT FOUND THEN
    v_reasons:=v_reasons||jsonb_build_array('field_execution_case_no_longer_current');
  ELSE
    IF v_current.visit_plan_id IS DISTINCT FROM v_visit_plan_id
       OR v_current.rep_employee_id IS DISTINCT FROM v_rep_employee_id THEN
      v_reasons:=v_reasons||jsonb_build_array('visit_plan_or_rep_identity_changed_after_snapshot');
    END IF;

    IF v_current.rep_user_id IS DISTINCT FROM v_frozen_rep_user_id
       OR v_current.manager_user_id IS DISTINCT FROM v_frozen_manager_user_id
       OR COALESCE(v_current.responsibility_unambiguous,false)
          IS DISTINCT FROM COALESCE((v_sc.responsibility_evidence->>'responsibility_unambiguous')::BOOLEAN,false) THEN
      v_reasons:=v_reasons||jsonb_build_array('field_execution_responsibility_changed_after_snapshot');
    END IF;

    IF v_decision.decision_type IN ('CREATE_WORK','ESCALATE') THEN
      IF NOT COALESCE(v_current.responsibility_unambiguous,false)
         OR NOT COALESCE(v_current.rep_active,false)
         OR NOT COALESCE(v_current.manager_active,false) THEN
        v_reasons:=v_reasons||jsonb_build_array('field_execution_responsibility_ambiguous_or_unavailable');
      END IF;

      IF v_decision.recommended_assignee_user_id IS DISTINCT FROM v_current.rep_user_id THEN
        v_reasons:=v_reasons||jsonb_build_array('recommended_field_assignee_not_plan_rep');
      END IF;
      IF v_decision.recommended_owner_user_id IS DISTINCT FROM v_current.manager_user_id THEN
        v_reasons:=v_reasons||jsonb_build_array('recommended_field_owner_not_direct_manager');
      END IF;

      IF COALESCE(v_sc.facts->>'plan_date','') IS DISTINCT FROM COALESCE(v_current.facts->>'plan_date','')
         OR COALESCE(v_sc.facts->>'plan_status','') IS DISTINCT FROM COALESCE(v_current.facts->>'plan_status','') THEN
        v_reasons:=v_reasons||jsonb_build_array('visit_plan_state_changed_after_snapshot');
      END IF;

      IF COALESCE(v_sc.facts->>'pending_count','') IS DISTINCT FROM COALESCE(v_current.facts->>'pending_count','')
         OR COALESCE(v_sc.facts->>'completed_count','') IS DISTINCT FROM COALESCE(v_current.facts->>'completed_count','')
         OR COALESCE(v_sc.facts->>'skipped_count','') IS DISTINCT FROM COALESCE(v_current.facts->>'skipped_count','')
         OR COALESCE(v_sc.facts->>'missed_count','') IS DISTINCT FROM COALESCE(v_current.facts->>'missed_count','')
         OR COALESCE(v_sc.facts->>'rescheduled_count','') IS DISTINCT FROM COALESCE(v_current.facts->>'rescheduled_count','') THEN
        v_reasons:=v_reasons||jsonb_build_array('visit_day_commitment_counts_changed_after_snapshot');
      END IF;

      IF COALESCE(v_sc.facts->'pending_items','[]'::JSONB)
         IS DISTINCT FROM COALESCE(v_current.facts->'pending_items','[]'::JSONB) THEN
        v_reasons:=v_reasons||jsonb_build_array('visit_day_pending_commitments_changed_after_snapshot');
      END IF;

      IF COALESCE(v_sc.facts->>'latest_linked_activity_at','') IS DISTINCT FROM
         COALESCE(v_current.facts->>'latest_linked_activity_at','') THEN
        v_reasons:=v_reasons||jsonb_build_array('new_visit_day_activity_after_snapshot');
      END IF;
    END IF;
  END IF;

  IF v_decision.decision_type='CREATE_WORK' AND EXISTS(
    SELECT 1
    FROM public.work_links wl
    JOIN public.work_items wi ON wi.id=wl.work_item_id
    WHERE wl.entity_type='visit_plan' AND wl.entity_id=v_visit_plan_id
      AND wi.status::TEXT NOT IN ('done','cancelled')
      AND (v_decision.committed_work_item_id IS NULL OR wi.id<>v_decision.committed_work_item_id)
  ) THEN
    v_reasons:=v_reasons||jsonb_build_array('active_visit_plan_work_collision_now');
  END IF;

  IF v_decision.decision_type='ESCALATE' AND (
    v_decision.linked_work_item_id IS NULL OR NOT EXISTS(
      SELECT 1
      FROM public.work_links wl
      JOIN public.work_items wi ON wi.id=wl.work_item_id
      WHERE wi.id=v_decision.linked_work_item_id
        AND wi.status::TEXT NOT IN ('done','cancelled')
        AND wl.entity_type='visit_plan' AND wl.entity_id=v_visit_plan_id
    )
  ) THEN
    v_reasons:=v_reasons||jsonb_build_array('linked_visit_plan_work_no_longer_active');
  END IF;

  IF v_decision.decision_type IN ('CREATE_WORK','ESCALATE') THEN
    IF v_decision.recommended_owner_user_id IS NULL
       OR NOT private.work_actor_is_active(v_decision.recommended_owner_user_id) THEN
      v_reasons:=v_reasons||jsonb_build_array('recommended_owner_unavailable');
    END IF;
    IF v_decision.recommended_assignee_user_id IS NULL
       OR NOT private.work_actor_is_active(v_decision.recommended_assignee_user_id) THEN
      v_reasons:=v_reasons||jsonb_build_array('recommended_assignee_unavailable');
    END IF;

    SELECT * INTO v_capture
    FROM ai_ops.snapshot_domain_captures dc
    WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='field_execution';
    IF NOT FOUND OR v_capture.capture_status<>'completed' THEN
      v_reasons:=v_reasons||jsonb_build_array('snapshot_not_complete_for_action');
    END IF;

    IF EXISTS(
      SELECT 1 FROM ai_ops.operational_context oc
      WHERE oc.status='active' AND oc.updated_at>v_sc.created_at
        AND oc.valid_from<=v_now AND (oc.valid_until IS NULL OR oc.valid_until>v_now)
        AND oc.visibility IN ('management','standard')
        AND (oc.confidence_class<>'ai_inference' OR oc.approved_by_user_id IS NOT NULL)
        AND (
          (v_rep_employee_id IS NOT NULL AND oc.subject_type='employee' AND oc.subject_id=v_rep_employee_id)
          OR (
            NULLIF(v_sc.facts->>'branch_id','') IS NOT NULL
            AND oc.subject_type='branch' AND oc.subject_id=(v_sc.facts->>'branch_id')::UUID
          )
        )
    ) THEN
      v_reasons:=v_reasons||jsonb_build_array('new_field_execution_governed_context_after_snapshot');
    END IF;
  END IF;

  RETURN v_reasons;
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.current_field_execution_decision_issues_pre_bounded_v1(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.current_field_execution_decision_issues(p_decision_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN ai_ops.apply_selected_case_capture_actionability(
    p_decision_id,
    ai_ops.current_field_execution_decision_issues_pre_bounded_v1(p_decision_id)
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.current_field_execution_decision_issues(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

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
  JOIN ai_ops.snapshots s ON s.run_id=d.run_id
  JOIN ai_ops.snapshot_cases sc ON sc.snapshot_id=s.id AND sc.case_id=d.case_id
  WHERE d.id=p_decision_id;

  IF NOT FOUND THEN RETURN jsonb_build_array('frozen_case_evidence_missing'); END IF;

  CASE v_domain
    WHEN 'receivables' THEN RETURN ai_ops.current_decision_issues_credit_v1(p_decision_id);
    WHEN 'sales' THEN RETURN ai_ops.current_sales_target_decision_issues(p_decision_id);
    WHEN 'customer_health' THEN RETURN ai_ops.current_customer_health_decision_issues(p_decision_id);
    WHEN 'inventory' THEN RETURN ai_ops.current_inventory_decision_issues(p_decision_id);
    WHEN 'field_execution' THEN RETURN ai_ops.current_field_execution_decision_issues(p_decision_id);
    ELSE RETURN jsonb_build_array('unsupported_validation_domain');
  END CASE;
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.current_decision_issues(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.current_field_execution_decision_issues(UUID) IS
  'Read-only Field Execution current-state guard with exact candidate recheck, rep/manager routing, commitment drift, Work collision and shared bounded-partial actionability.';
COMMENT ON FUNCTION ai_ops.current_decision_issues(UUID) IS
  'Canonical current-state guard for Receivables, Sales, Customer Health, Inventory and Field Execution.';

RESET lock_timeout;
RESET statement_timeout;
