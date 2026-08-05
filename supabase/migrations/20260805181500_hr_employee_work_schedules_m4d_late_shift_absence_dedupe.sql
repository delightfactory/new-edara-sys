-- =============================================================================
-- EDARA — Employee Work Schedules M4D
-- Late-shift absence notifications with atomic per-employee/date deduplication.
--
-- No new cron is created. Enabled mode reuses the existing 15-minute attendance
-- operational scan. Disabled mode remains the exact production orchestrator.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '90s';

DO $preflight$
DECLARE
  v_hash TEXT;
BEGIN
  IF to_regprocedure('public.notify_absent_employees_scheduled()') IS NULL
     OR to_regprocedure('public.scan_attendance_daily_review_alerts()') IS NULL
     OR to_regprocedure('public.scan_attendance_tracking_alerts()') IS NULL
     OR to_regprocedure('public.hr_employee_work_schedules_activation_ready()') IS NULL THEN
    RAISE EXCEPTION 'M4D preflight failed: M4C/activation dependencies are missing';
  END IF;

  IF to_regclass('public.notification_alert_state') IS NULL THEN
    RAISE EXCEPTION 'M4D preflight failed: notification_alert_state is missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'M4D preflight failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'M4D preflight failed: no runtime schedule/snapshot data is expected';
  END IF;

  IF to_regprocedure('public.run_attendance_operational_scan_legacy_20260805()') IS NOT NULL
     OR to_regprocedure('public.run_attendance_operational_scan_scheduled()') IS NOT NULL THEN
    RAISE EXCEPTION 'M4D preflight failed: one or more M4D helpers already exist';
  END IF;

  SELECT md5(pg_get_functiondef('public.run_attendance_operational_scan()'::regprocedure))
  INTO v_hash;
  IF v_hash <> '40baaa14f7df81f78025d14ebb0fc288' THEN
    RAISE EXCEPTION 'M4D preflight failed: operational scan drifted (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.call_dispatch_notification(text,uuid[],jsonb,text,uuid)'::regprocedure))
  INTO v_hash;
  IF v_hash <> '557854bb217541d6de88652153f95f49' THEN
    RAISE EXCEPTION 'M4D preflight failed: notification dispatcher drifted (%)', v_hash;
  END IF;
END;
$preflight$;

DO $clone_legacy$
DECLARE
  v_definition TEXT;
BEGIN
  SELECT pg_get_functiondef('public.run_attendance_operational_scan()'::regprocedure)
  INTO v_definition;

  v_definition := replace(
    v_definition,
    'FUNCTION public.run_attendance_operational_scan(',
    'FUNCTION public.run_attendance_operational_scan_legacy_20260805('
  );

  EXECUTE v_definition;
END;
$clone_legacy$;

REVOKE ALL ON FUNCTION public.run_attendance_operational_scan_legacy_20260805()
  FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Replace the scheduled notifier with an atomic once-per-employee/date claim.
-- ----------------------------------------------------------------------------
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
  v_alert_key TEXT;
  v_state_id UUID;
BEGIN
  -- Resolve today's alert state once attendance appears after a prior alert.
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

      IF v_day_kind <> 'work_day' OR now() < v_scheduled_start THEN
        CONTINUE;
      END IF;

      v_alert_key := 'hr.attendance.absent::'
        || v_emp.employee_id::TEXT
        || '::'
        || v_today::TEXT;
      v_state_id := NULL;

      -- The unique alert_key is the concurrency guard. Only the transaction
      -- that inserts the row sends the notification; later 15-minute scans skip.
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
          'employee_id', v_emp.employee_id::TEXT
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

  RAISE NOTICE '[notify_absent_employees_scheduled] % first alerts claimed/dispatched for %',
    v_count,
    v_today;
END;
$function$;

REVOKE ALL ON FUNCTION public.notify_absent_employees_scheduled()
  FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Enabled-mode orchestrator: existing tracking + daily review + deduped absence.
-- Return shape remains exactly compatible with the current orchestrator.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.run_attendance_operational_scan_scheduled()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_tracking JSONB;
  v_daily JSONB;
BEGIN
  v_tracking := public.scan_attendance_tracking_alerts();
  v_daily := public.scan_attendance_daily_review_alerts();
  PERFORM public.notify_absent_employees_scheduled();

  RETURN jsonb_build_object(
    'success', true,
    'tracking', v_tracking,
    'daily_review', v_daily
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.run_attendance_operational_scan_scheduled()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.run_attendance_operational_scan()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF NOT public.hr_employee_work_schedules_enabled() THEN
    RETURN public.run_attendance_operational_scan_legacy_20260805();
  END IF;

  RETURN public.run_attendance_operational_scan_scheduled();
END;
$function$;

GRANT EXECUTE ON FUNCTION public.run_attendance_operational_scan()
  TO anon, authenticated, service_role;

DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'M4D assertion failed: feature/readiness changed';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'M4D assertion failed: migration changed runtime data';
  END IF;

  SELECT pg_get_functiondef('public.notify_absent_employees_scheduled()'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%notification_alert_state%'
     OR v_definition NOT ILIKE '%ON CONFLICT (alert_key) DO NOTHING%'
     OR v_definition NOT ILIKE '%scheduled_start_at%'
     OR v_definition NOT ILIKE '%resolve_employee_work_schedule%' THEN
    RAISE EXCEPTION 'M4D assertion failed: deduped scheduled notifier is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.run_attendance_operational_scan_scheduled()'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%scan_attendance_tracking_alerts%'
     OR v_definition NOT ILIKE '%scan_attendance_daily_review_alerts%'
     OR v_definition NOT ILIKE '%notify_absent_employees_scheduled%'
     OR v_definition NOT ILIKE '%''tracking'', v_tracking%'
     OR v_definition NOT ILIKE '%''daily_review'', v_daily%' THEN
    RAISE EXCEPTION 'M4D assertion failed: scheduled orchestrator is incomplete/incompatible';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.notify_absent_employees_scheduled()',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.run_attendance_operational_scan_scheduled()',
    'EXECUTE'
  ) OR has_function_privilege(
    'service_role',
    'public.run_attendance_operational_scan_scheduled()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'M4D assertion failed: an internal helper is exposed';
  END IF;
END;
$assertions$;

COMMIT;
