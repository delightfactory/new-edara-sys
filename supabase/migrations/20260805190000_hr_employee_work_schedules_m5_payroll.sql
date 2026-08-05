-- =============================================================================
-- EDARA — Employee Work Schedules M5
-- Schedule-aware payroll inputs with exact legacy fallback.
--
-- Only schedule-dependent inputs change in enabled mode:
--   1. full-period scheduled workday count;
--   2. interim/partial entitlement workday count;
--   3. scheduled minutes used as the overtime hourly denominator.
--
-- Salary history, adjustments, advances, commissions, insurance/tax switches,
-- deficit carryovers, run guards, clearance, and line/run writes are inherited
-- from the exact production function definition protected by an MD5 guard.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

-- ----------------------------------------------------------------------------
-- 0. Preflight: exact production baseline and disabled rollout state
-- ----------------------------------------------------------------------------
DO $preflight$
DECLARE
  v_hash TEXT;
BEGIN
  IF to_regprocedure('public.resolve_employee_work_schedule_core(uuid,date,boolean)') IS NULL
     OR to_regprocedure('public.hr_employee_work_schedules_activation_ready()') IS NULL THEN
    RAISE EXCEPTION 'M5 preflight failed: schedule resolver/activation guard is missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'M5 preflight failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'M5 preflight failed: no runtime schedule/snapshot data is expected';
  END IF;

  IF to_regprocedure('public.get_employee_scheduled_period(uuid,date,date,boolean)') IS NOT NULL
     OR to_regprocedure('public.assert_employee_payroll_schedule_snapshots(uuid,date,date)') IS NOT NULL
     OR to_regprocedure('public.calculate_employee_payroll_legacy_20260805(uuid,uuid)') IS NOT NULL
     OR to_regprocedure('public.calculate_employee_payroll_scheduled(uuid,uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'M5 preflight failed: one or more M5 helpers already exist';
  END IF;

  SELECT md5(pg_get_functiondef('public.calculate_employee_payroll(uuid,uuid)'::regprocedure))
  INTO v_hash;
  IF v_hash <> 'c294bf592059b7e86429960c3e2b3075' THEN
    RAISE EXCEPTION 'M5 preflight failed: calculate_employee_payroll drifted (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.calculate_payroll_run(uuid)'::regprocedure))
  INTO v_hash;
  IF v_hash <> 'f97661bab79bc9b4fe7c68a19c9e9238' THEN
    RAISE EXCEPTION 'M5 preflight failed: calculate_payroll_run drifted (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.approve_payroll_run(uuid,uuid)'::regprocedure))
  INTO v_hash;
  IF v_hash <> 'e32a1fcea2993bfbd1c0e3880b37cbd6' THEN
    RAISE EXCEPTION 'M5 preflight failed: approve_payroll_run drifted (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.check_payroll_attendance_clearance(date,date,uuid)'::regprocedure))
  INTO v_hash;
  IF v_hash <> '3732e7614a8b0a06cdf170f237d426fd' THEN
    RAISE EXCEPTION 'M5 preflight failed: payroll attendance clearance drifted (%)', v_hash;
  END IF;
END;
$preflight$;

-- ----------------------------------------------------------------------------
-- 1. Central aggregate for scheduled days/minutes over any inclusive date range
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.get_employee_scheduled_period(
  p_employee_id UUID,
  p_start_date DATE,
  p_end_date DATE,
  p_use_custom BOOLEAN DEFAULT true
)
RETURNS TABLE (
  scheduled_work_days INTEGER,
  scheduled_minutes BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF p_employee_id IS NULL OR p_start_date IS NULL OR p_end_date IS NULL THEN
    RAISE EXCEPTION 'employee_id, start_date, and end_date are required';
  END IF;

  IF p_end_date < p_start_date THEN
    RAISE EXCEPTION 'end_date cannot precede start_date';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.hr_employees WHERE id = p_employee_id) THEN
    RAISE EXCEPTION 'Employee % does not exist', p_employee_id;
  END IF;

  RETURN QUERY
  SELECT
    COUNT(*) FILTER (WHERE r.day_kind = 'work_day')::INTEGER,
    COALESCE(
      SUM(CASE WHEN r.day_kind = 'work_day' THEN r.scheduled_minutes ELSE 0 END),
      0
    )::BIGINT
  FROM generate_series(p_start_date, p_end_date, INTERVAL '1 day') g(target_date)
  CROSS JOIN LATERAL public.resolve_employee_work_schedule_core(
    p_employee_id,
    g.target_date::DATE,
    COALESCE(p_use_custom, false)
  ) r;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_employee_scheduled_period(UUID, DATE, DATE, BOOLEAN)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_employee_scheduled_period(UUID, DATE, DATE, BOOLEAN) IS
  'Internal aggregate of resolved workdays and scheduled minutes for payroll and parity diagnostics.';

