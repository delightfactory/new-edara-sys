-- =============================================================================
-- EDARA — Employee Work Schedules M4A
-- Schedule-aware daily absence marking and automatic checkout.
--
-- Disabled mode remains the exact production implementation.
-- Enabled mode uses per-employee resolver/snapshot times and fails closed on
-- missing custom-schedule snapshots.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '90s';

DO $preflight$
DECLARE
  v_hash TEXT;
BEGIN
  IF to_regprocedure('public.resolve_employee_work_schedule(uuid,date)') IS NULL
     OR to_regprocedure('public.ensure_attendance_schedule_snapshot(uuid)') IS NULL
     OR to_regprocedure('public.hr_employee_work_schedules_activation_ready()') IS NULL THEN
    RAISE EXCEPTION 'M4A preflight failed: schedule resolver/snapshot/activation guard is missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'M4A preflight failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'M4A preflight failed: no schedule/snapshot data is expected before rehearsal';
  END IF;

  IF to_regprocedure('public.mark_daily_absences_legacy_20260805(date)') IS NOT NULL
     OR to_regprocedure('public.mark_daily_absences_scheduled(date)') IS NOT NULL
     OR to_regprocedure('public.run_auto_checkout_legacy_20260805(date)') IS NOT NULL
     OR to_regprocedure('public.run_auto_checkout_scheduled(date)') IS NOT NULL THEN
    RAISE EXCEPTION 'M4A preflight failed: one or more M4A helpers already exist';
  END IF;

  SELECT md5(pg_get_functiondef('public.mark_daily_absences(date)'::regprocedure)) INTO v_hash;
  IF v_hash <> '21e4cb27c5d1008da928cbf14ad56f1b' THEN
    RAISE EXCEPTION 'M4A preflight failed: mark_daily_absences drifted (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.run_auto_checkout(date)'::regprocedure)) INTO v_hash;
  IF v_hash <> '7687df6dc398cd73ed53408c2c53d1a8' THEN
    RAISE EXCEPTION 'M4A preflight failed: run_auto_checkout drifted (%)', v_hash;
  END IF;
END;
$preflight$;

DO $clone_legacy$
DECLARE
  v_definition TEXT;
BEGIN
  SELECT pg_get_functiondef('public.mark_daily_absences(date)'::regprocedure)
  INTO v_definition;
  v_definition := replace(
    v_definition,
    'FUNCTION public.mark_daily_absences(',
    'FUNCTION public.mark_daily_absences_legacy_20260805('
  );
  EXECUTE v_definition;

  SELECT pg_get_functiondef('public.run_auto_checkout(date)'::regprocedure)
  INTO v_definition;
  v_definition := replace(
    v_definition,
    'FUNCTION public.run_auto_checkout(',
    'FUNCTION public.run_auto_checkout_legacy_20260805('
  );
  EXECUTE v_definition;
END;
$clone_legacy$;

