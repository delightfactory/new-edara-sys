-- =============================================================================
-- Employee Work Schedules — integrated attendance + payroll simulation
--
-- DISPOSABLE DATABASE ONLY.
-- Required session guard:
--   SET SESSION edara.allow_schedule_simulation = 'disposable-only';
--
-- Creates temporary employees, schedules, attendance, payroll period/run, and
-- lines inside one transaction. Every record is rolled back at the end.
-- The production feature switch remains FALSE; scheduled internals are invoked
-- directly to test the prepared runtime without authorizing activation.
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

  v_emp_six UUID := extensions.gen_random_uuid();
  v_emp_nine UUID := extensions.gen_random_uuid();
  v_emp_rules UUID := extensions.gen_random_uuid();

  v_schedule_six UUID;
  v_schedule_nine UUID;
  v_schedule_rules UUID;

  v_days_six JSONB;
  v_days_nine JSONB;
  v_result JSONB;

  v_rule_late_date DATE;
  v_rule_ot_date DATE;
  v_rule_off_date DATE;
  v_attendance_id UUID;
  v_penalty_count INTEGER;
  v_penalty_sum NUMERIC;

  v_six_work_days INTEGER;
  v_nine_work_days INTEGER;
  v_six_minutes BIGINT;
  v_nine_minutes BIGINT;
  v_ot_rate NUMERIC;
  v_expected_ot NUMERIC;
  v_line RECORD;
  v_hash_suffix TEXT := substr(replace(extensions.gen_random_uuid()::TEXT, '-', ''), 1, 10);
