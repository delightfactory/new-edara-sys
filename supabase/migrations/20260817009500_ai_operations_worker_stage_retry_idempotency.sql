-- ============================================================================
-- AI Operations Planner — Decision Staging Retry Idempotency
--
-- DESIGN-TIME MIGRATION ONLY.
-- A successful worker_stage_decisions call transitions the run to `staged` and
-- clears its lease. If the database commit succeeds but the response is lost,
-- an exact retry previously failed the `reasoning + live lease` guard before
-- reaching the existing submission-hash idempotency branch.
--
-- Permit only an exact replay of the already-staged immutable submission by the
-- same claimed worker/context. Any changed payload still fails closed.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

ALTER FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB)
  RENAME TO worker_stage_decisions_pre_retry_idempotency_v1;
REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions_pre_retry_idempotency_v1(UUID,TEXT,TEXT,JSONB)
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
  v_existing_count INTEGER;
  v_existing_hashes INTEGER;
  v_snapshot_case_count INTEGER;
  v_action_count INTEGER;
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

  -- Normal first submission and any still-live reasoning path retain every
  -- existing validation by delegating to the previously canonical wrapper.
  IF v_run.status<>'staged' THEN
    RETURN ai_ops.worker_stage_decisions_pre_retry_idempotency_v1(
      p_run_id,p_worker_id,p_context_hash,p_decisions
    );
  END IF;

  -- `staged` is immutable from the worker's perspective. The only accepted
  -- operation is an exact acknowledgement replay of the already committed set.
  IF p_worker_id IS NULL OR btrim(p_worker_id)='' OR length(p_worker_id)>120
     OR v_run.claimed_by IS DISTINCT FROM p_worker_id THEN
    RAISE EXCEPTION 'staged retry worker identity does not match the run claimant';
  END IF;

  IF NULLIF(p_context_hash,'') IS NULL
     OR v_run.result_summary->>'worker_context_hash' IS DISTINCT FROM p_context_hash THEN
    RAISE EXCEPTION 'staged retry context hash does not match the frozen run context';
  END IF;

  SELECT s.id INTO v_snapshot_id
  FROM ai_ops.snapshots s
  WHERE s.run_id=p_run_id;
  IF v_snapshot_id IS NULL
     OR NOT ai_ops.snapshot_has_required_domain_captures(v_snapshot_id) THEN
    RAISE EXCEPTION 'staged retry is missing one or more required operational domain captures';
  END IF;

  v_submission_hash:=md5(p_decisions::TEXT);
  IF NULLIF(v_run.result_summary->>'worker_submission_hash','') IS DISTINCT FROM v_submission_hash THEN
    RAISE EXCEPTION 'run already contains a different staged decision submission';
  END IF;

  v_decision_count:=jsonb_array_length(p_decisions);
  SELECT count(*)::INTEGER INTO v_snapshot_case_count
  FROM ai_ops.snapshot_cases sc
  WHERE sc.snapshot_id=v_snapshot_id;

  SELECT count(*)::INTEGER,
         count(DISTINCT d.management_only_metadata->>'worker_submission_hash')::INTEGER,
         count(*) FILTER (WHERE d.decision_type IN ('CREATE_WORK','ESCALATE'))::INTEGER
  INTO v_existing_count,v_existing_hashes,v_action_count
  FROM ai_ops.decisions d
  WHERE d.run_id=p_run_id;

  IF v_decision_count<>v_snapshot_case_count
     OR v_existing_count<>v_decision_count
     OR v_existing_hashes<>1
     OR EXISTS (
       SELECT 1
       FROM ai_ops.decisions d
       WHERE d.run_id=p_run_id
         AND d.management_only_metadata->>'worker_submission_hash' IS DISTINCT FROM v_submission_hash
     ) THEN
    RAISE EXCEPTION 'staged retry does not exactly match the persisted decision set';
  END IF;

  RETURN jsonb_build_object(
    'staged',true,
    'idempotent_reuse',true,
    'decision_count',v_existing_count,
    'action_count',v_action_count,
    'zero_action_run',v_action_count=0,
    'submission_hash',v_submission_hash,
    'retry_after_committed_stage',true
  );
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB) IS
  'Canonical staging entrypoint. Preserves full seven-domain first-submit validation and permits only exact same-worker/context/payload replay after a successfully committed staged response is lost.';

RESET lock_timeout;
RESET statement_timeout;
