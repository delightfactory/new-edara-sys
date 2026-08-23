\set ON_ERROR_STOP on

-- Runtime qualification for an ISOLATED production clone only.
-- The entire lifecycle probe is rolled back; only the migrations applied before
-- this file remain on the clone.

BEGIN;

-- Test-only recursive predicate. pg_temp keeps this behavioral assertion out
-- of the production API surface, and the enclosing transaction removes it.
CREATE FUNCTION pg_temp.worker_json_has_meaningful_value(p_value JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_type TEXT;
BEGIN
  IF p_value IS NULL OR p_value = 'null'::JSONB THEN
    RETURN false;
  END IF;

  v_type := jsonb_typeof(p_value);

  IF v_type = 'object' THEN
    RETURN EXISTS (
      SELECT 1
      FROM jsonb_each(p_value) AS e(key, value)
      WHERE e.key NOT IN ('_truncated', '_truncated_depth', '_total_items')
        AND pg_temp.worker_json_has_meaningful_value(e.value)
    );
  END IF;

  IF v_type = 'array' THEN
    RETURN EXISTS (
      SELECT 1
      FROM jsonb_array_elements(p_value) AS e(value)
      WHERE pg_temp.worker_json_has_meaningful_value(e.value)
    );
  END IF;

  IF v_type = 'string' THEN
    RETURN btrim(p_value #>> '{}') <> ''
      AND btrim(p_value #>> '{}') !~ '^(…)?\[truncated\]$';
  END IF;

  -- Zero and false remain meaningful operational facts.
  RETURN v_type IN ('number', 'boolean');
END;
$$;

DO $$
DECLARE
  v_now TIMESTAMPTZ := clock_timestamp();
  v_local_now TIMESTAMP := clock_timestamp() AT TIME ZONE 'Africa/Cairo';
  v_day SMALLINT := extract(dow from clock_timestamp() AT TIME ZONE 'Africa/Cairo')::SMALLINT;
  v_materialized JSONB;
  v_claim JSONB;
  v_context JSONB;
  v_run_id UUID;
  v_context_bytes INTEGER;
  v_context_limit INTEGER;
  v_required_domains INTEGER;
  v_capture_count INTEGER;
  v_case_count INTEGER;
  v_bad_case_count INTEGER;
  v_case_domain_count INTEGER;
  v_expected_case_domain_count INTEGER;
BEGIN
  IF to_regnamespace('ai_ops') IS NULL THEN
    RAISE EXCEPTION 'ai_ops schema is missing after migration rehearsal';
  END IF;

  v_required_domains := cardinality(ai_ops.required_operational_domains());
  IF v_required_domains <> 7 THEN
    RAISE EXCEPTION 'expected seven required operational domains, got %', v_required_domains;
  END IF;

  UPDATE ai_ops.settings
  SET planner_enabled = true,
      shadow_mode = true,
      auto_commit_enabled = false,
      updated_at = v_now
  WHERE singleton = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI Operations settings singleton is missing';
  END IF;

  INSERT INTO ai_ops.run_schedules(
    code, run_type, timezone, local_time, weekdays,
    recovery_window_minutes, enabled, settings
  ) VALUES (
    'release_context_rehearsal',
    'morning',
    'Africa/Cairo',
    (v_local_now::time - interval '1 minute')::time,
    ARRAY[v_day]::SMALLINT[],
    180,
    true,
    '{}'::JSONB
  );

  v_materialized := public.ai_ops_worker_materialize_due_runs();
  IF COALESCE((v_materialized->>'materialized')::INTEGER, 0) < 1 THEN
    RAISE EXCEPTION 'rehearsal did not materialize a due run: %', v_materialized;
  END IF;

  v_claim := public.ai_ops_worker_claim_next_run('release-context-rehearsal', 1200);
  IF COALESCE((v_claim->>'claimed')::BOOLEAN, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'rehearsal worker did not claim a run: %', v_claim;
  END IF;

  v_run_id := (v_claim->>'run_id')::UUID;
  v_context := public.ai_ops_worker_get_context(v_run_id, 'release-context-rehearsal');

  IF COALESCE((v_context->>'blocked')::BOOLEAN, false) THEN
    RAISE EXCEPTION 'worker context is blocked on realistic clone data: %', v_context;
  END IF;

  v_context_bytes := (v_context->>'context_bytes')::INTEGER;
  v_context_limit := (v_context->>'context_limit_bytes')::INTEGER;

  IF v_context_bytes IS NULL OR v_context_limit IS NULL THEN
    RAISE EXCEPTION 'worker context did not report byte accounting: %', v_context;
  END IF;

  IF v_context_bytes > v_context_limit THEN
    RAISE EXCEPTION 'worker context % bytes exceeds hard limit %', v_context_bytes, v_context_limit;
  END IF;

  IF v_context_limit <> 65536 THEN
    RAISE EXCEPTION 'rehearsal must not pass by raising the 65536-byte safety limit; got %', v_context_limit;
  END IF;

  v_capture_count := jsonb_array_length(v_context->'context'->'snapshot'->'domain_captures');
  IF v_capture_count <> v_required_domains THEN
    RAISE EXCEPTION 'worker context has % domain captures, expected %', v_capture_count, v_required_domains;
  END IF;

  v_case_count := jsonb_array_length(v_context->'context'->'cases');

  SELECT count(DISTINCT c->>'domain')::INTEGER INTO v_case_domain_count
  FROM jsonb_array_elements(v_context->'context'->'cases') c
  WHERE c->>'domain' = ANY(ai_ops.required_operational_domains());

  SELECT count(*)::INTEGER INTO v_expected_case_domain_count
  FROM jsonb_array_elements(v_context->'context'->'snapshot'->'domain_captures') dc
  WHERE (
      COALESCE((dc->>'case_count')::INTEGER, 0) > 0
      OR COALESCE((dc->>'has_more')::BOOLEAN, false)
      OR COALESCE((dc->>'global_budget_exhausted')::BOOLEAN, false)
    )
    AND dc->>'domain' = ANY(ai_ops.required_operational_domains());

  IF v_case_domain_count <> v_expected_case_domain_count
     OR EXISTS (
       SELECT 1
       FROM jsonb_array_elements(v_context->'context'->'snapshot'->'domain_captures') dc
       WHERE (
           COALESCE((dc->>'case_count')::INTEGER, 0) > 0
           OR COALESCE((dc->>'has_more')::BOOLEAN, false)
           OR COALESCE((dc->>'global_budget_exhausted')::BOOLEAN, false)
         )
         AND dc->>'domain' = ANY(ai_ops.required_operational_domains())
         AND NOT EXISTS (
           SELECT 1
           FROM jsonb_array_elements(v_context->'context'->'cases') c
           WHERE c->>'domain' = dc->>'domain'
         )
     )
     OR EXISTS (
       SELECT 1
       FROM jsonb_array_elements(v_context->'context'->'cases') c
       WHERE NOT EXISTS (
         SELECT 1
         FROM jsonb_array_elements(v_context->'context'->'snapshot'->'domain_captures') dc
         WHERE dc->>'domain' = c->>'domain'
           AND (
             COALESCE((dc->>'case_count')::INTEGER, 0) > 0
             OR COALESCE((dc->>'has_more')::BOOLEAN, false)
             OR COALESCE((dc->>'global_budget_exhausted')::BOOLEAN, false)
           )
       )
     ) THEN
    RAISE EXCEPTION 'worker case domains % do not exactly match % demand-bearing domain captures',
      v_case_domain_count, v_expected_case_domain_count;
  END IF;

  SELECT count(*)::INTEGER INTO v_bad_case_count
  FROM jsonb_array_elements(v_context->'context'->'cases') c
  WHERE NOT (
    c ? 'case_id'
    AND c ? 'case_key'
    AND c ? 'domain'
    AND c ? 'case_type'
    AND c ? 'entity_type'
    AND c ? 'severity'
    AND c ? 'facts'
    AND c ? 'responsibility_evidence'
    AND c ? 'operational_context'
    AND c ? 'trust'
    AND pg_temp.worker_json_has_meaningful_value(c->'facts')
    AND pg_temp.worker_json_has_meaningful_value(c->'responsibility_evidence')
    AND pg_temp.worker_json_has_meaningful_value(c->'operational_context')
    AND pg_temp.worker_json_has_meaningful_value(c->'trust')
  );

  IF v_bad_case_count > 0 THEN
    RAISE EXCEPTION '%/% frozen cases contain missing, empty, null or marker-only decision evidence after compaction',
      v_bad_case_count, v_case_count;
  END IF;

  IF NULLIF(v_context->>'context_hash', '') IS NULL THEN
    RAISE EXCEPTION 'worker context hash is missing';
  END IF;

  RAISE NOTICE 'AI Ops clone context PASS: run %, % cases, % domains, %/% bytes, tier %',
    v_run_id,
    v_case_count,
    v_capture_count,
    v_context_bytes,
    v_context_limit,
    v_context->>'compaction_tier';
END;
$$;

ROLLBACK;
