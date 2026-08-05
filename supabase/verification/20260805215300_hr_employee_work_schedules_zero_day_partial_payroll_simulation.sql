-- =============================================================================
-- Employee Work Schedules — zero scheduled-day partial payroll simulation
--
-- DISPOSABLE DATABASE ONLY.
-- Required session guard:
--   SET SESSION edara.allow_schedule_simulation = 'disposable-only';
--
-- Proves that a hire/entitlement interval containing no scheduled workday earns
-- zero days and zero gross salary instead of the inherited synthetic one day.
-- Every inserted row is rolled back.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '180s';

DO $simulation$
DECLARE
  v_actor UUID;
  v_period_start DATE;
  v_period_end DATE;
  v_period_id UUID := extensions.gen_random_uuid();
  v_run_id UUID := extensions.gen_random_uuid();
  v_employee_id UUID := extensions.gen_random_uuid();
  v_suffix TEXT := substr(replace(extensions.gen_random_uuid()::TEXT, '-', ''), 1, 10);
  v_off_day public.hr_day_of_week;
  v_full_work_days INTEGER;
  v_partial_work_days INTEGER;
  v_line public.hr_payroll_lines%ROWTYPE;
BEGIN
  IF current_setting('edara.allow_schedule_simulation', true) IS DISTINCT FROM 'disposable-only' THEN
    RAISE EXCEPTION 'Simulation safety stop: disposable-only session flag is required';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Simulation requires feature/readiness to remain false';
  END IF;

  SELECT candidate.user_id
  INTO v_actor
  FROM (
    SELECT ur.user_id
    FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id = ur.role_id
    GROUP BY ur.user_id
    HAVING bool_or(rp.permission = '*')
       OR bool_or(rp.permission = 'hr.payroll.calculate')
       OR bool_or(rp.permission = 'hr.payroll.approve')
  ) candidate
  JOIN public.profiles p ON p.id = candidate.user_id
  ORDER BY candidate.user_id
  LIMIT 1;

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Simulation could not find a payroll-capable actor';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_actor::TEXT, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  SELECT make_date(y, m, 1)
  INTO v_period_start
  FROM generate_series(2023, 2025) y
  CROSS JOIN generate_series(1, 12) m
  WHERE make_date(y, m, 1) < date_trunc('month', now() AT TIME ZONE 'Africa/Cairo')::DATE
    AND NOT EXISTS (
      SELECT 1
      FROM public.hr_payroll_periods pp
      WHERE pp.year = y AND pp.month = m
    )
  ORDER BY y DESC, m DESC
  LIMIT 1;

  IF v_period_start IS NULL THEN
    RAISE EXCEPTION 'Simulation could not find an unused completed payroll month';
  END IF;

  v_period_end := (v_period_start + INTERVAL '1 month - 1 day')::DATE;
  v_off_day := public.hr_day_of_week_for_date(v_period_end);

  INSERT INTO public.hr_employees (
    id,
    employee_number,
    full_name,
    personal_phone,
    status,
    hire_date,
    weekly_off_day,
    is_field_employee,
    base_salary,
    created_by,
    notes
  ) VALUES (
    v_employee_id,
    'SIM-ZERO-' || v_suffix,
    'محاكاة استحقاق صفر أيام',
    '+999810' || v_suffix,
    'active',
    v_period_end,
    v_off_day,
    false,
    6000,
    v_actor,
    'Disposable zero-day partial payroll simulation'
  );

  INSERT INTO public.hr_salary_history (
    employee_id,
    effective_date,
    base_salary,
    transport_allowance,
    housing_allowance,
    other_allowances,
    change_reason,
    changed_by
  ) VALUES (
    v_employee_id,
    v_period_end,
    6000,
    0,
    0,
    0,
    'Disposable zero-day payroll salary',
    v_actor
  );

  SELECT p.scheduled_work_days
  INTO v_full_work_days
  FROM public.get_employee_scheduled_period(
    v_employee_id,
    v_period_start,
    v_period_end,
    true
  ) p;

  SELECT p.scheduled_work_days
  INTO v_partial_work_days
  FROM public.get_employee_scheduled_period(
    v_employee_id,
    v_period_end,
    v_period_end,
    true
  ) p;

  IF v_full_work_days <= 0 OR v_partial_work_days <> 0 THEN
    RAISE EXCEPTION
      'Simulation setup failed: full_work_days=% partial_work_days=%',
      v_full_work_days,
      v_partial_work_days;
  END IF;

  INSERT INTO public.hr_payroll_periods (
    id, year, month, name, start_date, end_date, is_closed
  ) VALUES (
    v_period_id,
    EXTRACT(YEAR FROM v_period_start)::INTEGER,
    EXTRACT(MONTH FROM v_period_start)::INTEGER,
    'Disposable zero-day partial payroll period',
    v_period_start,
    v_period_end,
    false
  );

  INSERT INTO public.hr_payroll_runs (
    id,
    number,
    period_id,
    status,
    calculation_mode,
    calculated_through_date,
    created_by,
    notes
  ) VALUES (
    v_run_id,
    'SIM-ZERO-PAY-' || v_suffix,
    v_period_id,
    'draft',
    'final',
    v_period_end,
    v_actor,
    'Disposable zero scheduled-day partial payroll simulation'
  );

  PERFORM public.calculate_employee_payroll_scheduled(v_employee_id, v_run_id);

  SELECT * INTO v_line
  FROM public.hr_payroll_lines
  WHERE payroll_run_id = v_run_id
    AND employee_id = v_employee_id;

  IF v_line.id IS NULL
     OR NOT v_line.is_partial_month
     OR v_line.total_working_days <> v_full_work_days
     OR v_line.actual_work_days <> 0
     OR v_line.absent_days <> 0
     OR abs(v_line.gross_earned) > 0.01
     OR abs(v_line.net_salary) > 0.01 THEN
    RAISE EXCEPTION
      'Simulation failed: zero-day partial interval earned money or days; line=%',
      to_jsonb(v_line);
  END IF;
END;
$simulation$;

SELECT jsonb_build_object(
  'simulation_status', 'pass_before_rollback',
  'partial_interval_scheduled_days', 0,
  'gross_earned', 0,
  'net_salary', 0,
  'next_action', 'ROLLBACK'
) AS result;

ROLLBACK;
