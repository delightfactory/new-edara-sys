-- =============================================================================
-- EDARA — Employee Work Schedules M4C
-- Schedule-aware absence notifications and open-day review alerts.
--
-- Existing cron schedules are not changed.
-- Tracking-gap logic and operational orchestration remain untouched.
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
    RAISE EXCEPTION 'M4C preflight failed: resolver/snapshot/activation guard is missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'M4C preflight failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'M4C preflight failed: no runtime schedule/snapshot data is expected';
  END IF;

  IF to_regprocedure('public.notify_absent_employees_legacy_20260805()') IS NOT NULL
     OR to_regprocedure('public.notify_absent_employees_scheduled()') IS NOT NULL
     OR to_regprocedure('public.scan_attendance_daily_review_alerts_legacy_20260805()') IS NOT NULL
     OR to_regprocedure('public.scan_attendance_daily_review_alerts_scheduled()') IS NOT NULL THEN
    RAISE EXCEPTION 'M4C preflight failed: one or more M4C helpers already exist';
  END IF;

  SELECT md5(pg_get_functiondef('public.notify_absent_employees()'::regprocedure)) INTO v_hash;
  IF v_hash <> '0d117e202cbbcf08e9d1b35b4b4dab14' THEN
    RAISE EXCEPTION 'M4C preflight failed: notify_absent_employees drifted (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.scan_attendance_daily_review_alerts()'::regprocedure)) INTO v_hash;
  IF v_hash <> '9997ff7734f0289b85c5d9a3b8330c38' THEN
    RAISE EXCEPTION 'M4C preflight failed: daily review scan drifted (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.scan_attendance_tracking_alerts()'::regprocedure)) INTO v_hash;
  IF v_hash <> '139e2ad118b89ff33d5052e67041e4e6' THEN
    RAISE EXCEPTION 'M4C preflight failed: tracking scan drifted (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.run_attendance_operational_scan()'::regprocedure)) INTO v_hash;
  IF v_hash <> '40baaa14f7df81f78025d14ebb0fc288' THEN
    RAISE EXCEPTION 'M4C preflight failed: operational scan drifted (%)', v_hash;
  END IF;
END;
$preflight$;

DO $clone_legacy$
DECLARE
  v_definition TEXT;
BEGIN
  SELECT pg_get_functiondef('public.notify_absent_employees()'::regprocedure)
  INTO v_definition;
  v_definition := replace(
    v_definition,
    'FUNCTION public.notify_absent_employees(',
    'FUNCTION public.notify_absent_employees_legacy_20260805('
  );
  EXECUTE v_definition;

  SELECT pg_get_functiondef('public.scan_attendance_daily_review_alerts()'::regprocedure)
  INTO v_definition;
  v_definition := replace(
    v_definition,
    'FUNCTION public.scan_attendance_daily_review_alerts(',
    'FUNCTION public.scan_attendance_daily_review_alerts_legacy_20260805('
  );
  EXECUTE v_definition;
END;
$clone_legacy$;

REVOKE ALL ON FUNCTION public.notify_absent_employees_legacy_20260805()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.scan_attendance_daily_review_alerts_legacy_20260805()
  FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Schedule-aware absence notifications
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.notify_absent_employees_scheduled()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_emp RECORD;
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_count INTEGER := 0;
  v_day_kind TEXT;
  v_scheduled_start TIMESTAMPTZ;
