-- HR Variable Schedules V2 — Batch 3B1
-- Auto-checkout schedule timing only.
--
-- Scope:
--   * preserve the public run_auto_checkout(date) signature and Legacy implementation;
--   * while the shared V2 runtime gate is false, execute the exact Legacy path;
--   * after a later release activation, use a custom scheduled end only for a
--     custom-schedule working day;
--   * never invent a company end-time for a custom non-working day;
--   * preserve manual-lock, approved/paid payroll, alert, log, leave-settlement,
--     and penalty-reprocessing behavior.
--
-- This migration does NOT activate V2. The runtime gate remains hard-coded false.

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
    AND p.proname = 'run_auto_checkout'
    AND pg_get_function_identity_arguments(p.oid) = 'p_target_date date';

  IF v_hash IS DISTINCT FROM 'd13869f50592c2dc31c63e9212183c81' THEN
    RAISE EXCEPTION 'Batch 3B1 baseline mismatch for run_auto_checkout; review production drift before applying';
  END IF;

  IF to_regprocedure('public.run_auto_checkout_legacy(date)') IS NOT NULL
     OR to_regprocedure('public.run_auto_checkout_custom_schedule(date)') IS NOT NULL THEN
    RAISE EXCEPTION 'Batch 3B1 helper function name collision';
  END IF;

  IF to_regprocedure('public.hr_variable_schedules_v2_runtime_enabled()') IS NULL
     OR to_regprocedure('public.resolve_employee_custom_schedule(uuid,date)') IS NULL THEN
    RAISE EXCEPTION 'Batch 3B1 prerequisites are missing';
  END IF;
END;
$guard$;

ALTER FUNCTION public.run_auto_checkout(date)
  RENAME TO run_auto_checkout_legacy;

