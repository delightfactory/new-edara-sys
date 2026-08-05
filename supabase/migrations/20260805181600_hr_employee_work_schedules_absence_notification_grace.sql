-- =============================================================================
-- EDARA — Employee Work Schedules absence notification grace
--
-- A scheduled absence notification must not be claimed before the employee's
-- own start time plus the existing late-grace setting. Atomic deduplication and
-- existing cron schedules remain unchanged.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '90s';

DO $preflight$
DECLARE
  v_definition TEXT;
BEGIN
  IF to_regprocedure('public.notify_absent_employees_scheduled()') IS NULL
     OR to_regprocedure('public.run_attendance_operational_scan_scheduled()') IS NULL THEN
    RAISE EXCEPTION 'Absence-grace preflight failed: M4D scheduled notification paths are missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Absence-grace preflight failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Absence-grace preflight failed: no runtime schedule/snapshot data is expected';
  END IF;

  SELECT pg_get_functiondef('public.notify_absent_employees_scheduled()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%notification_alert_state%'
     OR v_definition NOT ILIKE '%ON CONFLICT (alert_key) DO NOTHING%'
     OR v_definition NOT ILIKE '%scheduled_start_at%' THEN
    RAISE EXCEPTION 'Absence-grace preflight failed: unexpected scheduled notifier definition';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.notify_absent_employees_scheduled()
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
  v_late_grace_minutes INTEGER := 15;
  v_alert_key TEXT;
  v_state_id UUID;
BEGIN
  SELECT COALESCE(value::INTEGER, 15)
  INTO v_late_grace_minutes
  FROM public.company_settings
  WHERE key = 'hr.late_grace_minutes';

  v_late_grace_minutes := GREATEST(0, COALESCE(v_late_grace_minutes, 15));

  UPDATE public.notification_alert_state nas
  SET resolved_at = COALESCE(nas.resolved_at, now())
  FROM public.hr_employees he
  WHERE nas.event_key = 'hr.attendance.absent'
    AND nas.alert_key = (
      'hr.attendance.absent::' || he.id::TEXT || '::' || v_today::TEXT
    )
    AND nas.resolved_at IS NULL
    AND EXISTS (
      SELECT 1
      FROM public.hr_attendance_days ad
      WHERE ad.employee_id = he.id
        AND ad.shift_date = v_today
    );

  FOR v_emp IN
    SELECT
      he.id AS employee_id,
      he.full_name AS emp_name,
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
      IF v_emp.manager_profile IS NULL THEN
        CONTINUE;
      END IF;

      SELECT r.day_kind, r.scheduled_start_at
      INTO v_day_kind, v_scheduled_start
      FROM public.resolve_employee_work_schedule(v_emp.employee_id, v_today) r;

      IF v_day_kind <> 'work_day'
         OR now() < v_scheduled_start + make_interval(mins => v_late_grace_minutes) THEN
        CONTINUE;
      END IF;

      v_alert_key := 'hr.attendance.absent::'
        || v_emp.employee_id::TEXT
        || '::'
        || v_today::TEXT;
      v_state_id := NULL;

      INSERT INTO public.notification_alert_state (
        alert_key,
        event_key,
        entity_type,
        entity_id,
        last_sent_at,
        resolved_at,
        send_count,
        cooldown_hours
      ) VALUES (
        v_alert_key,
        'hr.attendance.absent',
        'hr_employee',
        v_emp.employee_id,
        now(),
        NULL,
        1,
        24
      )
      ON CONFLICT (alert_key) DO NOTHING
      RETURNING id INTO v_state_id;

      IF v_state_id IS NULL THEN
        CONTINUE;
      END IF;

      PERFORM public.call_dispatch_notification(
        'hr.attendance.absent',
        ARRAY[v_emp.manager_profile],
        jsonb_build_object(
          'employee_name', v_emp.emp_name,
          'date', to_char(v_today, 'YYYY-MM-DD'),
          'employee_id', v_emp.employee_id::TEXT,
          'scheduled_start_at', v_scheduled_start,
          'late_grace_minutes', v_late_grace_minutes
        ),
        'hr_attendance_day',
        NULL
      );

      v_count := v_count + 1;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING '[notify_absent_employees_scheduled] employee % error: %',
          v_emp.employee_id,
          SQLERRM;
    END;
  END LOOP;

  RAISE NOTICE '[notify_absent_employees_scheduled] % first alerts claimed/dispatched for % after % grace minutes',
    v_count,
    v_today,
    v_late_grace_minutes;
END;
$function$;

REVOKE ALL ON FUNCTION public.notify_absent_employees_scheduled()
  FROM PUBLIC, anon, authenticated, service_role;

DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  SELECT pg_get_functiondef('public.notify_absent_employees_scheduled()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%hr.late_grace_minutes%'
     OR v_definition NOT ILIKE '%scheduled_start_at + make_interval%'
     OR v_definition NOT ILIKE '%ON CONFLICT (alert_key) DO NOTHING%'
     OR v_definition NOT ILIKE '%notification_alert_state%' THEN
    RAISE EXCEPTION 'Absence-grace assertion failed: notifier grace/dedupe contract is incomplete';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.notify_absent_employees_scheduled()',
    'EXECUTE'
  ) OR has_function_privilege(
    'service_role',
    'public.notify_absent_employees_scheduled()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Absence-grace assertion failed: internal notifier is exposed';
  END IF;
END;
$assertions$;

COMMIT;
