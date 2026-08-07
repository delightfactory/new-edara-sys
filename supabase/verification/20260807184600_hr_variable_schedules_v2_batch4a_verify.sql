-- HR Variable Schedules V2 — Batch 4A verification
-- Read-only assertions: helpers exist, remain private, and official payroll code is untouched.

DO $verify$
DECLARE
  v_hash text;
  v_day_body text;
  v_metrics_body text;
BEGIN
  IF public.hr_variable_schedules_v2_runtime_enabled() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Batch 4A verification failed: V2 runtime gate must remain false';
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n'))
  INTO v_hash
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'calculate_employee_payroll'
    AND pg_get_function_identity_arguments(p.oid) = 'p_employee_id uuid, p_run_id uuid';

  IF v_hash IS DISTINCT FROM 'c24e182e9088e1a219d40aafb9e8c43a' THEN
    RAISE EXCEPTION
      'Batch 4A verification failed: calculate_employee_payroll changed (actual=%)',
      v_hash;
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n'))
  INTO v_hash
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'calculate_payroll_run'
    AND pg_get_function_identity_arguments(p.oid) = 'p_run_id uuid';

  IF v_hash IS DISTINCT FROM '2b79ef75f35f8deb2f2daa768e64d50f' THEN
    RAISE EXCEPTION 'Batch 4A verification failed: calculate_payroll_run changed (actual=%)', v_hash;
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n'))
  INTO v_hash
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'approve_payroll_run'
    AND pg_get_function_identity_arguments(p.oid) = 'p_run_id uuid, p_user_id uuid';

  IF v_hash IS DISTINCT FROM '4a3e9678f6a4c7b74f422d47c8239465' THEN
    RAISE EXCEPTION 'Batch 4A verification failed: approve_payroll_run changed (actual=%)', v_hash;
  END IF;

  SELECT p.prosrc
  INTO v_day_body
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'hr_v2_resolve_payroll_schedule_day'
    AND pg_get_function_identity_arguments(p.oid) = 'p_employee_id uuid, p_date date';

  IF v_day_body IS NULL
     OR position('resolve_employee_custom_schedule' in v_day_body) = 0
     OR position('is_employee_work_day_legacy' in v_day_body) = 0
     OR position('hr.work_hours_per_day' in v_day_body) = 0
     OR position('scheduled_minutes := 0' in v_day_body) = 0
     OR position('public_holiday' in v_day_body) = 0
     OR position('custom_off' in v_day_body) = 0 THEN
    RAISE EXCEPTION 'Batch 4A verification failed: day helper contract incomplete';
  END IF;

  SELECT p.prosrc
  INTO v_metrics_body
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nname = 'public'
    AND p.proname = 'hr_v2_get_payroll_schedule_metrics'
    AND pg_get_function_identity_arguments(p.oid) = 'p_employee_id uuid, p_date_from date, p_date_to date';

  IF v_metrics_body IS NULL
     OR position('generate_series' in v_metrics_body) = 0
     OR position('hr_v2_resolve_payroll_schedule_day' in v_metrics_body) = 0
     OR position('work_days := 0' in v_metrics_body) = 0
     OR position('scheduled_minutes := 0' in v_metrics_body) = 0
     OR position('work_days := work_days + 1' in v_metrics_body) = 0 THEN
    RAISE EXCEPTION 'Batch 4A verification failed: range metrics contract incomplete';
  END IF;

  IF has_function_privilege('anon', 'public.hr_v2_resolve_payroll_schedule_day(uuid,date)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.hr_v2_resolve_payroll_schedule_day(uuid,date)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.hr_v2_resolve_payroll_schedule_day(uuid,date)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.hr_v2_get_payroll_schedule_metrics(uuid,date,date)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.hr_v2_get_payroll_schedule_metrics(uuid,date,date)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.hr_v2_get_payroll_schedule_metrics(uuid,date,date)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Batch 4A verification failed: private payroll helper became externally executable';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('hr_v2_resolve_payroll_schedule_day', 'hr_v2_get_payroll_schedule_metrics')
      AND p.provolatile = 's'
    GROUP BY n.nspname
    HAVING count(*) = 2
  ) THEN
    RAISE EXCEPTION 'Batch 4A verification failed: payroll metrics helpers must remain STABLE';
  END IF;
END;
$verify$;

SELECT 'batch4a_verify_pass' AS result;
