-- HR Variable Schedules V2 — Batch 4B
-- Narrow payroll adapter only.
--
-- Safety model:
--   * preserve the exact captured production calculator as Legacy;
--   * keep the public signature unchanged;
--   * runtime gate=false continues to execute the exact Legacy function;
--   * runtime gate=true but no complete effective custom schedule in the employee's
--     current payroll calculation interval also executes the exact Legacy function;
--   * only the custom path changes schedule-dependent inputs:
--       - expected workdays;
--       - scheduled hours used by overtime rate denominator;
--       - partial/interim entitled workdays;
--   * commissions, advances, insurance, tax, manual adjustments, deficit carryover,
--     payroll-line persistence and run totals remain the captured production logic;
--   * no payroll data is changed by installing this batch.

BEGIN;

DO $guard$
DECLARE
  v_hash text;
BEGIN
  IF to_regprocedure('public.hr_variable_schedules_v2_runtime_enabled()') IS NULL
     OR to_regprocedure('public.hr_v2_get_payroll_schedule_metrics(uuid,date,date)') IS NULL
     OR to_regprocedure('public.resolve_employee_custom_schedule(uuid,date)') IS NULL THEN
    RAISE EXCEPTION 'Batch 4B prerequisites are missing';
  END IF;

  IF to_regprocedure('public.calculate_employee_payroll_legacy(uuid,uuid)') IS NOT NULL
     OR to_regprocedure('public.calculate_employee_payroll_custom_schedule(uuid,uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'Batch 4B helper function name collision';
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
      'Batch 4B payroll baseline mismatch (actual=%); review production drift before continuing',
      v_hash;
  END IF;
END;
$guard$;

-- Preserve the exact current production implementation as the authoritative
-- Legacy path. Runtime-disabled and no-custom cases return through this function.
ALTER FUNCTION public.calculate_employee_payroll(uuid, uuid)
  RENAME TO calculate_employee_payroll_legacy;

REVOKE ALL ON FUNCTION public.calculate_employee_payroll_legacy(uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;

-- Derive the custom-only implementation from the guarded Legacy body at install
-- time, then patch only the schedule-dependent blocks. This avoids maintaining a
-- second hand-copied payroll engine while preserving the exact Legacy function.
DO $build_custom$
DECLARE
  v_body text;
  v_before text;
  v_old text;
  v_new text;
BEGIN
  SELECT replace(p.prosrc, E'\r\n', E'\n')
  INTO v_body
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'calculate_employee_payroll_legacy'
    AND pg_get_function_identity_arguments(p.oid) = 'p_employee_id uuid, p_run_id uuid';

  IF v_body IS NULL THEN
    RAISE EXCEPTION 'Batch 4B could not read Legacy payroll body';
  END IF;

  -- Add V2 metric records only; all existing variables remain untouched.
  v_old := E'  v_work_hours_per_day NUMERIC;\n';
  v_new := E'  v_work_hours_per_day NUMERIC;\n\n'
    || E'  -- V2 custom-schedule payroll inputs only.\n'
    || E'  v_v2_full_metrics   RECORD;\n'
    || E'  v_v2_range_metrics  RECORD;\n';

  IF position(v_old in v_body) = 0 THEN
    RAISE EXCEPTION 'Batch 4B declaration patch anchor not found';
  END IF;
  v_body := replace(v_body, v_old, v_new);

  -- Replace only the full-period Legacy calendar/hour derivation. The resulting
  -- average hours/day keeps the existing overtime formula mathematically equal to
  -- base_salary / total scheduled hours for variable-duration schedules.
  v_old := $old_full$
  v_off_day_name := COALESCE(v_emp.weekly_off_day::TEXT, NULL);
  IF v_off_day_name IS NULL THEN
    SELECT value INTO v_off_day_name FROM company_settings WHERE key = 'hr.weekly_off_day';
  END IF;
  v_off_day_name := COALESCE(v_off_day_name, 'friday');

  v_off_dow := CASE lower(v_off_day_name)
    WHEN 'sunday'    THEN 0 WHEN 'monday'    THEN 1 WHEN 'tuesday'   THEN 2
    WHEN 'wednesday' THEN 3 WHEN 'thursday'  THEN 4 WHEN 'friday'    THEN 5
    WHEN 'saturday'  THEN 6 ELSE 5 END;

  v_calendar_days := 0;
  v_d := v_period.start_date;
  WHILE v_d <= v_period.end_date LOOP
    IF EXTRACT(DOW FROM v_d)::INTEGER <> v_off_dow THEN
      v_calendar_days := v_calendar_days + 1;
    END IF;
    v_d := v_d + 1;
  END LOOP;

  SELECT COUNT(*) INTO v_public_holidays
  FROM hr_public_holidays
  WHERE holiday_date BETWEEN v_period.start_date AND v_period.end_date
    AND EXTRACT(DOW FROM holiday_date)::INTEGER <> v_off_dow;

  v_calendar_days := v_calendar_days - COALESCE(v_public_holidays, 0);
  IF v_calendar_days <= 0 THEN v_calendar_days := 26; END IF;

  v_working_days := v_calendar_days;
  v_daily_rate := COALESCE(v_salary.gross_salary, 0) / v_working_days;

  SELECT COALESCE(value::NUMERIC, 8) INTO v_work_hours_per_day
  FROM company_settings WHERE key = 'hr.work_hours_per_day';

$old_full$;

  v_new := $new_full$
  SELECT *
  INTO v_v2_full_metrics
  FROM public.hr_v2_get_payroll_schedule_metrics(
    p_employee_id,
    v_period.start_date,
    v_period.end_date
  );

  IF COALESCE(v_v2_full_metrics.custom_dates, 0) <= 0 THEN
    RAISE EXCEPTION 'V2 custom payroll path invoked without custom schedule dates';
  END IF;

  v_working_days := COALESCE(v_v2_full_metrics.work_days, 0);

  -- Do not synthesize a workday. A zero-day custom month cannot safely provide a
  -- salary or hourly denominator, so fail closed instead of inventing Legacy 26/1.
  IF v_working_days <= 0
     OR COALESCE(v_v2_full_metrics.scheduled_minutes, 0) <= 0 THEN
    RAISE EXCEPTION
      'V2 custom payroll period has no positive scheduled work denominator for employee %',
      p_employee_id;
  END IF;

  v_daily_rate := COALESCE(v_salary.gross_salary, 0) / v_working_days;
  v_work_hours_per_day :=
    (v_v2_full_metrics.scheduled_minutes::NUMERIC / 60.0) / v_working_days;

$new_full$;

  IF position(v_old in v_body) = 0 THEN
    RAISE EXCEPTION 'Batch 4B full-period schedule patch anchor not found';
  END IF;
  v_body := replace(v_body, v_old, v_new);

  -- Replace only partial/interim entitled-workday loops. Zero workdays remain zero;
  -- the legacy minimum-one fallback is intentionally not carried into custom mode.
  v_old := $old_partial$
  IF v_is_interim THEN
    v_is_partial := true;
    v_partial_working := 0;
    v_d := GREATEST(v_period.start_date, v_emp.hire_date);
    WHILE v_d <= LEAST(v_calc_date, COALESCE(v_emp.termination_date, v_calc_date)) LOOP
      IF EXTRACT(DOW FROM v_d)::INTEGER <> v_off_dow THEN
        IF NOT EXISTS (SELECT 1 FROM hr_public_holidays WHERE holiday_date = v_d) THEN
          v_partial_working := v_partial_working + 1;
        END IF;
      END IF;
      v_d := v_d + 1;
    END LOOP;
    IF v_partial_working <= 0 THEN v_partial_working := 1; END IF;
    v_gross_earned := v_daily_rate * v_partial_working;
    v_entitled_days := v_partial_working;
  ELSE
    v_gross_earned := COALESCE(v_salary.gross_salary, 0);

    -- Partial month logic (hire or termination) for final calculation
    IF v_emp.hire_date > v_period.start_date AND v_emp.hire_date <= v_period.end_date THEN
      v_is_partial := true;
      v_partial_working := 0;
      v_d := v_emp.hire_date;
      WHILE v_d <= v_period.end_date LOOP
        IF EXTRACT(DOW FROM v_d)::INTEGER <> v_off_dow THEN
          IF NOT EXISTS (SELECT 1 FROM hr_public_holidays WHERE holiday_date = v_d) THEN
            v_partial_working := v_partial_working + 1;
          END IF;
        END IF;
        v_d := v_d + 1;
      END LOOP;
      IF v_partial_working <= 0 THEN v_partial_working := 1; END IF;
      v_gross_earned := v_daily_rate * v_partial_working;
      v_entitled_days := v_partial_working;
    END IF;

    IF v_emp.termination_date IS NOT NULL AND v_emp.termination_date >= v_period.start_date AND v_emp.termination_date <= v_period.end_date THEN
      v_is_partial := true;
      v_partial_working := 0;
      v_d := GREATEST(v_period.start_date, v_emp.hire_date);
      WHILE v_d <= v_emp.termination_date LOOP
        IF EXTRACT(DOW FROM v_d)::INTEGER <> v_off_dow THEN
          IF NOT EXISTS (SELECT 1 FROM hr_public_holidays WHERE holiday_date = v_d) THEN
            v_partial_working := v_partial_working + 1;
          END IF;
        END IF;
        v_d := v_d + 1;
      END LOOP;
      IF v_partial_working <= 0 THEN v_partial_working := 1; END IF;
      v_gross_earned := v_daily_rate * v_partial_working;
      v_entitled_days := v_partial_working;
    END IF;
  END IF;

$old_partial$;

  v_new := $new_partial$
  IF v_is_interim THEN
    v_is_partial := true;

    SELECT *
    INTO v_v2_range_metrics
    FROM public.hr_v2_get_payroll_schedule_metrics(
      p_employee_id,
      GREATEST(v_period.start_date, v_emp.hire_date),
      LEAST(v_calc_date, COALESCE(v_emp.termination_date, v_calc_date))
    );

    v_partial_working := COALESCE(v_v2_range_metrics.work_days, 0);
    v_gross_earned := v_daily_rate * v_partial_working;
    v_entitled_days := v_partial_working;
  ELSE
    v_gross_earned := COALESCE(v_salary.gross_salary, 0);

    -- Partial month logic (hire or termination) for final calculation.
    IF v_emp.hire_date > v_period.start_date AND v_emp.hire_date <= v_period.end_date THEN
      v_is_partial := true;

      SELECT *
      INTO v_v2_range_metrics
      FROM public.hr_v2_get_payroll_schedule_metrics(
        p_employee_id,
        v_emp.hire_date,
        v_period.end_date
      );

      v_partial_working := COALESCE(v_v2_range_metrics.work_days, 0);
      v_gross_earned := v_daily_rate * v_partial_working;
      v_entitled_days := v_partial_working;
    END IF;

    IF v_emp.termination_date IS NOT NULL
       AND v_emp.termination_date >= v_period.start_date
       AND v_emp.termination_date <= v_period.end_date THEN
      v_is_partial := true;

      SELECT *
      INTO v_v2_range_metrics
      FROM public.hr_v2_get_payroll_schedule_metrics(
        p_employee_id,
        GREATEST(v_period.start_date, v_emp.hire_date),
        v_emp.termination_date
      );

      v_partial_working := COALESCE(v_v2_range_metrics.work_days, 0);
      v_gross_earned := v_daily_rate * v_partial_working;
      v_entitled_days := v_partial_working;
    END IF;
  END IF;

$new_partial$;

  IF position(v_old in v_body) = 0 THEN
    RAISE EXCEPTION 'Batch 4B partial-period schedule patch anchor not found';
  END IF;
  v_body := replace(v_body, v_old, v_new);

  -- Sanity: all custom schedule-dependent inputs must be present and Legacy
  -- minimum-day fallbacks must not survive in the custom implementation.
  IF position('hr_v2_get_payroll_schedule_metrics' in v_body) = 0
     OR position('v_v2_full_metrics.scheduled_minutes' in v_body) = 0
     OR position('IF v_calendar_days <= 0 THEN v_calendar_days := 26; END IF;' in v_body) > 0
     OR position('IF v_partial_working <= 0 THEN v_partial_working := 1; END IF;' in v_body) > 0 THEN
    RAISE EXCEPTION 'Batch 4B custom payroll body patch sanity check failed';
  END IF;

  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public.calculate_employee_payroll_custom_schedule(p_employee_id uuid, p_run_id uuid) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''public'' AS %L',
    v_body
  );
END;
$build_custom$;

COMMENT ON FUNCTION public.calculate_employee_payroll_custom_schedule(uuid, uuid) IS
  'Private V2 payroll implementation derived from the guarded production calculator; only schedule-dependent inputs are adapted.';

REVOKE ALL ON FUNCTION public.calculate_employee_payroll_custom_schedule(uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;

-- Public compatibility adapter. The default installed state remains exact Legacy
-- because the global runtime gate is still hard-false. When later enabled, only an
-- employee with a complete effective custom schedule overlapping the relevant
-- calculation interval can reach the custom payroll implementation.
CREATE OR REPLACE FUNCTION public.calculate_employee_payroll(
  p_employee_id uuid,
  p_run_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_has_custom boolean := false;
  v_today date := (now() AT TIME ZONE 'Africa/Cairo')::date;
BEGIN
  IF NOT public.hr_variable_schedules_v2_runtime_enabled() THEN
    RETURN public.calculate_employee_payroll_legacy(p_employee_id, p_run_id);
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.hr_payroll_runs r
    JOIN public.hr_payroll_periods p ON p.id = r.period_id
    JOIN public.hr_employees e ON e.id = p_employee_id
    JOIN public.hr_employee_work_schedules s ON s.employee_id = e.id
    WHERE r.id = p_run_id
      AND s.effective_from <= LEAST(
        COALESCE(e.termination_date, p.end_date),
        CASE
          WHEN p.end_date >= v_today THEN v_today - 1
          ELSE p.end_date
        END
      )
      AND (s.effective_to IS NULL OR s.effective_to >= GREATEST(p.start_date, e.hire_date))
      AND (
        SELECT COUNT(*)
        FROM public.hr_employee_work_schedule_days d
        WHERE d.schedule_id = s.id
      ) = 7
      AND EXISTS (
        SELECT 1
        FROM public.hr_employee_work_schedule_days d
        WHERE d.schedule_id = s.id
          AND d.is_working_day = true
      )
  )
  INTO v_has_custom;

  IF NOT COALESCE(v_has_custom, false) THEN
    RETURN public.calculate_employee_payroll_legacy(p_employee_id, p_run_id);
  END IF;

  RETURN public.calculate_employee_payroll_custom_schedule(p_employee_id, p_run_id);
END;
$function$;

COMMENT ON FUNCTION public.calculate_employee_payroll(uuid, uuid) IS
  'V2-compatible payroll adapter. Exact Legacy path unless release gate is enabled and a complete effective custom employee schedule overlaps the payroll calculation interval.';

-- Preserve the original public callable surface. Private aliases stay revoked.
GRANT EXECUTE ON FUNCTION public.calculate_employee_payroll(uuid, uuid)
  TO PUBLIC, anon, authenticated, service_role;

COMMIT;