BEGIN
  FOR v_emp IN
    SELECT
      he.id AS employee_id,
      he.full_name AS emp_name,
      he.hire_date,
      he.termination_date,
      mgr.user_id AS manager_profile
    FROM public.hr_employees he
    LEFT JOIN public.hr_employees mgr ON mgr.id = he.direct_manager_id
    WHERE he.status = 'active'
      AND (he.hire_date IS NULL OR he.hire_date <= v_today)
      AND (he.termination_date IS NULL OR he.termination_date >= v_today)
      AND NOT EXISTS (
        SELECT 1
        FROM public.hr_leave_requests lr
        WHERE lr.employee_id = he.id
          AND lr.status IN ('approved_supervisor', 'approved_hr', 'approved')
          AND v_today BETWEEN lr.start_date AND lr.end_date
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.hr_permission_requests pr
        WHERE pr.employee_id = he.id
          AND pr.permission_date = v_today
          AND pr.status = 'approved'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.hr_attendance_days ad
        WHERE ad.employee_id = he.id
          AND ad.shift_date = v_today
      )
  LOOP
    BEGIN
      SELECT r.day_kind, r.scheduled_start_at
      INTO v_day_kind, v_scheduled_start
      FROM public.resolve_employee_work_schedule(v_emp.employee_id, v_today) r;

      IF v_day_kind <> 'work_day' THEN
        CONTINUE;
      END IF;

      -- Preserve the existing cron time but never notify before this employee's
      -- own scheduled start. No new grace policy is invented in this feature.
      IF now() < v_scheduled_start THEN
        CONTINUE;
      END IF;

      IF v_emp.manager_profile IS NOT NULL THEN
        PERFORM public.call_dispatch_notification(
          'hr.attendance.absent',
          ARRAY[v_emp.manager_profile],
          jsonb_build_object(
            'employee_name', v_emp.emp_name,
            'date', to_char(v_today, 'YYYY-MM-DD'),
            'employee_id', v_emp.employee_id::TEXT
          ),
          'hr_attendance_day',
          NULL
        );

        v_count := v_count + 1;
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING '[notify_absent_employees_scheduled] employee % error: %',
          v_emp.employee_id,
          SQLERRM;
    END;
  END LOOP;

  RAISE NOTICE '[notify_absent_employees_scheduled] % notifications dispatched for %',
    v_count,
    v_today;
END;
$function$;

REVOKE ALL ON FUNCTION public.notify_absent_employees_scheduled()
  FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Schedule-aware open-day review scan
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.scan_attendance_daily_review_alerts_scheduled()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_open_day_alerts INTEGER := 0;
  v_auto_resolved INTEGER := 0;
  v_delay_minutes INTEGER := 120;
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  r public.hr_attendance_days%ROWTYPE;
  v_eligible BOOLEAN;
