-- ============================================================================
-- AI Operations — freeze enriched global planner context for exact replay.
--
-- The previous closure builder is deterministic for frozen Cases but also
-- incorporates recent feedback/outcomes. This layer persists that exact result
-- once per snapshot so later database changes cannot alter historical model input.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE TABLE ai_ops.snapshot_global_context (
  snapshot_id UUID PRIMARY KEY REFERENCES ai_ops.snapshots(id) ON DELETE RESTRICT,
  run_id UUID NOT NULL UNIQUE REFERENCES ai_ops.planner_runs(id) ON DELETE RESTRICT,
  payload_version TEXT NOT NULL DEFAULT 'global-planning-v1',
  payload JSONB NOT NULL,
  payload_bytes INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ai_ops_snapshot_global_context_version_not_blank CHECK (btrim(payload_version) <> ''),
  CONSTRAINT ai_ops_snapshot_global_context_payload_object CHECK (jsonb_typeof(payload) = 'object'),
  CONSTRAINT ai_ops_snapshot_global_context_bytes_positive CHECK (payload_bytes > 0)
);
ALTER TABLE ai_ops.snapshot_global_context ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE ai_ops.snapshot_global_context FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION ai_ops.reject_snapshot_global_context_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'AI snapshot global context is immutable';
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.reject_snapshot_global_context_mutation() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER trg_ai_ops_snapshot_global_context_immutable
  BEFORE UPDATE OR DELETE ON ai_ops.snapshot_global_context
  FOR EACH ROW EXECUTE FUNCTION ai_ops.reject_snapshot_global_context_mutation();

CREATE OR REPLACE FUNCTION ai_ops.capture_global_operational_context(
  p_snapshot_id UUID,
  p_run_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_existing ai_ops.snapshot_global_context%ROWTYPE;
  v_payload JSONB;
  v_bytes INTEGER;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('ai_ops:global-context:'||p_snapshot_id::TEXT,0));

  SELECT * INTO v_existing
  FROM ai_ops.snapshot_global_context
  WHERE snapshot_id=p_snapshot_id;
  IF FOUND THEN
    IF v_existing.run_id IS DISTINCT FROM p_run_id THEN
      RAISE EXCEPTION 'snapshot global context run binding mismatch';
    END IF;
    RETURN v_existing.payload;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM ai_ops.snapshots s
    WHERE s.id=p_snapshot_id AND s.run_id=p_run_id
  ) THEN
    RAISE EXCEPTION 'snapshot/run binding is invalid for global context capture';
  END IF;

  v_payload := ai_ops.build_global_operational_context(p_snapshot_id,p_run_id);
  v_bytes := octet_length(convert_to(v_payload::TEXT,'UTF8'));

  INSERT INTO ai_ops.snapshot_global_context(
    snapshot_id,run_id,payload_version,payload,payload_bytes
  ) VALUES (
    p_snapshot_id,p_run_id,'global-planning-v1',v_payload,v_bytes
  ) RETURNING * INTO v_existing;

  RETURN v_existing.payload;
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.capture_global_operational_context(UUID,UUID)
  FROM PUBLIC, anon, authenticated, service_role;

