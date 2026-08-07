-- HR Variable Schedules V2 — Batch 3C verification
-- Read-only contract assertions for public-holiday precedence.

DO $verify$
DECLARE
  v_body text;
BEGIN
  IF public.hr_variable_schedules_v2_runtime_enabled() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Batch 3C verification failed: V2 runtime gate must remain false';
  END IF;

  SELECT p.prosrc
  INTO v_body
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'resolve_employee_custom_schedule'
    AND pg_get_function_identity_arguments(p.oid) = 'p_employee_id uuid, p_date date';

  IF v_body IS NULL
     OR position('hr_public_holidays' in v_body) = 0
     OR position('holiday_date = p_date' in v_body) = 0
     OR position('WHEN holiday.is_public_holiday THEN false' in v_body) = 0
     OR position('WHEN holiday.is_public_holiday THEN NULL::time without time zone' in v_body) = 0
     OR position('WHEN holiday.is_public_holiday THEN 0' in v_body) = 0
     OR position('COUNT(*)' in v_body) = 0
     OR position('work_days.is_working_day = true' in v_body) = 0 THEN
    RAISE EXCEPTION 'Batch 3C verification failed: resolver holiday/fallback contract incomplete';
  END IF;

  IF has_function_privilege('anon', 'public.resolve_employee_custom_schedule(uuid,date)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.resolve_employee_custom_schedule(uuid,date)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.resolve_employee_custom_schedule(uuid,date)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Batch 3C verification failed: resolver execute ACL changed';
  END IF;

  -- The two attendance consumers that create/refresh custom schedule snapshots
  -- must continue to source their runtime context through this central resolver.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'record_attendance_gps_v2_custom_schedule'
      AND position('resolve_employee_custom_schedule' in p.prosrc) > 0
  ) THEN
    RAISE EXCEPTION 'Batch 3C verification failed: GPS custom path is not using central resolver';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'upsert_attendance_and_reprocess_custom_schedule'
      AND position('resolve_employee_custom_schedule' in p.prosrc) > 0
  ) THEN
    RAISE EXCEPTION 'Batch 3C verification failed: admin attendance custom path is not using central resolver';
  END IF;
END;
$verify$;

SELECT 'batch3c_verify_pass' AS result;
