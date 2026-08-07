-- HR Variable Schedules V2 — Batch 3A1 verification
-- Read-only assertions for the later disposable PostgreSQL rehearsal.

DO $verify$
DECLARE
  v_legacy_hash text;
  v_wrapper_body text;
  v_absence_hash text;
BEGIN
  IF public.hr_variable_schedules_v2_runtime_enabled() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Batch 3A1 verification failed: V2 runtime gate must remain false';
  END IF;

  SELECT md5(p.prosrc)
  INTO v_legacy_hash
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'is_employee_work_day_legacy'
    AND pg_get_function_identity_arguments(p.oid) = 'p_employee_id uuid, p_date date';

  IF v_legacy_hash IS DISTINCT FROM '3cba7e6bfed001d409ca4e868344a799' THEN
    RAISE EXCEPTION 'Batch 3A1 verification failed: Legacy work-day classifier body drifted';
  END IF;

  SELECT p.prosrc
  INTO v_wrapper_body
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'is_employee_work_day'
    AND pg_get_function_identity_arguments(p.oid) = 'p_employee_id uuid, p_date date';

  IF v_wrapper_body IS NULL
     OR position('IF NOT public.hr_variable_schedules_v2_runtime_enabled()' in v_wrapper_body) = 0
     OR position('resolve_employee_custom_schedule' in v_wrapper_body) = 0
     OR position('IF NOT public.hr_variable_schedules_v2_runtime_enabled()' in v_wrapper_body)
        > position('resolve_employee_custom_schedule' in v_wrapper_body)
     OR position('hr_public_holidays' in v_wrapper_body) = 0
     OR position('RETURN ''public_holiday''' in v_wrapper_body) = 0
     OR position('RETURN ''weekly_off''' in v_wrapper_body) = 0 THEN
    RAISE EXCEPTION 'Batch 3A1 verification failed: compatibility classifier contract incomplete';
  END IF;

  IF NOT has_function_privilege('anon', 'public.is_employee_work_day(uuid,date)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.is_employee_work_day(uuid,date)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Batch 3A1 verification failed: public classifier execute contract changed';
  END IF;

  IF has_function_privilege('anon', 'public.is_employee_work_day_legacy(uuid,date)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.is_employee_work_day_legacy(uuid,date)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Batch 3A1 verification failed: Legacy classifier alias became externally executable';
  END IF;

  -- Batch 3A1 must not rewrite the absence engine itself.
  SELECT md5(pg_get_functiondef(p.oid))
  INTO v_absence_hash
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'mark_daily_absences'
    AND pg_get_function_identity_arguments(p.oid) = 'p_target_date date';

  IF v_absence_hash IS DISTINCT FROM '21e4cb27c5d1008da928cbf14ad56f1b' THEN
    RAISE EXCEPTION 'Batch 3A1 verification failed: mark_daily_absences was unexpectedly modified';
  END IF;
END;
$verify$;
