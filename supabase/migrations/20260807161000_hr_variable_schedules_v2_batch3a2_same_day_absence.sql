-- HR Variable Schedules V2 — Batch 3A2
-- Same-day absence timing only.
-- Past/future target dates continue through the exact Legacy function.

BEGIN;

DO $guard$
DECLARE
  v_hash text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid))
  INTO v_hash
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'mark_daily_absences'
    AND pg_get_function_identity_arguments(p.oid) = 'p_target_date date';

  IF v_hash IS DISTINCT FROM '21e4cb27c5d1008da928cbf14ad56f1b' THEN
    RAISE EXCEPTION 'Batch 3A2 baseline mismatch for mark_daily_absences; review production drift before applying';
  END IF;

  IF to_regprocedure('public.mark_daily_absences_legacy(date)') IS NOT NULL THEN
    RAISE EXCEPTION 'Batch 3A2 helper function name collision';
  END IF;

  IF to_regprocedure('public.hr_variable_schedules_v2_runtime_enabled()') IS NULL
     OR to_regprocedure('public.resolve_employee_custom_schedule(uuid,date)') IS NULL
     OR to_regprocedure('public.is_employee_work_day(uuid,date)') IS NULL THEN
    RAISE EXCEPTION 'Batch 3A2 prerequisites are missing';
  END IF;
END;
$guard$;

ALTER FUNCTION public.mark_daily_absences(date)
  RENAME TO mark_daily_absences_legacy;

REVOKE ALL ON FUNCTION public.mark_daily_absences_legacy(date)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.mark_daily_absences(
  p_target_date date DEFAULT CURRENT_DATE
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_emp hr_employees%ROWTYPE;
  v_is_worked boolean;
  v_has_leave boolean;
  v_is_locked boolean;
  v_in_closed_payroll boolean;
  v_today date := (now() AT TIME ZONE 'Africa/Cairo')::date;
  v_work_end time;
  v_grace_minutes integer;
  v_company_cutoff timestamptz;
  v_custom_cutoff timestamptz;
  v_schedule record;
BEGIN
  -- During development, and for every non-current target date after activation,
  -- preserve the exact Legacy function path.
  IF NOT public.hr_variable_schedules_v2_runtime_enabled()
     OR p_target_date IS DISTINCT FROM v_today THEN
    PERFORM public.mark_daily_absences_legacy(p_target_date);
    RETURN;
  END IF;

  -- Keep the current company-wide minimum same-day guard exactly. V2 never makes
  -- same-day absence marking earlier for legacy employees or custom employees.
  SELECT COALESCE(value, '17:00')::time INTO v_work_end
  FROM company_settings WHERE key = 'hr.work_end_time';

  SELECT COALESCE(value, '120')::integer INTO v_grace_minutes
  FROM company_settings WHERE key = 'hr.absence_run_delay_minutes';

  v_company_cutoff :=
    (p_target_date::text || ' ' || v_work_end::text)::timestamp AT TIME ZONE 'Africa/Cairo'
    + (v_grace_minutes || ' minutes')::interval;

  IF now() < v_company_cutoff THEN
    RAISE EXCEPTION 'لا يمكن رصد الغياب لليوم الحالي إلا بعد نهاية الدوام بمهلة % دقيقة', v_grace_minutes;
  END IF;

  FOR v_emp IN
    SELECT * FROM hr_employees WHERE status = 'active'
  LOOP
    -- Preserve current employment-date guards.
    IF v_emp.hire_date IS NOT NULL AND v_emp.hire_date > p_target_date THEN
      CONTINUE;
    END IF;

    IF v_emp.termination_date IS NOT NULL AND v_emp.termination_date < p_target_date THEN
      CONTINUE;
    END IF;

    -- Exact Legacy classification for legacy employees; custom classification only
    -- when the gated resolver has an effective complete custom schedule.
    IF public.is_employee_work_day(v_emp.id, p_target_date) <> 'work_day' THEN
      CONTINUE;
    END IF;

    SELECT * INTO v_schedule
    FROM public.resolve_employee_custom_schedule(v_emp.id, p_target_date);

    IF FOUND AND v_schedule.is_working_day THEN
      v_custom_cutoff :=
        (p_target_date::text || ' ' || v_schedule.end_time::text)::timestamp AT TIME ZONE 'Africa/Cairo'
        + (v_grace_minutes || ' minutes')::interval;

      -- A later custom shift is simply skipped until its own end+delay. Other
      -- employees continue to be processed at the normal company cutoff.
      IF now() < v_custom_cutoff THEN
        CONTINUE;
      END IF;
    END IF;

    SELECT EXISTS (
      SELECT 1 FROM hr_attendance_days
      WHERE employee_id = v_emp.id
        AND shift_date = p_target_date
        AND status <> 'absent_unauthorized'
    ) INTO v_is_worked;

    SELECT EXISTS (
      SELECT 1 FROM hr_leave_requests
      WHERE employee_id = v_emp.id
        AND status = 'approved'
        AND p_target_date BETWEEN start_date AND end_date
    ) INTO v_has_leave;

    SELECT EXISTS (
      SELECT 1 FROM hr_attendance_days
      WHERE employee_id = v_emp.id
        AND shift_date = p_target_date
        AND COALESCE(is_manually_locked, false) = true
    ) INTO v_is_locked;

    SELECT EXISTS (
      SELECT 1 FROM hr_payroll_runs pr
      JOIN hr_payroll_periods pp ON pp.id = pr.period_id
      JOIN hr_payroll_lines pl ON pl.payroll_run_id = pr.id
      WHERE pl.employee_id = v_emp.id
        AND pr.status IN ('approved', 'paid')
        AND p_target_date BETWEEN pp.start_date AND pp.end_date
    ) INTO v_in_closed_payroll;

    IF NOT v_is_worked AND NOT v_has_leave AND NOT v_is_locked AND NOT v_in_closed_payroll THEN
      INSERT INTO hr_attendance_days (
        employee_id, shift_date, work_date, status, day_value, review_status, updated_at
      ) VALUES (
        v_emp.id, p_target_date, p_target_date, 'absent_unauthorized', 0, 'ok', now()
      )
      ON CONFLICT (employee_id, shift_date) DO UPDATE SET
        status = 'absent_unauthorized',
        day_value = 0,
        updated_at = now()
      WHERE COALESCE(hr_attendance_days.is_manually_locked, false) = false
        AND hr_attendance_days.status NOT IN ('absent_unauthorized', 'on_leave')
        AND hr_attendance_days.source_leave_request_id IS NULL
        AND hr_attendance_days.punch_in_time IS NULL;
    END IF;
  END LOOP;
END;
$function$;

COMMENT ON FUNCTION public.mark_daily_absences(date) IS
  'V2 compatibility wrapper: exact Legacy outside current-day gated processing; current-day custom employees wait for their own scheduled end plus the existing absence delay.';

REVOKE ALL ON FUNCTION public.mark_daily_absences(date)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_daily_absences(date)
  TO PUBLIC, anon, authenticated, service_role;

COMMIT;
