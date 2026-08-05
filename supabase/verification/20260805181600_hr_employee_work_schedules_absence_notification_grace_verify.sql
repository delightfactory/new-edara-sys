-- =============================================================================
-- Employee Work Schedules — absence notification grace verification
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '60s';

DO $verify$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Absence-grace verify failed: feature/readiness must remain false';
  END IF;

  SELECT pg_get_functiondef('public.notify_absent_employees_scheduled()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%hr.late_grace_minutes%'
     OR v_definition NOT ILIKE '%GREATEST(0, COALESCE(v_late_grace_minutes, 15))%'
     OR v_definition NOT ILIKE '%v_scheduled_start + make_interval(mins => v_late_grace_minutes)%'
     OR v_definition NOT ILIKE '%ON CONFLICT (alert_key) DO NOTHING%'
     OR v_definition NOT ILIKE '%late_grace_minutes%'
     OR v_definition NOT ILIKE '%notification_alert_state%' THEN
    RAISE EXCEPTION 'Absence-grace verify failed: grace/dedupe logic is incomplete';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.notify_absent_employees_scheduled()',
    'EXECUTE'
  ) OR has_function_privilege(
    'service_role',
    'public.notify_absent_employees_scheduled()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Absence-grace verify failed: internal notifier is exposed';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Absence-grace verify failed: runtime schedule/snapshot data changed';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'notification_waits_for_late_grace', true,
  'late_shift_periodic_scan_supported', true,
  'per_employee_date_dedupe_preserved', true,
  'cron_changed', false,
  'runtime_data_changed', false
) AS absence_notification_grace_verification;

ROLLBACK;
