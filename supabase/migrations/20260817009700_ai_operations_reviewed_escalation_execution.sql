-- ============================================================================
-- AI Operations Planner — Human-Approved ESCALATE Execution Bridge
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply to production until explicitly
-- reviewed, DB-tested and approved.
--
-- Closes the last executable decision gap in the reviewed AI Operations path:
-- CREATE_WORK keeps the existing reviewed Work builders; ESCALATE now executes
-- the native Work escalation overlay on the frozen existing Work item.
-- Approval and execution remain separate user actions.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION private.ai_ops_execute_reviewed_escalation(
  p_decision_id UUID,
  p_approved_execution_by UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_settings ai_ops.settings%ROWTYPE;
  v_decision ai_ops.decisions%ROWTYPE;
  v_review ai_ops.decision_reviews%ROWTYPE;
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_sc ai_ops.snapshot_cases%ROWTYPE;
  v_work public.work_items%ROWTYPE;
  v_escalation public.work_escalations%ROWTYPE;
  v_issues JSONB;
  v_work_result JSONB;
  v_fingerprint TEXT;
  v_frozen_work_id UUID;
  v_operation_id UUID;
  v_reason TEXT;
  v_now TIMESTAMPTZ := clock_timestamp();
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('ai_ops:commit:' || p_decision_id::TEXT, 0));

  IF p_approved_execution_by IS NULL
     OR NOT private.work_actor_is_active(p_approved_execution_by) THEN
    RAISE EXCEPTION 'approved execution actor is not an active Work actor';
  END IF;

  SELECT * INTO v_decision
  FROM ai_ops.decisions
  WHERE id = p_decision_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI Operations decision not found';
  END IF;

  IF v_decision.decision_type <> 'ESCALATE' THEN
    RETURN jsonb_build_object(
      'committed', false,
      'blocked', true,
      'reason', 'bridge_supports_escalate_only',
      'decision_type', v_decision.decision_type
    );
  END IF;

  -- Durable decision metadata is the exact response-loss retry source of truth.
  IF v_decision.commit_status = 'committed'
     AND v_decision.committed_work_item_id IS NOT NULL
     AND NULLIF(v_decision.validation_detail->>'work_escalation_id','') IS NOT NULL THEN
    SELECT * INTO v_escalation
    FROM public.work_escalations e
    WHERE e.id = (v_decision.validation_detail->>'work_escalation_id')::UUID
      AND e.work_item_id = v_decision.committed_work_item_id;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'committed', true,
        'idempotent_reuse', true,
        'decision_id', p_decision_id,
        'work_item_id', v_escalation.work_item_id,
        'escalation_id', v_escalation.id,
        'operational_mutation', 'work_escalation_overlay'
      );
    END IF;

    RAISE EXCEPTION 'decision references missing committed Work escalation';
  END IF;

  SELECT * INTO v_settings
  FROM ai_ops.settings
  WHERE singleton = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI Operations settings are not initialized';
  END IF;

  IF NOT v_settings.planner_enabled THEN
    RETURN jsonb_build_object(
      'committed', false,
      'blocked', true,
      'reason', 'planner_disabled_kill_switch'
    );
  END IF;

  IF v_settings.shadow_mode THEN
    RETURN jsonb_build_object(
      'committed', false,
      'blocked', true,
      'reason', 'shadow_mode_blocks_operational_commit'
    );
  END IF;

  SELECT * INTO v_review
  FROM ai_ops.decision_reviews
  WHERE decision_id = p_decision_id;

  IF NOT FOUND OR v_review.review_state <> 'approved' THEN
    RETURN jsonb_build_object(
      'committed', false,
      'blocked', true,
      'reason', 'human_approval_required'
    );
  END IF;

  IF v_decision.validation_state <> 'validated' THEN
    RETURN jsonb_build_object(
      'committed', false,
      'blocked', true,
      'reason', 'decision_not_validated'
    );
  END IF;

  v_fingerprint := md5(jsonb_build_object(
    'id', v_decision.id,
    'run_id', v_decision.run_id,
    'case_id', v_decision.case_id,
    'revision', v_decision.revision,
    'decision_type', v_decision.decision_type,
    'recommended_owner_user_id', v_decision.recommended_owner_user_id,
    'recommended_assignee_user_id', v_decision.recommended_assignee_user_id,
    'responsibility_basis', v_decision.responsibility_basis,
    'concise_rationale', v_decision.concise_rationale,
    'confidence', v_decision.confidence,
    'expected_outcome', v_decision.expected_outcome,
    'next_action_text', v_decision.next_action_text,
    'due_at', v_decision.due_at,
    'review_after', v_decision.review_after,
    'linked_work_item_id', v_decision.linked_work_item_id
  )::TEXT);

  IF v_review.decision_fingerprint IS DISTINCT FROM v_fingerprint
     OR v_review.decision_revision <> v_decision.revision THEN
    RETURN jsonb_build_object(
      'committed', false,
      'blocked', true,
      'reason', 'review_fingerprint_mismatch'
    );
  END IF;

  -- Revalidate current business/Work reality in the same transaction immediately
  -- before invoking the native Work mutation.
  v_issues := ai_ops.current_decision_issues(p_decision_id);
  IF jsonb_array_length(v_issues) > 0 THEN
    UPDATE ai_ops.decisions
    SET
      validation_state = 'rejected',
      commit_status = 'rejected',
      validation_detail = COALESCE(validation_detail, '{}'::JSONB) || jsonb_build_object(
        'commit_revalidation_failed', true,
        'commit_revalidation_codes', v_issues,
        'commit_revalidation_at', v_now,
        'stage_only', true
      ),
      validated_at = v_now,
      validated_by_user_id = NULL,
      updated_at = v_now
    WHERE id = p_decision_id;

    RETURN jsonb_build_object(
      'committed', false,
      'blocked', true,
      'reason', 'current_state_changed',
      'validation_codes', v_issues
    );
  END IF;

  SELECT * INTO v_snapshot
  FROM ai_ops.snapshots
  WHERE run_id = v_decision.run_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'decision snapshot missing';
  END IF;

  SELECT * INTO v_sc
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id = v_snapshot.id
    AND sc.case_id = v_decision.case_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'decision-time frozen evidence missing';
  END IF;

  -- Never accept a target Work id from the RPC. Re-derive it from immutable
  -- decision-time evidence and require it to match the staged linked_work_item_id.
  v_frozen_work_id := NULLIF(v_sc.facts->'existing_active_work'->>'work_item_id','')::UUID;

  IF v_frozen_work_id IS NULL
     OR v_decision.linked_work_item_id IS NULL
     OR v_decision.linked_work_item_id IS DISTINCT FROM v_frozen_work_id THEN
    UPDATE ai_ops.decisions
    SET
      commit_status = 'rejected',
      validation_detail = COALESCE(validation_detail, '{}'::JSONB) || jsonb_build_object(
        'escalation_target_revalidation_failed', true,
        'frozen_work_item_id', v_frozen_work_id,
        'linked_work_item_id', v_decision.linked_work_item_id,
        'stage_only', true
      ),
      updated_at = v_now
    WHERE id = p_decision_id;

    RETURN jsonb_build_object(
      'committed', false,
      'blocked', true,
      'reason', 'frozen_escalation_target_mismatch'
    );
  END IF;

  SELECT * INTO v_work
  FROM public.work_items wi
  WHERE wi.id = v_frozen_work_id
  FOR UPDATE;

  IF NOT FOUND OR v_work.status IN ('done','cancelled') THEN
    UPDATE ai_ops.decisions
    SET
      commit_status = 'rejected',
      validation_detail = COALESCE(validation_detail, '{}'::JSONB) || jsonb_build_object(
        'escalation_target_no_longer_active', true,
        'work_item_id', v_frozen_work_id,
        'stage_only', true
      ),
      updated_at = v_now
    WHERE id = p_decision_id;

    RETURN jsonb_build_object(
      'committed', false,
      'blocked', true,
      'reason', 'escalation_target_no_longer_active',
      'work_item_id', v_frozen_work_id
    );
  END IF;

  -- The reason becomes visible in Work. Never expose management-only rationale;
  -- use the employee-safe explanation or a neutral operational fallback.
  v_reason := left(
    COALESCE(
      NULLIF(btrim(v_decision.employee_safe_reason), ''),
      'تصعيد تشغيلي معتمد بعد مراجعة حالة العمل الحالية.'
    ),
    1200
  );

  -- Stable per decision+actor operation id gives exact response-loss replay while
  -- allowing a different authorized manager to retry a previously failed attempt.
  v_operation_id := md5(
    'ai_ops:escalate:' || p_decision_id::TEXT || ':' || p_approved_execution_by::TEXT
  )::UUID;

  -- Reuse the native Work command. This preserves optimistic concurrency,
  -- work_actor_can_update_item, visibility-safe target resolution, Work events,
  -- operation idempotency and the escalation overlay model.
  v_work_result := public.work_escalate(
    v_operation_id,
    v_frozen_work_id,
    v_work.state_version,
    v_reason,
    NULL
  );

  IF NOT COALESCE((v_work_result->>'ok')::BOOLEAN, false) THEN
    UPDATE ai_ops.decisions
    SET
      commit_status = 'failed',
      validation_detail = COALESCE(validation_detail, '{}'::JSONB) || jsonb_build_object(
        'work_escalation_execution_failed', true,
        'work_escalation_operation_id', v_operation_id,
        'work_escalation_response', v_work_result,
        'work_escalation_attempted_at', v_now,
        'stage_only', true
      ),
      updated_at = v_now
    WHERE id = p_decision_id;

    RETURN jsonb_build_object(
      'committed', false,
      'blocked', true,
      'reason', 'native_work_escalation_rejected',
      'work_item_id', v_frozen_work_id,
      'work_result', v_work_result
    );
  END IF;

  SELECT * INTO v_escalation
  FROM public.work_escalations e
  WHERE e.work_item_id = v_frozen_work_id
    AND e.escalated_by_user_id = p_approved_execution_by
    AND e.resolved_at IS NULL
    AND e.reason = v_reason
  ORDER BY e.escalated_at DESC, e.id DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'native Work escalation reported success without a durable escalation row';
  END IF;

  UPDATE ai_ops.decisions
  SET
    committed_work_item_id = v_frozen_work_id,
    committed_at = v_now,
    commit_status = 'committed',
    validation_detail = COALESCE(validation_detail, '{}'::JSONB) || jsonb_build_object(
      'commit_revalidated_against_current_state', true,
      'commit_revalidated_at', v_now,
      'human_review_id', v_review.id,
      'approved_execution_by', p_approved_execution_by,
      'work_escalation_id', v_escalation.id,
      'work_escalation_operation_id', v_operation_id,
      'stage_only', false
    ),
    updated_at = v_now
  WHERE id = p_decision_id;

  UPDATE ai_ops.cases
  SET
    status = 'actioned',
    updated_at = v_now,
    state_version = state_version + 1
  WHERE id = v_decision.case_id;

  -- Escalation changes an existing Work item; it must not inflate work_created_count.
  UPDATE ai_ops.planner_runs
  SET
    checkpoint = 'reviewed_escalation_committed',
    result_summary = result_summary || jsonb_build_object(
      'last_committed_decision_id', v_decision.id,
      'last_committed_work_item_id', v_frozen_work_id,
      'last_committed_escalation_id', v_escalation.id,
      'last_commit_at', v_now
    ),
    updated_at = v_now
  WHERE id = v_decision.run_id;

  RETURN jsonb_build_object(
    'committed', true,
    'idempotent_reuse', false,
    'decision_id', p_decision_id,
    'work_item_id', v_frozen_work_id,
    'escalation_id', v_escalation.id,
    'operational_mutation', 'work_escalation_overlay'
  );