BEGIN
  SELECT COALESCE(value::INTEGER, 120)
  INTO v_delay_minutes
  FROM public.company_settings
  WHERE key = 'hr.open_day_review_delay_minutes';

  v_delay_minutes := COALESCE(v_delay_minutes, 120);

  FOR r IN
    SELECT d.*
    FROM public.hr_attendance_days d
    WHERE d.punch_in_time IS NOT NULL
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
      AND NOT EXISTS (
        SELECT 1
        FROM public.hr_attendance_alerts a_prev
        WHERE a_prev.attendance_day_id = d.id
          AND a_prev.alert_type = 'open_day_unclosed'
          AND a_prev.status IN ('resolved', 'dismissed')
      )
    FOR UPDATE OF d SKIP LOCKED
  LOOP
    BEGIN
      IF r.schedule_snapshot_at IS NULL THEN
        PERFORM public.ensure_attendance_schedule_snapshot(r.id);

        SELECT * INTO r
        FROM public.hr_attendance_days
        WHERE id = r.id
        FOR UPDATE;
      END IF;

      IF r.shift_date < v_today THEN
        v_eligible := true;
      ELSIF r.shift_date > v_today THEN
        v_eligible := false;
      ELSIF r.schedule_day_kind = 'work_day' THEN
        v_eligible := now() > r.scheduled_end_at + make_interval(mins => v_delay_minutes);
      ELSE
        -- No expected end exists. Wait until the next calendar day and then
        -- request manual review rather than inventing an end time.
        v_eligible := false;
      END IF;

      IF NOT v_eligible THEN
        CONTINUE;
      END IF;

      v_open_day_alerts := v_open_day_alerts + 1;

      IF r.review_status <> 'reviewed' THEN
        UPDATE public.hr_attendance_days
        SET review_status = 'needs_review',
            updated_at = now()
        WHERE id = r.id
          AND review_status <> 'reviewed';
      END IF;

      PERFORM public.upsert_attendance_alert(
        r.employee_id,
        r.id,
        'open_day_unclosed',
        'high',
        'يوم حضور غير مغلق',
        format('الموظف سجل حضوره يوم %s ولم يسجل انصرافه حتى الآن', r.shift_date),
        jsonb_build_object(
          'shift_date', r.shift_date,
          'punch_in_time', r.punch_in_time,
          'schedule_day_kind', r.schedule_day_kind,
          'scheduled_end_at', r.scheduled_end_at
        )
      );
    EXCEPTION
      WHEN OTHERS THEN
        UPDATE public.hr_attendance_days
        SET review_status = CASE
              WHEN review_status = 'reviewed' THEN 'reviewed'::public.hr_review_status
              ELSE 'needs_review'::public.hr_review_status
            END,
            updated_at = now()
        WHERE id = r.id;

        RAISE WARNING '[scan_attendance_daily_review_alerts_scheduled] day % skipped: %',
          r.id,
          SQLERRM;
        CONTINUE;
    END;
  END LOOP;

  UPDATE public.hr_attendance_alerts a
  SET status = 'resolved',
      resolved_at = now(),
      resolution_note = 'تم إغلاق اليوم يدويًا — أُغلق التنبيه تلقائيًا',
      updated_at = now()
  FROM public.hr_attendance_days d
  WHERE a.alert_type = 'open_day_unclosed'
    AND a.status = 'open'
    AND a.attendance_day_id = d.id
    AND d.punch_out_time IS NOT NULL;

  GET DIAGNOSTICS v_auto_resolved = ROW_COUNT;

  RETURN jsonb_build_object(
    'success', true,
    'open_day_alerts_raised', v_open_day_alerts,
    'open_day_alerts_auto_resolved', v_auto_resolved
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.scan_attendance_daily_review_alerts_scheduled()
  FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Public wrappers
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_absent_employees()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF NOT public.hr_employee_work_schedules_enabled() THEN
    PERFORM public.notify_absent_employees_legacy_20260805();
    RETURN;
  END IF;

  PERFORM public.notify_absent_employees_scheduled();
END;
$function$;

CREATE OR REPLACE FUNCTION public.scan_attendance_daily_review_alerts()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF NOT public.hr_employee_work_schedules_enabled() THEN
    RETURN public.scan_attendance_daily_review_alerts_legacy_20260805();
  END IF;

  RETURN public.scan_attendance_daily_review_alerts_scheduled();
END;
$function$;

GRANT EXECUTE ON FUNCTION public.notify_absent_employees()
  TO anon, service_role;
GRANT EXECUTE ON FUNCTION public.scan_attendance_daily_review_alerts()
  TO anon, authenticated, service_role;

DO $assertions$
DECLARE
  v_definition TEXT;
  v_hash TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'M4C assertion failed: feature/readiness changed';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'M4C assertion failed: migration changed runtime data';
  END IF;

  SELECT pg_get_functiondef('public.notify_absent_employees_scheduled()'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%resolve_employee_work_schedule%'
     OR v_definition NOT ILIKE '%scheduled_start_at%'
     OR v_definition ILIKE '%is_employee_work_day%' THEN
    RAISE EXCEPTION 'M4C assertion failed: scheduled absence notification is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.scan_attendance_daily_review_alerts_scheduled()'::regprocedure)
  INTO v_definition;
  IF v_definition ILIKE '%hr.work_end_time%'
     OR v_definition NOT ILIKE '%scheduled_end_at%'
     OR v_definition NOT ILIKE '%ensure_attendance_schedule_snapshot%' THEN
    RAISE EXCEPTION 'M4C assertion failed: scheduled daily review bypasses snapshot';
  END IF;

  -- Tracking logic and the operational orchestrator are schedule-neutral and
  -- intentionally remain byte-identical.
  SELECT md5(pg_get_functiondef('public.scan_attendance_tracking_alerts()'::regprocedure))
  INTO v_hash;
  IF v_hash <> '139e2ad118b89ff33d5052e67041e4e6' THEN
    RAISE EXCEPTION 'M4C assertion failed: tracking scan changed (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.run_attendance_operational_scan()'::regprocedure))
  INTO v_hash;
  IF v_hash <> '40baaa14f7df81f78025d14ebb0fc288' THEN
    RAISE EXCEPTION 'M4C assertion failed: operational scan changed (%)', v_hash;
  END IF;
END;
$assertions$;

COMMIT;
