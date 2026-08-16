-- ============================================================================
-- AI Operations Planner — Run Finalization & Lifecycle Closure
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply until explicitly reviewed/approved.
-- Depends on the complete first Credit slice through:
--   * 20260816173600_ai_operations_commit_runtime_safety.sql
--
-- Purpose:
--   * prevent valid planner runs from remaining staged forever
--   * make zero-case and shadow-mode runs explicit successful terminal outcomes
--   * keep operational-mode runs staged only while human review / approved Work
--     execution is genuinely pending
--   * surface stale/blocked/unsupported execution as partial, never false success
--   * centralize lifecycle refresh after stage, validation, review and commit
--
-- No Sales/Customer/Credit/HR/Inventory mutation occurs here.
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
  v_total INTEGER := 0;
  v_reviewed INTEGER := 0;
  v_human_rejected INTEGER := 0;
  v_system_rejected INTEGER := 0;
  v_pending_review INTEGER := 0;
  v_pending_work_commit INTEGER := 0;
  v_blocked_work_commit INTEGER := 0;
  v_committed_work INTEGER := 0;
  v_unsupported_execution INTEGER := 0;
  v_next_status TEXT;
  v_checkpoint TEXT;
  v_terminal BOOLEAN := false;
  v_reason TEXT;
BEGIN
  SELECT * INTO v_run
  FROM ai_ops.planner_runs
  WHERE id = p_run_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'planner run not found';
  END IF;

  -- Terminal or pre-staging runs are deliberately left untouched. This helper
  -- resolves only the review/commit lifecycle after decisions have been staged.
  IF v_run.status NOT IN ('staged', 'committing') THEN
    RETURN jsonb_build_object(
      'run_id', v_run.id,
      'status', v_run.status,
      'checkpoint', v_run.checkpoint,
      'terminal', v_run.status IN ('completed','partial','failed','abandoned'),
      'changed', false
    );
  END IF;

  SELECT * INTO v_settings
  FROM ai_ops.settings
  WHERE singleton = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI Operations settings are not initialized';
  END IF;

  SELECT
    count(*)::INTEGER,
    count(dr.id) FILTER (WHERE dr.id IS NOT NULL)::INTEGER,
    count(*) FILTER (WHERE dr.review_state = 'rejected')::INTEGER,
    count(*) FILTER (WHERE d.validation_state = 'rejected')::INTEGER,
    count(*) FILTER (
      WHERE d.validation_state <> 'rejected'
        AND dr.id IS NULL
    )::INTEGER,
    count(*) FILTER (
      WHERE dr.review_state = 'approved'
        AND d.decision_type = 'CREATE_WORK'
        AND d.committed_work_item_id IS NULL
        AND d.commit_status NOT IN ('rejected','failed','skipped')
    )::INTEGER,
    count(*) FILTER (
      WHERE dr.review_state = 'approved'
        AND d.decision_type = 'CREATE_WORK'
        AND d.committed_work_item_id IS NULL
        AND d.commit_status IN ('rejected','failed','skipped')
    )::INTEGER,
    count(*) FILTER (
      WHERE dr.review_state = 'approved'
        AND d.decision_type = 'CREATE_WORK'
        AND d.committed_work_item_id IS NOT NULL
        AND d.commit_status = 'committed'
    )::INTEGER,
    count(*) FILTER (
      WHERE dr.review_state = 'approved'
        AND d.decision_type = 'ESCALATE'
    )::INTEGER
  INTO
    v_total,
    v_reviewed,
    v_human_rejected,
    v_system_rejected,
    v_pending_review,
    v_pending_work_commit,
    v_blocked_work_commit,
    v_committed_work,
    v_unsupported_execution
  FROM ai_ops.decisions d
  LEFT JOIN ai_ops.decision_reviews dr ON dr.decision_id = d.id
  WHERE d.run_id = p_run_id;

  IF v_total = 0 THEN
    v_next_status := 'completed';
    v_checkpoint := 'completed_zero_cases';
    v_terminal := true;
    v_reason := 'zero_cases_is_valid_success';
  ELSIF v_settings.shadow_mode THEN
    -- Shadow mode deliberately records recommendations without creating an
    -- authorization queue that can never execute.
    v_next_status := 'completed';
    v_checkpoint := 'completed_shadow_analysis';
    v_terminal := true;
    v_reason := 'shadow_mode_analysis_only';
  ELSIF NOT v_settings.planner_enabled THEN
    v_next_status := 'partial';
    v_checkpoint := 'planner_disabled_after_staging';
    v_terminal := true;
    v_reason := 'planner_disabled_before_review_flow_finished';
  ELSIF v_pending_review > 0 THEN
    v_next_status := 'staged';
    v_checkpoint := 'awaiting_human_review';
    v_reason := 'human_review_pending';
  ELSIF v_pending_work_commit > 0 THEN
    v_next_status := 'staged';
    v_checkpoint := 'awaiting_work_commit';
    v_reason := 'approved_work_execution_pending';
  ELSIF v_system_rejected > 0
     OR v_blocked_work_commit > 0
     OR v_unsupported_execution > 0 THEN
    v_next_status := 'partial';
    v_checkpoint := CASE
      WHEN v_unsupported_execution > 0 THEN 'review_complete_execution_not_supported'
      WHEN v_blocked_work_commit > 0 THEN 'review_complete_work_commit_blocked'
      ELSE 'review_complete_with_stale_decisions'
    END;
    v_terminal := true;
    v_reason := CASE
      WHEN v_unsupported_execution > 0 THEN 'approved_execution_type_not_supported_in_current_slice'
      WHEN v_blocked_work_commit > 0 THEN 'approved_work_could_not_be_committed_safely'
      ELSE 'one_or_more_decisions_became_stale_or_unsafe'
    END;
  ELSE
    v_next_status := 'completed';
    v_checkpoint := 'review_flow_completed';
    v_terminal := true;
    v_reason := 'all_decisions_terminal';
  END IF;

  UPDATE ai_ops.planner_runs
  SET
    status = v_next_status,
    checkpoint = v_checkpoint,
    lease_expires_at = CASE WHEN v_terminal THEN NULL ELSE lease_expires_at END,
    completed_at = CASE WHEN v_terminal THEN COALESCE(completed_at, v_now) ELSE NULL END,
    result_summary = result_summary || jsonb_build_object(
      'lifecycle_refresh_at', v_now,
      'lifecycle_reason', v_reason,
      'decision_total', v_total,
      'decision_reviewed', v_reviewed,
      'human_rejected_decisions', v_human_rejected,
      'system_rejected_decisions', v_system_rejected,
      'pending_human_review', v_pending_review,
      'pending_work_commit', v_pending_work_commit,
      'blocked_work_commit', v_blocked_work_commit,
      'committed_work_decisions', v_committed_work,
      'unsupported_execution_decisions', v_unsupported_execution,
      'shadow_mode_at_refresh', v_settings.shadow_mode,
      'planner_enabled_at_refresh', v_settings.planner_enabled
    ),
    updated_at = v_now
  WHERE id = p_run_id
  RETURNING * INTO v_run;

  RETURN jsonb_build_object(
    'run_id', v_run.id,
    'status', v_run.status,
    'checkpoint', v_run.checkpoint,
    'terminal', v_terminal,
    'changed', true,
    'reason', v_reason,
    'pending_human_review', v_pending_review,
    'pending_work_commit', v_pending_work_commit,
    'system_rejected_decisions', v_system_rejected,
    'blocked_work_commit', v_blocked_work_commit,
    'unsupported_execution_decisions', v_unsupported_execution
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.refresh_run_terminal_state(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION ai_ops.refresh_run_terminal_state(UUID) IS
  'Deterministic planner-run lifecycle resolver. Keeps staged only for real pending review/Work execution; zero-case/shadow complete, stale/blocked/unsupported execution becomes partial.';

-- --------------------------------------------------------------------------
-- Stage wrapper: zero-case and shadow-mode runs become terminal immediately.
-- --------------------------------------------------------------------------
ALTER FUNCTION ai_ops.worker_stage_decisions(UUID, TEXT, TEXT, JSONB)
  RENAME TO worker_stage_decisions_v1;

CREATE OR REPLACE FUNCTION ai_ops.worker_stage_decisions(
  p_run_id UUID,
  p_worker_id TEXT,
  p_context_hash TEXT,
  p_decisions JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_result JSONB;
  v_lifecycle JSONB;
BEGIN
  v_result := ai_ops.worker_stage_decisions_v1(
    p_run_id,
    p_worker_id,
    p_context_hash,
    p_decisions
  );
  v_lifecycle := ai_ops.refresh_run_terminal_state(p_run_id);
  RETURN v_result || jsonb_build_object('run_lifecycle', v_lifecycle);
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions_v1(UUID, TEXT, TEXT, JSONB)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions(UUID, TEXT, TEXT, JSONB)
  FROM PUBLIC, anon, authenticated, service_role;

-- --------------------------------------------------------------------------
-- Validation wrapper: a fully stale/unsafe run cannot remain staged forever.
-- --------------------------------------------------------------------------
ALTER FUNCTION ai_ops.validate_staged_run(UUID)
  RENAME TO validate_staged_run_v1;

CREATE OR REPLACE FUNCTION ai_ops.validate_staged_run(p_run_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_result JSONB;
  v_lifecycle JSONB;
BEGIN
  v_result := ai_ops.validate_staged_run_v1(p_run_id);
  v_lifecycle := ai_ops.refresh_run_terminal_state(p_run_id);
  RETURN v_result || jsonb_build_object('run_lifecycle', v_lifecycle);
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.validate_staged_run_v1(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION ai_ops.validate_staged_run(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

-- --------------------------------------------------------------------------
-- Human review wrapper: rejection/passive approval may complete a run; approved
-- CREATE_WORK deliberately remains staged until a separate explicit commit.
-- --------------------------------------------------------------------------
ALTER FUNCTION public.ai_ops_review_decision(UUID, TEXT, TEXT)
  RENAME TO ai_ops_review_decision_v1;

CREATE OR REPLACE FUNCTION public.ai_ops_review_decision(
  p_decision_id UUID,
  p_review_state TEXT,
  p_review_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_result JSONB;
  v_run_id UUID;
  v_lifecycle JSONB;
BEGIN
  v_result := public.ai_ops_review_decision_v1(
    p_decision_id,
    p_review_state,
    p_review_note
  );

  SELECT d.run_id INTO v_run_id
  FROM ai_ops.decisions d
  WHERE d.id = p_decision_id;

  IF v_run_id IS NOT NULL THEN
    v_lifecycle := ai_ops.refresh_run_terminal_state(v_run_id);
  END IF;

  RETURN v_result || jsonb_build_object('run_lifecycle', COALESCE(v_lifecycle, '{}'::JSONB));
END;
$$;

REVOKE ALL ON FUNCTION public.ai_ops_review_decision_v1(UUID, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ai_ops_review_decision(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ai_ops_review_decision(UUID, TEXT, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_review_decision(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ai_ops_review_decision(UUID, TEXT, TEXT) TO service_role;

-- --------------------------------------------------------------------------
-- Explicit Work commit wrapper: finish/partial the run from the durable commit
-- outcome. Approval and execution remain two separate user actions.
-- --------------------------------------------------------------------------
ALTER FUNCTION public.ai_ops_commit_reviewed_decision(UUID)
  RENAME TO ai_ops_commit_reviewed_decision_v1;

CREATE OR REPLACE FUNCTION public.ai_ops_commit_reviewed_decision(p_decision_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_result JSONB;
  v_run_id UUID;
  v_lifecycle JSONB;
BEGIN
  v_result := public.ai_ops_commit_reviewed_decision_v1(p_decision_id);

  SELECT d.run_id INTO v_run_id
  FROM ai_ops.decisions d
  WHERE d.id = p_decision_id;

  IF v_run_id IS NOT NULL THEN
    v_lifecycle := ai_ops.refresh_run_terminal_state(v_run_id);
  END IF;

  RETURN v_result || jsonb_build_object('run_lifecycle', COALESCE(v_lifecycle, '{}'::JSONB));
END;
$$;

REVOKE ALL ON FUNCTION public.ai_ops_commit_reviewed_decision_v1(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) TO service_role;

COMMENT ON FUNCTION public.ai_ops_review_decision(UUID, TEXT, TEXT) IS
  'Human review gate with deterministic run lifecycle refresh. Approval itself never performs operational execution.';
COMMENT ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) IS
  'Explicit human-triggered reviewed CREATE_WORK commit followed by deterministic planner-run lifecycle refresh.';

RESET lock_timeout;
RESET statement_timeout;
