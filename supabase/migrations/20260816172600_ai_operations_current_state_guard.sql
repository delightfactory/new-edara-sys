-- ============================================================================
-- AI Operations Planner — Reusable Current-State Decision Guard
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply until explicitly reviewed/approved.
-- Depends on: 20260816172500_ai_operations_decision_validation.sql
--
-- Centralizes the same fail-closed current-reality checks for:
--   * staged decision validation
--   * future commit-time Work bridge revalidation
--
-- One source of safety truth prevents drift between validation and execution.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.current_decision_issues(p_decision_id UUID)
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
  v_domain_capture ai_ops.snapshot_domain_captures%ROWTYPE;
  v_sc ai_ops.snapshot_cases%ROWTYPE;
  v_now TIMESTAMPTZ := clock_timestamp();
  v_business_date DATE := (clock_timestamp() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_reasons JSONB := '[]'::JSONB;
  v_current_order RECORD;
  v_snapshot_remaining NUMERIC;
  v_snapshot_rep UUID;
  v_snapshot_order_rep UUID;
  v_snapshot_override_by UUID;
  v_active_collision UUID;
BEGIN
  SELECT * INTO v_decision
  FROM ai_ops.decisions
  WHERE id = p_decision_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_array('decision_missing');
  END IF;

  SELECT * INTO v_run FROM ai_ops.planner_runs WHERE id = v_decision.run_id;
  IF NOT FOUND THEN RETURN jsonb_build_array('decision_run_missing'); END IF;

  SELECT * INTO v_snapshot FROM ai_ops.snapshots WHERE run_id = v_run.id;
  IF NOT FOUND THEN RETURN jsonb_build_array('run_snapshot_missing'); END IF;

  SELECT * INTO v_domain_capture
  FROM ai_ops.snapshot_domain_captures dc
  WHERE dc.snapshot_id = v_snapshot.id AND dc.domain = 'receivables';
  IF NOT FOUND THEN RETURN jsonb_build_array('receivables_capture_missing'); END IF;

  SELECT * INTO v_sc
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id = v_snapshot.id AND sc.case_id = v_decision.case_id;
  IF NOT FOUND THEN RETURN jsonb_build_array('frozen_case_evidence_missing'); END IF;

  IF v_sc.domain <> 'receivables' OR v_sc.case_type <> 'overdue_invoice' THEN
    RETURN jsonb_build_array('unsupported_validation_domain');
  END IF;

  SELECT
    so.id,
    so.customer_id,
    so.rep_id,
    so.status::TEXT AS status,
    so.payment_terms,
    so.delivered_at,
    so.due_date,
    COALESCE(so.credit_override, false) AS credit_override,
    so.credit_override_by,
    c.assigned_rep_id,
    GREATEST(
      0::NUMERIC,
      COALESCE(so.total_amount, 0)
        - COALESCE(so.paid_amount, 0)
        - COALESCE(so.returned_amount, 0)
    )::NUMERIC AS remaining_amount
  INTO v_current_order
  FROM public.sales_orders so
  JOIN public.customers c ON c.id = so.customer_id
  WHERE so.id = v_sc.entity_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_array('sales_order_missing');
  END IF;

  v_snapshot_remaining := NULLIF(v_sc.facts->>'remaining_amount', '')::NUMERIC;
  v_snapshot_rep := NULLIF(v_sc.responsibility_evidence->'current_customer_rep'->>'user_id', '')::UUID;
  v_snapshot_order_rep := NULLIF(v_sc.responsibility_evidence->'order_rep'->>'user_id', '')::UUID;
  v_snapshot_override_by := NULLIF(v_sc.responsibility_evidence->'credit_override'->>'user_id', '')::UUID;

  IF v_current_order.status NOT IN ('delivered','partially_delivered')
     OR v_current_order.payment_terms NOT IN ('credit','mixed')
     OR v_current_order.delivered_at IS NULL
     OR v_current_order.due_date IS NULL
     OR v_current_order.due_date >= v_business_date
     OR v_current_order.remaining_amount <= 0 THEN
    v_reasons := v_reasons || jsonb_build_array('invoice_no_longer_overdue_candidate');
  END IF;

  IF v_current_order.due_date::TEXT IS DISTINCT FROM v_sc.facts->>'due_date' THEN
    v_reasons := v_reasons || jsonb_build_array('due_date_changed_after_snapshot');
  END IF;

  IF v_snapshot_remaining IS NULL
     OR abs(v_current_order.remaining_amount - v_snapshot_remaining) > 0.01 THEN
    v_reasons := v_reasons || jsonb_build_array('remaining_balance_changed_after_snapshot');
  END IF;

  IF v_current_order.assigned_rep_id IS DISTINCT FROM v_snapshot_rep THEN
    v_reasons := v_reasons || jsonb_build_array('customer_assignment_changed_after_snapshot');
  END IF;

  IF v_current_order.rep_id IS DISTINCT FROM v_snapshot_order_rep THEN
    v_reasons := v_reasons || jsonb_build_array('order_rep_changed_after_snapshot');
  END IF;

  IF v_current_order.credit_override IS DISTINCT FROM COALESCE((v_sc.facts->>'credit_override')::BOOLEAN, false)
     OR v_current_order.credit_override_by IS DISTINCT FROM v_snapshot_override_by THEN
    v_reasons := v_reasons || jsonb_build_array('credit_override_changed_after_snapshot');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.sales_order_due_date_history h
    WHERE h.order_id = v_current_order.id AND h.created_at > v_sc.created_at
  ) THEN
    v_reasons := v_reasons || jsonb_build_array('due_date_history_changed_after_snapshot');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.customer_credit_history h
    WHERE h.customer_id = v_current_order.customer_id AND h.created_at > v_sc.created_at
  ) THEN
    v_reasons := v_reasons || jsonb_build_array('customer_credit_policy_changed_after_snapshot');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM ai_ops.operational_context oc
    WHERE oc.status = 'active'
      AND oc.updated_at > v_sc.created_at
      AND oc.visibility IN ('management','standard')
      AND (oc.confidence_class <> 'ai_inference' OR oc.approved_by_user_id IS NOT NULL)
      AND (oc.valid_until IS NULL OR oc.valid_until > v_now)
      AND (
        (oc.subject_type = 'sales_order' AND oc.subject_id = v_current_order.id)
        OR (oc.subject_type = 'customer' AND oc.subject_id = v_current_order.customer_id)
      )
  ) THEN
    v_reasons := v_reasons || jsonb_build_array('new_governed_context_after_snapshot');
  END IF;

  IF v_decision.decision_type = 'CREATE_WORK' THEN
    IF v_decision.recommended_owner_user_id IS NULL
       OR NOT private.work_actor_is_active(v_decision.recommended_owner_user_id) THEN
      v_reasons := v_reasons || jsonb_build_array('recommended_owner_unavailable');
    END IF;

    IF v_decision.recommended_assignee_user_id IS NOT NULL
       AND NOT private.work_actor_is_active(v_decision.recommended_assignee_user_id) THEN
      v_reasons := v_reasons || jsonb_build_array('recommended_assignee_unavailable');
    END IF;

    SELECT wi.id INTO v_active_collision
    FROM public.work_links wl
    JOIN public.work_items wi ON wi.id = wl.work_item_id
    WHERE wl.entity_type = 'sales_order'
      AND wl.entity_id = v_current_order.id
      AND wi.status NOT IN ('done'::public.work_item_status, 'cancelled'::public.work_item_status)
    ORDER BY wi.updated_at DESC, wi.id
    LIMIT 1;

    IF v_active_collision IS NOT NULL THEN
      v_reasons := v_reasons || jsonb_build_array('active_work_collision_now');
    END IF;
  ELSIF v_decision.decision_type = 'ESCALATE' THEN
    IF v_decision.linked_work_item_id IS NULL THEN
      v_reasons := v_reasons || jsonb_build_array('escalation_has_no_linked_work');
    ELSIF NOT EXISTS (
      SELECT 1 FROM public.work_items wi
      WHERE wi.id = v_decision.linked_work_item_id
        AND wi.status NOT IN ('done'::public.work_item_status, 'cancelled'::public.work_item_status)
    ) THEN
      v_reasons := v_reasons || jsonb_build_array('linked_work_no_longer_active');
    END IF;
  END IF;

  IF v_decision.decision_type IN ('CREATE_WORK','ESCALATE')
     AND (v_snapshot.snapshot_status <> 'ready' OR v_domain_capture.capture_status <> 'completed') THEN
    v_reasons := v_reasons || jsonb_build_array('snapshot_not_complete_for_action');
  END IF;

  RETURN v_reasons;
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.current_decision_issues(UUID) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION ai_ops.validate_staged_run(p_run_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_run ai_ops.planner_runs%ROWTYPE;
  v_decision ai_ops.decisions%ROWTYPE;
  v_now TIMESTAMPTZ := clock_timestamp();
  v_business_date DATE := (clock_timestamp() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_reasons JSONB;
  v_validated INTEGER := 0;
  v_rejected INTEGER := 0;
  v_skipped INTEGER := 0;
BEGIN
  SELECT * INTO v_run
  FROM ai_ops.planner_runs
  WHERE id = p_run_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'planner run not found'; END IF;
  IF v_run.status <> 'staged' THEN
    RAISE EXCEPTION 'only staged runs can be validated: %', v_run.status;
  END IF;

  FOR v_decision IN
    SELECT d.* FROM ai_ops.decisions d
    WHERE d.run_id = p_run_id
    ORDER BY d.created_at ASC, d.id ASC
    FOR UPDATE
  LOOP
    IF v_decision.validation_state <> 'pending' THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    v_reasons := ai_ops.current_decision_issues(v_decision.id);

    IF jsonb_array_length(v_reasons) = 0 THEN
      UPDATE ai_ops.decisions
      SET
        validation_state = 'validated',
        validation_detail = validation_detail || jsonb_build_object(
          'validated_against_current_state', true,
          'validation_business_date', v_business_date,
          'validation_codes', '[]'::JSONB,
          'requires_human_review', true,
          'stage_only', true
        ),
        validated_at = v_now,
        validated_by_user_id = NULL
      WHERE id = v_decision.id;
      v_validated := v_validated + 1;
    ELSE
      UPDATE ai_ops.decisions
      SET
        validation_state = 'rejected',
        validation_detail = validation_detail || jsonb_build_object(
          'validated_against_current_state', true,
          'validation_business_date', v_business_date,
          'validation_codes', v_reasons,
          'requires_human_review', true,
          'stage_only', true,
          'rejected_as_stale_or_unsafe', true
        ),
        validated_at = v_now,
        validated_by_user_id = NULL
      WHERE id = v_decision.id;
      v_rejected := v_rejected + 1;
    END IF;
  END LOOP;

  UPDATE ai_ops.planner_runs
  SET
    checkpoint = 'decisions_validated',
    result_summary = result_summary || jsonb_build_object(
      'validated_decisions', v_validated,
      'rejected_decisions', v_rejected,
      'validation_skipped_existing', v_skipped,
      'validation_business_date', v_business_date,
      'validation_completed_at', v_now
    ),
    updated_at = v_now
  WHERE id = p_run_id;

  RETURN jsonb_build_object(
    'run_id', p_run_id,
    'validated', v_validated,
    'rejected', v_rejected,
    'skipped_existing', v_skipped,
    'business_date', v_business_date,
    'execution_performed', false
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.validate_staged_run(UUID) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION ai_ops.current_decision_issues(UUID) IS
  'Single source of current-state safety issues for staged/commit-time AI decision checking. Read-only and fail-closed.';

COMMENT ON FUNCTION ai_ops.validate_staged_run(UUID) IS
  'Validates staged decisions through current_decision_issues(); mutates ai_ops validation state only and performs no operational action.';

RESET lock_timeout;
RESET statement_timeout;
