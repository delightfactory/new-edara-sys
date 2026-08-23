-- AI Operations Operator scheduler kill switch — MANUAL OPERATION ONLY.
-- Safe to run even if no poller exists.

DO $$
DECLARE
  v_job RECORD;
BEGIN
  FOR v_job IN
    SELECT jobid FROM cron.job WHERE jobname = 'ai-operations-worker-poller'
  LOOP
    PERFORM cron.unschedule(v_job.jobid);
  END LOOP;
END;
$$;

-- Verification (read-only):
-- SELECT jobid, jobname, schedule, active
-- FROM cron.job
-- WHERE jobname = 'ai-operations-worker-poller';
