-- HR Variable Schedules V2 — Batch 4B payroll simulation
-- Rollback-only. Executes the real custom payroll implementation against synthetic
-- data and proves schedule-derived workdays/hours feed payroll without changing
-- unrelated salary components.

BEGIN;

-- The isolated HR snapshot intentionally excludes unrelated payroll-support
-- modules. The real payroll engine still reads these relations, so provide only
-- the empty columns it actually touches inside this rollback-only simulation.
CREATE TABLE public.hr_payroll_adjustments (
  employee_id uuid NOT NULL,
  type text NOT NULL,
  amount numeric NOT NULL,
  reason text NOT NULL,
  effective_date date NOT NULL,
  status text NOT NULL,
  created_by uuid,
  payroll_line_id uuid
);

CREATE TABLE public.hr_commission_records (
  employee_id uuid NOT NULL,
  period_id uuid NOT NULL,
  commission_amount numeric NOT NULL DEFAULT 0,
  is_eligible boolean NOT NULL DEFAULT false,
  included_in_run uuid
);

CREATE TABLE public.hr_advances (
  id uuid PRIMARY KEY,
  employee_id uuid NOT NULL
);

CREATE TABLE public.hr_advance_installments (
  advance_id uuid NOT NULL,
  amount numeric NOT NULL DEFAULT 0,
  due_year integer NOT NULL,
  due_month integer NOT NULL,
  status text NOT NULL
);

