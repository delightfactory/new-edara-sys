-- ============================================================
-- 87_analytics_sweep_cron_and_admin_refresh.sql
-- EDARA v2 - Analytics Sweep Cron and Admin Manual Refresh
-- Sets up an hourly cron job and an admin-only RPC to trigger manual refresh.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Schedule the Top-of-the-hour Cron Job safely
-- ------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      PERFORM cron.unschedule('analytics-watermark-sweep');
    EXCEPTION WHEN OTHERS THEN
      -- Ignore if not scheduled
    END;
    
    PERFORM cron.schedule(
      'analytics-watermark-sweep',
      '0 * * * *',
      'CALL analytics.run_analytics_watermark_sweep(1)'
    );
  ELSE
    RAISE NOTICE 'pg_cron extension is not installed. Analytics sweep cron was not scheduled.';
  END IF;
END
$$;

-- ------------------------------------------------------------
-- 2. Admin-only RPC for manual refresh
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.analytics_refresh_now()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, analytics
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_lock_available boolean;
BEGIN
  IF NOT check_permission(v_uid, 'reports.view_all') THEN
    RAISE EXCEPTION 'analytics_unauthorized:domain=all';
  END IF;

  -- Test if the sweep lock is currently held
  SELECT pg_try_advisory_lock(hashtext('analytics_global_sweep')) INTO v_lock_available;
  IF NOT v_lock_available THEN
    RETURN FALSE;
  END IF;
  
  -- Release immediately so the procedure can take it
  PERFORM pg_advisory_unlock(hashtext('analytics_global_sweep'));

  CALL analytics.run_analytics_watermark_sweep(1);
  RETURN TRUE;
END;
$$;

-- Grant execution explicitly to authenticated users (RLS is enforced inside by check_permission)
GRANT EXECUTE ON FUNCTION public.analytics_refresh_now() TO authenticated;
