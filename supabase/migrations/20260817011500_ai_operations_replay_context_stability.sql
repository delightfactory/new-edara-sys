-- ============================================================================
-- AI Operations — final model-context stability across recovery attempts
--
-- planner_runs.attempt_no is valuable runtime telemetry but changes on every
-- lease recovery. It is not business evidence and must not perturb the model
-- input/hash for an otherwise identical frozen snapshot. Keep it in the run
-- ledger, exclude it only from the final model context.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '60s';

ALTER FUNCTION public.ai_ops_worker_get_context(UUID,TEXT)
  RENAME TO ai_ops_worker_get_context_pre_replay_stability_v1;
REVOKE ALL ON FUNCTION public.ai_ops_worker_get_context_pre_replay_stability_v1(UUID,TEXT)
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
  v_settings ai_ops.settings%ROWTYPE;
  v_bytes INTEGER;
  v_hash TEXT;
  v_now TIMESTAMPTZ:=clock_timestamp();
BEGIN
  v_result:=public.ai_ops_worker_get_context_pre_replay_stability_v1(p_run_id,p_worker_id);
  IF COALESCE((v_result->>'blocked')::BOOLEAN,false) THEN RETURN v_result; END IF;

  v_context:=v_result->'context';
  v_context:=v_context #- '{run,attempt_no}';
  v_context:=jsonb_set(
    v_context,
    '{run,recovery_semantics}',
    to_jsonb('volatile_attempt_metadata_excluded_from_model_input'::TEXT),
    true
  );

  SELECT * INTO v_settings FROM ai_ops.settings WHERE singleton=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations settings are not initialized'; END IF;

  v_bytes:=octet_length(convert_to(v_context::TEXT,'UTF8'));
  IF v_bytes>v_settings.max_worker_context_bytes THEN
    UPDATE ai_ops.planner_runs
    SET
      status='partial',checkpoint='context_budget_blocked_after_replay_stability',
      lease_expires_at=NULL,completed_at=v_now,error_class='context_budget_exceeded',
      error_message=format('stable replay worker context %s bytes exceeds limit %s',v_bytes,v_settings.max_worker_context_bytes),
      result_summary=result_summary||jsonb_build_object(
        'stable_replay_context_bytes',v_bytes,
        'worker_context_limit_bytes',v_settings.max_worker_context_bytes,
        'volatile_attempt_metadata_excluded',true
      ),updated_at=v_now
    WHERE id=p_run_id;
    RETURN jsonb_build_object(
      'blocked',true,'reason','context_budget_exceeded_after_replay_stability',
      'run_id',p_run_id,'context_bytes',v_bytes,'context_limit_bytes',v_settings.max_worker_context_bytes
    );
  END IF;

  v_hash:=md5(v_context::TEXT);
  UPDATE ai_ops.planner_runs
  SET
    result_summary=result_summary||jsonb_build_object(
      'worker_context_hash',v_hash,
      'worker_context_hash_algorithm','md5-jsonb-identity',
      'worker_context_bytes',v_bytes,
      'volatile_attempt_metadata_excluded',true,
      'replay_context_stable_under_unchanged_policy_and_settings',true
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
  'Final service-only model context. Excludes volatile attempt_no while retaining it in planner_runs, so recovery telemetry cannot perturb otherwise identical frozen reasoning input.';

RESET lock_timeout;
RESET statement_timeout;
