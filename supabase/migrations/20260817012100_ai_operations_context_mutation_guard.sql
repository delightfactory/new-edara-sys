-- ============================================================================
-- AI Operations — governed operational-context mutation guard
--
-- Human context is authoritative planning evidence. A decision based on frozen
-- context must become stale if that context is revoked/changed, and a relevant
-- new approved context appearing after the snapshot must force re-analysis.
-- This is an additive current-state guard only; it never mutates source/context.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

ALTER FUNCTION ai_ops.current_decision_issues(UUID)
  RENAME TO current_decision_issues_pre_context_mutation_guard_v1;
REVOKE ALL ON FUNCTION ai_ops.current_decision_issues_pre_context_mutation_guard_v1(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.current_decision_issues(p_decision_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_issues JSONB;
  v_decision ai_ops.decisions%ROWTYPE;
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_sc ai_ops.snapshot_cases%ROWTYPE;
  v_now TIMESTAMPTZ:=clock_timestamp();
  v_frozen_changed BOOLEAN:=false;
  v_new_relevant BOOLEAN:=false;
BEGIN
  v_issues:=ai_ops.current_decision_issues_pre_context_mutation_guard_v1(p_decision_id);

  SELECT * INTO v_decision
  FROM ai_ops.decisions d
  WHERE d.id=p_decision_id;
  IF NOT FOUND THEN
    RETURN COALESCE(v_issues,'[]'::JSONB)||jsonb_build_array('decision_missing');
  END IF;

  SELECT * INTO v_snapshot
  FROM ai_ops.snapshots s
  WHERE s.run_id=v_decision.run_id;
  IF NOT FOUND THEN
    RETURN COALESCE(v_issues,'[]'::JSONB)||jsonb_build_array('decision_snapshot_missing');
  END IF;

  SELECT * INTO v_sc
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id=v_snapshot.id AND sc.case_id=v_decision.case_id;
  IF NOT FOUND THEN
    RETURN COALESCE(v_issues,'[]'::JSONB)||jsonb_build_array('decision_snapshot_case_missing');
  END IF;

  -- A context item that existed in frozen evidence must still be the same
  -- approved/active fact. Revocation, expiry or content/routing change makes the
  -- old decision stale even when the operational source row itself did not move.
  SELECT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(
      CASE
        WHEN jsonb_typeof(v_sc.operational_context->'items')='array'
          THEN v_sc.operational_context->'items'
        ELSE '[]'::JSONB
      END
    ) frozen
    LEFT JOIN ai_ops.operational_context oc
      ON oc.id=NULLIF(frozen->>'id','')::UUID
    WHERE oc.id IS NULL
       OR oc.status<>'active'
       OR oc.valid_from>v_now
       OR (oc.valid_until IS NOT NULL AND oc.valid_until<=v_now)
       OR oc.context_type IS DISTINCT FROM frozen->>'context_type'
       OR left(COALESCE(NULLIF(oc.context_payload->>'summary',''),oc.context_type),500)
            IS DISTINCT FROM frozen->>'summary'
       OR oc.owner_user_id IS DISTINCT FROM NULLIF(frozen->>'owner_user_id','')::UUID
       OR oc.source_type IS DISTINCT FROM frozen->>'source_type'
       OR oc.confidence_class IS DISTINCT FROM frozen->>'confidence_class'
       OR oc.lifecycle_type IS DISTINCT FROM frozen->>'lifecycle_type'
       OR oc.valid_from IS DISTINCT FROM NULLIF(frozen->>'valid_from','')::TIMESTAMPTZ
       OR oc.valid_until IS DISTINCT FROM NULLIF(frozen->>'valid_until','')::TIMESTAMPTZ
       OR oc.review_on IS DISTINCT FROM NULLIF(frozen->>'review_on','')::DATE
       OR oc.visibility IS DISTINCT FROM frozen->>'visibility'
  ) INTO v_frozen_changed;

  -- Detect relevant new context after the snapshot. Relevance is deliberately
  -- bounded to exact Case entity/known frozen subjects and normalized entity ids
  -- already present in Case facts; no fuzzy text matching or arbitrary joins.
  SELECT EXISTS (
    SELECT 1
    FROM ai_ops.operational_context oc
    WHERE oc.status='active'
      AND oc.valid_from<=v_now
      AND (oc.valid_until IS NULL OR oc.valid_until>v_now)
      AND oc.visibility IN ('management','standard')
      AND (oc.confidence_class<>'ai_inference' OR oc.approved_by_user_id IS NOT NULL)
      AND oc.created_at>v_snapshot.data_as_of
      AND NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements(
          CASE
            WHEN jsonb_typeof(v_sc.operational_context->'items')='array'
              THEN v_sc.operational_context->'items'
            ELSE '[]'::JSONB
          END
        ) frozen
        WHERE NULLIF(frozen->>'id','')::UUID=oc.id
      )
      AND (
        (v_sc.entity_type IS NOT NULL AND v_sc.entity_id IS NOT NULL
          AND oc.subject_type=v_sc.entity_type AND oc.subject_id=v_sc.entity_id)
        OR (NULLIF(v_sc.facts->>'customer_id','') IS NOT NULL
          AND oc.subject_type='customer'
          AND oc.subject_id=NULLIF(v_sc.facts->>'customer_id','')::UUID)
        OR (NULLIF(v_sc.facts->>'product_id','') IS NOT NULL
          AND oc.subject_type='product'
          AND oc.subject_id=NULLIF(v_sc.facts->>'product_id','')::UUID)
        OR (NULLIF(v_sc.facts->>'branch_id','') IS NOT NULL
          AND oc.subject_type='branch'
          AND oc.subject_id=NULLIF(v_sc.facts->>'branch_id','')::UUID)
        OR (NULLIF(v_sc.facts->>'department_id','') IS NOT NULL
          AND oc.subject_type='department'
          AND oc.subject_id=NULLIF(v_sc.facts->>'department_id','')::UUID)
        OR (NULLIF(v_sc.facts->>'employee_id','') IS NOT NULL
          AND oc.subject_type='employee'
          AND oc.subject_id=NULLIF(v_sc.facts->>'employee_id','')::UUID)
        OR (NULLIF(v_sc.facts->>'affected_employee_id','') IS NOT NULL
          AND oc.subject_type='employee'
          AND oc.subject_id=NULLIF(v_sc.facts->>'affected_employee_id','')::UUID)
        OR (NULLIF(v_sc.facts->>'affected_user_id','') IS NOT NULL
          AND oc.subject_type='employee'
          AND oc.subject_id=NULLIF(v_sc.facts->>'affected_user_id','')::UUID)
        OR (NULLIF(v_sc.facts->'existing_active_work'->>'work_item_id','') IS NOT NULL
          AND oc.subject_type='work_item'
          AND oc.subject_id=NULLIF(v_sc.facts->'existing_active_work'->>'work_item_id','')::UUID)
        OR EXISTS (
          SELECT 1
          FROM jsonb_array_elements(
            CASE
              WHEN jsonb_typeof(v_sc.operational_context->'items')='array'
                THEN v_sc.operational_context->'items'
              ELSE '[]'::JSONB
            END
          ) frozen
          WHERE frozen->>'subject_type'=oc.subject_type
            AND NULLIF(frozen->>'subject_id','')::UUID=oc.subject_id
        )
      )
  ) INTO v_new_relevant;

  IF v_frozen_changed THEN
    v_issues:=COALESCE(v_issues,'[]'::JSONB)||jsonb_build_array('frozen_operational_context_changed');
  END IF;
  IF v_new_relevant THEN
    v_issues:=COALESCE(v_issues,'[]'::JSONB)||jsonb_build_array('new_relevant_operational_context_after_snapshot');
  END IF;

  -- Keep issue codes unique while preserving a deterministic lexical order.
  SELECT COALESCE(jsonb_agg(code ORDER BY code),'[]'::JSONB)
  INTO v_issues
  FROM (
    SELECT DISTINCT value::TEXT #>> '{}' AS code
    FROM jsonb_array_elements(COALESCE(v_issues,'[]'::JSONB))
  ) q;

  RETURN v_issues;
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.current_decision_issues(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.current_decision_issues(UUID) IS
  'Final current-state safety gate with governed-context drift detection. Revoked/expired/changed frozen context or relevant new post-snapshot approved context invalidates the old recommendation.';

RESET lock_timeout;
RESET statement_timeout;
