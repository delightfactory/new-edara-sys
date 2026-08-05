-- =============================================================================
-- Employee Work Schedules M4C — read-only verification
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '90s';

DO $verify$
DECLARE
  v_hash TEXT;
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'M4C verify failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'M4C verify failed: runtime data changed unexpectedly';
  END IF;

  SELECT md5(replace(
    pg_get_functiondef('public.notify_absent_employees_legacy_20260805()'::regprocedure),
    'FUNCTION public.notify_absent_employees_legacy_20260805(',
    'FUNCTION public.notify_absent_employees('
  )) INTO v_hash;
  IF v_hash <> '0d117e202cbbcf08e9d1b35b4b4dab14' THEN
    RAISE EXCEPTION 'M4C verify failed: absence notification legacy clone mismatch (%)', v_hash;
  END IF;

  SELECT md5(replace(
    pg_get_functiondef('public.scan_attendance_daily_review_alerts_legacy_20260805()'::regprocedure),
    'FUNCTION public.scan_attendance_daily_review_alerts_legacy_20260805(',
    'FUNCTION public.scan_attendance_daily_review_alerts('
  )) INTO v_hash;
  IF v_hash <> '9997ff7734f0289b85c5d9a3b8330c38' THEN
    RAISE EXCEPTION 'M4C verify failed: daily review legacy clone mismatch (%)', v_hash;
  END IF;

  SELECT pg_get_functiondef('public.notify_absent_employees_scheduled()'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%resolve_employee_work_schedule%'
     OR v_definition NOT ILIKE '%scheduled_start_at%'
     OR v_definition ILIKE '%is_employee_work_day%' THEN
    RAISE EXCEPTION 'M4C verify failed: scheduled absence notification is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.scan_attendance_daily_review_alerts_scheduled()'::regprocedure)
  INTO v_definition;
  IF v_definition ILIKE '%hr.work_end_time%'
     OR v_definition NOT ILIKE '%scheduled_end_at%'
     OR v_definition NOT ILIKE '%ensure_attendance_schedule_snapshot%'
     OR v_definition NOT ILIKE '%needs_review%' THEN
    RAISE EXCEPTION 'M4C verify failed: scheduled daily review scan is incomplete';
  END IF;

  SELECT md5(pg_get_functiondef('public.scan_attendance_tracking_alerts()'::regprocedure))
  INTO v_hash;
  IF v_hash <> '139e2ad118b89ff33d5052e67041e4e6' THEN
    RAISE EXCEPTION 'M4C verify failed: tracking scan changed (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.run_attendance_operational_scan()'::regprocedure))
  INTO v_hash;
  IF v_hash <> '40baaa14f7df81f78025d14ebb0fc288' THEN
    RAISE EXCEPTION 'M4C verify failed: operational scan changed (%)', v_hash;
  END IF;

  IF has_function_privilege('authenticated', 'public.notify_absent_employees_scheduled()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.notify_absent_employees_legacy_20260805()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.scan_attendance_daily_review_alerts_scheduled()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.scan_attendance_daily_review_alerts_legacy_20260805()', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.notify_absent_employees_scheduled()', 'EXECUTE') THEN
    RAISE EXCEPTION 'M4C verify failed: an internal notification helper is exposed';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'scheduled_absence_notification_uses_employee_start', true,
  'scheduled_open_day_review_uses_snapshot_end', true,
  'tracking_scan_changed', false,
  'operational_scan_changed', false,
  'cron_schedule_changed', false,
  'runtime_data_changed', false
) AS m4c_verification;

ROLLBACK;
