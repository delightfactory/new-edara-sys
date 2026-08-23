-- ============================================================================
-- AI Operations — freeze the attempt number associated with first model context
--
-- planner_runs.attempt_no keeps changing as runtime telemetry. The model context
-- carries the attempt number from the FIRST successful context construction and
-- replays that frozen value thereafter. This preserves the existing typed field
-- without allowing recovery mechanics to perturb model input identity.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE TABLE ai_ops.snapshot_context_runtime_metadata (
  snapshot_id UUID PRIMARY KEY REFERENCES ai_ops.snapshots(id) ON DELETE RESTRICT,
  run_id UUID NOT NULL UNIQUE REFERENCES ai_ops.planner_runs(id) ON DELETE RESTRICT,
  first_context_attempt_no INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ai_ops_snapshot_context_attempt_positive CHECK (first_context_attempt_no>0)
);
ALTER TABLE ai_ops.snapshot_context_runtime_metadata ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE ai_ops.snapshot_context_runtime_metadata FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.reject_snapshot_context_runtime_metadata_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'AI snapshot runtime context metadata is immutable';
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.reject_snapshot_context_runtime_metadata_mutation()
  FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER trg_ai_ops_snapshot_context_runtime_metadata_immutable
  BEFORE UPDATE OR DELETE ON ai_ops.snapshot_context_runtime_metadata
  FOR EACH ROW EXECUTE FUNCTION ai_ops.reject_snapshot_context_runtime_metadata_mutation();

CREATE OR REPLACE FUNCTION ai_ops.capture_first_context_attempt(
  p_snapshot_id UUID,
  p_run_id UUID,
  p_attempt_no INTEGER
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_row ai_ops.snapshot_context_runtime_metadata%ROWTYPE;
BEGIN
  IF COALESCE(p_attempt_no,0)<=0 THEN
    RAISE EXCEPTION 'context attempt number must be positive';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('ai_ops:context-attempt-freeze:'||p_snapshot_id::TEXT,0));

  SELECT * INTO v_row
  FROM ai_ops.snapshot_context_runtime_metadata
  WHERE snapshot_id=p_snapshot_id;
  IF FOUND THEN
    IF v_row.run_id IS DISTINCT FROM p_run_id THEN
      RAISE EXCEPTION 'snapshot context attempt run binding mismatch';
    END IF;
    RETURN v_row.first_context_attempt_no;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM ai_ops.snapshots s
    WHERE s.id=p_snapshot_id AND s.run_id=p_run_id
  ) THEN
    RAISE EXCEPTION 'snapshot/run binding is invalid for context attempt freeze';
  END IF;

  INSERT INTO ai_ops.snapshot_context_runtime_metadata(
    snapshot_id,run_id,first_context_attempt_no
  ) VALUES (p_snapshot_id,p_run_id,p_attempt_no)
  RETURNING * INTO v_row;

  RETURN v_row.first_context_attempt_no;
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.capture_first_context_attempt(UUID,UUID,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

ALTER FUNCTION public.ai_ops_worker_get_context(UUID,TEXT)
  RENAME TO ai_ops_worker_get_context_pre_attempt_freeze_v1;
REVOKE ALL ON FUNCTION public.ai_ops_worker_get_context_pre_attempt_freeze_v1(UUID,TEXT)
  FROM PUBLIC,anon,authenticated,service_role;

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
  v_snapshot_id UUID;
  v_run ai_ops.planner_runs%ROWTYPE;
  v_frozen_attempt INTEGER;
  v_settings ai_ops.settings%ROWTYPE;
  v_bytes INTEGER;
  v_hash TEXT;
  v_now TIMESTAMPTZ:=clock_timestamp();
BEGIN
  v_result:=public.ai_ops_worker_get_context_pre_attempt_freeze_v1(p_run_id,p_worker_id);
  IF COALESCE((v_result->>'blocked')::BOOLEAN,false) THEN RETURN v_result; END IF;

  v_context:=v_result->'context';
  v_snapshot_id:=NULLIF(v_context->'snapshot'->>'snapshot_id','')::UUID;
  IF v_snapshot_id IS NULL THEN RAISE EXCEPTION 'worker context snapshot id is missing'; END IF;

  SELECT * INTO v_run FROM ai_ops.planner_runs WHERE id=p_run_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations run not found'; END IF;

  v_frozen_attempt:=ai_ops.capture_first_context_attempt(
    v_snapshot_id,p_run_id,v_run.attempt_no
  );
  v_context:=jsonb_set(v_context,'{run,attempt_no}',to_jsonb(v_frozen_attempt),true);
  v_context:=jsonb_set(
    v_context,'{run,recovery_semantics}',
    to_jsonb('attempt_no_is_first_context_attempt_and_is_frozen_for_replay'::TEXT),true
  );

  SELECT * INTO v_settings FROM ai_ops.settings WHERE singleton=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations settings are not initialized'; END IF;

  v_bytes:=octet_length(convert_to(v_context::TEXT,'UTF8'));
  IF v_bytes>v_settings.max_worker_context_bytes THEN
    UPDATE ai_ops.planner_runs
    SET
      status='partial',checkpoint='context_budget_blocked_after_attempt_freeze',
      lease_expires_at=NULL,completed_at=v_now,error_class='context_budget_exceeded',
      error_message=format('attempt-frozen worker context %s bytes exceeds limit %s',v_bytes,v_settings.max_worker_context_bytes),
      result_summary=result_summary||jsonb_build_object(
        'attempt_frozen_context_bytes',v_bytes,
        'worker_context_limit_bytes',v_settings.max_worker_context_bytes,
        'first_context_attempt_no',v_frozen_attempt
      ),updated_at=v_now
    WHERE id=p_run_id;
    RETURN jsonb_build_object(
      'blocked',true,'reason','context_budget_exceeded_after_attempt_freeze',
      'run_id',p_run_id,'snapshot_id',v_snapshot_id,
      'context_bytes',v_bytes,'context_limit_bytes',v_settings.max_worker_context_bytes
    );
  END IF;

  v_hash:=md5(v_context::TEXT);
  UPDATE ai_ops.planner_runs
  SET
    result_summary=result_summary||jsonb_build_object(
      'worker_context_hash',v_hash,
      'worker_context_hash_algorithm','md5-jsonb-identity',
      'worker_context_bytes',v_bytes,
      'first_context_attempt_no',v_frozen_attempt,
      'attempt_metadata_frozen_for_replay',true
    ),updated_at=v_now
  WHERE id=p_run_id;

  RETURN v_result||jsonb_build_object(
    'context_hash',v_hash,
    'context_bytes',v_bytes,
    'context',v_context
  );
END;
$$;
REVOKE ALL ON FUNCTION public.ai_ops_worker_get_context(UUID,TEXT)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ai_ops_worker_get_context(UUID,TEXT) TO service_role;

COMMENT ON FUNCTION public.ai_ops_worker_get_context(UUID,TEXT) IS
  'Final service-only model context with frozen first-context attempt metadata. Runtime retries remain observable in planner_runs but cannot alter otherwise identical model input.';

RESET lock_timeout;
RESET statement_timeout;
