-- HR Variable Schedules V2 — Batch 4B verification
-- Read-only assertions for payroll compatibility routing and custom-only schedule inputs.

DO $verify$
DECLARE
  v_hash text;
  v_wrapper text;
  v_custom text;
BEGIN
  IF public.hr_variable_schedules_v2_runtime_enabled() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Batch 4B verification failed: runtime gate must remain false';
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n'))
  INTO v_hash
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'calculate_employee_payroll_legacy'
    AND pg_get_function_identity_arguments(p.oid) = 'p_employee_id uuid, p_run_id uuid';

  IF v_hash IS DISTINCT FROM 'c24e182e9088e1a219d40aafb9e8c43a' THEN
    RAISE EXCEPTION
      'Batch 4B verification failed: exact Legacy payroll body was not preserved (actual=%)',
      v_hash;
  END IF;

  SELECT p.prosrc
  INTO v_wrapper
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'calculate_employee_payroll'
    AND pg_get_function_identity_arguments(p.oid) = 'p_employee_id uuid, p_run_id uuid';

  IF v_wrapper IS NULL
     OR position('hr_variable_schedules_v2_runtime_enabled' in v_wrapper) = 0
     OR position('calculate_employee_payroll_legacy' in v_wrapper) = 0
     OR position('calculate_employee_payroll_custom_schedule' in v_wrapper) = 0
     OR position('hr_employee_work_schedules' in v_wrapper) = 0
     OR position('COUNT(*)' in v_wrapper) = 0 THEN
    RAISE EXCEPTION 'Batch 4B verification failed: public payroll compatibility wrapper incomplete';
  END IF;

  SELECT p.prosrc
  INTO v_custom
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'calculate_employee_payroll_custom_schedule'
    AND pg_get_function_identity_arguments(p.oid) = 'p_employee_id uuid, p_run_id uuid';

  IF v_custom IS NULL
     OR position('hr_v2_get_payroll_schedule_metrics' in v_custom) = 0
     OR position('v_v2_full_metrics.scheduled_minutes' in v_custom) = 0
     OR position('v_work_hours_per_day :=' in v_custom) = 0
     OR position('v_partial_working := COALESCE(v_v2_range_metrics.work_days, 0)' in v_custom) = 0 THEN
    RAISE EXCEPTION 'Batch 4B verification failed: custom payroll schedule inputs incomplete';
  END IF;

  IF position('IF v_calendar_days <= 0 THEN v_calendar_days := 26; END IF;' in v_custom) > 0
     OR position('IF v_partial_working <= 0 THEN v_partial_working := 1; END IF;' in v_custom) > 0 THEN
    RAISE EXCEPTION 'Batch 4B verification failed: Legacy synthetic workday fallback survived custom path';
  END IF;

  -- Unrelated payroll components must remain present in the derived custom body.
  IF position('hr_commission_records' in v_custom) = 0
     OR position('hr_advance_installments' in v_custom) = 0
     OR position('hr.social_insurance.enabled' in v_custom) = 0
     OR position('hr.income_tax.enabled' in v_custom) = 0
     OR position('hr.health_insurance.enabled' in v_custom) = 0
     OR position('hr_payroll_adjustments' in v_custom) = 0
     OR position('deficit_carryover' in v_custom) = 0
     OR position('ON CONFLICT (payroll_run_id, employee_id) DO UPDATE' in v_custom) = 0 THEN
    RAISE EXCEPTION 'Batch 4B verification failed: unrelated payroll engine component was lost';
  END IF;

  IF has_function_privilege('anon', 'public.calculate_employee_payroll_legacy(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.calculate_employee_payroll_legacy(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.calculate_employee_payroll_legacy(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.calculate_employee_payroll_custom_schedule(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.calculate_employee_payroll_custom_schedule(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.calculate_employee_payroll_custom_schedule(uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Batch 4B verification failed: private payroll implementation became externally executable';
  END IF;

  IF NOT has_function_privilege('authenticated', 'public.calculate_employee_payroll(uuid,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.calculate_employee_payroll(uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Batch 4B verification failed: public payroll callable surface lost execute privilege';
  END IF;
END;
$verify$;

SELECT 'batch4b_verify_pass' AS result;
