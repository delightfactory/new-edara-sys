-- =============================================================================
-- Employee Work Schedules — partial work during unpaid leave simulation
--
-- DISPOSABLE DATABASE ONLY.
-- Required session guard:
--   SET SESSION edara.allow_schedule_simulation = 'disposable-only';
--
-- Proves that half a scheduled day actually worked during an approved unpaid
-- leave earns a 0.50 day value, leaves a 0.50 salary deduction, and produces no
-- automatic attendance penalty. Everything is rolled back.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '180s';

DO $guard$
BEGIN
  IF current_setting('edara.allow_schedule_simulation', true) IS DISTINCT FROM 'disposable-only' THEN
    RAISE EXCEPTION 'Simulation safety stop: disposable-only session flag is required';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Simulation requires feature/readiness to start false';
  END IF;
END;
$guard$;

CREATE OR REPLACE FUNCTION public.hr_employee_work_schedules_enabled()
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
  SELECT true;
$function$;

REVOKE ALL ON FUNCTION public.hr_employee_work_schedules_enabled()
  FROM PUBLIC, anon, authenticated;

DO $simulation$
DECLARE
  v_actor UUID;
  v_employee_id UUID := extensions.gen_random_uuid();
  v_period_id UUID := extensions.gen_random_uuid();
  v_run_id UUID := extensions.gen_random_uuid();
  v_request_id UUID;
  v_unpaid_type_id UUID;
  v_period_start DATE;
  v_period_end DATE;
  v_leave_date DATE;
  v_work_days INTEGER;
  v_attendance_id UUID;
  v_resolved RECORD;
  v_daily_rate NUMERIC;
  v_line public.hr_payroll_lines%ROWTYPE;
  v_suffix TEXT := substr(replace(extensions.gen_random_uuid()::TEXT, '-', ''), 1, 10);
