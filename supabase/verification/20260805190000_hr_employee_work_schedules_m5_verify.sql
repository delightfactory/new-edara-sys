-- =============================================================================
-- Employee Work Schedules M5 — read-only payroll verification
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '120s';

DO $verify$
DECLARE
  v_hash TEXT;
  v_definition TEXT;
  v_legacy_definition TEXT;
  v_scheduled_definition TEXT;
  v_bad TEXT;
  v_term TEXT;
  v_legacy_count INTEGER;
  v_scheduled_count INTEGER;
  v_company_hours NUMERIC;
  v_window_minutes INTEGER;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'M5 verify failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'M5 verify failed: runtime data changed unexpectedly';
  END IF;

  SELECT md5(replace(
    pg_get_functiondef('public.calculate_employee_payroll_legacy_20260805(uuid,uuid)'::regprocedure),
    'FUNCTION public.calculate_employee_payroll_legacy_20260805(',
    'FUNCTION public.calculate_employee_payroll('
  )) INTO v_hash;
  IF v_hash <> 'c294bf592059b7e86429960c3e2b3075' THEN
    RAISE EXCEPTION 'M5 verify failed: payroll legacy clone mismatch (%)', v_hash;
  END IF;

  SELECT pg_get_functiondef('public.calculate_employee_payroll(uuid,uuid)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%hr_employee_work_schedules_enabled%'
     OR v_definition NOT ILIKE '%calculate_employee_payroll_legacy_20260805%'
     OR v_definition NOT ILIKE '%calculate_employee_payroll_scheduled%' THEN
    RAISE EXCEPTION 'M5 verify failed: public payroll dispatcher is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.calculate_employee_payroll_scheduled(uuid,uuid)'::regprocedure)
  INTO v_scheduled_definition;
  SELECT pg_get_functiondef('public.calculate_employee_payroll_legacy_20260805(uuid,uuid)'::regprocedure)
  INTO v_legacy_definition;

  IF v_scheduled_definition ILIKE '%hr.weekly_off_day%'
     OR v_scheduled_definition ILIKE '%hr.work_hours_per_day%'
     OR v_scheduled_definition ILIKE '%EXTRACT(DOW FROM v_d)%'
     OR v_scheduled_definition NOT ILIKE '%get_employee_scheduled_period%'
     OR v_scheduled_definition NOT ILIKE '%assert_employee_payroll_schedule_snapshots%'
     OR v_scheduled_definition NOT ILIKE '%v_period_scheduled_minutes / 60.0%' THEN
    RAISE EXCEPTION 'M5 verify failed: scheduled payroll schedule inputs are incomplete';
  END IF;

  -- Unrelated financial/guard subsystems must remain present in exactly the
  -- same textual multiplicity after deriving the scheduled function.
  FOREACH v_term IN ARRAY ARRAY[
    'check_payroll_attendance_clearance',
    'get_employee_salary_at_date',
    'hr_payroll_adjustments',
    'hr_advance_installments',
    'hr_advances',
    'hr_commission_records',
    'hr.social_insurance.enabled',
    'hr.social_insurance.employee_rate',
    'hr.income_tax.enabled',
    'hr.health_insurance.enabled',
    'deficit_carryover',
    '[ترحيل تلقائي]',
    'hr_payroll_lines',
    'hr_payroll_runs',
    'calculation_mode',
    'calculated_through_date'
  ] LOOP
    v_legacy_count := (
      length(v_legacy_definition) - length(replace(v_legacy_definition, v_term, ''))
    ) / length(v_term);

    v_scheduled_count := (
      length(v_scheduled_definition) - length(replace(v_scheduled_definition, v_term, ''))
    ) / length(v_term);

    IF v_legacy_count IS DISTINCT FROM v_scheduled_count THEN
      RAISE EXCEPTION
        'M5 verify failed: unrelated term % count differs; legacy=% scheduled=%',
        v_term,
        v_legacy_count,
        v_scheduled_count;
    END IF;
  END LOOP;

  SELECT COALESCE(value::NUMERIC, 8)
  INTO v_company_hours
  FROM public.company_settings
  WHERE key = 'hr.work_hours_per_day';

  SELECT (
    EXTRACT(EPOCH FROM (
      (SELECT COALESCE(value, '17:00')::TIME FROM public.company_settings WHERE key = 'hr.work_end_time')
      -
      (SELECT COALESCE(value, '09:00')::TIME FROM public.company_settings WHERE key = 'hr.work_start_time')
    )) / 60
  )::INTEGER
  INTO v_window_minutes;

  IF v_company_hours * 60 <> v_window_minutes THEN
    RAISE EXCEPTION
      'M5 verify failed: current company hour setting (%) disagrees with start/end window (%)',
      v_company_hours * 60,
      v_window_minutes;
  END IF;

  -- Default-schedule parity over every current employee and several complete
  -- calendar months. Legacy day-kind is the exact disabled implementation.
  WITH periods AS (
    SELECT
      make_date(y, m, 1) AS start_date,
      (make_date(y, m, 1) + INTERVAL '1 month - 1 day')::DATE AS end_date
    FROM generate_series(2026, 2026) y
    CROSS JOIN generate_series(4, 8) m
  ), expected AS (
    SELECT
      e.id AS employee_id,
      p.start_date,
      p.end_date,
      COUNT(*) FILTER (
        WHERE public.is_employee_work_day_legacy_20260805(e.id, d::DATE) = 'work_day'
      )::INTEGER AS expected_days
    FROM public.hr_employees e
    CROSS JOIN periods p
    CROSS JOIN LATERAL generate_series(p.start_date, p.end_date, INTERVAL '1 day') d
    GROUP BY e.id, p.start_date, p.end_date
  ), actual AS (
    SELECT
      x.employee_id,
      x.start_date,
      x.end_date,
      x.expected_days,
      a.scheduled_work_days,
      a.scheduled_minutes
    FROM expected x
    CROSS JOIN LATERAL public.get_employee_scheduled_period(
      x.employee_id,
      x.start_date,
      x.end_date,
      false
    ) a
  )
  SELECT string_agg(
           format(
             '%s %s..%s expected_days=%s actual_days=%s expected_minutes=%s actual_minutes=%s',
             employee_id,
             start_date,
             end_date,
             expected_days,
             scheduled_work_days,
             expected_days * v_window_minutes,
             scheduled_minutes
           ),
           E'\n' ORDER BY employee_id, start_date
         )
  INTO v_bad
  FROM actual
  WHERE scheduled_work_days IS DISTINCT FROM expected_days
     OR scheduled_minutes IS DISTINCT FROM (expected_days * v_window_minutes)::BIGINT;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'M5 verify failed: default schedule parity mismatch:%', E'\n' || v_bad;
  END IF;

  -- Approval, run orchestration, and existing clearance remain byte-identical.
  SELECT md5(pg_get_functiondef('public.calculate_payroll_run(uuid)'::regprocedure)) INTO v_hash;
  IF v_hash <> 'f97661bab79bc9b4fe7c68a19c9e9238' THEN
    RAISE EXCEPTION 'M5 verify failed: calculate_payroll_run changed (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.approve_payroll_run(uuid,uuid)'::regprocedure)) INTO v_hash;
  IF v_hash <> 'e32a1fcea2993bfbd1c0e3880b37cbd6' THEN
    RAISE EXCEPTION 'M5 verify failed: approve_payroll_run changed (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.check_payroll_attendance_clearance(date,date,uuid)'::regprocedure)) INTO v_hash;
  IF v_hash <> '3732e7614a8b0a06cdf170f237d426fd' THEN
    RAISE EXCEPTION 'M5 verify failed: attendance clearance changed (%)', v_hash;
  END IF;

  IF has_function_privilege('authenticated', 'public.calculate_employee_payroll_scheduled(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.calculate_employee_payroll_legacy_20260805(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.calculate_employee_payroll_scheduled(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.get_employee_scheduled_period(uuid,date,date,boolean)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.assert_employee_payroll_schedule_snapshots(uuid,date,date)', 'EXECUTE') THEN
    RAISE EXCEPTION 'M5 verify failed: an internal payroll helper is exposed';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'legacy_payroll_clone_exact', true,
  'default_workday_parity', true,
  'default_scheduled_minutes_parity', true,
  'unrelated_financial_paths_preserved', true,
  'calculate_payroll_run_changed', false,
  'approve_payroll_run_changed', false,
  'attendance_clearance_changed', false,
  'runtime_data_changed', false
) AS m5_verification;

ROLLBACK;