-- Isolate the payroll math from permissions/clearance and salary-history data.
-- These replacements exist only inside this transaction and are fully rolled back.
CREATE OR REPLACE FUNCTION public.check_permission(p_user_id uuid, p_permission text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $function$
  SELECT true;
$function$;

CREATE OR REPLACE FUNCTION public.check_payroll_attendance_clearance(
  p_date_from date,
  p_date_to date,
  p_branch_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $function$
  SELECT jsonb_build_object('cleared', true, 'blockers', '[]'::jsonb);
$function$;

CREATE OR REPLACE FUNCTION public.get_employee_salary_at_date(
  p_employee_id uuid,
  p_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  base_salary numeric,
  transport_allowance numeric,
  housing_allowance numeric,
  other_allowances numeric,
  gross_salary numeric,
  effective_date date
)
LANGUAGE sql
STABLE
AS $function$
  SELECT
    6000::numeric,
    0::numeric,
    0::numeric,
    0::numeric,
    6000::numeric,
    DATE '2020-06-01';
$function$;

CREATE OR REPLACE FUNCTION public.hr_variable_schedules_v2_runtime_enabled()
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT true;
$function$;

DO $fixture$
DECLARE
  v_employee_id uuid := '94100000-0000-0000-0000-000000000001'::uuid;
  v_period_id uuid := '94100000-0000-0000-0000-000000000002'::uuid;
  v_run_id uuid := '94100000-0000-0000-0000-000000000003'::uuid;
  v_schedule_id uuid := '94100000-0000-0000-0000-000000000004'::uuid;
BEGIN
  INSERT INTO public.hr_employees (
    id, employee_number, full_name, personal_phone, hire_date, status,
    base_salary
  ) VALUES (
    v_employee_id, 'V2-B4B-PAYROLL', 'V2 Batch 4B Payroll Fixture', '01000000013',
    DATE '2019-01-01', 'active', 6000
  );

  INSERT INTO public.hr_payroll_periods (
    id, year, month, name, start_date, end_date
  ) VALUES (
    v_period_id, 2020, 6, 'V2 Batch 4B payroll simulation', DATE '2020-06-01', DATE '2020-06-30'
  );

  INSERT INTO public.hr_payroll_runs (id, number, period_id, status)
  VALUES (v_run_id, 'V2-B4B-PAYROLL', v_period_id, 'draft');

  INSERT INTO public.company_settings (key, value)
  VALUES
    ('hr.overtime_rate', '1.5'),
    ('hr.social_insurance.enabled', 'false'),
    ('hr.social_insurance.employee_rate', '11'),
    ('hr.income_tax.enabled', 'false'),
    ('hr.health_insurance.enabled', 'false'),
    ('hr.health_insurance.amount', '0')
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

  -- Historical dates are simulation-only. Lifecycle triggers remain authoritative
  -- in normal runtime and are disabled only long enough to create this local fixture.
  ALTER TABLE public.hr_employee_work_schedules
    DISABLE TRIGGER trg_hr_employee_work_schedules_lifecycle;
  ALTER TABLE public.hr_employee_work_schedule_days
    DISABLE TRIGGER trg_hr_employee_work_schedule_days_lifecycle;

  INSERT INTO public.hr_employee_work_schedules (
    id, employee_id, effective_from, effective_to, notes
  ) VALUES (
    v_schedule_id, v_employee_id, DATE '2020-06-01', DATE '2020-06-30',
    'Rollback-only Batch 4B payroll fixture'
  );

  -- Sunday-Thursday, 6 hours/day. Friday/Saturday are custom off.
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

  -- Full attendance on every scheduled workday. Exactly one day carries two
  -- overtime hours so the hourly denominator can be verified from scheduled hours.
  INSERT INTO public.hr_attendance_days (
    employee_id,
    shift_date,
    work_date,
    status,
    day_value,
    overtime_minutes,
    custom_schedule_id,
    custom_scheduled_start,
    custom_scheduled_end,
    custom_scheduled_minutes
  )
  SELECT
    v_employee_id,
    gs::date,
    gs::date,
    'present'::hr_attendance_status,
    1,
    CASE WHEN row_number() OVER (ORDER BY gs) = 1 THEN 120 ELSE 0 END,
    d.custom_schedule_id,
    TIME '09:00',
    TIME '15:00',
    d.scheduled_minutes
  FROM generate_series(DATE '2020-06-01', DATE '2020-06-30', interval '1 day') gs
  CROSS JOIN LATERAL public.hr_v2_resolve_payroll_schedule_day(v_employee_id, gs::date) d
  WHERE d.is_working_day;
END;
$fixture$;

DO $simulation$
DECLARE
  v_employee_id uuid := '94100000-0000-0000-0000-000000000001'::uuid;
  v_run_id uuid := '94100000-0000-0000-0000-000000000003'::uuid;
  v_line_id uuid;
  v_metrics record;
  v_line record;
  v_expected_overtime numeric;
BEGIN
  SELECT *
  INTO v_metrics
  FROM public.hr_v2_get_payroll_schedule_metrics(
    v_employee_id,
    DATE '2020-06-01',
    DATE '2020-06-30'
  );

  IF v_metrics.custom_dates <> 30
     OR v_metrics.work_days <= 0
     OR v_metrics.scheduled_minutes <> v_metrics.work_days * 360 THEN
    RAISE EXCEPTION 'Batch 4B payroll simulation failed: fixture metrics invalid';
  END IF;

  SELECT public.calculate_employee_payroll(v_employee_id, v_run_id)
  INTO v_line_id;

  SELECT *
  INTO v_line
  FROM public.hr_payroll_lines
  WHERE id = v_line_id;

  v_expected_overtime := ROUND(
    2 * (6000 / (v_metrics.scheduled_minutes::numeric / 60.0)) * 1.5,
    2
  );

  IF v_line.total_working_days <> v_metrics.work_days THEN
    RAISE EXCEPTION
      'Batch 4B payroll simulation failed: payroll workdays % != schedule workdays %',
      v_line.total_working_days, v_metrics.work_days;
  END IF;

  IF v_line.actual_work_days <> v_metrics.work_days
     OR v_line.absent_days <> 0
     OR v_line.absence_deduction <> 0 THEN
    RAISE EXCEPTION 'Batch 4B payroll simulation failed: full scheduled attendance produced absence';
  END IF;

  IF v_line.gross_earned <> 6000
     OR v_line.base_salary <> 6000
     OR v_line.transport_allowance <> 0
     OR v_line.housing_allowance <> 0
     OR v_line.other_allowances <> 0 THEN
    RAISE EXCEPTION 'Batch 4B payroll simulation failed: unrelated salary components changed';
  END IF;

  IF abs(v_line.overtime_amount - v_expected_overtime) > 0.01 THEN
    RAISE EXCEPTION
      'Batch 4B payroll simulation failed: overtime % != schedule-hour expected %',
      v_line.overtime_amount, v_expected_overtime;
  END IF;

  IF v_line.commission_amount <> 0
     OR v_line.advance_deduction <> 0
     OR v_line.social_insurance <> 0
     OR v_line.income_tax <> 0
     OR v_line.health_insurance <> 0
     OR v_line.other_deductions <> 0
     OR v_line.deficit_carryover <> 0 THEN
    RAISE EXCEPTION 'Batch 4B payroll simulation failed: unrelated payroll component became non-zero';
  END IF;

  IF abs(v_line.net_salary - (6000 + v_expected_overtime)) > 0.01 THEN
    RAISE EXCEPTION 'Batch 4B payroll simulation failed: net salary does not match isolated expected value';
  END IF;
END;
$simulation$;

ROLLBACK;

DO $post_rollback$
BEGIN
  IF public.hr_variable_schedules_v2_runtime_enabled() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Batch 4B payroll simulation failed: runtime gate survived rollback';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.hr_employees WHERE employee_number = 'V2-B4B-PAYROLL'
  ) OR EXISTS (
    SELECT 1 FROM public.hr_payroll_runs WHERE number = 'V2-B4B-PAYROLL'
  ) THEN
    RAISE EXCEPTION 'Batch 4B payroll simulation failed: fixture survived rollback';
  END IF;
END;
$post_rollback$;

SELECT 'batch4b_payroll_simulation_pass' AS result;