BEGIN
  SELECT candidate.user_id
  INTO v_actor
  FROM (
    SELECT ur.user_id
    FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id = ur.role_id
    GROUP BY ur.user_id
    HAVING bool_or(rp.permission = '*')
       OR (
         bool_or(rp.permission = 'hr.payroll.calculate')
         AND bool_or(rp.permission = 'hr.leaves.approve')
       )
  ) candidate
  JOIN public.profiles p ON p.id = candidate.user_id
  ORDER BY candidate.user_id
  LIMIT 1;

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Simulation could not find a payroll/leave actor';
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

  SELECT id INTO v_unpaid_type_id
  FROM public.hr_leave_types
  WHERE code = 'UNPAID'
    AND is_active = true
    AND is_paid = false
    AND affects_salary = true
  LIMIT 1;

  IF v_unpaid_type_id IS NULL THEN
    RAISE EXCEPTION 'Simulation requires the active UNPAID salary-affecting leave type';
  END IF;

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
    'SIM-PART-UNP-' || v_suffix,
    'محاكاة عمل جزئي أثناء إجازة بدون أجر',
    '+999840' || v_suffix,
    'active',
    v_period_start,
    'friday',
    false,
    6000,
    v_actor,
    'Disposable partial unpaid leave simulation'
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
    v_period_start,
    6000,
    0,
    0,
    0,
    'Disposable partial unpaid leave salary',
    v_actor
  );

  SELECT count(*) FILTER (WHERE r.day_kind = 'work_day')::INTEGER,
         min(g.target_date::DATE) FILTER (WHERE r.day_kind = 'work_day')
  INTO v_work_days, v_leave_date
  FROM generate_series(v_period_start, v_period_end, INTERVAL '1 day') g(target_date)
  CROSS JOIN LATERAL public.resolve_employee_work_schedule_core(
    v_employee_id,
    g.target_date::DATE,
    true
  ) r;

  IF v_work_days <= 1 OR v_leave_date IS NULL THEN
    RAISE EXCEPTION 'Simulation could not resolve workdays for the payroll month';
  END IF;

  INSERT INTO public.hr_leave_requests (
    employee_id,
    leave_type_id,
    start_date,
    end_date,
    days_count,
    reason
  ) VALUES (
    v_employee_id,
    v_unpaid_type_id,
    v_leave_date,
    v_leave_date,
    99,
    'Disposable partial-work unpaid leave'
  )
  RETURNING id INTO v_request_id;

  UPDATE public.hr_leave_requests
  SET status = 'approved_supervisor'
  WHERE id = v_request_id;

  UPDATE public.hr_leave_requests
  SET status = 'approved'
  WHERE id = v_request_id;

  SELECT d.id INTO v_attendance_id
  FROM public.hr_attendance_days d
  WHERE d.source_leave_request_id = v_request_id
    AND d.shift_date = v_leave_date;

  SELECT * INTO v_resolved
  FROM public.resolve_employee_work_schedule_core(v_employee_id, v_leave_date, true);

  IF v_attendance_id IS NULL OR v_resolved.scheduled_minutes <= 0 THEN
    RAISE EXCEPTION 'Simulation failed: synchronized leave attendance is missing';
  END IF;

  UPDATE public.hr_attendance_days
  SET punch_in_time = v_resolved.scheduled_start_at,
      punch_out_time = v_resolved.scheduled_start_at
        + make_interval(mins => v_resolved.scheduled_minutes / 2),
      effective_hours = v_resolved.scheduled_minutes / 120.0,
      updated_at = now()
  WHERE id = v_attendance_id;

  PERFORM public.normalize_attendance_day_schedule_metrics(v_attendance_id);

  IF NOT EXISTS (
    SELECT 1
    FROM public.hr_attendance_days d
    WHERE d.id = v_attendance_id
      AND d.status = 'present'
      AND d.day_value = 0.50
      AND d.late_minutes = 0
      AND d.early_leave_minutes = 0
      AND d.overtime_minutes = 0
      AND d.checkout_status = 'on_time'
      AND COALESCE(d.leave_balance_restored, false) = false
  ) OR EXISTS (
    SELECT 1
    FROM public.hr_penalty_instances pi
    WHERE pi.attendance_day_id = v_attendance_id
      AND COALESCE(pi.is_overridden, false) = false
  ) THEN
    RAISE EXCEPTION 'Simulation failed: partial unpaid work was not normalized to 0.50 penalty-free day';
  END IF;

  INSERT INTO public.hr_attendance_days (
    employee_id,
    shift_date,
    work_date,
    punch_in_time,
    punch_out_time,
    status,
    checkout_status,
    late_minutes,
    early_leave_minutes,
    overtime_minutes,
    effective_hours,
    day_value,
    review_status,
    is_manually_locked,
    schedule_day_kind,
    scheduled_start_at,
    scheduled_end_at,
    scheduled_minutes,
    schedule_source,
    work_schedule_id,
    schedule_snapshot_at
  )
  SELECT
    v_employee_id,
    g.target_date::DATE,
    g.target_date::DATE,
    r.scheduled_start_at,
    r.scheduled_end_at,
    'present',
    'on_time',
    0,
    0,
    0,
    r.scheduled_minutes / 60.0,
    1,
    'reviewed',
    false,
    r.day_kind,
    r.scheduled_start_at,
    r.scheduled_end_at,
    r.scheduled_minutes,
    r.schedule_source,
    r.work_schedule_id,
    now()
  FROM generate_series(v_period_start, v_period_end, INTERVAL '1 day') g(target_date)
  CROSS JOIN LATERAL public.resolve_employee_work_schedule_core(
    v_employee_id,
    g.target_date::DATE,
    true
  ) r
  WHERE r.day_kind = 'work_day'
    AND g.target_date::DATE <> v_leave_date;

  INSERT INTO public.hr_payroll_periods (
    id, year, month, name, start_date, end_date, is_closed
  ) VALUES (
    v_period_id,
    EXTRACT(YEAR FROM v_period_start)::INTEGER,
    EXTRACT(MONTH FROM v_period_start)::INTEGER,
    'Disposable partial unpaid leave period',
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
    'SIM-PART-UNP-PAY-' || v_suffix,
    v_period_id,
    'draft',
    'final',
    v_period_end,
    v_actor,
    'Disposable partial unpaid leave payroll simulation'
  );

  PERFORM public.calculate_employee_payroll_scheduled(v_employee_id, v_run_id);

  SELECT * INTO v_line
  FROM public.hr_payroll_lines
  WHERE payroll_run_id = v_run_id
    AND employee_id = v_employee_id;

  v_daily_rate := 6000 / v_work_days::NUMERIC;

  IF v_line.id IS NULL
     OR v_line.total_working_days <> v_work_days
     OR abs(v_line.actual_work_days - (v_work_days - 0.5)) > 0.001
     OR abs(v_line.absent_days - 0.5) > 0.001
     OR abs(v_line.absence_deduction - (v_daily_rate * 0.5)) > 0.01
     OR abs(v_line.penalty_deduction) > 0.01 THEN
    RAISE EXCEPTION
      'Simulation failed: partial unpaid payroll effect is incorrect; line=% daily_rate=%',
      to_jsonb(v_line),
      v_daily_rate;
  END IF;
END;
$simulation$;

SELECT jsonb_build_object(
  'simulation_status', 'pass_before_rollback',
  'worked_day_fraction', 0.50,
  'unpaid_day_fraction', 0.50,
  'automatic_penalty', 0,
  'production_feature_setting_changed', false,
  'next_action', 'ROLLBACK'
) AS result;

ROLLBACK;
