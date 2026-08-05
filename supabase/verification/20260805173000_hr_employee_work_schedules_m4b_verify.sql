-- =============================================================================
-- Employee Work Schedules M4B — read-only verification
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '90s';

DO $verify$
DECLARE
  v_hash TEXT;
  v_definition TEXT;
  v_missing UUID := '00000000-0000-0000-0000-000000000000';
  v_wrapper_count INTEGER;
  v_legacy_count INTEGER;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'M4B verify failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'M4B verify failed: runtime data changed unexpectedly';
  END IF;

  SELECT md5(replace(
    pg_get_functiondef('public.process_attendance_penalties_legacy_20260805(uuid)'::regprocedure),
    'FUNCTION public.process_attendance_penalties_legacy_20260805(',
    'FUNCTION public.process_attendance_penalties('
  )) INTO v_hash;
  IF v_hash <> '7ea1046753bbcfbbb47bcb35c27f986e' THEN
    RAISE EXCEPTION 'M4B verify failed: penalty legacy clone mismatch (%)', v_hash;
  END IF;

  SELECT md5(replace(
    pg_get_functiondef('public.settle_attendance_day_against_leave_legacy_20260805(uuid,boolean)'::regprocedure),
    'FUNCTION public.settle_attendance_day_against_leave_legacy_20260805(',
    'FUNCTION public.settle_attendance_day_against_leave('
  )) INTO v_hash;
  IF v_hash <> 'c5724ab559a12ca470bcd0bae8ad8206' THEN
    RAISE EXCEPTION 'M4B verify failed: leave settlement legacy clone mismatch (%)', v_hash;
  END IF;

  -- Missing IDs return before mutation and prove disabled wrapper parity.
  SELECT public.process_attendance_penalties(v_missing) INTO v_wrapper_count;
  SELECT public.process_attendance_penalties_legacy_20260805(v_missing) INTO v_legacy_count;
  IF v_wrapper_count IS DISTINCT FROM v_legacy_count THEN
    RAISE EXCEPTION
      'M4B verify failed: disabled penalty wrapper differs; wrapper=% legacy=%',
      v_wrapper_count,
      v_legacy_count;
  END IF;

  PERFORM public.settle_attendance_day_against_leave(v_missing, false);
  PERFORM public.settle_attendance_day_against_leave_legacy_20260805(v_missing, false);

  SELECT pg_get_functiondef('public.process_attendance_penalties_scheduled(uuid)'::regprocedure)
  INTO v_definition;
  IF v_definition ILIKE '%hr.work_hours_per_day%'
     OR v_definition ILIKE '%hr.work_end_time%'
     OR v_definition NOT ILIKE '%scheduled_minutes%'
     OR v_definition NOT ILIKE '%scheduled_end_at%'
     OR v_definition NOT ILIKE '%schedule_day_kind%' THEN
    RAISE EXCEPTION 'M4B verify failed: scheduled penalty engine is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.settle_attendance_day_against_leave_scheduled(uuid,boolean)'::regprocedure)
  INTO v_definition;
  IF v_definition ILIKE '%hr.work_hours_per_day%'
     OR v_definition NOT ILIKE '%scheduled_minutes%'
     OR v_definition NOT ILIKE '%needs_review%' THEN
    RAISE EXCEPTION 'M4B verify failed: scheduled leave settlement is incomplete';
  END IF;

  SELECT md5(pg_get_functiondef('public.reprocess_attendance_day_penalties(uuid)'::regprocedure))
  INTO v_hash;
  IF v_hash <> '5d1d271f18585e9d2381b9d1c12fa684' THEN
    RAISE EXCEPTION 'M4B verify failed: reprocess helper changed (%)', v_hash;
  END IF;

  IF has_function_privilege('authenticated', 'public.process_attendance_penalties_scheduled(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.process_attendance_penalties_legacy_20260805(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.settle_attendance_day_against_leave_scheduled(uuid,boolean)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.settle_attendance_day_against_leave_legacy_20260805(uuid,boolean)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.process_attendance_penalties_scheduled(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'M4B verify failed: an internal financial helper is exposed';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'disabled_penalty_parity', true,
  'disabled_leave_settlement_parity', true,
  'scheduled_penalties_use_snapshot_minutes', true,
  'scheduled_leave_uses_snapshot_minutes', true,
  'reprocess_helper_changed', false,
  'runtime_data_changed', false
) AS m4b_verification;

ROLLBACK;
