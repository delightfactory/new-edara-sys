-- Non-operational storage maintenance.
-- This migration does not modify business or analytics rows.

DO $$
BEGIN
  IF to_regclass('analytics.snapshot_cust_health_unique') IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM pg_index
       WHERE indexrelid = 'analytics.snapshot_cust_health_unique'::regclass
         AND indisvalid
         AND indisready
         AND indislive
     ) THEN
    RAISE EXCEPTION
      'Required replacement index analytics.snapshot_cust_health_unique is not healthy';
  END IF;

  IF to_regclass('analytics.snapshot_cust_risk_unique') IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM pg_index
       WHERE indexrelid = 'analytics.snapshot_cust_risk_unique'::regclass
         AND indisvalid
         AND indisready
         AND indislive
     ) THEN
    RAISE EXCEPTION
      'Required replacement index analytics.snapshot_cust_risk_unique is not healthy';
  END IF;
END;
$$;

-- Each UNIQUE index above has the same ordered columns as its redundant index.
DROP INDEX IF EXISTS analytics.idx_snap_cust_health;
DROP INDEX IF EXISTS analytics.idx_snap_cust_risk_date_cust;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
     AND NOT EXISTS (
       SELECT 1
       FROM cron.job
       WHERE jobname = 'edara-cron-log-retention'
     ) THEN
    PERFORM cron.schedule(
      'edara-cron-log-retention',
      '30 2 * * *',
      $cmd$
        DELETE FROM cron.job_run_details
        WHERE coalesce(end_time, start_time) < now() - interval '14 days'
      $cmd$
    );
  END IF;
END;
$$;
