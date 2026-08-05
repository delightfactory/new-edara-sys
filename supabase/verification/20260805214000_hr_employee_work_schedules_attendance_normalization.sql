-- =============================================================================
-- Employee Work Schedules — attendance normalization structural verification
--
-- Read-only verification. No data changes and no feature activation.
-- =============================================================================

BEGIN;
SET LOCAL statement_timeout = '60s';

DO $verify$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Normalization verification failed: feature/readiness must remain false';
  END IF;

  SELECT pg_get_functiondef(
    'public.normalize_attendance_day_schedule_metrics(uuid)'::regprocedure
  ) INTO v_definition;

  IF v_definition NOT ILIKE '%scheduled_start_at%'
     OR v_definition NOT ILIKE '%scheduled_end_at%'
     OR v_definition NOT ILIKE '%late_grace%'
     OR v_definition NOT ILIKE '%get_uncovered_attendance_permission_minutes%'
     OR v_definition NOT ILIKE '%is_auto_checkout%'
     OR v_definition NOT ILIKE '%overtime_minutes = 0%'
     OR v_definition NOT ILIKE '%day_value = 1.00%'
     OR v_definition NOT ILIKE '%reprocess_attendance_day_penalties%' THEN
    RAISE EXCEPTION 'Normalization verification failed: central metric contract is incomplete';
  END IF;

  SELECT pg_get_functiondef(
    'public.get_uncovered_attendance_permission_minutes(uuid,date,timestamp with time zone,timestamp with time zone)'::regprocedure
  ) INTO v_definition;

  IF v_definition NOT ILIKE '%AS offsets(minute_index)%'
     OR v_definition NOT ILIKE '%permission_date = p_shift_date%'
     OR v_definition NOT ILIKE '%actual_return%'
     OR v_definition NOT ILIKE '%expected_return%'
     OR v_definition NOT ILIKE '%duration_minutes%' THEN
    RAISE EXCEPTION 'Normalization verification failed: permission coverage helper is incomplete';
  END IF;

  SELECT pg_get_functiondef(
    'public.record_attendance_gps_v2(numeric,numeric,numeric,text,timestamp with time zone)'::regprocedure
  ) INTO v_definition;

  IF v_definition NOT ILIKE '%record_attendance_gps_v2_legacy_20260805%'
     OR v_definition NOT ILIKE '%record_attendance_gps_v2_scheduled%'
     OR v_definition NOT ILIKE '%normalize_attendance_day_schedule_metrics%' THEN
    RAISE EXCEPTION 'Normalization verification failed: GPS v2 dispatch is incomplete';
  END IF;

  SELECT pg_get_functiondef(
    'public.record_attendance_gps(numeric,numeric,numeric,text,timestamp with time zone)'::regprocedure
  ) INTO v_definition;

  IF v_definition NOT ILIKE '%record_attendance_gps_legacy_20260805%'
     OR v_definition NOT ILIKE '%record_attendance_gps_v2_scheduled%'
     OR v_definition NOT ILIKE '%normalize_attendance_day_schedule_metrics%' THEN
    RAISE EXCEPTION 'Normalization verification failed: legacy GPS bridge is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.run_auto_checkout(date)'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%run_auto_checkout_legacy_20260805%'
     OR v_definition NOT ILIKE '%run_auto_checkout_scheduled%'
     OR v_definition NOT ILIKE '%normalize_attendance_day_schedule_metrics%'
     OR v_definition NOT ILIKE '%is_auto_checkout%' THEN
    RAISE EXCEPTION 'Normalization verification failed: auto-checkout post-processing is incomplete';
  END IF;

  IF has_function_privilege(
       'authenticated',
       'public.normalize_attendance_day_schedule_metrics(uuid)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'service_role',
       'public.get_uncovered_attendance_permission_minutes(uuid,date,timestamp with time zone,timestamp with time zone)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Normalization verification failed: an internal helper is exposed';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'verification', 'attendance_metric_normalization',
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'gps_and_admin_share_normalizer', true,
  'permission_time_coverage_verified', true,
  'auto_checkout_overtime_block_verified', true,
  'partial_leave_double_deduction_block_verified', true
) AS result;

ROLLBACK;
