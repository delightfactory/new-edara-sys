-- ============================================================================
-- AI Operations Planner — Work Health Current-State Guard
--
-- DESIGN-TIME MIGRATION ONLY. Re-reads source Work immediately before any
-- consequential action. The source Work item is never mutated by this guard.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.current_work_health_decision_issues_pre_bounded_v1(
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
  v_source_work_id UUID;
  v_owner_employee_id UUID;
  v_assignee_employee_id UUID;
  v_now TIMESTAMPTZ:=clock_timestamp();
  v_reasons JSONB:='[]'::JSONB;
BEGIN
  SELECT * INTO v_decision FROM ai_ops.decisions WHERE id=p_decision_id;
  IF NOT FOUND THEN RETURN jsonb_build_array('decision_missing'); END IF;

  SELECT * INTO v_snapshot FROM ai_ops.snapshots WHERE run_id=v_decision.run_id;
  IF NOT FOUND THEN RETURN jsonb_build_array('run_snapshot_missing'); END IF;

  SELECT * INTO v_sc
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id=v_snapshot.id AND sc.case_id=v_decision.case_id;
  IF NOT FOUND THEN RETURN jsonb_build_array('frozen_case_evidence_missing'); END IF;

  IF v_sc.domain<>'work_health' OR v_sc.case_type NOT IN (
    'overdue_work','blocked_work','waiting_follow_up_due','stale_work','missing_next_action'
  ) THEN
    RETURN jsonb_build_array('unsupported_work_health_case_type');
  END IF;

  v_source_work_id:=COALESCE(v_sc.entity_id,NULLIF(v_sc.facts->>'work_item_id','')::UUID);
  v_owner_employee_id:=NULLIF(v_sc.responsibility_evidence->>'owner_employee_id','')::UUID;
  v_assignee_employee_id:=NULLIF(v_sc.responsibility_evidence->>'assignee_employee_id','')::UUID;

  IF v_source_work_id IS NULL THEN
    RETURN jsonb_build_array('source_work_identity_missing');
  END IF;

  IF NOT EXISTS(SELECT 1 FROM public.work_items wi WHERE wi.id=v_source_work_id) THEN
    RETURN jsonb_build_array('source_work_missing');
  END IF;

  -- Re-run the exact current Work Health kernel at commit/review time.
  SELECT * INTO v_current
  FROM ai_ops.work_health_candidates(v_now,2000) c
  WHERE c.case_key=v_sc.case_key
  LIMIT 1;

  IF NOT FOUND THEN
    v_reasons:=v_reasons||jsonb_build_array('work_health_case_no_longer_current');
  ELSE
    IF v_current.source_work_item_id IS DISTINCT FROM v_source_work_id THEN
      v_reasons:=v_reasons||jsonb_build_array('source_work_identity_changed_after_snapshot');
    END IF;

    IF v_current.case_type IS DISTINCT FROM v_sc.case_type THEN
      v_reasons:=v_reasons||jsonb_build_array('work_health_case_type_changed_after_snapshot');
    END IF;

    IF COALESCE(v_current.facts->>'state_version','') IS DISTINCT FROM
       COALESCE(v_sc.facts->>'state_version','') THEN
      v_reasons:=v_reasons||jsonb_build_array('source_work_state_version_changed_after_snapshot');
    END IF;

    IF COALESCE(v_current.facts->>'status','') IS DISTINCT FROM COALESCE(v_sc.facts->>'status','')
       OR COALESCE(v_current.facts->>'priority','') IS DISTINCT FROM COALESCE(v_sc.facts->>'priority','')
       OR COALESCE(v_current.facts->>'due_at','') IS DISTINCT FROM COALESCE(v_sc.facts->>'due_at','')
       OR COALESCE(v_current.facts->>'next_action_text','') IS DISTINCT FROM COALESCE(v_sc.facts->>'next_action_text','')
       OR COALESCE(v_current.facts->>'next_action_at','') IS DISTINCT FROM COALESCE(v_sc.facts->>'next_action_at','')
       OR COALESCE(v_current.facts->>'waiting_since','') IS DISTINCT FROM COALESCE(v_sc.facts->>'waiting_since','')
       OR COALESCE(v_current.facts->>'last_meaningful_activity_at','') IS DISTINCT FROM COALESCE(v_sc.facts->>'last_meaningful_activity_at','') THEN
      v_reasons:=v_reasons||jsonb_build_array('source_work_execution_state_changed_after_snapshot');
    END IF;

    IF COALESCE(v_current.facts->>'is_overdue','') IS DISTINCT FROM COALESCE(v_sc.facts->>'is_overdue','')
       OR COALESCE(v_current.facts->>'is_blocked','') IS DISTINCT FROM COALESCE(v_sc.facts->>'is_blocked','')
       OR COALESCE(v_current.facts->>'is_stale','') IS DISTINCT FROM COALESCE(v_sc.facts->>'is_stale','')
       OR COALESCE(v_current.facts->>'is_escalated','') IS DISTINCT FROM COALESCE(v_sc.facts->>'is_escalated','')
       OR COALESCE(v_current.facts->>'is_follow_up_due','') IS DISTINCT FROM COALESCE(v_sc.facts->>'is_follow_up_due','')
       OR COALESCE(v_current.facts->>'is_missing_next_action','') IS DISTINCT FROM COALESCE(v_sc.facts->>'is_missing_next_action','') THEN
      v_reasons:=v_reasons||jsonb_build_array('work_health_signals_changed_after_snapshot');
    END IF;

    IF COALESCE(v_current.facts->>'settings_state_version','') IS DISTINCT FROM
       COALESCE(v_sc.facts->>'settings_state_version','') THEN
      v_reasons:=v_reasons||jsonb_build_array('work_operational_settings_changed_after_snapshot');
    END IF;

    IF v_current.owner_user_id IS DISTINCT FROM NULLIF(v_sc.responsibility_evidence->>'owner_user_id','')::UUID
       OR v_current.assignee_user_id IS DISTINCT FROM NULLIF(v_sc.responsibility_evidence->>'assignee_user_id','')::UUID
       OR COALESCE(v_current.responsibility_unambiguous,false)
          IS DISTINCT FROM COALESCE((v_sc.responsibility_evidence->>'responsibility_unambiguous')::BOOLEAN,false) THEN
      v_reasons:=v_reasons||jsonb_build_array('work_health_responsibility_changed_after_snapshot');
    END IF;

    IF v_decision.decision_type IN ('CREATE_WORK','ESCALATE') THEN
      IF NOT COALESCE(v_current.responsibility_unambiguous,false)
         OR NOT COALESCE(v_current.owner_active,false) THEN
        v_reasons:=v_reasons||jsonb_build_array('work_health_owner_unavailable');
      END IF;

      -- Recovery Work is deliberately routed to the source accountable owner,
      -- not back to the execution assignee as a duplicate task.
      IF v_decision.recommended_owner_user_id IS DISTINCT FROM v_current.owner_user_id THEN
        v_reasons:=v_reasons||jsonb_build_array('recommended_work_health_owner_not_source_owner');
      END IF;
      IF v_decision.recommended_assignee_user_id IS DISTINCT FROM v_current.owner_user_id THEN
        v_reasons:=v_reasons||jsonb_build_array('recommended_work_health_assignee_not_source_owner');
      END IF;
    END IF;
  END IF;

  IF v_decision.decision_type='CREATE_WORK' AND EXISTS(
    SELECT 1
    FROM public.work_links wl
    JOIN public.work_items recovery ON recovery.id=wl.work_item_id
    WHERE wl.entity_type='work_item' AND wl.entity_id=v_source_work_id
      AND recovery.status::TEXT NOT IN ('done','cancelled')
      AND recovery.metadata->>'ai_domain'='work_health'
      AND (v_decision.committed_work_item_id IS NULL OR recovery.id<>v_decision.committed_work_item_id)
  ) THEN
    v_reasons:=v_reasons||jsonb_build_array('active_work_health_recovery_collision_now');
  END IF;

  IF v_decision.decision_type='ESCALATE' AND (
    v_decision.linked_work_item_id IS DISTINCT FROM v_source_work_id
    OR NOT EXISTS(
      SELECT 1 FROM public.work_items wi
      WHERE wi.id=v_source_work_id AND wi.status::TEXT NOT IN ('draft','done','cancelled')
    )
  ) THEN
    v_reasons:=v_reasons||jsonb_build_array('linked_source_work_no_longer_active');
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
    WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='work_health';
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
          (v_owner_employee_id IS NOT NULL AND oc.subject_type='employee' AND oc.subject_id=v_owner_employee_id)
          OR (v_assignee_employee_id IS NOT NULL AND oc.subject_type='employee' AND oc.subject_id=v_assignee_employee_id)
          OR (
            NULLIF(v_sc.facts->>'branch_id','') IS NOT NULL
            AND oc.subject_type='branch' AND oc.subject_id=(v_sc.facts->>'branch_id')::UUID
          )
          OR (
            NULLIF(v_sc.facts->>'owning_department_id','') IS NOT NULL
            AND oc.subject_type='department' AND oc.subject_id=(v_sc.facts->>'owning_department_id')::UUID
          )
        )
    ) THEN
      v_reasons:=v_reasons||jsonb_build_array('new_work_health_governed_context_after_snapshot');
    END IF;
  END IF;

  RETURN v_reasons;
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.current_work_health_decision_issues_pre_bounded_v1(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.current_work_health_decision_issues(p_decision_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN ai_ops.apply_selected_case_capture_actionability(
    p_decision_id,
    ai_ops.current_work_health_decision_issues_pre_bounded_v1(p_decision_id)
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.current_work_health_decision_issues(UUID)
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
    WHEN 'work_health' THEN RETURN ai_ops.current_work_health_decision_issues(p_decision_id);
    ELSE RETURN jsonb_build_array('unsupported_validation_domain');
  END CASE;
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.current_decision_issues(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.current_work_health_decision_issues(UUID) IS
  'Read-only Work Health current-state guard with source state-version/signal/settings/routing drift, recovery collision and shared bounded-partial actionability.';
COMMENT ON FUNCTION ai_ops.current_decision_issues(UUID) IS
  'Canonical current-state guard for Receivables, Sales, Customer Health, Inventory, Field Execution and Work Health.';

RESET lock_timeout;
RESET statement_timeout;