-- Replace the final service gateway so the global context delivered to the model
-- is always the immutable snapshot copy. The final context/prompt hashes remain
-- the staging identity and audit source of truth.
CREATE OR REPLACE FUNCTION public.ai_ops_worker_get_context(
  p_run_id UUID,
  p_worker_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_result JSONB;
  v_context JSONB;
  v_run ai_ops.planner_runs%ROWTYPE;
  v_settings ai_ops.settings%ROWTYPE;
  v_policy ai_ops.planner_policies%ROWTYPE;
  v_snapshot_id UUID;
  v_reconciliation JSONB;
  v_global JSONB;
  v_hash TEXT;
  v_bytes INTEGER;
  v_now TIMESTAMPTZ := clock_timestamp();
BEGIN
  v_result := public.ai_ops_worker_get_context_pre_policy_closure_v1(p_run_id,p_worker_id);
  IF COALESCE((v_result->>'blocked')::BOOLEAN,false) THEN RETURN v_result; END IF;

  SELECT * INTO v_run FROM ai_ops.planner_runs WHERE id=p_run_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'planner run missing after worker context build'; END IF;
  SELECT * INTO v_settings FROM ai_ops.settings WHERE singleton=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations settings are not initialized'; END IF;

  SELECT * INTO v_policy
  FROM ai_ops.planner_policies p
  WHERE p.policy_version=v_run.planner_policy_version
    AND p.prompt_version=v_run.prompt_version
    AND p.enabled=true;
  IF NOT FOUND THEN
    UPDATE ai_ops.planner_runs
    SET status='partial',checkpoint='planner_policy_missing',lease_expires_at=NULL,
        completed_at=v_now,error_class='planner_policy_missing',
        error_message='No enabled planner policy matches frozen run policy/prompt versions',updated_at=v_now
    WHERE id=p_run_id;
    RETURN jsonb_build_object(
      'blocked',true,'reason','planner_policy_missing','run_id',p_run_id,
      'planner_policy_version',v_run.planner_policy_version,'prompt_version',v_run.prompt_version
    );
  END IF;
  IF v_policy.prompt_hash IS DISTINCT FROM md5(v_policy.system_prompt) THEN
    RAISE EXCEPTION 'planner policy prompt hash mismatch';
  END IF;

  SELECT s.id INTO v_snapshot_id FROM ai_ops.snapshots s WHERE s.run_id=p_run_id;
  IF v_snapshot_id IS NULL THEN RAISE EXCEPTION 'worker snapshot missing after context build'; END IF;

  v_reconciliation := ai_ops.reconcile_cases_from_snapshot(v_snapshot_id);
  v_global := ai_ops.capture_global_operational_context(v_snapshot_id,p_run_id);
  v_context := v_result->'context';
  v_context := jsonb_set(v_context,'{planner_policy}',jsonb_build_object(
    'policy_version',v_policy.policy_version,
    'prompt_version',v_policy.prompt_version,
    'prompt_hash',v_policy.prompt_hash,
    'system_prompt',v_policy.system_prompt,
    'methodology',v_policy.methodology
  ),true);
  v_context := jsonb_set(v_context,'{global_operational_context}',v_global,true);
  v_context := jsonb_set(v_context,'{reconciliation}',v_reconciliation,true);

  v_bytes := octet_length(convert_to(v_context::TEXT,'UTF8'));
  IF v_bytes>v_settings.max_worker_context_bytes THEN
    UPDATE ai_ops.planner_runs
    SET status='partial',checkpoint='context_budget_blocked_after_policy',lease_expires_at=NULL,
        completed_at=v_now,error_class='context_budget_exceeded',
        error_message=format('enriched worker context %s bytes exceeds limit %s',v_bytes,v_settings.max_worker_context_bytes),
        result_summary=result_summary||jsonb_build_object(
          'enriched_worker_context_bytes',v_bytes,
          'worker_context_limit_bytes',v_settings.max_worker_context_bytes,
          'planner_prompt_hash',v_policy.prompt_hash,
          'global_context_frozen',true
        ),updated_at=v_now
    WHERE id=p_run_id;
    RETURN jsonb_build_object(
      'blocked',true,'reason','context_budget_exceeded_after_policy','run_id',p_run_id,
      'context_bytes',v_bytes,'context_limit_bytes',v_settings.max_worker_context_bytes
    );
  END IF;

  v_hash:=md5(v_context::TEXT);
  UPDATE ai_ops.planner_runs
  SET prompt_hash=v_policy.prompt_hash,
      result_summary=result_summary||jsonb_build_object(
        'worker_context_hash',v_hash,
        'worker_context_hash_algorithm','md5-jsonb-identity',
        'worker_context_bytes',v_bytes,
        'planner_prompt_hash',v_policy.prompt_hash,
        'planner_policy_version_runtime',v_policy.policy_version,
        'prompt_version_runtime',v_policy.prompt_version,
        'global_operational_context',true,
        'global_context_frozen',true,
        'global_context_payload_version','global-planning-v1',
        'outcome_reconciliation',v_reconciliation
      ),updated_at=v_now
  WHERE id=p_run_id;

  RETURN jsonb_build_object(
    'blocked',false,'context_hash',v_hash,'context_hash_algorithm','md5-jsonb-identity',
    'context_bytes',v_bytes,'context_limit_bytes',v_settings.max_worker_context_bytes,
    'prompt_hash',v_policy.prompt_hash,'planner_policy_version',v_policy.policy_version,
    'prompt_version',v_policy.prompt_version,'context',v_context
  );
END;
$$;
REVOKE ALL ON FUNCTION public.ai_ops_worker_get_context(UUID,TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ai_ops_worker_get_context(UUID,TEXT) TO service_role;

RESET lock_timeout;
RESET statement_timeout;