REVOKE ALL ON FUNCTION public.mark_daily_absences_legacy_20260805(DATE)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.run_auto_checkout_legacy_20260805(DATE)
  FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Schedule-aware absence marking
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.mark_daily_absences_scheduled(
  p_target_date DATE DEFAULT CURRENT_DATE
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_emp public.hr_employees%ROWTYPE;
  v_existing public.hr_attendance_days%ROWTYPE;
  v_existing_found BOOLEAN;
  v_has_leave BOOLEAN;
  v_in_closed_payroll BOOLEAN;
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_delay_minutes INTEGER;
  v_day_kind TEXT;
  v_scheduled_start TIMESTAMPTZ;
  v_scheduled_end TIMESTAMPTZ;
  v_scheduled_minutes INTEGER;
  v_schedule_source TEXT;
  v_work_schedule_id UUID;
  v_snapshot_at TIMESTAMPTZ;
BEGIN
  IF p_target_date > v_today THEN
    RAISE EXCEPTION 'لا يمكن رصد الغياب لأيام في المستقبل';
  END IF;

  SELECT COALESCE(value, '120')::INTEGER
  INTO v_delay_minutes
  FROM public.company_settings
  WHERE key = 'hr.absence_run_delay_minutes';

  v_delay_minutes := COALESCE(v_delay_minutes, 120);

  FOR v_emp IN
    SELECT *
    FROM public.hr_employees
    WHERE status = 'active'
  LOOP
    BEGIN
      IF v_emp.hire_date IS NOT NULL AND v_emp.hire_date > p_target_date THEN
        CONTINUE;
      END IF;

      IF v_emp.termination_date IS NOT NULL AND v_emp.termination_date < p_target_date THEN
        CONTINUE;
      END IF;

      SELECT
        r.day_kind,
        r.scheduled_start_at,
        r.scheduled_end_at,
        r.scheduled_minutes,
        r.schedule_source,
        r.work_schedule_id
      INTO
        v_day_kind,
        v_scheduled_start,
        v_scheduled_end,
        v_scheduled_minutes,
        v_schedule_source,
        v_work_schedule_id
      FROM public.resolve_employee_work_schedule(v_emp.id, p_target_date) r;

      IF v_day_kind <> 'work_day' THEN
        CONTINUE;
      END IF;

      -- Current-day processing is per employee. Early shifts do not wait for
      -- the latest company-wide shift, and late shifts are never marked absent
      -- before their own end plus the configured delay.
      IF p_target_date = v_today
         AND now() < v_scheduled_end + make_interval(mins => v_delay_minutes) THEN
        CONTINUE;
      END IF;

      SELECT * INTO v_existing
      FROM public.hr_attendance_days
      WHERE employee_id = v_emp.id
        AND shift_date = p_target_date
      FOR UPDATE;

      v_existing_found := FOUND;

      IF v_existing_found THEN
        IF v_existing.schedule_snapshot_at IS NULL THEN
          -- The M2 helper creates only safe legacy fallback snapshots and stops
          -- if a custom schedule should have been snapshotted atomically.
          PERFORM public.ensure_attendance_schedule_snapshot(v_existing.id);

          SELECT * INTO v_existing
          FROM public.hr_attendance_days
          WHERE id = v_existing.id;
        END IF;

        IF v_existing.status <> 'absent_unauthorized'
           OR COALESCE(v_existing.is_manually_locked, false)
           OR v_existing.source_leave_request_id IS NOT NULL
           OR v_existing.punch_in_time IS NOT NULL THEN
          CONTINUE;
        END IF;

        -- Reuse the immutable row snapshot rather than re-resolving into the
        -- UPSERT. The values must agree with the resolver by construction.
        v_day_kind := v_existing.schedule_day_kind;
        v_scheduled_start := v_existing.scheduled_start_at;
        v_scheduled_end := v_existing.scheduled_end_at;
        v_scheduled_minutes := v_existing.scheduled_minutes;
        v_schedule_source := v_existing.schedule_source;
        v_work_schedule_id := v_existing.work_schedule_id;
        v_snapshot_at := v_existing.schedule_snapshot_at;
      ELSE
        v_snapshot_at := now();
      END IF;

      SELECT EXISTS (
        SELECT 1
        FROM public.hr_leave_requests
        WHERE employee_id = v_emp.id
          AND status = 'approved'
          AND p_target_date BETWEEN start_date AND end_date
      ) INTO v_has_leave;

      IF v_has_leave THEN
        CONTINUE;
      END IF;

      SELECT EXISTS (
        SELECT 1
        FROM public.hr_payroll_runs pr
        JOIN public.hr_payroll_periods pp ON pp.id = pr.period_id
        JOIN public.hr_payroll_lines pl ON pl.payroll_run_id = pr.id
        WHERE pl.employee_id = v_emp.id
          AND pr.status IN ('approved', 'paid')
          AND p_target_date BETWEEN pp.start_date AND pp.end_date
      ) INTO v_in_closed_payroll;

      IF v_in_closed_payroll THEN
        CONTINUE;
      END IF;

      INSERT INTO public.hr_attendance_days (
        employee_id,
        shift_date,
        work_date,
        status,
        day_value,
        review_status,
        schedule_day_kind,
        scheduled_start_at,
        scheduled_end_at,
        scheduled_minutes,
        schedule_source,
        work_schedule_id,
        schedule_snapshot_at,
        updated_at
      ) VALUES (
        v_emp.id,
        p_target_date,
        p_target_date,
        'absent_unauthorized',
        0,
        'ok',
        v_day_kind,
        v_scheduled_start,
        v_scheduled_end,
        v_scheduled_minutes,
        v_schedule_source,
        v_work_schedule_id,
        v_snapshot_at,
        now()
      )
      ON CONFLICT (employee_id, shift_date)
      DO UPDATE SET
        status = 'absent_unauthorized',
        day_value = 0,
        schedule_day_kind = COALESCE(public.hr_attendance_days.schedule_day_kind, EXCLUDED.schedule_day_kind),
        scheduled_start_at = COALESCE(public.hr_attendance_days.scheduled_start_at, EXCLUDED.scheduled_start_at),
        scheduled_end_at = COALESCE(public.hr_attendance_days.scheduled_end_at, EXCLUDED.scheduled_end_at),
        scheduled_minutes = COALESCE(public.hr_attendance_days.scheduled_minutes, EXCLUDED.scheduled_minutes),
        schedule_source = COALESCE(public.hr_attendance_days.schedule_source, EXCLUDED.schedule_source),
        work_schedule_id = COALESCE(public.hr_attendance_days.work_schedule_id, EXCLUDED.work_schedule_id),
        schedule_snapshot_at = COALESCE(public.hr_attendance_days.schedule_snapshot_at, EXCLUDED.schedule_snapshot_at),
        updated_at = now()
      WHERE COALESCE(public.hr_attendance_days.is_manually_locked, false) = false
        AND public.hr_attendance_days.status NOT IN ('absent_unauthorized', 'on_leave')
        AND public.hr_attendance_days.source_leave_request_id IS NULL
        AND public.hr_attendance_days.punch_in_time IS NULL;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING '[mark_daily_absences_scheduled] employee % date % skipped: %',
          v_emp.id,
          p_target_date,
          SQLERRM;
        CONTINUE;
    END;
  END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION public.mark_daily_absences_scheduled(DATE)
  FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Schedule-aware automatic checkout
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.run_auto_checkout_scheduled(
  p_target_date DATE DEFAULT CURRENT_DATE
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_day public.hr_attendance_days%ROWTYPE;
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_grace_minutes INTEGER;
  v_cutoff_time TIMESTAMPTZ;
  v_auto_checkout_time TIMESTAMPTZ;
  v_early_leave_minutes INTEGER;
  v_overtime_minutes INTEGER;
  v_effective_hours NUMERIC(5,2);
  v_checkout_status public.hr_checkout_status;
BEGIN
  IF p_target_date > v_today THEN
    RAISE EXCEPTION 'لا يمكن الإغلاق التلقائي لأيام في المستقبل';
  END IF;

  SELECT COALESCE(value, '15')::INTEGER
  INTO v_grace_minutes
  FROM public.company_settings
  WHERE key = 'hr.auto_checkout_minutes';

  v_grace_minutes := COALESCE(v_grace_minutes, 15);

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
    FOR UPDATE OF d SKIP LOCKED
  LOOP
    BEGIN
      IF v_day.schedule_snapshot_at IS NULL THEN
        PERFORM public.ensure_attendance_schedule_snapshot(v_day.id);

        SELECT * INTO v_day
        FROM public.hr_attendance_days
        WHERE id = v_day.id
        FOR UPDATE;
      END IF;

      IF v_day.schedule_day_kind <> 'work_day' THEN
        -- No expected end exists. Closing or granting overtime automatically
        -- would invent a financial rule, so leave the day open for review.
        UPDATE public.hr_attendance_days
        SET review_status = CASE
              WHEN review_status = 'reviewed' THEN 'reviewed'::public.hr_review_status
              ELSE 'needs_review'::public.hr_review_status
            END,
            updated_at = now()
        WHERE id = v_day.id;

        RAISE WARNING '[run_auto_checkout_scheduled] non-working attendance day % requires manual checkout review', v_day.id;
        CONTINUE;
      END IF;

      v_cutoff_time := v_day.scheduled_end_at + make_interval(mins => v_grace_minutes);

      IF p_target_date = v_today AND now() < v_cutoff_time THEN
        CONTINUE;
      END IF;

      IF v_day.last_tracking_ping_at IS NOT NULL
         AND v_day.last_tracking_ping_at > v_day.punch_in_time THEN
        v_auto_checkout_time := v_day.last_tracking_ping_at;
      ELSE
        v_auto_checkout_time := v_day.scheduled_end_at;
      END IF;

      IF v_auto_checkout_time < v_day.punch_in_time THEN
        v_auto_checkout_time := v_day.punch_in_time;
      END IF;

      v_early_leave_minutes := 0;
      v_overtime_minutes := 0;

      IF v_auto_checkout_time < v_day.scheduled_end_at THEN
        v_early_leave_minutes := GREATEST(
          0,
          EXTRACT(EPOCH FROM (v_day.scheduled_end_at - v_auto_checkout_time)) / 60
        )::INTEGER;
      ELSIF v_auto_checkout_time > v_day.scheduled_end_at THEN
        v_overtime_minutes := GREATEST(
          0,
          EXTRACT(EPOCH FROM (v_auto_checkout_time - v_day.scheduled_end_at)) / 60
        )::INTEGER;
      END IF;

      v_effective_hours := GREATEST(
        0,
        EXTRACT(EPOCH FROM (v_auto_checkout_time - v_day.punch_in_time)) / 3600.0
      );

      IF v_overtime_minutes > 0 THEN
        v_checkout_status := 'overtime';
      ELSIF v_early_leave_minutes > 0 THEN
        IF EXISTS (
          SELECT 1 FROM public.hr_leave_requests
          WHERE employee_id = v_day.employee_id
            AND start_date <= v_day.shift_date
            AND end_date >= v_day.shift_date
            AND status = 'approved'
        ) OR EXISTS (
          SELECT 1 FROM public.hr_permission_requests
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
      SET punch_out_time = v_auto_checkout_time,
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
        employee_id,
        attendance_day_id,
        alert_type,
        severity,
        status,
        title,
        details
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
        employee_id,
        attendance_day_id,
        log_type,
        latitude,
        longitude,
        gps_accuracy,
        location_id,
        event_time,
        synced_at,
        requires_review
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

      PERFORM public.settle_attendance_day_against_leave(v_day.id);
      PERFORM public.reprocess_attendance_day_penalties(v_day.id);
    EXCEPTION
      WHEN OTHERS THEN
        UPDATE public.hr_attendance_days
        SET review_status = CASE
              WHEN review_status = 'reviewed' THEN 'reviewed'::public.hr_review_status
              ELSE 'needs_review'::public.hr_review_status
            END,
            updated_at = now()
        WHERE id = v_day.id;

        RAISE WARNING '[run_auto_checkout_scheduled] attendance day % skipped: %',
          v_day.id,
          SQLERRM;
        CONTINUE;
    END;
  END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION public.run_auto_checkout_scheduled(DATE)
  FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Public wrappers: exact legacy behavior while disabled.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_daily_absences(
  p_target_date DATE DEFAULT CURRENT_DATE
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF NOT public.hr_employee_work_schedules_enabled() THEN
    PERFORM public.mark_daily_absences_legacy_20260805(p_target_date);
    RETURN;
  END IF;

  PERFORM public.mark_daily_absences_scheduled(p_target_date);
END;
$function$;

CREATE OR REPLACE FUNCTION public.run_auto_checkout(
  p_target_date DATE DEFAULT CURRENT_DATE
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF NOT public.hr_employee_work_schedules_enabled() THEN
    PERFORM public.run_auto_checkout_legacy_20260805(p_target_date);
    RETURN;
  END IF;

  PERFORM public.run_auto_checkout_scheduled(p_target_date);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.mark_daily_absences(DATE)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.run_auto_checkout(DATE)
  TO anon, authenticated, service_role;

DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'M4A assertion failed: feature/readiness changed';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'M4A assertion failed: migration changed runtime data';
  END IF;

  SELECT pg_get_functiondef('public.mark_daily_absences(date)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%mark_daily_absences_legacy_20260805%'
     OR v_definition NOT ILIKE '%mark_daily_absences_scheduled%'
     OR v_definition NOT ILIKE '%hr_employee_work_schedules_enabled%' THEN
    RAISE EXCEPTION 'M4A assertion failed: absence wrapper is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.run_auto_checkout(date)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%run_auto_checkout_legacy_20260805%'
     OR v_definition NOT ILIKE '%run_auto_checkout_scheduled%'
     OR v_definition NOT ILIKE '%hr_employee_work_schedules_enabled%' THEN
    RAISE EXCEPTION 'M4A assertion failed: auto-checkout wrapper is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.mark_daily_absences_scheduled(date)'::regprocedure)
  INTO v_definition;
  IF v_definition ILIKE '%hr.work_end_time%'
     OR v_definition NOT ILIKE '%resolve_employee_work_schedule%'
     OR v_definition NOT ILIKE '%schedule_snapshot_at%' THEN
    RAISE EXCEPTION 'M4A assertion failed: scheduled absence implementation bypasses resolver/snapshot';
  END IF;

  SELECT pg_get_functiondef('public.run_auto_checkout_scheduled(date)'::regprocedure)
  INTO v_definition;
  IF v_definition ILIKE '%hr.work_end_time%'
     OR v_definition NOT ILIKE '%scheduled_end_at%'
     OR v_definition NOT ILIKE '%ensure_attendance_schedule_snapshot%' THEN
    RAISE EXCEPTION 'M4A assertion failed: scheduled auto-checkout bypasses snapshot';
  END IF;
END;
$assertions$;

COMMIT;
