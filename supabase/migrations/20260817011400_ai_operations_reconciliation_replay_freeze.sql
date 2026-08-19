-- ============================================================================
-- AI Operations — freeze reconciliation result for exact context replay
--
-- Reconciliation is idempotent in state, but its counters naturally differ on a
-- second call after the first call already resolved/reopened Cases. Model input
-- identity must not differ across recovery attempts for the same snapshot, so
-- the first reconciliation result is frozen and replayed thereafter.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE TABLE ai_ops.snapshot_reconciliation (
  snapshot_id UUID PRIMARY KEY REFERENCES ai_ops.snapshots(id) ON DELETE RESTRICT,
  run_id UUID NOT NULL UNIQUE REFERENCES ai_ops.planner_runs(id) ON DELETE RESTRICT,
  payload_version TEXT NOT NULL DEFAULT 'reconciliation-v1',
  payload JSONB NOT NULL,
  payload_bytes INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ai_ops_snapshot_reconciliation_version_not_blank CHECK (btrim(payload_version)<>''),
  CONSTRAINT ai_ops_snapshot_reconciliation_payload_object CHECK (jsonb_typeof(payload)='object'),
  CONSTRAINT ai_ops_snapshot_reconciliation_bytes_positive CHECK (payload_bytes>0)
);
ALTER TABLE ai_ops.snapshot_reconciliation ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE ai_ops.snapshot_reconciliation FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.reject_snapshot_reconciliation_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'AI snapshot reconciliation evidence is immutable';
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.reject_snapshot_reconciliation_mutation()
  FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER trg_ai_ops_snapshot_reconciliation_immutable
  BEFORE UPDATE OR DELETE ON ai_ops.snapshot_reconciliation
  FOR EACH ROW EXECUTE FUNCTION ai_ops.reject_snapshot_reconciliation_mutation();

CREATE OR REPLACE FUNCTION ai_ops.capture_snapshot_reconciliation(
  p_snapshot_id UUID,
  p_run_id UUID,
  p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_existing ai_ops.snapshot_reconciliation%ROWTYPE;
  v_payload JSONB:=COALESCE(p_payload,'{}'::JSONB);
  v_bytes INTEGER;
BEGIN
  IF jsonb_typeof(v_payload)<>'object' THEN
    RAISE EXCEPTION 'snapshot reconciliation payload must be an object';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('ai_ops:reconciliation-freeze:'||p_snapshot_id::TEXT,0));

  SELECT * INTO v_existing
  FROM ai_ops.snapshot_reconciliation
  WHERE snapshot_id=p_snapshot_id;
  IF FOUND THEN
    IF v_existing.run_id IS DISTINCT FROM p_run_id THEN
      RAISE EXCEPTION 'snapshot reconciliation run binding mismatch';
    END IF;
    RETURN v_existing.payload;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM ai_ops.snapshots s
    WHERE s.id=p_snapshot_id AND s.run_id=p_run_id
  ) THEN
    RAISE EXCEPTION 'snapshot/run binding is invalid for reconciliation freeze';
  END IF;

  v_bytes:=octet_length(convert_to(v_payload::TEXT,'UTF8'));
  INSERT INTO ai_ops.snapshot_reconciliation(
    snapshot_id,run_id,payload_version,payload,payload_bytes
  ) VALUES (
    p_snapshot_id,p_run_id,'reconciliation-v1',v_payload,v_bytes
  ) RETURNING * INTO v_existing;

  RETURN v_existing.payload;
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.capture_snapshot_reconciliation(UUID,UUID,JSONB)
  FROM PUBLIC,anon,authenticated,service_role;

ALTER FUNCTION public.ai_ops_worker_get_context(UUID,TEXT)
  RENAME TO ai_ops_worker_get_context_pre_reconciliation_freeze_v1;
REVOKE ALL ON FUNCTION public.ai_ops_worker_get_context_pre_reconciliation_freeze_v1(UUID,TEXT)
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
  v_reconciliation JSONB;
  v_settings ai_ops.settings%ROWTYPE;
  v_bytes INTEGER;
  v_hash TEXT;
  v_now TIMESTAMPTZ:=clock_timestamp();
BEGIN
  v_result:=public.ai_ops_worker_get_context_pre_reconciliation_freeze_v1(p_run_id,p_worker_id);
  IF COALESCE((v_result->>'blocked')::BOOLEAN,false) THEN RETURN v_result; END IF;

  v_context:=v_result->'context';
  v_snapshot_id:=NULLIF(v_context->'snapshot'->>'snapshot_id','')::UUID;
  IF v_snapshot_id IS NULL THEN RAISE EXCEPTION 'worker context snapshot id is missing'; END IF;

  v_reconciliation:=ai_ops.capture_snapshot_reconciliation(
    v_snapshot_id,p_run_id,COALESCE(v_context->'reconciliation','{}'::JSONB)
  );
  v_context:=jsonb_set(v_context,'{reconciliation}',v_reconciliation,true);

  SELECT * INTO v_settings FROM ai_ops.settings WHERE singleton=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations settings are not initialized'; END IF;

  v_bytes:=octet_length(convert_to(v_context::TEXT,'UTF8'));
  IF v_bytes>v_settings.max_worker_context_bytes THEN
    UPDATE ai_ops.planner_runs
    SET
      status='partial',checkpoint='context_budget_blocked_after_reconciliation_freeze',
      lease_expires_at=NULL,completed_at=v_now,error_class='context_budget_exceeded',
      error_message=format('replay-frozen worker context %s bytes exceeds limit %s',v_bytes,v_settings.max_worker_context_bytes),
      result_summary=result_summary||jsonb_build_object(
        'replay_frozen_context_bytes',v_bytes,
        'worker_context_limit_bytes',v_settings.max_worker_context_bytes,
        'reconciliation_frozen',true
      ),updated_at=v_now
    WHERE id=p_run_id;
    RETURN jsonb_build_object(
      'blocked',true,'reason','context_budget_exceeded_after_reconciliation_freeze',
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
      'reconciliation_frozen',true,
      'reconciliation_payload_version','reconciliation-v1'
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
  'Final service-only worker context with immutable reconciliation replay evidence. Repeated recovery attempts for the same snapshot receive the same reconciliation payload and final context identity.';

RESET lock_timeout;
RESET statement_timeout;
