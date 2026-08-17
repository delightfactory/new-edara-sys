from pathlib import Path

root = Path(__file__).resolve().parents[1]
path = root / 'supabase/migrations/46_notification_full_coverage.sql'
text = path.read_text(encoding='utf-8')

old_schedule = '''-- Idempotent: unschedule before re-scheduling
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'notify-absent-employees') THEN
    PERFORM cron.unschedule('notify-absent-employees');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'notify-expiring-contracts') THEN
    PERFORM cron.unschedule('notify-expiring-contracts');
  END IF;
END $$;

-- Daily at 14:00 UTC (≈ 16:00 Cairo Standard Time — end of workday)
SELECT cron.schedule(
  'notify-absent-employees',
  '0 14 * * *',
  $$ SELECT public.notify_absent_employees(); $$
);

-- Daily at 08:00 UTC (≈ 10:00 Cairo — morning check)
SELECT cron.schedule(
  'notify-expiring-contracts',
  '0 8 * * *',
  $$ SELECT public.notify_expiring_contracts(); $$
);
'''

new_schedule = '''-- Idempotent when pg_cron is available. Fresh/local databases may not have
-- pg_cron enabled; notification functions must still migrate successfully and
-- can be scheduled later when the extension is enabled.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
     AND to_regclass('cron.job') IS NOT NULL THEN
    BEGIN
      PERFORM cron.unschedule('notify-absent-employees');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    BEGIN
      PERFORM cron.unschedule('notify-expiring-contracts');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    PERFORM cron.schedule(
      'notify-absent-employees',
      '0 14 * * *',
      'SELECT public.notify_absent_employees();'
    );
    PERFORM cron.schedule(
      'notify-expiring-contracts',
      '0 8 * * *',
      'SELECT public.notify_expiring_contracts();'
    );
    RAISE NOTICE '[46_notification_full_coverage] pg_cron jobs scheduled';
  ELSE
    RAISE NOTICE '[46_notification_full_coverage] pg_cron unavailable — notification functions installed; schedule jobs after enabling pg_cron';
  END IF;
END $$;
'''

old_verify = '''  SELECT COUNT(*) INTO v_cron_count
  FROM   cron.job
  WHERE  jobname IN ('notify-absent-employees', 'notify-expiring-contracts');
'''
new_verify = '''  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
     AND to_regclass('cron.job') IS NOT NULL THEN
    SELECT COUNT(*) INTO v_cron_count
    FROM   cron.job
    WHERE  jobname IN ('notify-absent-employees', 'notify-expiring-contracts');
  ELSE
    v_cron_count := 0;
  END IF;
'''

old_warning = "  IF v_cron_count   < 2   THEN RAISE WARNING '  ⚠️  Missing cron jobs';  END IF;"
new_warning = "  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') AND v_cron_count < 2 THEN RAISE WARNING '  ⚠️  Missing cron jobs'; END IF;"

for old, new, label in [
    (old_schedule, new_schedule, 'schedule block'),
    (old_verify, new_verify, 'verification query'),
    (old_warning, new_warning, 'verification warning'),
]:
    if old not in text:
        raise RuntimeError(f'expected {label} anchor missing')
    text = text.replace(old, new, 1)

path.write_text(text, encoding='utf-8')
Path(__file__).unlink(missing_ok=True)
(root / '.github/workflows/fix-notification-cron-portability.yml').unlink(missing_ok=True)
