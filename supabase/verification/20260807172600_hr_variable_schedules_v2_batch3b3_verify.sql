-- HR Variable Schedules V2 — Batch 3B3 verification
-- Read-only assertions for the isolated PostgreSQL rehearsal.

DO $verify$
DECLARE
  v_legacy_hash text;
  v_wrapper_body text;
  v_custom_body text;
BEGIN
  IF public.hr_variable_schedules_v2_runtime_enabled() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Batch 3B3 verification failed: V2 runtime gate must remain false';
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n'))
  INTO v_legacy_hash
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'settle_attendance_day_against_leave_legacy'
    AND pg_get_function_identity_arguments(p.oid) = 'p_attendance_day_id uuid, p_force boolean';

  IF v_legacy_hash IS DISTINCT FROM 'f0cd9bc5b6787e76aa970de6a9ce9370' THEN
    RAISE EXCEPTION 'Batch 3B3 verification failed: Legacy leave-settlement body drifted';
  END IF;

  SELECT p.prosrc
  INTO v_wrapper_body
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'settle_attendance_day_against_leave'
    AND pg_get_function_identity_arguments(p.oid) = 'p_attendance_day_id uuid, p_force boolean';

  IF v_wrapper_body IS NULL
     OR position('IF NOT public.hr_variable_schedules_v2_runtime_enabled()' in v_wrapper_body) = 0
     OR position('settle_attendance_day_against_leave_legacy' in v_wrapper_body) = 0
     OR position('source_leave_request_id IS NULL' in v_wrapper_body) = 0
     OR position('custom_schedule_id IS NOT NULL' in v_wrapper_body) = 0
     OR position('resolve_employee_custom_schedule' in v_wrapper_body) = 0
     OR position('IF NOT v_is_custom_working_day' in v_wrapper_body) = 0
     OR position('settle_attendance_day_against_leave_custom_schedule' in v_wrapper_body) = 0 THEN
    RAISE EXCEPTION 'Batch 3B3 verification failed: compatibility wrapper contract incomplete';
  END IF;

  IF position('IF NOT public.hr_variable_schedules_v2_runtime_enabled()' in v_wrapper_body)
     > position('resolve_employee_custom_schedule' in v_wrapper_body) THEN
    RAISE EXCEPTION 'Batch 3B3 verification failed: runtime gate is not checked before custom lookup';
  END IF;

  SELECT p.prosrc
  INTO v_custom_body
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'settle_attendance_day_against_leave_custom_schedule'
    AND pg_get_function_identity_arguments(p.oid) = 'p_attendance_day_id uuid, p_force boolean';

  IF v_custom_body IS NULL
     OR position('custom_scheduled_minutes' in v_custom_body) = 0
     OR position('resolve_employee_custom_schedule' in v_custom_body) = 0
     OR position('v_work_hours := v_scheduled_minutes::numeric / 60.0' in v_custom_body) = 0
     OR position('leave_balance_restored' in v_custom_body) = 0
     OR position('used_days = GREATEST(0, used_days - 1)' in v_custom_body) = 0
     OR position('pr.status IN (''approved'', ''paid'')' in v_custom_body) = 0
     OR position('COALESCE(v_day.effective_hours, 0) >= v_work_hours' in v_custom_body) = 0
     OR position('COALESCE(v_day.effective_hours, 0) / v_work_hours' in v_custom_body) = 0 THEN
    RAISE EXCEPTION 'Batch 3B3 verification failed: custom leave-settlement duration contract incomplete';
  END IF;

  IF NOT has_function_privilege('anon', 'public.settle_attendance_day_against_leave(uuid,boolean)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.settle_attendance_day_against_leave(uuid,boolean)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.settle_attendance_day_against_leave(uuid,boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Batch 3B3 verification failed: public leave-settlement execute contract changed';
  END IF;

  IF has_function_privilege('anon', 'public.settle_attendance_day_against_leave_legacy(uuid,boolean)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.settle_attendance_day_against_leave_legacy(uuid,boolean)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.settle_attendance_day_against_leave_custom_schedule(uuid,boolean)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.settle_attendance_day_against_leave_custom_schedule(uuid,boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Batch 3B3 verification failed: internal leave-settlement helper became externally executable';
  END IF;
END;
$verify$;

SELECT 'batch3b3_verify_pass' AS result;
