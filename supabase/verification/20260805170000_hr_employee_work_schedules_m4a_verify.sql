-- =============================================================================
-- Employee Work Schedules M4A — read-only verification
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '90s';

DO $verify$
DECLARE
  v_hash TEXT;
  v_definition TEXT;
  v_wrapper_error TEXT;
  v_legacy_error TEXT;
  v_future DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE + 5;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'M4A verify failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'M4A verify failed: runtime data changed unexpectedly';
  END IF;

  SELECT md5(replace(
    pg_get_functiondef('public.mark_daily_absences_legacy_20260805(date)'::regprocedure),
    'FUNCTION public.mark_daily_absences_legacy_20260805(',
    'FUNCTION public.mark_daily_absences('
  )) INTO v_hash;
  IF v_hash <> '21e4cb27c5d1008da928cbf14ad56f1b' THEN
    RAISE EXCEPTION 'M4A verify failed: absence legacy clone mismatch (%)', v_hash;
  END IF;

  SELECT md5(replace(
    pg_get_functiondef('public.run_auto_checkout_legacy_20260805(date)'::regprocedure),
    'FUNCTION public.run_auto_checkout_legacy_20260805(',
    'FUNCTION public.run_auto_checkout('
  )) INTO v_hash;
  IF v_hash <> '7687df6dc398cd73ed53408c2c53d1a8' THEN
    RAISE EXCEPTION 'M4A verify failed: auto-checkout legacy clone mismatch (%)', v_hash;
  END IF;

  -- Future dates fail before any mutation; use that guard to prove disabled
  -- wrappers return the same operational error as the exact legacy helpers.
  BEGIN
    PERFORM public.mark_daily_absences(v_future);
  EXCEPTION WHEN OTHERS THEN
    v_wrapper_error := SQLSTATE || ':' || SQLERRM;
  END;

  BEGIN
    PERFORM public.mark_daily_absences_legacy_20260805(v_future);
  EXCEPTION WHEN OTHERS THEN
    v_legacy_error := SQLSTATE || ':' || SQLERRM;
  END;

  IF v_wrapper_error IS NULL OR v_wrapper_error IS DISTINCT FROM v_legacy_error THEN
    RAISE EXCEPTION
      'M4A verify failed: disabled absence wrapper mismatch; wrapper=% legacy=%',
      v_wrapper_error,
      v_legacy_error;
  END IF;

  v_wrapper_error := NULL;
  v_legacy_error := NULL;

  BEGIN
    PERFORM public.run_auto_checkout(v_future);
  EXCEPTION WHEN OTHERS THEN
    v_wrapper_error := SQLSTATE || ':' || SQLERRM;
  END;

  BEGIN
    PERFORM public.run_auto_checkout_legacy_20260805(v_future);
  EXCEPTION WHEN OTHERS THEN
    v_legacy_error := SQLSTATE || ':' || SQLERRM;
  END;

  IF v_wrapper_error IS NULL OR v_wrapper_error IS DISTINCT FROM v_legacy_error THEN
    RAISE EXCEPTION
      'M4A verify failed: disabled auto-checkout wrapper mismatch; wrapper=% legacy=%',
      v_wrapper_error,
      v_legacy_error;
  END IF;

  SELECT pg_get_functiondef('public.mark_daily_absences_scheduled(date)'::regprocedure)
  INTO v_definition;
  IF v_definition ILIKE '%hr.work_end_time%'
     OR v_definition NOT ILIKE '%resolve_employee_work_schedule%'
     OR v_definition NOT ILIKE '%schedule_snapshot_at%'
     OR v_definition NOT ILIKE '%scheduled_end_at%' THEN
    RAISE EXCEPTION 'M4A verify failed: scheduled absence implementation is not resolver/snapshot based';
  END IF;

  SELECT pg_get_functiondef('public.run_auto_checkout_scheduled(date)'::regprocedure)
  INTO v_definition;
  IF v_definition ILIKE '%hr.work_end_time%'
     OR v_definition NOT ILIKE '%ensure_attendance_schedule_snapshot%'
     OR v_definition NOT ILIKE '%scheduled_end_at%'
     OR v_definition NOT ILIKE '%needs_review%' THEN
    RAISE EXCEPTION 'M4A verify failed: scheduled auto-checkout implementation is incomplete';
  END IF;

  IF has_function_privilege('authenticated', 'public.mark_daily_absences_scheduled(date)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.mark_daily_absences_legacy_20260805(date)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.run_auto_checkout_scheduled(date)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.run_auto_checkout_legacy_20260805(date)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.run_auto_checkout_scheduled(date)', 'EXECUTE') THEN
    RAISE EXCEPTION 'M4A verify failed: an internal automation helper is exposed';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'disabled_absence_parity', true,
  'disabled_auto_checkout_parity', true,
  'scheduled_absence_uses_employee_end', true,
  'scheduled_auto_checkout_uses_snapshot', true,
  'runtime_data_changed', false
) AS m4a_verification;

ROLLBACK;
