-- ============================================================================
-- AI Operations Planner — Inventory Current-State Guard
--
-- DESIGN-TIME MIGRATION ONLY. Inventory sources are re-read but never mutated.
-- Consequential action fails closed when the shortage/transfer is no longer
-- current, responsibility is ambiguous, supply evidence drifted, Work collides,
-- actors are unavailable, governed context changed, or frozen evidence is not
-- actionable under the shared bounded-partial contract.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.current_inventory_decision_issues_pre_bounded_v1(
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
  v_warehouse_id UUID;
  v_product_id UUID;
  v_transfer_id UUID;
  v_current_responsible UUID;
  v_frozen_responsible UUID;
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

  IF v_sc.domain<>'inventory' OR v_sc.case_type NOT IN ('local_shortage','stalled_transfer') THEN
    RETURN jsonb_build_array('unsupported_inventory_case_type');
  END IF;

  v_warehouse_id:=NULLIF(v_sc.facts->>'warehouse_id','')::UUID;
  v_product_id:=NULLIF(v_sc.facts->>'product_id','')::UUID;
  v_transfer_id:=NULLIF(v_sc.facts->>'transfer_id','')::UUID;
  v_frozen_responsible:=NULLIF(v_sc.responsibility_evidence->>'responsible_user_id','')::UUID;

  IF v_warehouse_id IS NULL THEN
    RETURN jsonb_build_array('inventory_warehouse_identity_missing');
  END IF;

  IF NOT EXISTS(SELECT 1 FROM public.warehouses w WHERE w.id=v_warehouse_id AND w.is_active=true) THEN
    v_reasons:=v_reasons||jsonb_build_array('inventory_warehouse_missing_or_inactive');
    RETURN v_reasons;
  END IF;

  IF v_sc.case_type='local_shortage' AND (
    v_product_id IS NULL OR NOT EXISTS(
      SELECT 1 FROM public.products p WHERE p.id=v_product_id AND p.is_active=true
    )
  ) THEN
    v_reasons:=v_reasons||jsonb_build_array('inventory_product_missing_or_inactive');
    RETURN v_reasons;
  END IF;

  IF v_sc.case_type='stalled_transfer' AND v_transfer_id IS NULL THEN
    RETURN jsonb_build_array('inventory_transfer_identity_missing');
  END IF;

  -- Re-run the exact deterministic kernel against current inventory state.
  SELECT * INTO v_current
  FROM ai_ops.inventory_candidates(v_business_date,2000) c
  WHERE c.case_key=v_sc.case_key
  LIMIT 1;

  IF NOT FOUND THEN
    v_reasons:=v_reasons||jsonb_build_array('inventory_case_no_longer_current');
  ELSE
    v_current_responsible:=v_current.responsible_user_id;

    IF v_current_responsible IS DISTINCT FROM v_frozen_responsible
       OR COALESCE(v_current.responsibility_unambiguous,false)
          IS DISTINCT FROM COALESCE((v_sc.responsibility_evidence->>'responsibility_unambiguous')::BOOLEAN,false) THEN
      v_reasons:=v_reasons||jsonb_build_array('inventory_responsibility_changed_after_snapshot');
    END IF;

    IF v_decision.decision_type IN ('CREATE_WORK','ESCALATE') THEN
      IF NOT COALESCE(v_current.responsibility_unambiguous,false)
         OR v_current_responsible IS NULL
         OR NOT COALESCE(v_current.responsible_user_active,false) THEN
        v_reasons:=v_reasons||jsonb_build_array('inventory_responsibility_ambiguous_or_unavailable');
      END IF;

      IF v_decision.recommended_assignee_user_id IS DISTINCT FROM v_current_responsible THEN
        v_reasons:=v_reasons||jsonb_build_array('recommended_inventory_assignee_not_responsible_manager');
      END IF;

      IF v_sc.case_type='local_shortage' THEN
        IF COALESCE(v_sc.facts->>'available_quantity','') IS DISTINCT FROM COALESCE(v_current.facts->>'available_quantity','')
           OR COALESCE(v_sc.facts->>'outbound_qty_30d','') IS DISTINCT FROM COALESCE(v_current.facts->>'outbound_qty_30d','')
           OR COALESCE(v_sc.facts->>'coverage_days','') IS DISTINCT FROM COALESCE(v_current.facts->>'coverage_days','') THEN
          v_reasons:=v_reasons||jsonb_build_array('inventory_shortage_balance_or_demand_changed_after_snapshot');
        END IF;

        IF COALESCE(v_sc.facts->>'alternate_available_quantity','') IS DISTINCT FROM COALESCE(v_current.facts->>'alternate_available_quantity','')
           OR COALESCE(v_sc.facts->>'incoming_transfer_count','') IS DISTINCT FROM COALESCE(v_current.facts->>'incoming_transfer_count','')
           OR COALESCE(v_sc.facts->>'incoming_transfer_remaining_qty','') IS DISTINCT FROM COALESCE(v_current.facts->>'incoming_transfer_remaining_qty','') THEN
          v_reasons:=v_reasons||jsonb_build_array('inventory_supply_feasibility_changed_after_snapshot');
        END IF;
      ELSE
        IF COALESCE(v_sc.facts->>'status','') IS DISTINCT FROM COALESCE(v_current.facts->>'status','')
           OR COALESCE(v_sc.facts->>'transfer_quantity','') IS DISTINCT FROM COALESCE(v_current.facts->>'transfer_quantity','')
           OR COALESCE(v_sc.facts->>'received_quantity','') IS DISTINCT FROM COALESCE(v_current.facts->>'received_quantity','') THEN
          v_reasons:=v_reasons||jsonb_build_array('inventory_transfer_state_changed_after_snapshot');
        END IF;
      END IF;
    END IF;
  END IF;

  IF v_decision.decision_type='CREATE_WORK' THEN
    IF v_sc.case_type='local_shortage' AND EXISTS(
      SELECT 1
      FROM public.work_items wi
      WHERE wi.status::TEXT NOT IN ('done','cancelled')
        AND (v_decision.committed_work_item_id IS NULL OR wi.id<>v_decision.committed_work_item_id)
        AND EXISTS(
          SELECT 1 FROM public.work_links wp
          WHERE wp.work_item_id=wi.id AND wp.entity_type='product' AND wp.entity_id=v_product_id
        )
        AND EXISTS(
          SELECT 1 FROM public.work_links ww
          WHERE ww.work_item_id=wi.id AND ww.entity_type='warehouse' AND ww.entity_id=v_warehouse_id
        )
    ) THEN
      v_reasons:=v_reasons||jsonb_build_array('active_inventory_shortage_work_collision_now');
    END IF;

    IF v_sc.case_type='stalled_transfer' AND EXISTS(
      SELECT 1
      FROM public.work_links wl
      JOIN public.work_items wi ON wi.id=wl.work_item_id
      WHERE wl.entity_type='stock_transfer' AND wl.entity_id=v_transfer_id
        AND wi.status::TEXT NOT IN ('done','cancelled')
        AND (v_decision.committed_work_item_id IS NULL OR wi.id<>v_decision.committed_work_item_id)
    ) THEN
      v_reasons:=v_reasons||jsonb_build_array('active_inventory_transfer_work_collision_now');
    END IF;
  END IF;

  IF v_decision.decision_type='ESCALATE' THEN
    IF v_decision.linked_work_item_id IS NULL THEN
      v_reasons:=v_reasons||jsonb_build_array('linked_inventory_work_no_longer_active');
    ELSIF v_sc.case_type='local_shortage' AND NOT EXISTS(
      SELECT 1 FROM public.work_items wi
      WHERE wi.id=v_decision.linked_work_item_id AND wi.status::TEXT NOT IN ('done','cancelled')
        AND EXISTS(SELECT 1 FROM public.work_links wp WHERE wp.work_item_id=wi.id AND wp.entity_type='product' AND wp.entity_id=v_product_id)
        AND EXISTS(SELECT 1 FROM public.work_links ww WHERE ww.work_item_id=wi.id AND ww.entity_type='warehouse' AND ww.entity_id=v_warehouse_id)
    ) THEN
      v_reasons:=v_reasons||jsonb_build_array('linked_inventory_work_no_longer_active');
    ELSIF v_sc.case_type='stalled_transfer' AND NOT EXISTS(
      SELECT 1
      FROM public.work_links wl JOIN public.work_items wi ON wi.id=wl.work_item_id
      WHERE wi.id=v_decision.linked_work_item_id AND wi.status::TEXT NOT IN ('done','cancelled')
        AND wl.entity_type='stock_transfer' AND wl.entity_id=v_transfer_id
    ) THEN
      v_reasons:=v_reasons||jsonb_build_array('linked_inventory_work_no_longer_active');
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
    WHERE dc.snapshot_id=v_snapshot.id AND dc.domain='inventory';
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
          (oc.subject_type='warehouse' AND oc.subject_id=v_warehouse_id)
          OR (v_product_id IS NOT NULL AND oc.subject_type='product' AND oc.subject_id=v_product_id)
          OR (
            NULLIF(v_sc.facts->>'branch_id','') IS NOT NULL
            AND oc.subject_type='branch' AND oc.subject_id=(v_sc.facts->>'branch_id')::UUID
          )
        )
    ) THEN
      v_reasons:=v_reasons||jsonb_build_array('new_inventory_governed_context_after_snapshot');
    END IF;
  END IF;

  RETURN v_reasons;
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.current_inventory_decision_issues_pre_bounded_v1(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.current_inventory_decision_issues(p_decision_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN ai_ops.apply_selected_case_capture_actionability(
    p_decision_id,
    ai_ops.current_inventory_decision_issues_pre_bounded_v1(p_decision_id)
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.current_inventory_decision_issues(UUID)
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
    ELSE RETURN jsonb_build_array('unsupported_validation_domain');
  END CASE;
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.current_decision_issues(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.current_inventory_decision_issues(UUID) IS
  'Read-only Inventory current-state guard with shared bounded-partial actionability, exact candidate recheck, responsibility/supply drift and Work collision protection.';
COMMENT ON FUNCTION ai_ops.current_decision_issues(UUID) IS
  'Canonical current-state guard for Receivables, Sales, Customer Health and Inventory.';

RESET lock_timeout;
RESET statement_timeout;
