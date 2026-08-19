-- ============================================================================
-- AI Operations Planner — Restore Run Lifecycle After Multi-Domain Staging
--
-- DESIGN-TIME MIGRATION ONLY.
-- Later multi-domain staging wrappers replaced the original run-finalization
-- wrapper. Restore terminal-state refresh without regressing response-loss
-- idempotency: staged/terminal exact retries remain read-only acknowledgements,
-- while the first reasoning submission is delegated to every existing guard.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

ALTER FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB)
  RENAME TO worker_stage_decisions_pre_lifecycle_restore_v1;
REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions_pre_lifecycle_restore_v1(UUID,TEXT,TEXT,JSONB)
  FROM PUBLIC,anon,authenticated,service_role;

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
  v_run ai_ops.planner_runs%ROWTYPE;
  v_snapshot_id UUID;
  v_submission_hash TEXT;
  v_decision_count INTEGER;
  v_snapshot_case_count INTEGER;
  v_existing_count INTEGER;
  v_existing_hashes INTEGER;
  v_action_count INTEGER;
  v_result JSONB;
  v_lifecycle JSONB;
BEGIN
  IF jsonb_typeof(p_decisions)<>'array' THEN
    RAISE EXCEPTION 'decisions payload must be a JSON array';
  END IF;

  SELECT * INTO v_run
  FROM ai_ops.planner_runs
  WHERE id=p_run_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'planner run not found';
  END IF;

  -- The live first-submission path retains every current seven-domain, lease,
  -- context, action-budget and payload validation in the preserved implementation.
  IF v_run.status NOT IN ('staged','completed','partial') THEN
    v_result:=ai_ops.worker_stage_decisions_pre_lifecycle_restore_v1(
      p_run_id,p_worker_id,p_context_hash,p_decisions
    );
    v_lifecycle:=ai_ops.refresh_run_terminal_state(p_run_id);
    RETURN v_result||jsonb_build_object('run_lifecycle',v_lifecycle);
  END IF;

  -- Once a submission is durable, the worker may only replay the exact frozen
  -- acknowledgement. This also covers response loss after lifecycle refresh has
  -- already changed staged -> completed/partial (including zero-case/shadow runs).
  IF p_worker_id IS NULL OR btrim(p_worker_id)='' OR length(p_worker_id)>120
     OR v_run.claimed_by IS DISTINCT FROM p_worker_id THEN
    RAISE EXCEPTION 'staging retry worker identity does not match the run claimant';
  END IF;

  IF NULLIF(p_context_hash,'') IS NULL
     OR v_run.result_summary->>'worker_context_hash' IS DISTINCT FROM p_context_hash THEN
    RAISE EXCEPTION 'staging retry context hash does not match the frozen run context';
  END IF;

  SELECT s.id INTO v_snapshot_id
  FROM ai_ops.snapshots s
  WHERE s.run_id=p_run_id;
  IF v_snapshot_id IS NULL
     OR NOT ai_ops.snapshot_has_required_domain_captures(v_snapshot_id) THEN
    RAISE EXCEPTION 'staging retry is missing one or more required operational domain captures';
  END IF;

  v_submission_hash:=md5(p_decisions::TEXT);
  IF NULLIF(v_run.result_summary->>'worker_submission_hash','') IS DISTINCT FROM v_submission_hash THEN
    RAISE EXCEPTION 'run already contains a different staged decision submission';
  END IF;

  v_decision_count:=jsonb_array_length(p_decisions);
  SELECT count(*)::INTEGER INTO v_snapshot_case_count
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id=v_snapshot_id;

  SELECT
    count(*)::INTEGER,
    count(DISTINCT d.management_only_metadata->>'worker_submission_hash')::INTEGER,
    count(*) FILTER (WHERE d.decision_type IN ('CREATE_WORK','ESCALATE'))::INTEGER
  INTO v_existing_count,v_existing_hashes,v_action_count
  FROM ai_ops.decisions d
  WHERE d.run_id=p_run_id;

  IF v_decision_count<>v_snapshot_case_count
     OR v_existing_count<>v_decision_count
     OR (v_decision_count>0 AND v_existing_hashes<>1)
     OR (v_decision_count=0 AND v_existing_hashes<>0)
     OR EXISTS (
       SELECT 1
       FROM ai_ops.decisions d
       WHERE d.run_id=p_run_id
         AND (
           d.management_only_metadata->>'worker_submission_hash' IS DISTINCT FROM v_submission_hash
           OR d.management_only_metadata->>'worker_context_hash' IS DISTINCT FROM p_context_hash
           OR d.management_only_metadata->>'worker_id' IS DISTINCT FROM p_worker_id
         )
     ) THEN
    RAISE EXCEPTION 'staging retry does not exactly match the persisted decision set';
  END IF;

  -- Re-run the deterministic lifecycle resolver for legacy staged rows. For an
  -- already terminal run it deliberately returns changed=false and mutates nothing.
  v_lifecycle:=ai_ops.refresh_run_terminal_state(p_run_id);

  RETURN jsonb_build_object(
    'staged',true,
    'idempotent_reuse',true,
    'decision_count',v_existing_count,
    'action_count',v_action_count,
    'zero_action_run',v_action_count=0,
    'submission_hash',v_submission_hash,
    'retry_after_durable_stage',true,
    'run_lifecycle',v_lifecycle
  );
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB) IS
  'Canonical seven-domain staging entrypoint with restored run lifecycle closure and exact response-loss retry across staged/completed/partial outcomes.';

RESET lock_timeout;
RESET statement_timeout;
