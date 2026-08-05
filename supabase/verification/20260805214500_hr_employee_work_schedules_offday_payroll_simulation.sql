-- =============================================================================
-- Employee Work Schedules — off-day payroll isolation simulation
--
-- DISPOSABLE DATABASE ONLY.
-- Required session guard:
--   SET SESSION edara.allow_schedule_simulation = 'disposable-only';
--
-- Proves that one present row on a scheduled weekly off cannot compensate for
-- one missed scheduled work day. All rows are rolled back.
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
  v_hash_suffix TEXT := substr(replace(extensions.gen_random_uuid()::TEXT, '-', ''), 1, 10);
  v_missed_date DATE;
  v_off_date DATE;
  v_work_days INTEGER;
  v_daily_rate NUMERIC;
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
       OR (
         bool_or(rp.permission = 'hr.payroll.calculate')
         AND bool_or(rp.permission = 'hr.employees.edit')
       )
       OR (
         bool_or(rp.permission = 'hr.payroll.approve')
         AND bool_or(rp.permission = 'hr.employees.edit')
       )
  ) candidate
  JOIN public.profiles p ON p.id = candidate.user_id
  ORDER BY candidate.user_id
  LIMIT 1;

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Simulation could not find a payroll-capable HR actor';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_actor::TEXT, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  -- Use an unused completed month; no custom schedule is needed because the
  -- bug concerns a snapshotted company weekly-off row entering payroll totals.
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

  INSERT INTO public.hr_employees (
    id,
    employee_number,
    full_name,
    personal_phone,
    status,
    hire_date,
    is_field_employee,
    base_salary,
    created_by,
    notes
  ) VALUES (
    v_employee_id,
    'SIM-OFF-' || v_hash_suffix,
    'محاكاة عزل حضور يوم الإجازة',
    '+999700' || v_hash_suffix,
    'active',
    v_period_start,
    false,
    6000,
    v_actor,
    'Disposable off-day payroll isolation simulation'
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
    'Disposable off-day payroll simulation salary',
    v_actor
  );

  SELECT count(*) FILTER (WHERE r.day_kind = 'work_day')::INTEGER,
         min(g.target_date::DATE) FILTER (WHERE r.day_kind = 'work_day'),
         min(g.target_date::DATE) FILTER (WHERE r.day_kind = 'weekly_off')
  INTO v_work_days, v_missed_date, v_off_date
  FROM generate_series(v_period_start, v_period_end, INTERVAL '1 day') g(target_date)
  CROSS JOIN LATERAL public.resolve_employee_work_schedule_core(
    v_employee_id,
    g.target_date::DATE,
    true
  ) r;

  IF v_work_days <= 1 OR v_missed_date IS NULL OR v_off_date IS NULL THEN
    RAISE EXCEPTION 'Simulation could not resolve work/off dates';
  END IF;

  -- Attend every scheduled work day except one.
  INSERT INTO public.hr_attendance_days (
    employee_id,
    shift_date,
    work_date,
    status,
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
    'present',
    1.00,
    'reviewed',
    true,
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
    AND g.target_date::DATE <> v_missed_date;

  -- Deliberately add a reviewed present row on the weekly off.
  INSERT INTO public.hr_attendance_days (
    employee_id,
    shift_date,
    work_date,
    status,
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
    v_off_date,
    v_off_date,
    'present',
    1.00,
    'reviewed',
    true,
    r.day_kind,
    r.scheduled_start_at,
    r.scheduled_end_at,
    r.scheduled_minutes,
    r.schedule_source,
    r.work_schedule_id,
    now()
  FROM public.resolve_employee_work_schedule_core(
    v_employee_id,
    v_off_date,
    true
  ) r;

  INSERT INTO public.hr_payroll_periods (
    id, year, month, name, start_date, end_date, is_closed
  ) VALUES (
    v_period_id,
    EXTRACT(YEAR FROM v_period_start)::INTEGER,
    EXTRACT(MONTH FROM v_period_start)::INTEGER,
    'Disposable off-day payroll isolation period',
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
    'SIM-OFF-PAY-' || v_hash_suffix,
    v_period_id,
    'draft',
    'final',
    v_period_end,
    v_actor,
    'Disposable off-day payroll isolation simulation'
  );

  PERFORM public.calculate_employee_payroll_scheduled(v_employee_id, v_run_id);

  SELECT * INTO v_line
  FROM public.hr_payroll_lines
  WHERE payroll_run_id = v_run_id
    AND employee_id = v_employee_id;

  v_daily_rate := 6000 / v_work_days::NUMERIC;

  IF v_line.id IS NULL
     OR v_line.total_working_days <> v_work_days
     OR v_line.actual_work_days <> v_work_days - 1
     OR v_line.absent_days <> 1
     OR abs(v_line.absence_deduction - v_daily_rate) > 0.01
     OR v_line.overtime_hours <> 0 THEN
    RAISE EXCEPTION
      'Simulation failed: off-day attendance masked or altered scheduled absence; line=% work_days=% daily_rate=%',
      to_jsonb(v_line),
      v_work_days,
      v_daily_rate;
  END IF;
END;
$simulation$;

SELECT jsonb_build_object(
  'simulation_status', 'pass_before_rollback',
  'off_day_present_does_not_count_as_workday', true,
  'one_scheduled_absence_remains_one_absence', true,
  'feature_enabled_inside_transaction', public.hr_employee_work_schedules_enabled(),
  'activation_ready_inside_transaction', public.hr_employee_work_schedules_activation_ready(),
  'next_action', 'ROLLBACK'
) AS offday_payroll_simulation;

ROLLBACK;
