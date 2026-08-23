-- AI Operations Operator scheduler — MANUAL RELEASE STEP ONLY.
--
-- Preconditions:
--   1) ai-operations-worker Edge Function is deployed.
--   2) Vault contains exactly one secret named ai_ops_edge_function_url with
--      the full function URL.
--   3) Vault contains exactly one secret named ai_ops_worker_secret matching
--      INTERNAL_AI_OPS_WORKER_SECRET in the Edge Function environment.
--   4) pg_cron and pg_net are installed.
--
-- This script deliberately does not store or use the Supabase service-role key.
-- It is idempotent with respect to the named cron job: an existing job with the
-- same name is removed before the replacement is created.
--
-- Timeout contract: the worker caps a single model wait at 120 seconds. Keep
-- pg_net above that ceiling with 30 seconds for context RPCs, staging/validation
-- and response delivery so the scheduler cannot abandon a still-valid worker call.

DO $$
DECLARE
  v_url_count INTEGER;
  v_secret_count INTEGER;
  v_job RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE EXCEPTION 'pg_cron extension is required';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    RAISE EXCEPTION 'pg_net extension is required';
  END IF;

  SELECT count(*)::INTEGER INTO v_url_count
  FROM vault.decrypted_secrets
  WHERE name = 'ai_ops_edge_function_url'
    AND NULLIF(btrim(decrypted_secret), '') IS NOT NULL;

  SELECT count(*)::INTEGER INTO v_secret_count
  FROM vault.decrypted_secrets
  WHERE name = 'ai_ops_worker_secret'
    AND NULLIF(btrim(decrypted_secret), '') IS NOT NULL;

  IF v_url_count <> 1 THEN
    RAISE EXCEPTION 'Vault must contain exactly one non-empty ai_ops_edge_function_url secret; found %', v_url_count;
  END IF;

  IF v_secret_count <> 1 THEN
    RAISE EXCEPTION 'Vault must contain exactly one non-empty ai_ops_worker_secret secret; found %', v_secret_count;
  END IF;

  FOR v_job IN
    SELECT jobid FROM cron.job WHERE jobname = 'ai-operations-worker-poller'
  LOOP
    PERFORM cron.unschedule(v_job.jobid);
  END LOOP;
END;
$$;

SELECT cron.schedule(
  'ai-operations-worker-poller',
  '* * * * *',
  $cron$
    SELECT net.http_post(
      url := (
        SELECT decrypted_secret
        FROM vault.decrypted_secrets
        WHERE name = 'ai_ops_edge_function_url'
        LIMIT 1
      ),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-ai-ops-worker-secret', (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'ai_ops_worker_secret'
          LIMIT 1
        )
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 150000
    );
  $cron$
);

-- Verification (read-only):
-- SELECT jobid, jobname, schedule, active, command
-- FROM cron.job
-- WHERE jobname = 'ai-operations-worker-poller';
