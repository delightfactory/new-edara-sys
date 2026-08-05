-- =============================================================================
-- Employee Work Schedules — authoritative final installed-but-disabled preflight
--
-- Run only after every migration in CURRENT_MIGRATION_MANIFEST.md and after all
-- rollback simulations. Read-only; it never authorizes production activation.
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '180s';

DO $verify$
DECLARE
  v_missing TEXT;
  v_bad TEXT;
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'Final release preflight failed: feature helper reports enabled';
  END IF;

  IF public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Final release preflight failed: readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'Final release preflight failed: installed-state schedule tables must be empty';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_attendance_days
    WHERE schedule_snapshot_at IS NOT NULL
       OR schedule_day_kind IS NOT NULL
       OR scheduled_start_at IS NOT NULL
       OR scheduled_end_at IS NOT NULL
       OR scheduled_minutes IS NOT NULL
       OR schedule_source IS NOT NULL
       OR work_schedule_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Final release preflight failed: historical attendance was snapshotted or changed';
  END IF;

  WITH required(signature) AS (
    VALUES
      ('hr_employee_work_schedules_enabled()'),
      ('hr_employee_work_schedules_activation_ready()'),
      ('guard_employee_work_schedules_activation()'),
      ('resolve_employee_work_schedule_core(uuid,date,boolean)'),
      ('resolve_employee_work_schedule(uuid,date)'),
      ('ensure_attendance_schedule_snapshot(uuid)'),
      ('guard_attendance_schedule_snapshot_immutable()'),
      ('save_employee_work_schedule(uuid,date,jsonb,text)'),
      ('update_future_employee_work_schedule(uuid,jsonb,text)'),
      ('get_employee_work_schedule_admin_context()'),
      ('get_employee_scheduled_period(uuid,date,date,boolean)'),
      ('assert_employee_payroll_schedule_snapshots(uuid,date,date)'),
      ('get_company_default_scheduled_minutes()'),
      ('get_uncovered_attendance_permission_minutes(uuid,date,timestamp with time zone,timestamp with time zone)'),
      ('normalize_attendance_day_schedule_metrics(uuid)'),
      ('dispatch_absence_notification_strict(uuid,text,date,timestamp with time zone,integer)'),
      ('record_attendance_gps_v2(numeric,numeric,numeric,text,timestamp with time zone)'),
      ('record_attendance_gps(numeric,numeric,numeric,text,timestamp with time zone)'),
      ('upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)'),
      ('mark_daily_absences(date)'),
      ('run_auto_checkout(date)'),
      ('process_attendance_penalties(uuid)'),
      ('settle_attendance_day_against_leave(uuid,boolean)'),
      ('notify_absent_employees()'),
      ('scan_attendance_daily_review_alerts()'),
      ('run_attendance_operational_scan()'),
      ('calculate_employee_payroll(uuid,uuid)')
  ), actual AS (
    SELECT p.oid::regprocedure::TEXT AS signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
  )
  SELECT string_agg(r.signature, ', ' ORDER BY r.signature)
  INTO v_missing
  FROM required r
  LEFT JOIN actual a USING (signature)
  WHERE a.signature IS NULL;

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Final release preflight failed: required functions missing: %', v_missing;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'company_settings'
      AND t.tgname = 'trg_company_settings_employee_schedule_activation_guard'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'Final release preflight failed: activation guard trigger is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'hr_attendance_days'
      AND t.tgname = 'trg_hr_attendance_days_schedule_snapshot_immutable'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'Final release preflight failed: snapshot immutability trigger is missing';
  END IF;

  SELECT pg_get_functiondef('public.process_attendance_penalties_scheduled(uuid)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%get_uncovered_attendance_permission_minutes%'
     OR v_definition ILIKE '%FOR v_perm IN%'
     OR v_definition ILIKE '%v_covered_minutes INTEGER%' THEN
    RAISE EXCEPTION 'Final release preflight failed: overlapping permission calculation remains';
  END IF;

  SELECT pg_get_functiondef('public.calculate_employee_payroll_scheduled(uuid,uuid)'::regprocedure)
  INTO v_definition;
  IF v_definition ILIKE '%v_partial_working := 1%'
     OR v_definition NOT ILIKE '%GREATEST(COALESCE(v_partial_working, 0), 0)%'
     OR v_definition NOT ILIKE '%schedule_day_kind = ''work_day'' OR schedule_snapshot_at IS NULL%' THEN
    RAISE EXCEPTION 'Final release preflight failed: payroll schedule isolation is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.normalize_attendance_day_schedule_metrics(uuid)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%late_grace%'
     OR v_definition NOT ILIKE '%get_uncovered_attendance_permission_minutes%'
     OR v_definition NOT ILIKE '%is_auto_checkout%'
     OR v_definition NOT ILIKE '%overtime_minutes = 0%' THEN
    RAISE EXCEPTION 'Final release preflight failed: attendance metric normalization is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.notify_absent_employees_scheduled()'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%get_uncovered_attendance_permission_minutes%'
     OR v_definition NOT ILIKE '%pg_advisory_xact_lock%'
     OR v_definition NOT ILIKE '%dispatch_absence_notification_strict%'
     OR v_definition ILIKE '%ON CONFLICT (alert_key) DO NOTHING%' THEN
    RAISE EXCEPTION 'Final release preflight failed: absence notification retry/dedupe path is stale';
  END IF;

  WITH forbidden(signature, role_name) AS (
    VALUES
      ('upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)', 'anon'),
      ('mark_daily_absences(date)', 'anon'),
      ('run_auto_checkout(date)', 'anon'),
      ('scan_attendance_daily_review_alerts()', 'anon'),
      ('run_attendance_operational_scan()', 'anon'),
      ('notify_absent_employees()', 'anon'),
      ('process_attendance_penalties(uuid)', 'authenticated'),
      ('settle_attendance_day_against_leave(uuid,boolean)', 'authenticated'),
      ('normalize_attendance_day_schedule_metrics(uuid)', 'authenticated'),
      ('get_uncovered_attendance_permission_minutes(uuid,date,timestamp with time zone,timestamp with time zone)', 'service_role'),
      ('dispatch_absence_notification_strict(uuid,text,date,timestamp with time zone,integer)', 'service_role'),
      ('guard_attendance_schedule_snapshot_immutable()', 'service_role')
  )
  SELECT string_agg(format('%s exposed to %s', signature, role_name), ', ' ORDER BY signature)
  INTO v_bad
  FROM forbidden
  WHERE has_function_privilege(role_name, 'public.' || signature, 'EXECUTE');

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Final release preflight failed: restricted function exposure: %', v_bad;
  END IF;

  WITH expected(jobname, schedule, normalized_command, active) AS (
    VALUES
      ('scan-attendance-alerts', '*/15 * * * *', 'selectpublic.run_attendance_operational_scan();', true),
      ('notify-absent-employees', '0 14 * * *', 'selectpublic.notify_absent_employees();', true)
  ), actual AS (
    SELECT
      jobname,
      schedule,
      regexp_replace(lower(command), '\s+', '', 'g') AS normalized_command,
      active
    FROM cron.job
    WHERE jobname IN ('scan-attendance-alerts', 'notify-absent-employees')
  )
  SELECT string_agg(
    format('%s expected=%s/%s/%s actual=%s/%s/%s',
      e.jobname, e.schedule, e.normalized_command, e.active,
      COALESCE(a.schedule, '<missing>'), COALESCE(a.normalized_command, '<missing>'), a.active),
    E'\n' ORDER BY e.jobname
  )
  INTO v_bad
  FROM expected e
  LEFT JOIN actual a USING (jobname)
  WHERE a.jobname IS NULL
     OR a.schedule IS DISTINCT FROM e.schedule
     OR a.normalized_command IS DISTINCT FROM e.normalized_command
     OR a.active IS DISTINCT FROM e.active;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Final release preflight failed: attendance cron drift:%', E'\n' || v_bad;
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'preflight', 'employee_work_schedules_final_release',
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'schedule_rows', (SELECT count(*) FROM public.hr_employee_work_schedules),
  'snapshot_rows', (SELECT count(*) FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL),
  'production_activation_authorized', false
) AS result;

ROLLBACK;
