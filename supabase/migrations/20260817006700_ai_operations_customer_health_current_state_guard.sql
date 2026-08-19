-- ============================================================================
-- AI Operations Planner — Customer Health Current-State Guard
--
-- DESIGN-TIME MIGRATION ONLY. Read-only against operational business tables.
--
-- Consequential Customer Health action fails closed when:
--   * the deterministic case is no longer current,
--   * customer/target/routing state drifted,
--   * a newer interaction or Work commitment makes contact duplication likely,
--   * credit feasibility class materially changed,
--   * governed context changed,
--   * proposed Work actors are unavailable,
--   * Customer Health capture was incomplete.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.current_customer_health_decision_issues(
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
  v_customer_id UUID;
  v_target_id UUID;
  v_frozen_rep UUID;
  v_current_rep UUID;
  v_frozen_scope_owner UUID;
  v_current_scope_owner UUID;
  v_frozen_activity_at TIMESTAMPTZ;
  v_current_activity_at TIMESTAMPTZ;
  v_frozen_credit_state TEXT;
  v_current_credit_state TEXT;
  v_now TIMESTAMPTZ:=clock_timestamp();
  v_reasons JSONB:='[]'::JSONB;
BEGIN
  SELECT * INTO v_decision
  FROM ai_ops.decisions
  WHERE id=p_decision_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_array('decision_missing');
  END IF;

  SELECT s.*
  INTO v_snapshot
  FROM ai_ops.snapshots s
  WHERE s.run_id=v_decision.run_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_array('run_snapshot_missing');
  END IF;

  SELECT r.business_date INTO v_business_date
  FROM ai_ops.planner_runs r
  WHERE r.id=v_decision.run_id;

  SELECT * INTO v_sc
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id=v_snapshot.id
    AND sc.case_id=v_decision.case_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_array('frozen_case_evidence_missing');
  END IF;

  IF v_sc.domain<>'customer_health'
     OR v_sc.case_type NOT IN ('reactivation_gap','high_value_reactivation_opportunity') THEN
    RETURN jsonb_build_array('unsupported_customer_health_case_type');
  END IF;

  v_customer_id:=COALESCE(v_sc.entity_id,NULLIF(v_sc.facts->>'customer_id','')::UUID);
  IF v_customer_id IS NULL THEN
    RETURN jsonb_build_array('customer_identity_missing');
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM public.customers c
    WHERE c.id=v_customer_id AND c.is_active=true
  ) THEN
    v_reasons:=v_reasons||jsonb_build_array('customer_missing_or_inactive');
    RETURN v_reasons;
  END IF;

  -- Re-run the exact deterministic candidate kernel, not an approximate copy.
  SELECT * INTO v_current
  FROM ai_ops.customer_health_candidates(v_business_date,2000) c
  WHERE c.case_key=v_sc.case_key
  LIMIT 1;

  IF NOT FOUND THEN
    v_reasons:=v_reasons||jsonb_build_array('customer_health_case_no_longer_current');
  ELSE
    v_frozen_rep:=NULLIF(v_sc.facts->>'assigned_rep_user_id','')::UUID;
    v_current_rep:=v_current.assigned_rep_user_id;

    IF v_current_rep IS DISTINCT FROM v_frozen_rep THEN
      v_reasons:=v_reasons||jsonb_build_array('customer_assigned_rep_changed_after_snapshot');
    END IF;

    v_target_id:=NULLIF(v_sc.facts->>'target_id','')::UUID;
    IF v_target_id IS DISTINCT FROM v_current.target_id THEN
      v_reasons:=v_reasons||jsonb_build_array('reactivation_target_identity_changed_after_snapshot');
    END IF;

    IF v_sc.case_type='reactivation_gap' THEN
      IF COALESCE(v_sc.facts->>'dormancy_days','') IS DISTINCT FROM
         COALESCE(v_current.facts->>'dormancy_days','') THEN
        v_reasons:=v_reasons||jsonb_build_array('reactivation_dormancy_rule_changed_after_snapshot');
      END IF;
      IF COALESCE(v_sc.facts->>'min_reactivation_value','') IS DISTINCT FROM
         COALESCE(v_current.facts->>'min_reactivation_value','') THEN
        v_reasons:=v_reasons||jsonb_build_array('reactivation_minimum_value_changed_after_snapshot');
      END IF;
    END IF;

    IF v_decision.decision_type IN ('CREATE_WORK','ESCALATE') THEN
      IF COALESCE(v_sc.facts->>'last_sale_date','') IS DISTINCT FROM
         COALESCE(v_current.facts->>'last_sale_date','') THEN
        v_reasons:=v_reasons||jsonb_build_array('customer_sales_changed_after_snapshot');
      END IF;

      IF COALESCE(v_sc.facts->>'achieved_reactivation_value','') IS DISTINCT FROM
         COALESCE(v_current.facts->>'achieved_reactivation_value','') THEN
        v_reasons:=v_reasons||jsonb_build_array('reactivation_progress_changed_after_snapshot');
      END IF;

      v_frozen_credit_state:=COALESCE(v_sc.facts->>'credit_state','');
      v_current_credit_state:=COALESCE(v_current.facts->>'credit_state','');
      IF v_current_credit_state IS DISTINCT FROM v_frozen_credit_state THEN
        v_reasons:=v_reasons||jsonb_build_array('customer_credit_feasibility_changed_after_snapshot');
      END IF;

      v_frozen_activity_at:=NULLIF(
        v_sc.facts->'interaction'->>'latest_activity_at',''
      )::TIMESTAMPTZ;
      v_current_activity_at:=NULLIF(
        v_current.facts->'interaction'->>'latest_activity_at',''
      )::TIMESTAMPTZ;

      IF v_current_activity_at IS NOT NULL
         AND (v_frozen_activity_at IS NULL OR v_current_activity_at>v_frozen_activity_at) THEN
        v_reasons:=v_reasons||jsonb_build_array('new_customer_interaction_after_snapshot');
      END IF;

      IF COALESCE((v_current.facts->'interaction'->>'open_visit_commitments')::INTEGER,0)>
         COALESCE((v_sc.facts->'interaction'->>'open_visit_commitments')::INTEGER,0)
         OR COALESCE((v_current.facts->'interaction'->>'open_call_commitments')::INTEGER,0)>
            COALESCE((v_sc.facts->'interaction'->>'open_call_commitments')::INTEGER,0) THEN
        v_reasons:=v_reasons||jsonb_build_array('new_customer_contact_commitment_after_snapshot');
      END IF;
    END IF;
  END IF;

  IF v_decision.decision_type='CREATE_WORK' AND EXISTS(
    SELECT 1
    FROM public.work_links wl
    JOIN public.work_items wi ON wi.id=wl.work_item_id
    WHERE wl.entity_type='customer'
      AND wl.entity_id=v_customer_id
      AND wi.status::TEXT NOT IN ('done','cancelled')
      AND (v_decision.committed_work_item_id IS NULL OR wi.id<>v_decision.committed_work_item_id)
  ) THEN
    v_reasons:=v_reasons||jsonb_build_array('active_customer_work_collision_now');
  END IF;

  IF v_decision.decision_type='ESCALATE' THEN
    IF v_decision.linked_work_item_id IS NULL OR NOT EXISTS(
      SELECT 1
      FROM public.work_links wl
      JOIN public.work_items wi ON wi.id=wl.work_item_id
      WHERE wl.work_item_id=v_decision.linked_work_item_id
        AND wl.entity_type='customer'
        AND wl.entity_id=v_customer_id
        AND wi.status::TEXT NOT IN ('done','cancelled')
    ) THEN
      v_reasons:=v_reasons||jsonb_build_array('linked_customer_work_no_longer_active');
    END IF;
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
    WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='customer_health';

    IF NOT FOUND OR v_capture.capture_status<>'completed' THEN
      v_reasons:=v_reasons||jsonb_build_array('snapshot_not_complete_for_action');
    END IF;

    IF EXISTS(
      SELECT 1
      FROM ai_ops.operational_context oc
      WHERE oc.status='active'
        AND oc.updated_at>v_sc.created_at
        AND oc.valid_from<=v_now
        AND (oc.valid_until IS NULL OR oc.valid_until>v_now)
        AND oc.visibility IN ('management','standard')
        AND (oc.confidence_class<>'ai_inference' OR oc.approved_by_user_id IS NOT NULL)
        AND (
          (oc.subject_type='customer' AND oc.subject_id=v_customer_id)
          OR (
            v_current_rep IS NOT NULL
            AND oc.subject_type='employee'
            AND oc.subject_id=(
              SELECT he.id
              FROM public.hr_employees he
              WHERE he.user_id=v_current_rep
              ORDER BY he.updated_at DESC NULLS LAST,he.id
              LIMIT 1
            )
          )
          OR (
            v_target_id IS NOT NULL
            AND oc.subject_type='target'
            AND oc.subject_id=v_target_id
          )
        )
    ) THEN
      v_reasons:=v_reasons||jsonb_build_array('new_customer_governed_context_after_snapshot');
    END IF;
  END IF;

  v_frozen_scope_owner:=NULLIF(
    v_sc.responsibility_evidence->'target_scope_accountability'->>'user_id',''
  )::UUID;

  IF v_target_id IS NOT NULL THEN
    SELECT CASE t.scope::TEXT
      WHEN 'department' THEN dep.manager_id
      WHEN 'branch' THEN br.manager_id
      WHEN 'individual' THEN individual.user_id
      ELSE NULL
    END
    INTO v_current_scope_owner
    FROM public.targets t
    LEFT JOIN public.hr_departments dep
      ON t.scope::TEXT='department' AND dep.id=t.scope_id
    LEFT JOIN public.branches br
      ON t.scope::TEXT='branch' AND br.id=t.scope_id
    LEFT JOIN public.hr_employees individual
      ON t.scope::TEXT='individual' AND individual.id=t.scope_id
    WHERE t.id=v_target_id;

    IF v_current_scope_owner IS DISTINCT FROM v_frozen_scope_owner THEN
      v_reasons:=v_reasons||jsonb_build_array('reactivation_scope_accountability_changed_after_snapshot');
    END IF;
  END IF;

  RETURN v_reasons;
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.current_customer_health_decision_issues(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

-- Preserve the audited Receivables/Sales canonical guard unchanged and dispatch
-- Customer Health before invoking it, because older dispatchers correctly fail
-- closed on unknown future domains.
ALTER FUNCTION ai_ops.current_decision_issues(UUID)
  RENAME TO current_decision_issues_receivables_sales_v4;

REVOKE ALL ON FUNCTION ai_ops.current_decision_issues_receivables_sales_v4(UUID)
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
  JOIN ai_ops.snapshot_cases sc
    ON sc.snapshot_id=s.id
   AND sc.case_id=d.case_id
  WHERE d.id=p_decision_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_array('frozen_case_evidence_missing');
  END IF;

  IF v_domain='customer_health' THEN
    RETURN ai_ops.current_customer_health_decision_issues(p_decision_id);
  END IF;

  RETURN ai_ops.current_decision_issues_receivables_sales_v4(p_decision_id);
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.current_decision_issues(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.current_customer_health_decision_issues(UUID) IS
  'Read-only Customer Health commit/validation guard rechecking deterministic eligibility, routing, interactions, Work collision, credit feasibility class and governed context.';
COMMENT ON FUNCTION ai_ops.current_decision_issues(UUID) IS
  'Canonical domain-aware current-state guard for Receivables, Sales and Customer Health.';

RESET lock_timeout;
RESET statement_timeout;