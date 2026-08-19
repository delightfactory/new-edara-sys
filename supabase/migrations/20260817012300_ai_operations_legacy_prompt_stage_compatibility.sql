-- ============================================================================
-- AI Operations — legacy prompt-v1 staging compatibility
--
-- AI Operations has not been released to production, but an incremental local
-- development database may contain a pending/recoverable v1 run created before
-- structured quality existed. Such a run must be recoverable under its original
-- frozen contract. v2/v3 keep the strict structured-quality staging path.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

ALTER FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB)
  RENAME TO worker_stage_decisions_structured_quality_v1;
REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions_structured_quality_v1(UUID,TEXT,TEXT,JSONB)
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
  v_result JSONB;
BEGIN
  SELECT * INTO v_run
  FROM ai_ops.planner_runs r
  WHERE r.id=p_run_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'planner run not found'; END IF;

  IF v_run.prompt_version='v1' THEN
    -- Exact original core contract and lifecycle. Do not fabricate quality fields
    -- that the frozen v1 prompt never requested.
    v_result:=ai_ops.worker_stage_decisions_pre_structured_quality_v1(
      p_run_id,p_worker_id,p_context_hash,p_decisions
    );
    RETURN v_result||jsonb_build_object(
      'structured_decision_quality',false,
      'quality_contract','legacy_prompt_v1',
      'legacy_contract_preserved',true
    );
  END IF;

  RETURN ai_ops.worker_stage_decisions_structured_quality_v1(
    p_run_id,p_worker_id,p_context_hash,p_decisions
  );
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB) IS
  'Final internal staging dispatcher. Frozen prompt-v1 runs retain their original core contract; v2/v3 use exact structured-quality staging and retry hashes.';

RESET lock_timeout;
RESET statement_timeout;
