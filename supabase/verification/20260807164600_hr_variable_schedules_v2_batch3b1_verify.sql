-- HR Variable Schedules V2 — Batch 3B1 verification
-- Read-only structural/contract assertions for the isolated PostgreSQL rehearsal.

DO $verify$
DECLARE
  v_legacy_hash text;
  v_wrapper_body text;
  v_custom_body text;
BEGIN
  IF public.hr_variable_schedules_v2_runtime_enabled() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Batch 3B1 verification failed: V2 runtime gate must remain false';
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n'))
  INTO v_legacy_hash
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'run_auto_checkout_legacy'
    AND pg_get_function_identity_arguments(p.oid) = 'p_target_date date';

  IF v_legacy_hash IS DISTINCT FROM 'd13869f50592c2dc31c63e9212183c81' THEN
    RAISE EXCEPTION 'Batch 3B1 verification failed: Legacy auto-checkout body drifted';
  END IF;

  SELECT p.prosrc
  INTO v_wrapper_body
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'run_auto_checkout'
    AND pg_get_function_identity_arguments(p.oid) = 'p_target_date date';

  IF v_wrapper_body IS NULL
     OR position('IF NOT public.hr_variable_schedules_v2_runtime_enabled()' in v_wrapper_body) = 0
     OR position('run_auto_checkout_legacy' in v_wrapper_body) = 0
     OR position('resolve_employee_custom_schedule' in v_wrapper_body) = 0
     OR position('run_auto_checkout_custom_schedule' in v_wrapper_body) = 0 THEN
    RAISE EXCEPTION 'Batch 3B1 verification failed: compatibility wrapper contract incomplete';
  END IF;

  IF position('IF NOT public.hr_variable_schedules_v2_runtime_enabled()' in v_wrapper_body)
     > position('resolve_employee_custom_schedule' in v_wrapper_body) THEN
    RAISE EXCEPTION 'Batch 3B1 verification failed: runtime gate is not checked before custom lookup';
  END IF;

  SELECT p.prosrc
  INTO v_custom_body
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'run_auto_checkout_custom_schedule'
    AND pg_get_function_identity_arguments(p.oid) = 'p_target_date date';

  IF v_custom_body IS NULL
     OR position('custom_schedule_id IS NOT NULL' in v_custom_body) = 0
     OR position('custom_scheduled_end' in v_custom_body) = 0
     OR position('resolve_employee_custom_schedule' in v_custom_body) = 0
     OR position('v_has_custom_schedule AND NOT v_custom_working_day' in v_custom_body) = 0
     OR position('CONTINUE' in v_custom_body) = 0
     OR position('v_day_work_end := v_company_work_end' in v_custom_body) = 0
     OR position('COALESCE(d.is_manually_locked, false) = false' in v_custom_body) = 0
     OR position('pr.status IN (''approved'', ''paid'')' in v_custom_body) = 0
     OR position('hr.auto_checkout_minutes' in v_custom_body) = 0
     OR position('v_cutoff_time := v_scheduled_end' in v_custom_body) = 0
     OR position('settle_attendance_day_against_leave' in v_custom_body) = 0
     OR position('reprocess_attendance_day_penalties' in v_custom_body) = 0 THEN
    RAISE EXCEPTION 'Batch 3B1 verification failed: custom auto-checkout safety contract incomplete';
  END IF;

  IF NOT has_function_privilege('anon', 'public.run_auto_checkout(date)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.run_auto_checkout(date)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.run_auto_checkout(date)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Batch 3B1 verification failed: public auto-checkout execute contract changed';
  END IF;

  IF has_function_privilege('anon', 'public.run_auto_checkout_legacy(date)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.run_auto_checkout_legacy(date)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.run_auto_checkout_custom_schedule(date)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.run_auto_checkout_custom_schedule(date)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Batch 3B1 verification failed: internal auto-checkout helper became externally executable';
  END IF;
END;
$verify$;

SELECT 'batch3b1_verify_pass' AS result;
