-- =============================================================================
-- Employee Work Schedules — remaining release-safety verification
--
-- Read-only structural verification. It performs no writes and keeps the
-- runtime feature/readiness disabled.
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '90s';

DO $verify$
DECLARE
  v_definition TEXT;
  v_zero_day_count INTEGER;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Release-safety verification failed: feature/readiness must remain false';
  END IF;

  SELECT pg_get_functiondef('public.process_attendance_penalties_scheduled(uuid)'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%get_uncovered_attendance_permission_minutes%'
     OR v_definition ILIKE '%FOR v_perm IN%'
     OR v_definition ILIKE '%v_covered_minutes INTEGER%'
     OR v_definition NOT ILIKE '%deduction_minutes%v_minutes%' THEN
    RAISE EXCEPTION 'Release-safety verification failed: overlapping permissions are not unioned once';
  END IF;

  SELECT pg_get_functiondef('public.calculate_employee_payroll_scheduled(uuid,uuid)'::regprocedure)
  INTO v_definition;

  v_zero_day_count := (
    length(v_definition) - length(replace(
      v_definition,
      'GREATEST(COALESCE(v_partial_working, 0), 0)',
      ''
    ))
  ) / length('GREATEST(COALESCE(v_partial_working, 0), 0)');

  IF v_zero_day_count <> 3
     OR v_definition ILIKE '%v_partial_working := 1%' THEN
    RAISE EXCEPTION
      'Release-safety verification failed: partial-period zero-day guards count=%',
      v_zero_day_count;
  END IF;

  SELECT pg_get_functiondef('public.guard_attendance_schedule_snapshot_immutable()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%OLD.schedule_snapshot_at IS NOT NULL%'
     OR v_definition NOT ILIKE '%scheduled_start_at IS DISTINCT FROM OLD.scheduled_start_at%'
     OR v_definition NOT ILIKE '%scheduled_end_at IS DISTINCT FROM OLD.scheduled_end_at%'
     OR v_definition NOT ILIKE '%scheduled_minutes IS DISTINCT FROM OLD.scheduled_minutes%'
     OR v_definition NOT ILIKE '%work_schedule_id IS DISTINCT FROM OLD.work_schedule_id%' THEN
    RAISE EXCEPTION 'Release-safety verification failed: snapshot immutability contract is incomplete';
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
    RAISE EXCEPTION 'Release-safety verification failed: snapshot immutability trigger is missing';
  END IF;

  IF has_function_privilege(
       'authenticated',
       'public.guard_attendance_schedule_snapshot_immutable()',
       'EXECUTE'
     )
     OR has_function_privilege(
       'service_role',
       'public.guard_attendance_schedule_snapshot_immutable()',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Release-safety verification failed: snapshot trigger helper is exposed';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'verification', 'remaining_release_safety_fixes',
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'overlapping_permissions_union_verified', true,
  'zero_scheduled_day_entitlement_verified', true,
  'snapshot_immutability_verified', true
) AS result;

ROLLBACK;