-- ----------------------------------------------------------------------------
-- 2. Payroll snapshot guard
--    Payroll does not mutate attendance. Missing snapshots are tolerated only
--    for legacy/company dates that are not covered by an employee schedule.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.assert_employee_payroll_schedule_snapshots(
  p_employee_id UUID,
  p_start_date DATE,
  p_end_date DATE
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_bad_days TEXT;
BEGIN
  IF p_employee_id IS NULL OR p_start_date IS NULL OR p_end_date IS NULL THEN
    RAISE EXCEPTION 'employee_id, start_date, and end_date are required';
  END IF;

  IF p_end_date < p_start_date THEN
    RAISE EXCEPTION 'end_date cannot precede start_date';
  END IF;

  WITH missing AS (
    SELECT ad.id, ad.shift_date
    FROM public.hr_attendance_days ad
    WHERE ad.employee_id = p_employee_id
      AND ad.shift_date BETWEEN p_start_date AND p_end_date
      AND ad.schedule_snapshot_at IS NULL
  ), unsafe AS (
    SELECT m.id, m.shift_date, r.work_schedule_id
    FROM missing m
    CROSS JOIN LATERAL public.resolve_employee_work_schedule_core(
      p_employee_id,
      m.shift_date,
      true
    ) r
    WHERE r.schedule_source = 'employee'
  )
  SELECT string_agg(
           format('%s(day=%s,schedule=%s)', id, shift_date, work_schedule_id),
           ', ' ORDER BY shift_date, id
         )
  INTO v_bad_days
  FROM unsafe;

  IF v_bad_days IS NOT NULL THEN
    RAISE EXCEPTION
      'Payroll schedule snapshot clearance failed for employee %: %',
      p_employee_id,
      v_bad_days;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.assert_employee_payroll_schedule_snapshots(UUID, DATE, DATE)
  FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3. Clone exact production payroll implementation as disabled-mode fallback
-- ----------------------------------------------------------------------------
DO $clone_legacy$
DECLARE
  v_definition TEXT;
BEGIN
  SELECT pg_get_functiondef('public.calculate_employee_payroll(uuid,uuid)'::regprocedure)
  INTO v_definition;

  v_definition := replace(
    v_definition,
    'FUNCTION public.calculate_employee_payroll(',
    'FUNCTION public.calculate_employee_payroll_legacy_20260805('
  );

  EXECUTE v_definition;
END;
$clone_legacy$;

REVOKE ALL ON FUNCTION public.calculate_employee_payroll_legacy_20260805(UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.calculate_employee_payroll_legacy_20260805(UUID, UUID) IS
  'Internal exact pre-M5 payroll implementation. Used only while employee work schedules are disabled.';

-- ----------------------------------------------------------------------------
-- 4. Derive the scheduled payroll implementation from the exact production
--    definition. Each replacement is bounded by deterministic markers and the
--    preflight hash; the migration stops if any expected section is missing.
-- ----------------------------------------------------------------------------
DO $build_scheduled$
DECLARE
  v_definition TEXT;
  v_start INTEGER;
  v_end INTEGER;
  v_marker_start TEXT;
  v_marker_end TEXT;
  v_replacement TEXT;
  v_old_overtime TEXT;
  v_new_overtime TEXT;
BEGIN
  SELECT pg_get_functiondef('public.calculate_employee_payroll(uuid,uuid)'::regprocedure)
  INTO v_definition;

  -- Normalize only line endings for deterministic transformation.
  v_definition := replace(v_definition, E'\r\n', E'\n');
  v_definition := replace(v_definition, E'\r', E'\n');

  v_definition := replace(
    v_definition,
    'FUNCTION public.calculate_employee_payroll(',
    'FUNCTION public.calculate_employee_payroll_scheduled('
  );

  -- Add one full-period minute denominator. Existing legacy declarations are
  -- intentionally retained even if no longer used, minimizing transformation.
  IF strpos(v_definition, E'  v_working_days     INTEGER;\n') = 0 THEN
    RAISE EXCEPTION 'M5 build failed: working-days declaration marker is missing';
  END IF;

  v_definition := replace(
    v_definition,
    E'  v_working_days     INTEGER;\n',
    E'  v_working_days     INTEGER;\n  v_period_scheduled_minutes BIGINT;\n'
  );

  -- Replace full-period off-day/company-hours calculation only.
  v_marker_start := '  v_off_day_name := COALESCE(v_emp.weekly_off_day::TEXT, NULL);';
  v_marker_end := '  -- استخراج البيانات يدوياً بدلاً من get_monthly_attendance_summary';
  v_start := strpos(v_definition, v_marker_start);
  v_end := strpos(v_definition, v_marker_end);

  IF v_start = 0 OR v_end = 0 OR v_end <= v_start THEN
    RAISE EXCEPTION 'M5 build failed: full-period schedule section markers are missing';
  END IF;

  v_replacement := $replacement$
  SELECT p.scheduled_work_days, p.scheduled_minutes
  INTO v_working_days, v_period_scheduled_minutes
  FROM public.get_employee_scheduled_period(
    p_employee_id,
    v_period.start_date,
    v_period.end_date,
    true
  ) p;

  IF v_working_days <= 0 OR v_period_scheduled_minutes <= 0 THEN
    RAISE EXCEPTION
      'لا يمكن حساب الراتب: جدول الموظف لا يحتوي أيام وساعات عمل مقررة خلال الفترة';
  END IF;

  v_daily_rate := COALESCE(v_salary.gross_salary, 0) / v_working_days;

  -- Payroll itself never creates/refreshes attendance snapshots. A custom
  -- schedule date with a missing snapshot blocks calculation for reconciliation.
  PERFORM public.assert_employee_payroll_schedule_snapshots(
    p_employee_id,
    v_period.start_date,
    v_calc_date
  );

$replacement$;

  v_definition := substr(v_definition, 1, v_start - 1)
    || v_replacement
    || substr(v_definition, v_end);

  -- Replace all legacy partial/interim weekday loops as one bounded section.
  v_marker_start := '  v_entitled_days := v_working_days;';
  v_marker_end := '  SELECT COALESCE(SUM(day_value), 0) INTO v_attended_days';
  v_start := strpos(v_definition, v_marker_start);
  v_end := strpos(v_definition, v_marker_end);

  IF v_start = 0 OR v_end = 0 OR v_end <= v_start THEN
    RAISE EXCEPTION 'M5 build failed: entitlement section markers are missing';
  END IF;

  v_replacement := $replacement$
  v_entitled_days := v_working_days;

  -- حساب الأيام المستحقة في الحساب المبدئي (لا يحتسب ما بعد v_calc_date كغياب)
  IF v_is_interim THEN
    v_is_partial := true;

    SELECT p.scheduled_work_days
    INTO v_partial_working
    FROM public.get_employee_scheduled_period(
      p_employee_id,
      GREATEST(v_period.start_date, v_emp.hire_date),
      LEAST(v_calc_date, COALESCE(v_emp.termination_date, v_calc_date)),
      true
    ) p;

    -- Preserve the current payroll edge behavior for a started partial period
    -- containing no completed scheduled workday yet.
    IF v_partial_working <= 0 THEN v_partial_working := 1; END IF;

    v_gross_earned := v_daily_rate * v_partial_working;
    v_entitled_days := v_partial_working;
  ELSE
    v_gross_earned := COALESCE(v_salary.gross_salary, 0);

    -- Partial month logic (hire or termination) for final calculation.
    IF v_emp.hire_date > v_period.start_date
       AND v_emp.hire_date <= v_period.end_date THEN
      v_is_partial := true;

      SELECT p.scheduled_work_days
      INTO v_partial_working
      FROM public.get_employee_scheduled_period(
        p_employee_id,
        v_emp.hire_date,
        v_period.end_date,
        true
      ) p;

      IF v_partial_working <= 0 THEN v_partial_working := 1; END IF;
      v_gross_earned := v_daily_rate * v_partial_working;
      v_entitled_days := v_partial_working;
    END IF;

    IF v_emp.termination_date IS NOT NULL
       AND v_emp.termination_date >= v_period.start_date
       AND v_emp.termination_date <= v_period.end_date THEN
      v_is_partial := true;

      SELECT p.scheduled_work_days
      INTO v_partial_working
      FROM public.get_employee_scheduled_period(
        p_employee_id,
        GREATEST(v_period.start_date, v_emp.hire_date),
        v_emp.termination_date,
        true
      ) p;

      IF v_partial_working <= 0 THEN v_partial_working := 1; END IF;
      v_gross_earned := v_daily_rate * v_partial_working;
      v_entitled_days := v_partial_working;
    END IF;
  END IF;

$replacement$;

  v_definition := substr(v_definition, 1, v_start - 1)
    || v_replacement
    || substr(v_definition, v_end);

  -- Replace only the overtime hourly denominator. The rate setting and all
  -- downstream earnings/deductions remain exactly inherited.
  v_old_overtime := $old$
  v_overtime_amount := (v_total_overtime_minutes / 60.0)
    * (COALESCE(v_salary.base_salary, 0) / (v_working_days * v_work_hours_per_day))
    * v_overtime_rate;
$old$;

  v_new_overtime := $new$
  v_overtime_amount := (v_total_overtime_minutes / 60.0)
    * (COALESCE(v_salary.base_salary, 0) / (v_period_scheduled_minutes / 60.0))
    * v_overtime_rate;
$new$;

  IF strpos(v_definition, v_old_overtime) = 0 THEN
    RAISE EXCEPTION 'M5 build failed: overtime formula marker is missing';
  END IF;

  v_definition := replace(v_definition, v_old_overtime, v_new_overtime);

  -- Static safety assertions before compiling the derived function.
  IF v_definition ILIKE '%hr.weekly_off_day%'
     OR v_definition ILIKE '%hr.work_hours_per_day%'
     OR v_definition ILIKE '%EXTRACT(DOW FROM v_d)%' THEN
    RAISE EXCEPTION 'M5 build failed: legacy schedule assumptions remain in scheduled payroll';
  END IF;

  IF v_definition NOT ILIKE '%get_employee_scheduled_period%'
     OR v_definition NOT ILIKE '%assert_employee_payroll_schedule_snapshots%'
     OR v_definition NOT ILIKE '%v_period_scheduled_minutes / 60.0%' THEN
    RAISE EXCEPTION 'M5 build failed: scheduled payroll wiring is incomplete';
  END IF;

  EXECUTE v_definition;
END;
$build_scheduled$;

REVOKE ALL ON FUNCTION public.calculate_employee_payroll_scheduled(UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5. Public dispatcher. Existing callers and signatures remain unchanged.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_employee_payroll(
  p_employee_id UUID,
  p_run_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF NOT public.hr_employee_work_schedules_enabled() THEN
    RETURN public.calculate_employee_payroll_legacy_20260805(
      p_employee_id,
      p_run_id
    );
  END IF;

  RETURN public.calculate_employee_payroll_scheduled(
    p_employee_id,
    p_run_id
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.calculate_employee_payroll(UUID, UUID)
  TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 6. In-transaction assertions
-- ----------------------------------------------------------------------------
DO $assertions$
DECLARE
  v_definition TEXT;
  v_hash TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'M5 assertion failed: feature/readiness changed';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'M5 assertion failed: migration changed runtime data';
  END IF;

  SELECT pg_get_functiondef('public.calculate_employee_payroll(uuid,uuid)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%calculate_employee_payroll_legacy_20260805%'
     OR v_definition NOT ILIKE '%calculate_employee_payroll_scheduled%'
     OR v_definition NOT ILIKE '%hr_employee_work_schedules_enabled%' THEN
    RAISE EXCEPTION 'M5 assertion failed: payroll dispatcher is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.calculate_employee_payroll_scheduled(uuid,uuid)'::regprocedure)
  INTO v_definition;
  IF v_definition ILIKE '%hr.weekly_off_day%'
     OR v_definition ILIKE '%hr.work_hours_per_day%'
     OR v_definition NOT ILIKE '%get_employee_scheduled_period%'
     OR v_definition NOT ILIKE '%assert_employee_payroll_schedule_snapshots%'
     OR v_definition NOT ILIKE '%v_period_scheduled_minutes / 60.0%' THEN
    RAISE EXCEPTION 'M5 assertion failed: scheduled payroll contains an invalid schedule dependency';
  END IF;

  SELECT md5(pg_get_functiondef('public.calculate_payroll_run(uuid)'::regprocedure))
  INTO v_hash;
  IF v_hash <> 'f97661bab79bc9b4fe7c68a19c9e9238' THEN
    RAISE EXCEPTION 'M5 assertion failed: calculate_payroll_run changed (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.approve_payroll_run(uuid,uuid)'::regprocedure))
  INTO v_hash;
  IF v_hash <> 'e32a1fcea2993bfbd1c0e3880b37cbd6' THEN
    RAISE EXCEPTION 'M5 assertion failed: approve_payroll_run changed (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.check_payroll_attendance_clearance(date,date,uuid)'::regprocedure))
  INTO v_hash;
  IF v_hash <> '3732e7614a8b0a06cdf170f237d426fd' THEN
    RAISE EXCEPTION 'M5 assertion failed: attendance clearance changed (%)', v_hash;
  END IF;

  IF has_function_privilege('authenticated', 'public.calculate_employee_payroll_scheduled(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.calculate_employee_payroll_legacy_20260805(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.calculate_employee_payroll_scheduled(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.get_employee_scheduled_period(uuid,date,date,boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION 'M5 assertion failed: an internal payroll helper is exposed';
  END IF;
END;
$assertions$;

COMMIT;
