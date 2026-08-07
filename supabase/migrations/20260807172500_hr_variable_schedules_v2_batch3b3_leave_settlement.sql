-- HR Variable Schedules V2 — Batch 3B3
-- Leave settlement daily-duration adapter only.
--
-- Scope:
--   * preserve settle_attendance_day_against_leave(uuid,boolean) public signature;
--   * preserve exact Legacy behavior when V2 is disabled, no custom schedule applies,
--     or the custom date is a non-working day;
--   * for a custom working day, replace only company work-hours with the custom
--     scheduled daily duration for full-day restoration and partial day_value;
--   * preserve leave balance policy, approval state, manual locks, payroll locks,
--     idempotency, status updates, and all other Legacy behavior;
--   * do not activate V2.

BEGIN;

DO $guard$
DECLARE
  v_hash text;
BEGIN
  SELECT md5(replace(p.prosrc, E'\r\n', E'\n'))
  INTO v_hash
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'settle_attendance_day_against_leave'
    AND pg_get_function_identity_arguments(p.oid) = 'p_attendance_day_id uuid, p_force boolean';

  IF v_hash IS DISTINCT FROM 'f0cd9bc5b6787e76aa970de6a9ce9370' THEN
    RAISE EXCEPTION 'Batch 3B3 baseline mismatch for settle_attendance_day_against_leave; review production drift before applying';
  END IF;

  IF to_regprocedure('public.settle_attendance_day_against_leave_legacy(uuid,boolean)') IS NOT NULL
     OR to_regprocedure('public.settle_attendance_day_against_leave_custom_schedule(uuid,boolean)') IS NOT NULL THEN
    RAISE EXCEPTION 'Batch 3B3 helper function name collision';
  END IF;

  IF to_regprocedure('public.hr_variable_schedules_v2_runtime_enabled()') IS NULL
     OR to_regprocedure('public.resolve_employee_custom_schedule(uuid,date)') IS NULL THEN
    RAISE EXCEPTION 'Batch 3B3 prerequisites are missing';
  END IF;
END;
$guard$;

ALTER FUNCTION public.settle_attendance_day_against_leave(uuid, boolean)
  RENAME TO settle_attendance_day_against_leave_legacy;