END;
$$;

REVOKE ALL ON FUNCTION private.ai_ops_execute_reviewed_escalation(UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;

-- Preserve every existing domain-specific CREATE_WORK wrapper, then add the
-- ESCALATE branch at the canonical reviewed execution dispatcher.
ALTER FUNCTION private.work_create_ai_reviewed_task(UUID, UUID)
  RENAME TO work_create_ai_reviewed_task_pre_escalation_execution_v1;

REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_task_pre_escalation_execution_v1(UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.work_create_ai_reviewed_task(
  p_decision_id UUID,
  p_approved_execution_by UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_decision_type TEXT;
BEGIN
  SELECT d.decision_type INTO v_decision_type
  FROM ai_ops.decisions d
  WHERE d.id = p_decision_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI Operations decision not found';
  END IF;

  IF v_decision_type = 'ESCALATE' THEN
    RETURN private.ai_ops_execute_reviewed_escalation(
      p_decision_id,
      p_approved_execution_by
    );
  END IF;

  RETURN private.work_create_ai_reviewed_task_pre_escalation_execution_v1(
    p_decision_id,
    p_approved_execution_by
  );
END;
$$;

REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_task(UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;

-- ESCALATE is now a supported reviewed operational action. Keep approved
-- CREATE_WORK/ESCALATE staged until explicit execution, and treat either action
-- as committed only after its durable Work target is recorded.
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
        AND d.decision_type IN ('CREATE_WORK','ESCALATE')
        AND d.committed_work_item_id IS NULL
        AND d.commit_status NOT IN ('rejected','failed','skipped')
    )::INTEGER,
    count(*) FILTER (
      WHERE dr.review_state = 'approved'
        AND d.decision_type IN ('CREATE_WORK','ESCALATE')
        AND d.committed_work_item_id IS NULL
        AND d.commit_status IN ('rejected','failed','skipped')
    )::INTEGER,
    count(*) FILTER (
      WHERE dr.review_state = 'approved'
        AND d.decision_type IN ('CREATE_WORK','ESCALATE')
        AND d.committed_work_item_id IS NOT NULL
        AND d.commit_status = 'committed'
    )::INTEGER
  INTO
    v_total,
    v_reviewed,
    v_human_rejected,
    v_system_rejected,
    v_pending_review,
    v_pending_work_commit,
    v_blocked_work_commit,
    v_committed_work
  FROM ai_ops.decisions d
  LEFT JOIN ai_ops.decision_reviews dr ON dr.decision_id = d.id
  WHERE d.run_id = p_run_id;

  IF v_total = 0 THEN
    v_next_status := 'completed';
    v_checkpoint := 'completed_zero_cases';
    v_terminal := true;
    v_reason := 'zero_cases_is_valid_success';
  ELSIF v_settings.shadow_mode THEN
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
  ELSIF v_system_rejected > 0 OR v_blocked_work_commit > 0 THEN
    v_next_status := 'partial';
    v_checkpoint := CASE
      WHEN v_blocked_work_commit > 0 THEN 'review_complete_work_commit_blocked'
      ELSE 'review_complete_with_stale_decisions'
    END;
    v_terminal := true;
    v_reason := CASE
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
      'unsupported_execution_decisions', 0,
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
    'unsupported_execution_decisions', 0
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.refresh_run_terminal_state(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION ai_ops.refresh_run_terminal_state(UUID) IS
  'Deterministic reviewed-action lifecycle resolver. CREATE_WORK and ESCALATE remain staged until explicit safe execution; zero-case/shadow complete and stale/blocked actions become partial.';

-- Rebind the public commit gateway explicitly so its effective runtime path cannot
-- depend on historical function OIDs from earlier wrapper renames.
ALTER FUNCTION public.ai_ops_commit_reviewed_decision(UUID)
  RENAME TO ai_ops_commit_reviewed_decision_pre_escalation_execution_v1;

REVOKE ALL ON FUNCTION public.ai_ops_commit_reviewed_decision_pre_escalation_execution_v1(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ai_ops_commit_reviewed_decision(p_decision_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_result JSONB;
  v_run_id UUID;
  v_lifecycle JSONB;
BEGIN
  IF v_actor IS NULL OR NOT private.work_actor_is_active(v_actor) THEN
    RAISE EXCEPTION 'المستخدم غير متاح لتنفيذ قرار AI Operations'
      USING ERRCODE = '42501';
  END IF;

  IF NOT COALESCE(public.check_permission(v_actor, 'work.policies.manage'), false) THEN
    RAISE EXCEPTION 'لا تملك صلاحية تنفيذ قرارات التشغيل الذكي'
      USING ERRCODE = '42501';
  END IF;

  v_result := private.work_create_ai_reviewed_task(p_decision_id, v_actor);

  SELECT d.run_id INTO v_run_id
  FROM ai_ops.decisions d
  WHERE d.id = p_decision_id;

  IF v_run_id IS NOT NULL THEN
    v_lifecycle := ai_ops.refresh_run_terminal_state(v_run_id);
  END IF;

  RETURN v_result || jsonb_build_object(
    'run_lifecycle', COALESCE(v_lifecycle, '{}'::JSONB)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) TO service_role;

COMMENT ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) IS
  'Explicit human-approved AI Operations execution gateway. Revalidates current reality and dispatches CREATE_WORK or native Work ESCALATE; no autonomous execution.';

RESET lock_timeout;
RESET statement_timeout;
