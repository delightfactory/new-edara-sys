-- ============================================================================
-- AI Operations Planner — Shared Reviewed-Work Source Serialization
--
-- DESIGN-TIME MIGRATION ONLY.
-- Work Health recovery and HR / Availability coverage are alternative reviewed
-- remediation paths for the same source Work. They must share one source-level
-- serialization invariant and one cross-domain collision predicate.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION private.ai_ops_lock_reviewed_source_work(
  p_source_work_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_source_work_id IS NULL THEN
    RAISE EXCEPTION 'reviewed Work source identity is required';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('ai_ops:reviewed-work-source:'||p_source_work_id::TEXT,0)
  );
END;
$$;
REVOKE ALL ON FUNCTION private.ai_ops_lock_reviewed_source_work(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.ai_ops_has_active_reviewed_source_remediation(
  p_source_work_id UUID,
  p_exclude_work_item_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS(
    SELECT 1
    FROM public.work_links wl
    JOIN public.work_items remediation ON remediation.id=wl.work_item_id
    WHERE wl.entity_type='work_item'
      AND wl.entity_id=p_source_work_id
      AND remediation.status::TEXT NOT IN ('done','cancelled')
      AND remediation.metadata->>'ai_domain' IN ('work_health','hr_availability')
      AND (p_exclude_work_item_id IS NULL OR remediation.id<>p_exclude_work_item_id)
  );
$$;
REVOKE ALL ON FUNCTION private.ai_ops_has_active_reviewed_source_remediation(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

-- Make Work Health validation symmetric with the HR / Availability guard. The
-- previous guard detected Work Health recovery only; it must also see active HR
-- coverage for the same source Work before a decision can remain actionable.
ALTER FUNCTION ai_ops.current_work_health_decision_issues(UUID)
  RENAME TO current_work_health_decision_issues_pre_cross_domain_remediation_v1;
REVOKE ALL ON FUNCTION ai_ops.current_work_health_decision_issues_pre_cross_domain_remediation_v1(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.current_work_health_decision_issues(
  p_decision_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_reasons JSONB;
  v_decision_type TEXT;
  v_committed_work_item_id UUID;
  v_source_work_id UUID;
BEGIN
  v_reasons:=ai_ops.current_work_health_decision_issues_pre_cross_domain_remediation_v1(
    p_decision_id
  );

  SELECT d.decision_type::TEXT,d.committed_work_item_id,
         COALESCE(sc.entity_id,NULLIF(sc.facts->>'work_item_id','')::UUID)
  INTO v_decision_type,v_committed_work_item_id,v_source_work_id
  FROM ai_ops.decisions d
  JOIN ai_ops.snapshots s ON s.run_id=d.run_id
  JOIN ai_ops.snapshot_cases sc ON sc.snapshot_id=s.id AND sc.case_id=d.case_id
  WHERE d.id=p_decision_id AND sc.domain='work_health';

  IF FOUND
     AND v_decision_type='CREATE_WORK'
     AND v_source_work_id IS NOT NULL
     AND private.ai_ops_has_active_reviewed_source_remediation(
       v_source_work_id,v_committed_work_item_id
     )
     AND NOT (v_reasons ? 'active_coverage_or_work_health_recovery_collision_now') THEN
    v_reasons:=v_reasons||jsonb_build_array(
      'active_coverage_or_work_health_recovery_collision_now'
    );
  END IF;

  RETURN v_reasons;
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.current_work_health_decision_issues(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

-- Wrap the current Work Health source-lock bridge. The legacy domain-specific
-- lock remains inside the preserved implementation, but the shared lock is
-- always acquired first by every new commit path after this migration.
ALTER FUNCTION private.work_create_ai_reviewed_work_health_task(UUID,UUID)
  RENAME TO work_create_ai_reviewed_work_health_task_pre_shared_source_guard_v1;
REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_work_health_task_pre_shared_source_guard_v1(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.work_create_ai_reviewed_work_health_task(
  p_decision_id UUID,
  p_approved_execution_by UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_source_work_id UUID;
  v_committed_work_item_id UUID;
BEGIN
  SELECT COALESCE(sc.entity_id,NULLIF(sc.facts->>'work_item_id','')::UUID),
         d.committed_work_item_id
  INTO v_source_work_id,v_committed_work_item_id
  FROM ai_ops.decisions d
  JOIN ai_ops.snapshots s ON s.run_id=d.run_id
  JOIN ai_ops.snapshot_cases sc ON sc.snapshot_id=s.id AND sc.case_id=d.case_id
  WHERE d.id=p_decision_id AND sc.domain='work_health';

  IF v_source_work_id IS NULL THEN
    RAISE EXCEPTION 'Work Health decision-time source Work identity is missing';
  END IF;

  PERFORM private.ai_ops_lock_reviewed_source_work(v_source_work_id);

  IF v_committed_work_item_id IS NULL
     AND private.ai_ops_has_active_reviewed_source_remediation(v_source_work_id,NULL) THEN
    RETURN jsonb_build_object(
      'committed',false,
      'blocked',true,
      'reason','active_coverage_or_work_health_recovery_collision_now',
      'source_work_item_id',v_source_work_id,
      'domain','work_health'
    );
  END IF;

  RETURN private.work_create_ai_reviewed_work_health_task_pre_shared_source_guard_v1(
    p_decision_id,p_approved_execution_by
  );
END;
$$;
REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_work_health_task(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

-- Apply the identical shared source lock and collision rule to HR / Availability.
ALTER FUNCTION private.work_create_ai_reviewed_hr_availability_task(UUID,UUID)
  RENAME TO work_create_ai_reviewed_hr_availability_task_pre_shared_source_guard_v1;
REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_hr_availability_task_pre_shared_source_guard_v1(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.work_create_ai_reviewed_hr_availability_task(
  p_decision_id UUID,
  p_approved_execution_by UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_source_work_id UUID;
  v_committed_work_item_id UUID;
BEGIN
  SELECT NULLIF(sc.facts->>'source_work_item_id','')::UUID,
         d.committed_work_item_id
  INTO v_source_work_id,v_committed_work_item_id
  FROM ai_ops.decisions d
  JOIN ai_ops.snapshots s ON s.run_id=d.run_id
  JOIN ai_ops.snapshot_cases sc ON sc.snapshot_id=s.id AND sc.case_id=d.case_id
  WHERE d.id=p_decision_id AND sc.domain='hr_availability';

  IF v_source_work_id IS NULL THEN
    RAISE EXCEPTION 'HR Availability decision-time source Work identity is missing';
  END IF;

  PERFORM private.ai_ops_lock_reviewed_source_work(v_source_work_id);

  IF v_committed_work_item_id IS NULL
     AND private.ai_ops_has_active_reviewed_source_remediation(v_source_work_id,NULL) THEN
    RETURN jsonb_build_object(
      'committed',false,
      'blocked',true,
      'reason','active_coverage_or_work_health_recovery_collision_now',
      'source_work_item_id',v_source_work_id,
      'domain','hr_availability'
    );
  END IF;

  RETURN private.work_create_ai_reviewed_hr_availability_task_pre_shared_source_guard_v1(
    p_decision_id,p_approved_execution_by
  );
END;
$$;
REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_hr_availability_task(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION private.ai_ops_lock_reviewed_source_work(UUID) IS
  'Single cross-domain serialization invariant for human-approved AI remediation targeting the same source Work.';
COMMENT ON FUNCTION private.ai_ops_has_active_reviewed_source_remediation(UUID,UUID) IS
  'Cross-domain active-remediation predicate covering Work Health recovery and HR Availability coverage.';
COMMENT ON FUNCTION ai_ops.current_work_health_decision_issues(UUID) IS
  'Work Health current-state guard hardened with symmetric cross-domain HR Coverage / Work Health Recovery collision detection.';
COMMENT ON FUNCTION private.work_create_ai_reviewed_work_health_task(UUID,UUID) IS
  'Work Health reviewed recovery bridge serialized by the shared source-Work AI remediation invariant.';
COMMENT ON FUNCTION private.work_create_ai_reviewed_hr_availability_task(UUID,UUID) IS
  'HR Availability reviewed coverage bridge serialized by the shared source-Work AI remediation invariant.';

RESET lock_timeout;
RESET statement_timeout;
