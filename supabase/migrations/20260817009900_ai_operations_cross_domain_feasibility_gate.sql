-- AI Operations — deterministic cross-domain feasibility closure.
SET lock_timeout = '5s';
SET statement_timeout = '30s';

CREATE OR REPLACE FUNCTION ai_ops.current_cross_domain_feasibility_issues(p_decision_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_decision ai_ops.decisions%ROWTYPE;
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_run ai_ops.planner_runs%ROWTYPE;
  v_reasons JSONB := '[]'::JSONB;
  v_due_date DATE;
BEGIN
  SELECT * INTO v_decision FROM ai_ops.decisions WHERE id=p_decision_id;
  IF NOT FOUND OR v_decision.decision_type NOT IN ('CREATE_WORK','ESCALATE') THEN
    RETURN v_reasons;
  END IF;

  SELECT * INTO v_run FROM ai_ops.planner_runs WHERE id=v_decision.run_id;
  SELECT * INTO v_snapshot FROM ai_ops.snapshots WHERE run_id=v_decision.run_id;
  IF NOT FOUND THEN RETURN jsonb_build_array('decision_snapshot_missing'); END IF;

  IF v_decision.recommended_owner_user_id IS NOT NULL
     AND NOT private.work_actor_is_active(v_decision.recommended_owner_user_id) THEN
    v_reasons:=v_reasons||jsonb_build_array('recommended_owner_unavailable_now');
  END IF;
  IF v_decision.recommended_assignee_user_id IS NOT NULL
     AND NOT private.work_actor_is_active(v_decision.recommended_assignee_user_id) THEN
    v_reasons:=v_reasons||jsonb_build_array('recommended_assignee_unavailable_now');
  END IF;

  v_due_date:=COALESCE(
    (v_decision.due_at AT TIME ZONE 'Africa/Cairo')::DATE,
    v_run.business_date
  );

  IF v_decision.recommended_assignee_user_id IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM ai_ops.snapshot_cases sc
       WHERE sc.snapshot_id=v_snapshot.id
         AND sc.domain='hr_availability'
         AND NULLIF(sc.facts->>'affected_user_id','')::UUID=v_decision.recommended_assignee_user_id
         AND COALESCE(NULLIF(sc.facts->>'availability_date','')::DATE,v_run.business_date)<=v_due_date
     ) THEN
    v_reasons:=v_reasons||jsonb_build_array('assignee_has_frozen_hr_unavailability_conflict');
  END IF;

  RETURN v_reasons;
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.current_cross_domain_feasibility_issues(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

ALTER FUNCTION ai_ops.current_decision_issues(UUID)
  RENAME TO current_decision_issues_pre_cross_domain_feasibility_v1;
REVOKE ALL ON FUNCTION ai_ops.current_decision_issues_pre_cross_domain_feasibility_v1(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.current_decision_issues(p_decision_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    ai_ops.current_decision_issues_pre_cross_domain_feasibility_v1(p_decision_id)
    || ai_ops.current_cross_domain_feasibility_issues(p_decision_id);
$$;
REVOKE ALL ON FUNCTION ai_ops.current_decision_issues(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.current_cross_domain_feasibility_issues(UUID) IS
  'Hard cross-domain feasibility guard: current actor availability plus frozen HR allocation conflicts. No productivity score or arbitrary capacity threshold.';

RESET lock_timeout;
RESET statement_timeout;
