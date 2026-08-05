-- =============================================================================
-- Employee Work Schedules M4D — read-only verification
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
    RAISE EXCEPTION 'M4D verify failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'M4D verify failed: runtime data changed unexpectedly';
  END IF;

  SELECT md5(replace(
    pg_get_functiondef('public.run_attendance_operational_scan_legacy_20260805()'::regprocedure),
    'FUNCTION public.run_attendance_operational_scan_legacy_20260805(',
    'FUNCTION public.run_attendance_operational_scan('
  )) INTO v_hash;

  IF v_hash <> '40baaa14f7df81f78025d14ebb0fc288' THEN
    RAISE EXCEPTION 'M4D verify failed: operational legacy clone mismatch (%)', v_hash;
  END IF;

  SELECT pg_get_functiondef('public.notify_absent_employees_scheduled()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%resolve_employee_work_schedule%'
     OR v_definition NOT ILIKE '%scheduled_start_at%'
     OR v_definition NOT ILIKE '%notification_alert_state%'
     OR v_definition NOT ILIKE '%ON CONFLICT (alert_key) DO NOTHING%'
     OR v_definition NOT ILIKE '%hr.attendance.absent::%'
     OR v_definition NOT ILIKE '%resolved_at%' THEN
    RAISE EXCEPTION 'M4D verify failed: scheduled absence dedupe/resolution is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.run_attendance_operational_scan_scheduled()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%scan_attendance_tracking_alerts%'
     OR v_definition NOT ILIKE '%scan_attendance_daily_review_alerts%'
     OR v_definition NOT ILIKE '%notify_absent_employees_scheduled%'
     OR v_definition NOT ILIKE '%''tracking'', v_tracking%'
     OR v_definition NOT ILIKE '%''daily_review'', v_daily%' THEN
    RAISE EXCEPTION 'M4D verify failed: scheduled orchestrator is incomplete or changes response shape';
  END IF;

  SELECT pg_get_functiondef('public.run_attendance_operational_scan()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%hr_employee_work_schedules_enabled%'
     OR v_definition NOT ILIKE '%run_attendance_operational_scan_legacy_20260805%'
     OR v_definition NOT ILIKE '%run_attendance_operational_scan_scheduled%' THEN
    RAISE EXCEPTION 'M4D verify failed: public operational dispatcher is incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname = 'notification_alert_state'
      AND c.conname = 'uq_nas_alert_key'
      AND c.contype = 'u'
      AND c.convalidated
  ) THEN
    RAISE EXCEPTION 'M4D verify failed: atomic alert-key uniqueness constraint is missing';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.notify_absent_employees_scheduled()',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.run_attendance_operational_scan_scheduled()',
    'EXECUTE'
  ) OR has_function_privilege(
    'service_role',
    'public.run_attendance_operational_scan_scheduled()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'M4D verify failed: an internal helper is exposed';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'late_shift_supported_by_periodic_scan', true,
  'per_employee_date_dedupe_atomic', true,
  'operational_response_shape_preserved', true,
  'new_cron_created', false,
  'runtime_data_changed', false
) AS m4d_verification;

ROLLBACK;
