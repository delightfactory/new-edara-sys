-- ============================================================================
-- AI Operations — revision-aware run lifecycle.
--
-- Human revision preserves prior decision rows for audit. Run terminal-state
-- accounting must therefore evaluate only the latest revision per frozen Case;
-- otherwise a safely superseded old decision would incorrectly force `partial`.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION ai_ops.refresh_run_terminal_state(p_run_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_run ai_ops.planner_runs%ROWTYPE;
  v_settings ai_ops.settings%ROWTYPE;
  v_now TIMESTAMPTZ := clock_timestamp();
  v_history_rows INTEGER := 0;
  v_total INTEGER := 0;
  v_reviewed INTEGER := 0;
  v_human_rejected INTEGER := 0;
  v_system_rejected INTEGER := 0;
  v_pending_review INTEGER := 0;
  v_pending_work_commit INTEGER := 0;
  v_blocked_work_commit INTEGER := 0;
  v_committed_work INTEGER := 0;
  v_next_status TEXT;
  v_checkpoint TEXT;
  v_terminal BOOLEAN := false;
  v_reason TEXT;
BEGIN
  SELECT * INTO v_run
  FROM ai_ops.planner_runs
  WHERE id=p_run_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'planner run not found'; END IF;

  IF v_run.status NOT IN ('staged','committing') THEN
    RETURN jsonb_build_object(
      'run_id',v_run.id,'status',v_run.status,'checkpoint',v_run.checkpoint,
      'terminal',v_run.status IN ('completed','partial','failed','abandoned'),'changed',false
    );
  END IF;

  SELECT * INTO v_settings FROM ai_ops.settings WHERE singleton=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations settings are not initialized'; END IF;

  SELECT count(*)::INTEGER INTO v_history_rows
  FROM ai_ops.decisions d WHERE d.run_id=p_run_id;

  WITH latest AS (
    SELECT DISTINCT ON (d.case_id) d.*
    FROM ai_ops.decisions d
    WHERE d.run_id=p_run_id
    ORDER BY d.case_id,d.revision DESC,d.created_at DESC,d.id DESC
  )
  SELECT
    count(*)::INTEGER,
    count(dr.id) FILTER (WHERE dr.id IS NOT NULL)::INTEGER,
    count(*) FILTER (WHERE dr.review_state='rejected')::INTEGER,
    count(*) FILTER (WHERE d.validation_state='rejected')::INTEGER,
    count(*) FILTER (
      WHERE d.validation_state<>'rejected' AND dr.id IS NULL
    )::INTEGER,
    count(*) FILTER (
      WHERE dr.review_state='approved'
        AND d.decision_type IN ('CREATE_WORK','ESCALATE')
        AND d.committed_work_item_id IS NULL
        AND d.commit_status NOT IN ('rejected','failed','skipped')
    )::INTEGER,
    count(*) FILTER (
      WHERE dr.review_state='approved'
        AND d.decision_type IN ('CREATE_WORK','ESCALATE')
        AND d.committed_work_item_id IS NULL
        AND d.commit_status IN ('rejected','failed','skipped')
    )::INTEGER,
    count(*) FILTER (
      WHERE dr.review_state='approved'
        AND d.decision_type IN ('CREATE_WORK','ESCALATE')
        AND d.committed_work_item_id IS NOT NULL
        AND d.commit_status='committed'
    )::INTEGER
  INTO
    v_total,v_reviewed,v_human_rejected,v_system_rejected,v_pending_review,
    v_pending_work_commit,v_blocked_work_commit,v_committed_work
  FROM latest d
  LEFT JOIN ai_ops.decision_reviews dr ON dr.decision_id=d.id;

  IF v_total=0 THEN
    v_next_status:='completed'; v_checkpoint:='completed_zero_cases'; v_terminal:=true;
    v_reason:='zero_cases_is_valid_success';
  ELSIF v_settings.shadow_mode THEN
    v_next_status:='completed'; v_checkpoint:='completed_shadow_analysis'; v_terminal:=true;
    v_reason:='shadow_mode_analysis_only';
  ELSIF NOT v_settings.planner_enabled THEN
    v_next_status:='partial'; v_checkpoint:='planner_disabled_after_staging'; v_terminal:=true;
    v_reason:='planner_disabled_before_review_flow_finished';
  ELSIF v_pending_review>0 THEN
    v_next_status:='staged'; v_checkpoint:='awaiting_human_review';
    v_reason:='human_review_pending';
  ELSIF v_pending_work_commit>0 THEN
    v_next_status:='staged'; v_checkpoint:='awaiting_work_commit';
    v_reason:='approved_work_execution_pending';
  ELSIF v_system_rejected>0 OR v_blocked_work_commit>0 THEN
    v_next_status:='partial'; v_terminal:=true;
    v_checkpoint:=CASE WHEN v_blocked_work_commit>0 THEN 'review_complete_work_commit_blocked' ELSE 'review_complete_with_stale_decisions' END;
    v_reason:=CASE WHEN v_blocked_work_commit>0 THEN 'approved_work_could_not_be_committed_safely' ELSE 'one_or_more_latest_decisions_became_stale_or_unsafe' END;
  ELSE
    v_next_status:='completed'; v_checkpoint:='review_flow_completed'; v_terminal:=true;
    v_reason:='all_latest_decisions_terminal';
  END IF;

  UPDATE ai_ops.planner_runs
  SET
    status=v_next_status,
    checkpoint=v_checkpoint,
    lease_expires_at=CASE WHEN v_terminal THEN NULL ELSE lease_expires_at END,
    completed_at=CASE WHEN v_terminal THEN COALESCE(completed_at,v_now) ELSE NULL END,
    result_summary=result_summary||jsonb_build_object(
      'lifecycle_refresh_at',v_now,
      'lifecycle_reason',v_reason,
      'decision_history_rows',v_history_rows,
      'effective_latest_decisions',v_total,
      'superseded_decision_rows',GREATEST(v_history_rows-v_total,0),
      'decision_reviewed',v_reviewed,
      'human_rejected_decisions',v_human_rejected,
      'system_rejected_decisions',v_system_rejected,
      'pending_human_review',v_pending_review,
      'pending_work_commit',v_pending_work_commit,
      'blocked_work_commit',v_blocked_work_commit,
      'committed_work_decisions',v_committed_work,
      'unsupported_execution_decisions',0,
      'revision_aware_lifecycle',true,
      'shadow_mode_at_refresh',v_settings.shadow_mode,
      'planner_enabled_at_refresh',v_settings.planner_enabled
    ),
    updated_at=v_now
  WHERE id=p_run_id
  RETURNING * INTO v_run;

  RETURN jsonb_build_object(
    'run_id',v_run.id,'status',v_run.status,'checkpoint',v_run.checkpoint,
    'terminal',v_terminal,'changed',true,'reason',v_reason,
    'decision_history_rows',v_history_rows,'effective_latest_decisions',v_total,
    'pending_human_review',v_pending_review,'pending_work_commit',v_pending_work_commit,
    'system_rejected_decisions',v_system_rejected,'blocked_work_commit',v_blocked_work_commit,
    'unsupported_execution_decisions',0
  );
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.refresh_run_terminal_state(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.refresh_run_terminal_state(UUID) IS
  'Revision-aware planner lifecycle resolver. Only latest decision revision per Case drives pending/rejected/committed state; superseded rows remain audit history.';

RESET lock_timeout;
RESET statement_timeout;