BEGIN
  IF current_setting('edara.allow_schedule_simulation', true) IS DISTINCT FROM 'disposable-only' THEN
    RAISE EXCEPTION 'Simulation safety stop: disposable-only session flag is required';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Simulation requires feature/readiness to remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'Simulation requires empty schedule tables';
  END IF;

  SELECT candidate.user_id
  INTO v_actor
  FROM (
    SELECT DISTINCT ur.user_id
    FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id = ur.role_id
    WHERE rp.permission IN (
      '*',
      'hr.employees.edit',
      'hr.attendance.create',
      'hr.payroll.create'
    )
    GROUP BY ur.user_id
    HAVING bool_or(rp.permission = '*')
       OR count(DISTINCT rp.permission) FILTER (
            WHERE rp.permission IN (
              'hr.employees.edit',
              'hr.attendance.create',
              'hr.payroll.create'
            )
          ) = 3
  ) candidate
  JOIN public.profiles p ON p.id = candidate.user_id
  ORDER BY candidate.user_id
  LIMIT 1;

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Simulation could not find an actor with HR edit/attendance/payroll permissions';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_actor::TEXT, true);

  -- Select the first unused future month, avoiding collisions with real periods.
  SELECT make_date(y, m, 1)
  INTO v_period_start
  FROM generate_series(2035, 2045) y
  CROSS JOIN generate_series(1, 12) m
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.hr_payroll_periods pp
    WHERE pp.year = y AND pp.month = m
  )
  ORDER BY y, m
  LIMIT 1;

  IF v_period_start IS NULL THEN
    RAISE EXCEPTION 'Simulation could not find an unused future payroll month';
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
  ) VALUES
    (
      v_emp_six,
      'SIM6-' || v_hash_suffix,
      'محاكاة جدول ست ساعات',
      '+999600' || v_hash_suffix,
      'active',
      v_period_start,
      false,
      6000,
      v_actor,
      'Disposable employee work schedule simulation'
    ),
    (
      v_emp_nine,
      'SIM9-' || v_hash_suffix,
      'محاكاة مبيعات تسع ساعات',
      '+999900' || v_hash_suffix,
      'active',
      v_period_start,
      true,
      9000,
      v_actor,
      'Disposable employee work schedule simulation'
    ),
    (
      v_emp_rules,
      'SIMR-' || v_hash_suffix,
      'محاكاة قواعد الحضور',
      '+999300' || v_hash_suffix,
      'active',
      v_period_start,
      false,
      6000,
      v_actor,
      'Disposable attendance rule simulation'
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
  ) VALUES
    (v_emp_six, v_period_start, 6000, 0, 0, 0, 'Disposable simulation salary', v_actor),
    (v_emp_nine, v_period_start, 9000, 0, 0, 0, 'Disposable simulation salary', v_actor),
    (v_emp_rules, v_period_start, 6000, 0, 0, 0, 'Disposable simulation salary', v_actor);

  v_days_six := jsonb_build_array(
    jsonb_build_object('day_of_week','saturday',  'is_working_day',true,  'start_time','15:00','end_time','21:00'),
    jsonb_build_object('day_of_week','sunday',    'is_working_day',true,  'start_time','10:00','end_time','16:00'),
    jsonb_build_object('day_of_week','monday',    'is_working_day',true,  'start_time','15:00','end_time','21:00'),
    jsonb_build_object('day_of_week','tuesday',   'is_working_day',true,  'start_time','15:00','end_time','21:00'),
    jsonb_build_object('day_of_week','wednesday', 'is_working_day',true,  'start_time','10:00','end_time','16:00'),
    jsonb_build_object('day_of_week','thursday',  'is_working_day',true,  'start_time','10:00','end_time','16:00'),
    jsonb_build_object('day_of_week','friday',    'is_working_day',false, 'start_time',NULL,   'end_time',NULL)
  );

  v_days_nine := jsonb_build_array(
    jsonb_build_object('day_of_week','saturday',  'is_working_day',true,  'start_time','09:00','end_time','18:00'),
    jsonb_build_object('day_of_week','sunday',    'is_working_day',true,  'start_time','09:00','end_time','18:00'),
    jsonb_build_object('day_of_week','monday',    'is_working_day',true,  'start_time','09:00','end_time','18:00'),
    jsonb_build_object('day_of_week','tuesday',   'is_working_day',true,  'start_time','09:00','end_time','18:00'),
    jsonb_build_object('day_of_week','wednesday', 'is_working_day',true,  'start_time','09:00','end_time','18:00'),
    jsonb_build_object('day_of_week','thursday',  'is_working_day',true,  'start_time','09:00','end_time','18:00'),
    jsonb_build_object('day_of_week','friday',    'is_working_day',false, 'start_time',NULL,   'end_time',NULL)
  );

  SELECT public.save_employee_work_schedule(
    v_emp_six,
    v_period_start,
    v_days_six,
    'Simulation: six-hour mixed schedule'
  ) INTO v_result;
  v_schedule_six := (v_result #>> '{schedule,id}')::UUID;

  SELECT public.save_employee_work_schedule(
    v_emp_nine,
    v_period_start,
    v_days_nine,
    'Simulation: nine-hour sales schedule'
  ) INTO v_result;
  v_schedule_nine := (v_result #>> '{schedule,id}')::UUID;

  SELECT public.save_employee_work_schedule(
    v_emp_rules,
    v_period_start,
    v_days_six,
    'Simulation: attendance rules schedule'
  ) INTO v_result;
  v_schedule_rules := (v_result #>> '{schedule,id}')::UUID;

  IF v_schedule_six IS NULL OR v_schedule_nine IS NULL OR v_schedule_rules IS NULL THEN
    RAISE EXCEPTION 'Simulation failed: one or more schedules were not created';
  END IF;

  -- Identify rule-test dates from the resolver, not hard-coded calendar guesses.
  SELECT min(d::DATE) INTO v_rule_late_date
  FROM generate_series(v_period_start, v_period_end, INTERVAL '1 day') d
  CROSS JOIN LATERAL public.resolve_employee_work_schedule_core(v_emp_rules, d::DATE, true) r
  WHERE r.day_kind = 'work_day'
    AND public.hr_day_of_week_for_date(d::DATE) = 'saturday';

  SELECT min(d::DATE) INTO v_rule_ot_date
  FROM generate_series(v_rule_late_date + 1, v_period_end, INTERVAL '1 day') d
  CROSS JOIN LATERAL public.resolve_employee_work_schedule_core(v_emp_rules, d::DATE, true) r
  WHERE r.day_kind = 'work_day'
    AND public.hr_day_of_week_for_date(d::DATE) = 'saturday';

  SELECT min(d::DATE) INTO v_rule_off_date
  FROM generate_series(v_period_start, v_period_end, INTERVAL '1 day') d
  CROSS JOIN LATERAL public.resolve_employee_work_schedule_core(v_emp_rules, d::DATE, true) r
  WHERE r.day_kind = 'weekly_off';

  IF v_rule_late_date IS NULL OR v_rule_ot_date IS NULL OR v_rule_off_date IS NULL THEN
    RAISE EXCEPTION 'Simulation failed: suitable attendance rule dates were not found';
  END IF;

  -- 30 minutes late + 30 minutes unauthorized early leave on a six-hour day.
  SELECT (public.upsert_attendance_and_reprocess_scheduled(
    v_emp_rules,
    v_rule_late_date,
    (v_rule_late_date + TIME '15:30') AT TIME ZONE 'Africa/Cairo',
    (v_rule_late_date + TIME '20:30') AT TIME ZONE 'Africa/Cairo',
    'present',
    'Disposable 30-minute late/early simulation',
    v_actor
  )->>'attendance_day_id')::UUID INTO v_attendance_id;

  SELECT count(*)::INTEGER, COALESCE(sum(deduction_days), 0)
  INTO v_penalty_count, v_penalty_sum
  FROM public.hr_penalty_instances
  WHERE attendance_day_id = v_attendance_id
    AND is_overridden = false;

  IF v_penalty_count <> 2
     OR abs(v_penalty_sum - 0.3333) > 0.0001
     OR NOT EXISTS (
       SELECT 1
       FROM public.hr_penalty_instances
       WHERE attendance_day_id = v_attendance_id
         AND penalty_type = 'late'
         AND deduction_days = 0.25
     )
     OR NOT EXISTS (
       SELECT 1
       FROM public.hr_penalty_instances
       WHERE attendance_day_id = v_attendance_id
         AND penalty_type = 'early_leave_unauthorized'
         AND deduction_minutes = 30
         AND deduction_days = 0.0833
     ) THEN
    RAISE EXCEPTION
      'Simulation failed: six-hour late/early penalties incorrect; count=% sum=%',
      v_penalty_count,
      v_penalty_sum;
  END IF;

  -- One hour after the scheduled end must be one hour overtime.
  SELECT (public.upsert_attendance_and_reprocess_scheduled(
    v_emp_rules,
    v_rule_ot_date,
    (v_rule_ot_date + TIME '15:00') AT TIME ZONE 'Africa/Cairo',
    (v_rule_ot_date + TIME '22:00') AT TIME ZONE 'Africa/Cairo',
    'present',
    'Disposable overtime simulation',
    v_actor
  )->>'attendance_day_id')::UUID INTO v_attendance_id;

  IF NOT EXISTS (
    SELECT 1
    FROM public.hr_attendance_days
    WHERE id = v_attendance_id
      AND schedule_day_kind = 'work_day'
      AND scheduled_minutes = 360
      AND overtime_minutes = 60
      AND checkout_status = 'overtime'
  ) THEN
    RAISE EXCEPTION 'Simulation failed: six-hour overtime calculation is incorrect';
  END IF;

  -- Attendance on a weekly off day creates no automatic late/early/OT/penalty.
  SELECT (public.upsert_attendance_and_reprocess_scheduled(
    v_emp_rules,
    v_rule_off_date,
    (v_rule_off_date + TIME '10:00') AT TIME ZONE 'Africa/Cairo',
    (v_rule_off_date + TIME '14:00') AT TIME ZONE 'Africa/Cairo',
    'present',
    'Disposable weekly-off attendance simulation',
    v_actor
  )->>'attendance_day_id')::UUID INTO v_attendance_id;

  IF NOT EXISTS (
    SELECT 1
    FROM public.hr_attendance_days
    WHERE id = v_attendance_id
      AND schedule_day_kind = 'weekly_off'
      AND scheduled_minutes = 0
      AND late_minutes = 0
      AND early_leave_minutes = 0
      AND overtime_minutes = 0
  ) OR EXISTS (
    SELECT 1
    FROM public.hr_penalty_instances
    WHERE attendance_day_id = v_attendance_id
      AND is_overridden = false
  ) THEN
    RAISE EXCEPTION 'Simulation failed: weekly-off attendance generated an automatic financial effect';
  END IF;

  -- Populate complete reviewed workday attendance for payroll employees.
  INSERT INTO public.hr_attendance_days (
    employee_id,
    shift_date,
    work_date,
    status,
    late_minutes,
    early_leave_minutes,
    overtime_minutes,
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
    e.employee_id,
    d::DATE,
    d::DATE,
    'present',
    0,
    0,
    CASE WHEN row_number() OVER (PARTITION BY e.employee_id ORDER BY d) = 1 THEN 60 ELSE 0 END,
    1,
    'reviewed',
    true,
    r.day_kind,
    r.scheduled_start_at,
    r.scheduled_end_at,
    r.scheduled_minutes,
    r.schedule_source,
    r.work_schedule_id,
    now()
  FROM (VALUES (v_emp_six), (v_emp_nine)) e(employee_id)
  CROSS JOIN generate_series(v_period_start, v_period_end, INTERVAL '1 day') d
  CROSS JOIN LATERAL public.resolve_employee_work_schedule_core(e.employee_id, d::DATE, true) r
  WHERE r.day_kind = 'work_day';

  INSERT INTO public.hr_payroll_periods (
    id, year, month, name, start_date, end_date, is_closed
  ) VALUES (
    v_period_id,
    EXTRACT(YEAR FROM v_period_start)::INTEGER,
    EXTRACT(MONTH FROM v_period_start)::INTEGER,
    'Disposable schedule simulation period',
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
    'SIM-PAY-' || v_hash_suffix,
    v_period_id,
    'draft',
    'final',
    v_period_end,
    v_actor,
    'Disposable employee work schedule payroll simulation'
  );

  PERFORM public.calculate_employee_payroll_scheduled(v_emp_six, v_run_id);
  PERFORM public.calculate_employee_payroll_scheduled(v_emp_nine, v_run_id);

  SELECT p.scheduled_work_days, p.scheduled_minutes
  INTO v_six_work_days, v_six_minutes
  FROM public.get_employee_scheduled_period(v_emp_six, v_period_start, v_period_end, true) p;

  SELECT p.scheduled_work_days, p.scheduled_minutes
  INTO v_nine_work_days, v_nine_minutes
  FROM public.get_employee_scheduled_period(v_emp_nine, v_period_start, v_period_end, true) p;

  SELECT COALESCE(value::NUMERIC, 1.25)
  INTO v_ot_rate
  FROM public.company_settings
  WHERE key = 'hr.overtime_rate';
  v_ot_rate := COALESCE(v_ot_rate, 1.25);

  SELECT * INTO v_line
  FROM public.hr_payroll_lines
  WHERE payroll_run_id = v_run_id
    AND employee_id = v_emp_six;

  v_expected_ot := ROUND((6000 / (v_six_minutes / 60.0)) * v_ot_rate, 2);

  IF v_line.id IS NULL
     OR v_line.total_working_days <> v_six_work_days
     OR v_line.actual_work_days <> v_six_work_days
     OR v_line.absent_days <> 0
     OR v_line.overtime_hours <> 1
     OR abs(v_line.overtime_amount - v_expected_ot) > 0.01
     OR v_line.total_deductions <> 0
     OR abs(v_line.net_salary - (6000 + v_expected_ot)) > 0.01 THEN
    RAISE EXCEPTION
      'Simulation failed: six-hour payroll incorrect; line=% expected_ot=% days=% minutes=%',
      to_jsonb(v_line),
      v_expected_ot,
      v_six_work_days,
      v_six_minutes;
  END IF;

  SELECT * INTO v_line
  FROM public.hr_payroll_lines
  WHERE payroll_run_id = v_run_id
    AND employee_id = v_emp_nine;

  v_expected_ot := ROUND((9000 / (v_nine_minutes / 60.0)) * v_ot_rate, 2);

  IF v_line.id IS NULL
     OR v_line.total_working_days <> v_nine_work_days
     OR v_line.actual_work_days <> v_nine_work_days
     OR v_line.absent_days <> 0
     OR v_line.overtime_hours <> 1
     OR abs(v_line.overtime_amount - v_expected_ot) > 0.01
     OR v_line.total_deductions <> 0
     OR abs(v_line.net_salary - (9000 + v_expected_ot)) > 0.01 THEN
    RAISE EXCEPTION
      'Simulation failed: nine-hour payroll incorrect; line=% expected_ot=% days=% minutes=%',
      to_jsonb(v_line),
      v_expected_ot,
      v_nine_work_days,
      v_nine_minutes;
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Simulation failed: feature/readiness changed unexpectedly';
  END IF;
END;
$simulation$;

SELECT jsonb_build_object(
  'simulation_status', 'pass_before_rollback',
  'feature_enabled_inside_transaction', public.hr_employee_work_schedules_enabled(),
  'activation_ready_inside_transaction', public.hr_employee_work_schedules_activation_ready(),
  'temporary_employees', (
    SELECT count(*) FROM public.hr_employees WHERE employee_number LIKE 'SIM%'
  ),
  'temporary_schedule_rows', (SELECT count(*) FROM public.hr_employee_work_schedules),
  'temporary_payroll_lines', (
    SELECT count(*) FROM public.hr_payroll_lines WHERE notes ILIKE '%simulation%'
  ),
  'tested_six_hour_penalty_denominator', true,
  'tested_weekly_off_no_automatic_financial_effect', true,
  'tested_six_hour_payroll', true,
  'tested_nine_hour_sales_payroll', true,
  'next_action', 'ROLLBACK'
) AS runtime_payroll_simulation;

ROLLBACK;
