-- HR Variable Schedules V2 — Batch 3A2 verification
-- Read-only assertions for the later disposable PostgreSQL rehearsal.

DO $verify$
DECLARE
  v_legacy_hash text;
  v_wrapper_body text;
BEGIN
  IF public.hr_variable_schedules_v2_runtime_enabled() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Batch 3A2 verification failed: V2 runtime gate must remain false';
  END IF;

  SELECT md5(p.prosrc)
  INTO v_legacy_hash
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'mark_daily_absences_legacy'
    AND pg_get_function_identity_arguments(p.oid) = 'p_target_date date';

  IF v_legacy_hash IS DISTINCT FROM 'c6e5ca9060277416ec899d187eec3d89' THEN
    RAISE EXCEPTION 'Batch 3A2 verification failed: Legacy absence body drifted';
  END IF;

  SELECT p.prosrc
  INTO v_wrapper_body
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'mark_daily_absences'
    AND pg_get_function_identity_arguments(p.oid) = 'p_target_date date';

  IF v_wrapper_body IS NULL
     OR position('IF NOT public.hr_variable_schedules_v2_runtime_enabled()' in v_wrapper_body) = 0
     OR position('p_target_date IS DISTINCT FROM v_today' in v_wrapper_body) = 0
     OR position('mark_daily_absences_legacy' in v_wrapper_body) = 0
     OR position('hr.absence_run_delay_minutes' in v_wrapper_body) = 0
     OR position('v_company_cutoff' in v_wrapper_body) = 0
     OR position('resolve_employee_custom_schedule' in v_wrapper_body) = 0
     OR position('v_custom_cutoff' in v_wrapper_body) = 0
     OR position('IF now() < v_custom_cutoff' in v_wrapper_body) = 0 THEN
    RAISE EXCEPTION 'Batch 3A2 verification failed: same-day compatibility contract incomplete';
  END IF;

  IF position('mark_daily_absences_legacy' in v_wrapper_body)
     > position('resolve_employee_custom_schedule' in v_wrapper_body) THEN
    RAISE EXCEPTION 'Batch 3A2 verification failed: Legacy non-current dispatch is not before custom lookup';
  END IF;

  IF NOT has_function_privilege('anon', 'public.mark_daily_absences(date)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.mark_daily_absences(date)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Batch 3A2 verification failed: public absence execute contract changed';
  END IF;

  IF has_function_privilege('anon', 'public.mark_daily_absences_legacy(date)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.mark_daily_absences_legacy(date)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Batch 3A2 verification failed: Legacy absence alias became externally executable';
  END IF;
END;
$verify$;
