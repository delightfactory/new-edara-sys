\set ON_ERROR_STOP on

-- ISOLATED PRODUCTION CLONE ONLY.
-- This preparation intentionally persists on the clone so the real Edge worker
-- can claim a due run in the subsequent model lifecycle rehearsal.

DO $$
DECLARE
  v_now TIMESTAMPTZ := clock_timestamp();
  v_local_now TIMESTAMP := clock_timestamp() AT TIME ZONE 'Africa/Cairo';
  v_day SMALLINT := extract(dow from clock_timestamp() AT TIME ZONE 'Africa/Cairo')::SMALLINT;
  v_materialized JSONB;
  v_existing RECORD;
BEGIN
  IF to_regnamespace('ai_ops') IS NULL THEN
    RAISE EXCEPTION 'ai_ops schema is missing';
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

  FOR v_existing IN
    SELECT id FROM ai_ops.run_schedules WHERE code = 'release_edge_rehearsal'
  LOOP
    DELETE FROM ai_ops.run_schedules WHERE id = v_existing.id;
  END LOOP;

  INSERT INTO ai_ops.run_schedules(
    code, run_type, timezone, local_time, weekdays,
    recovery_window_minutes, enabled, settings
  ) VALUES (
    'release_edge_rehearsal',
    'morning',
    'Africa/Cairo',
    (v_local_now::time - interval '1 minute')::time,
    ARRAY[v_day]::SMALLINT[],
    180,
    true,
    jsonb_build_object('release_rehearsal', true)
  );

  v_materialized := public.ai_ops_worker_materialize_due_runs();
  IF COALESCE((v_materialized->>'materialized')::INTEGER, 0) < 1 THEN
    RAISE EXCEPTION 'edge rehearsal did not materialize a due run: %', v_materialized;
  END IF;

  RAISE NOTICE 'AI Ops clone Edge run prepared: %', v_materialized;
END;
$$;

SELECT id, run_key, status, scheduled_for, business_date
FROM ai_ops.planner_runs
WHERE status = 'pending'
ORDER BY scheduled_for, created_at
LIMIT 5;