REVOKE ALL ON FUNCTION public.settle_attendance_day_against_leave_legacy(uuid, boolean)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.settle_attendance_day_against_leave_custom_schedule(
  p_attendance_day_id uuid,
  p_force boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_day public.hr_attendance_days%ROWTYPE;
  v_leave_req public.hr_leave_requests%ROWTYPE;
  v_schedule record;
  v_scheduled_minutes integer;
  v_work_hours numeric;
  v_new_status public.hr_attendance_status;
BEGIN
  SELECT *
  INTO v_day
  FROM public.hr_attendance_days
  WHERE id = p_attendance_day_id;

  IF NOT FOUND
     OR v_day.source_leave_request_id IS NULL
     OR v_day.punch_in_time IS NULL
     OR v_day.punch_out_time IS NULL THEN
    RETURN;
  END IF;

  IF COALESCE(v_day.leave_balance_restored, false) = true THEN
    RETURN;
  END IF;

  IF NOT p_force AND COALESCE(v_day.is_manually_locked, false) = true THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_payroll_runs pr
    JOIN public.hr_payroll_periods pp ON pp.id = pr.period_id
    JOIN public.hr_payroll_lines pl ON pl.payroll_run_id = pr.id
    WHERE pl.employee_id = v_day.employee_id
      AND pr.status IN ('approved', 'paid')
      AND v_day.shift_date BETWEEN pp.start_date AND pp.end_date
  ) THEN
    RETURN;
  END IF;

  SELECT *
  INTO v_leave_req
  FROM public.hr_leave_requests
  WHERE id = v_day.source_leave_request_id;

  IF NOT FOUND OR v_leave_req.status <> 'approved' THEN
    RETURN;
  END IF;

  IF v_day.custom_schedule_id IS NOT NULL THEN
    v_scheduled_minutes := v_day.custom_scheduled_minutes;
  ELSE
    SELECT *
    INTO v_schedule
    FROM public.resolve_employee_custom_schedule(v_day.employee_id, v_day.shift_date);

    IF NOT FOUND OR NOT v_schedule.is_working_day THEN
      RAISE EXCEPTION 'Batch 3B3 custom settlement invoked without a custom working day';
    END IF;

    v_scheduled_minutes := v_schedule.scheduled_minutes;
  END IF;

  IF COALESCE(v_scheduled_minutes, 0) <= 0 THEN
    RAISE EXCEPTION 'Batch 3B3 custom attendance snapshot has no positive scheduled duration for attendance day %', p_attendance_day_id;
  END IF;

  v_work_hours := v_scheduled_minutes::numeric / 60.0;

  IF COALESCE(v_day.effective_hours, 0) >= v_work_hours THEN
    UPDATE public.hr_leave_balances
    SET used_days = GREATEST(0, used_days - 1),
        updated_at = now()
    WHERE employee_id = v_day.employee_id
      AND leave_type_id = v_leave_req.leave_type_id
      AND year = EXTRACT(YEAR FROM v_leave_req.start_date)::integer;

    v_new_status := 'present';
    IF COALESCE(v_day.late_minutes, 0) > 0 THEN
      v_new_status := 'late';
    END IF;

    UPDATE public.hr_attendance_days
    SET status = v_new_status,
        leave_balance_restored = true,
        leave_balance_restored_at = now(),
        updated_at = now()
    WHERE id = p_attendance_day_id;
  ELSE
    v_new_status := 'present';
    IF COALESCE(v_day.late_minutes, 0) > 0 THEN
      v_new_status := 'late';
    END IF;

    UPDATE public.hr_attendance_days
    SET status = v_new_status,
        day_value = LEAST(
          1.00,
          ROUND((COALESCE(v_day.effective_hours, 0) / v_work_hours)::numeric, 2)
        ),
        leave_balance_restored = false,
        updated_at = now()
    WHERE id = p_attendance_day_id;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.settle_attendance_day_against_leave_custom_schedule(uuid, boolean)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.settle_attendance_day_against_leave(
  p_attendance_day_id uuid,
  p_force boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_day public.hr_attendance_days%ROWTYPE;
  v_schedule record;
  v_is_custom_working_day boolean := false;
BEGIN
  IF NOT public.hr_variable_schedules_v2_runtime_enabled() THEN
    PERFORM public.settle_attendance_day_against_leave_legacy(p_attendance_day_id, p_force);
    RETURN;
  END IF;

  SELECT *
  INTO v_day
  FROM public.hr_attendance_days
  WHERE id = p_attendance_day_id;

  IF NOT FOUND OR v_day.source_leave_request_id IS NULL THEN
    PERFORM public.settle_attendance_day_against_leave_legacy(p_attendance_day_id, p_force);
    RETURN;
  END IF;

  IF v_day.custom_schedule_id IS NOT NULL THEN
    v_is_custom_working_day := COALESCE(v_day.custom_scheduled_minutes, 0) > 0;
  ELSE
    SELECT *
    INTO v_schedule
    FROM public.resolve_employee_custom_schedule(v_day.employee_id, v_day.shift_date);

    IF FOUND THEN
      v_is_custom_working_day :=
        v_schedule.is_working_day
        AND COALESCE(v_schedule.scheduled_minutes, 0) > 0;
    END IF;
  END IF;

  -- Batch 3B3 does not redefine leave policy for custom non-working days. Those
  -- dates continue through the exact Legacy settlement behavior.
  IF NOT v_is_custom_working_day THEN
    PERFORM public.settle_attendance_day_against_leave_legacy(p_attendance_day_id, p_force);
    RETURN;
  END IF;

  PERFORM public.settle_attendance_day_against_leave_custom_schedule(
    p_attendance_day_id,
    p_force
  );
END;
$function$;

COMMENT ON FUNCTION public.settle_attendance_day_against_leave(uuid, boolean) IS
  'V2 compatibility wrapper: exact Legacy settlement except custom working days use custom scheduled duration as the full-day/partial-day denominator.';

REVOKE ALL ON FUNCTION public.settle_attendance_day_against_leave(uuid, boolean)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.settle_attendance_day_against_leave(uuid, boolean)
  TO PUBLIC, anon, authenticated, service_role;

COMMIT;