REVOKE ALL ON FUNCTION public.run_auto_checkout_legacy(date)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.run_auto_checkout_custom_schedule(
  p_target_date date DEFAULT CURRENT_DATE
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_day public.hr_attendance_days%ROWTYPE;
  v_today date := (now() AT TIME ZONE 'Africa/Cairo')::date;
  v_company_work_end time;
  v_day_work_end time;
  v_grace_minutes integer;
  v_cutoff_time timestamptz;
  v_auto_checkout_time timestamptz;
  v_early_leave_minutes integer;
  v_overtime_minutes integer;
  v_effective_hours numeric(5,2);
  v_checkout_status public.hr_checkout_status;
  v_scheduled_end timestamptz;
  v_schedule record;
  v_has_custom_schedule boolean;
  v_custom_working_day boolean;
BEGIN
  IF p_target_date > v_today THEN
    RAISE EXCEPTION 'لا يمكن الإغلاق التلقائي لأيام في المستقبل';
  END IF;

  SELECT COALESCE(value, '17:00')::time
  INTO v_company_work_end
  FROM public.company_settings
  WHERE key = 'hr.work_end_time';

  SELECT COALESCE(value, '15')::integer
  INTO v_grace_minutes
  FROM public.company_settings
  WHERE key = 'hr.auto_checkout_minutes';

  FOR v_day IN
    SELECT d.*
    FROM public.hr_attendance_days d
    WHERE d.shift_date = p_target_date
      AND d.punch_in_time IS NOT NULL
      AND d.punch_out_time IS NULL
      AND COALESCE(d.is_manually_locked, false) = false
      AND NOT EXISTS (
        SELECT 1
        FROM public.hr_payroll_runs pr
        JOIN public.hr_payroll_periods pp ON pp.id = pr.period_id
        JOIN public.hr_payroll_lines pl ON pl.payroll_run_id = pr.id
        WHERE pl.employee_id = d.employee_id
          AND pr.status IN ('approved', 'paid')
          AND d.shift_date BETWEEN pp.start_date AND pp.end_date
      )
  LOOP
    v_has_custom_schedule := false;
    v_custom_working_day := false;
    v_day_work_end := v_company_work_end;

    -- Prefer the immutable attendance snapshot when this row was already
    -- processed under V2. This prevents later schedule planning from
    -- reinterpreting an in-flight attendance day.
    IF v_day.custom_schedule_id IS NOT NULL THEN
      v_has_custom_schedule := true;
      v_custom_working_day := COALESCE(v_day.custom_scheduled_minutes, 0) > 0;
      v_day_work_end := v_day.custom_scheduled_end;
    ELSE
      SELECT *
      INTO v_schedule
      FROM public.resolve_employee_custom_schedule(v_day.employee_id, v_day.shift_date);

      IF FOUND THEN
        v_has_custom_schedule := true;
        v_custom_working_day := v_schedule.is_working_day;
        v_day_work_end := v_schedule.end_time;
      END IF;
    END IF;

    -- A custom non-working weekday has no official scheduled end. Do not
    -- manufacture one from the company fallback and therefore do not create a
    -- false early-leave/overtime interpretation. It remains open for review.
    IF v_has_custom_schedule AND NOT v_custom_working_day THEN
      CONTINUE;
    END IF;

    IF v_day_work_end IS NULL THEN
      RAISE EXCEPTION 'Batch 3B1 could not resolve a scheduled end for attendance day %', v_day.id;
    END IF;

    v_scheduled_end :=
      (v_day.shift_date::text || ' ' || v_day_work_end::text)::timestamp
      AT TIME ZONE 'Africa/Cairo';

    -- Unlike the Legacy company-wide cutoff, a mixed population must be
    -- evaluated per row. Legacy rows still use the company end; custom rows use
    -- only their custom scheduled end.
    IF p_target_date = v_today THEN
      v_cutoff_time := v_scheduled_end + (v_grace_minutes || ' minutes')::interval;
      IF now() < v_cutoff_time THEN
        CONTINUE;
      END IF;
    END IF;

    IF v_day.last_tracking_ping_at IS NOT NULL
       AND v_day.last_tracking_ping_at > v_day.punch_in_time THEN
      v_auto_checkout_time := v_day.last_tracking_ping_at;
    ELSE
      v_auto_checkout_time := v_scheduled_end;
    END IF;

    IF v_auto_checkout_time < v_day.punch_in_time THEN
      v_auto_checkout_time := v_day.punch_in_time;
    END IF;

    v_early_leave_minutes := 0;
    v_overtime_minutes := 0;

    IF v_auto_checkout_time < v_scheduled_end THEN
      v_early_leave_minutes := GREATEST(
        0,
        EXTRACT(EPOCH FROM (v_scheduled_end - v_auto_checkout_time)) / 60
      )::integer;
    ELSIF v_auto_checkout_time > v_scheduled_end THEN
      v_overtime_minutes := GREATEST(
        0,
        EXTRACT(EPOCH FROM (v_auto_checkout_time - v_scheduled_end)) / 60
      )::integer;
    END IF;

    v_effective_hours := GREATEST(
      0,
      EXTRACT(EPOCH FROM (v_auto_checkout_time - v_day.punch_in_time)) / 3600.0
    );

    IF v_overtime_minutes > 0 THEN
      v_checkout_status := 'overtime';
    ELSIF v_early_leave_minutes > 0 THEN
      IF EXISTS (
        SELECT 1
        FROM public.hr_leave_requests
        WHERE employee_id = v_day.employee_id
          AND start_date <= v_day.shift_date
          AND end_date >= v_day.shift_date
          AND status = 'approved'
      ) OR EXISTS (
        SELECT 1
        FROM public.hr_permission_requests
        WHERE employee_id = v_day.employee_id
          AND permission_date = v_day.shift_date
          AND status = 'approved'
      ) THEN
        v_checkout_status := 'early_authorized';
      ELSE
        v_checkout_status := 'early_unauthorized';
      END IF;
    ELSE
      v_checkout_status := 'on_time';
    END IF;

    UPDATE public.hr_attendance_days
    SET
      punch_out_time = v_auto_checkout_time,
      checkout_status = v_checkout_status,
      early_leave_minutes = v_early_leave_minutes,
      overtime_minutes = v_overtime_minutes,
      effective_hours = v_effective_hours,
      is_auto_checkout = true,
      tracking_status = 'ended',
      tracking_ended_at = v_auto_checkout_time,
      updated_at = now()
    WHERE id = v_day.id;

    INSERT INTO public.hr_attendance_alerts (
      employee_id, attendance_day_id, alert_type, severity, status, title, details
    ) VALUES (
      v_day.employee_id,
      v_day.id,
      'auto_checkout',
      'medium',
      'open',
      'إغلاق تلقائي للدوام',
      'تم إغلاق الدوام تلقائياً لعدم وجود بصمة انصراف. يرجى المراجعة.'
    );

    INSERT INTO public.hr_attendance_logs (
      employee_id, attendance_day_id, log_type,
      latitude, longitude, gps_accuracy, location_id,
      event_time, synced_at, requires_review
    ) VALUES (
      v_day.employee_id,
      v_day.id,
      'auto_checkout',
      COALESCE(v_day.last_tracking_lat, 0),
      COALESCE(v_day.last_tracking_lng, 0),
      COALESCE(v_day.last_tracking_accuracy, 0),
      v_day.location_in_id,
      v_auto_checkout_time,
      now(),
      true
    );

    -- These helpers are intentionally not redesigned here. The shared runtime
    -- gate stays false until the later schedule-aware penalty and leave-settlement
    -- sub-batches are independently reviewed and rehearsed.
    PERFORM public.settle_attendance_day_against_leave(v_day.id);
    PERFORM public.reprocess_attendance_day_penalties(v_day.id);
  END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION public.run_auto_checkout_custom_schedule(date)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.run_auto_checkout(
  p_target_date date DEFAULT CURRENT_DATE
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Exact production behavior while V2 remains disabled.
  IF NOT public.hr_variable_schedules_v2_runtime_enabled() THEN
    PERFORM public.run_auto_checkout_legacy(p_target_date);
    RETURN;
  END IF;

  -- If no open attendance row on the target date belongs to a custom schedule,
  -- preserve the exact Legacy function rather than routing the company through
  -- the mixed schedule-aware implementation.
  IF NOT EXISTS (
    SELECT 1
    FROM public.hr_attendance_days d
    WHERE d.shift_date = p_target_date
      AND d.punch_in_time IS NOT NULL
      AND d.punch_out_time IS NULL
      AND (
        d.custom_schedule_id IS NOT NULL
        OR EXISTS (
          SELECT 1
          FROM public.resolve_employee_custom_schedule(d.employee_id, d.shift_date)
        )
      )
  ) THEN
    PERFORM public.run_auto_checkout_legacy(p_target_date);
    RETURN;
  END IF;

  PERFORM public.run_auto_checkout_custom_schedule(p_target_date);
END;
$function$;

COMMENT ON FUNCTION public.run_auto_checkout(date) IS
  'V2 compatibility wrapper: exact Legacy path unless runtime is enabled and an open custom-schedule attendance row exists.';

REVOKE ALL ON FUNCTION public.run_auto_checkout(date)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.run_auto_checkout(date)
  TO PUBLIC, anon, authenticated, service_role;

COMMIT;
