-- HR Variable Schedules V2 — Batch 4B routing simulation
-- Rollback-only. Proves the public payroll adapter selects exact Legacy by default,
-- remains Legacy when V2 is enabled but the employee has no complete custom schedule,
-- and selects the custom implementation only for a covered employee.

BEGIN;

DO $fixture$
DECLARE
  v_period_id uuid := '94000000-0000-0000-0000-000000000001'::uuid;
  v_run_id uuid := '94000000-0000-0000-0000-000000000002'::uuid;
  v_legacy_employee uuid := '94000000-0000-0000-0000-000000000003'::uuid;
  v_custom_employee uuid := '94000000-0000-0000-0000-000000000004'::uuid;
  v_schedule_id uuid := '94000000-0000-0000-0000-000000000005'::uuid;
BEGIN
  INSERT INTO public.hr_payroll_periods (
    id, year, month, name, start_date, end_date
  ) VALUES (
    v_period_id, 2020, 6, 'V2 Batch 4B routing fixture', DATE '2020-06-01', DATE '2020-06-30'
  );

  INSERT INTO public.hr_payroll_runs (id, number, period_id, status)
  VALUES (v_run_id, 'V2-B4B-ROUTING', v_period_id, 'draft');

  INSERT INTO public.hr_employees (
    id, employee_number, full_name, personal_phone, hire_date, status
  ) VALUES
    (v_legacy_employee, 'V2-B4B-LEGACY', 'V2 Batch 4B Legacy Route', '01000000011', DATE '2019-01-01', 'active'),
    (v_custom_employee, 'V2-B4B-CUSTOM', 'V2 Batch 4B Custom Route', '01000000012', DATE '2019-01-01', 'active');

  -- Historical custom schedule is required only to exercise routing. Production
  -- lifecycle guards intentionally forbid creating it, so disable these two V2
  -- triggers inside this rollback-only local simulation.
  ALTER TABLE public.hr_employee_work_schedules
    DISABLE TRIGGER trg_hr_employee_work_schedules_lifecycle;
  ALTER TABLE public.hr_employee_work_schedule_days
    DISABLE TRIGGER trg_hr_employee_work_schedule_days_lifecycle;

  INSERT INTO public.hr_employee_work_schedules (
    id, employee_id, effective_from, effective_to, notes
  ) VALUES (
    v_schedule_id, v_custom_employee, DATE '2020-06-01', DATE '2020-06-30',
    'Rollback-only Batch 4B routing fixture'
  );

  INSERT INTO public.hr_employee_work_schedule_days (
    schedule_id, day_of_week, is_working_day, start_time, end_time
  )
  SELECT
    v_schedule_id,
    dow::smallint,
    (dow BETWEEN 0 AND 4),
    CASE WHEN dow BETWEEN 0 AND 4 THEN TIME '09:00' ELSE NULL END,
    CASE WHEN dow BETWEEN 0 AND 4 THEN TIME '15:00' ELSE NULL END
  FROM generate_series(0, 6) AS dow;

  ALTER TABLE public.hr_employee_work_schedule_days
    ENABLE TRIGGER trg_hr_employee_work_schedule_days_lifecycle;
  ALTER TABLE public.hr_employee_work_schedules
    ENABLE TRIGGER trg_hr_employee_work_schedules_lifecycle;
END;
$fixture$;

-- Replace private implementations with deterministic sentinels only inside this
-- transaction. ROLLBACK restores the real derived functions afterward.
CREATE OR REPLACE FUNCTION public.calculate_employee_payroll_legacy(
  p_employee_id uuid,
  p_run_id uuid
)
RETURNS uuid
LANGUAGE sql
AS $function$
  SELECT '94000000-0000-0000-0000-000000000101'::uuid;
$function$;

CREATE OR REPLACE FUNCTION public.calculate_employee_payroll_custom_schedule(
  p_employee_id uuid,
  p_run_id uuid
)
RETURNS uuid
LANGUAGE sql
AS $function$
  SELECT '94000000-0000-0000-0000-000000000102'::uuid;
$function$;

DO $gate_false$
DECLARE
  v_result uuid;
BEGIN
  SELECT public.calculate_employee_payroll(
    '94000000-0000-0000-0000-000000000004'::uuid,
    '94000000-0000-0000-0000-000000000002'::uuid
  ) INTO v_result;

  IF v_result IS DISTINCT FROM '94000000-0000-0000-0000-000000000101'::uuid THEN
    RAISE EXCEPTION 'Batch 4B routing simulation failed: gate=false did not use Legacy';
  END IF;
END;
$gate_false$;

CREATE OR REPLACE FUNCTION public.hr_variable_schedules_v2_runtime_enabled()
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT true;
$function$;

DO $gate_true$
DECLARE
  v_result uuid;
BEGIN
  SELECT public.calculate_employee_payroll(
    '94000000-0000-0000-0000-000000000003'::uuid,
    '94000000-0000-0000-0000-000000000002'::uuid
  ) INTO v_result;

  IF v_result IS DISTINCT FROM '94000000-0000-0000-0000-000000000101'::uuid THEN
    RAISE EXCEPTION 'Batch 4B routing simulation failed: no-custom employee did not use Legacy';
  END IF;

  SELECT public.calculate_employee_payroll(
    '94000000-0000-0000-0000-000000000004'::uuid,
    '94000000-0000-0000-0000-000000000002'::uuid
  ) INTO v_result;

  IF v_result IS DISTINCT FROM '94000000-0000-0000-0000-000000000102'::uuid THEN
    RAISE EXCEPTION 'Batch 4B routing simulation failed: custom-covered employee did not use custom payroll';
  END IF;
END;
$gate_true$;

ROLLBACK;

DO $post_rollback$
BEGIN
  IF public.hr_variable_schedules_v2_runtime_enabled() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Batch 4B routing simulation failed: runtime gate survived rollback';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.hr_employees
    WHERE employee_number IN ('V2-B4B-LEGACY', 'V2-B4B-CUSTOM')
  ) THEN
    RAISE EXCEPTION 'Batch 4B routing simulation failed: fixture survived rollback';
  END IF;
END;
$post_rollback$;

SELECT 'batch4b_routing_simulation_pass' AS result;
