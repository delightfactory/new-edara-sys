-- =============================================================================
-- EDARA — Employee Work Schedules: absence notification delivery guard
--
-- Narrow fixes:
--   * a permission suppresses the absence alert only when it covers the
--     employee's scheduled start;
--   * the once-per-day alert state is written only after an HTTP dispatch is
--     successfully queued;
--   * an advisory lock prevents concurrent duplicate dispatches.
--
-- The shared notification dispatcher is not changed.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '90s';

DO $preflight$
BEGIN
  IF to_regprocedure('public.notify_absent_employees_scheduled()') IS NULL
     OR to_regprocedure(
       'public.get_uncovered_attendance_permission_minutes(uuid,date,timestamp with time zone,timestamp with time zone)'
     ) IS NULL
     OR to_regclass('public.notification_alert_state') IS NULL THEN
    RAISE EXCEPTION 'Absence delivery guard preflight failed: required functions/tables are missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Absence delivery guard preflight failed: feature/readiness must remain false';
  END IF;

  IF to_regprocedure('public.dispatch_absence_notification_strict(uuid,text,date,timestamp with time zone,integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'Absence delivery guard preflight failed: strict dispatcher already exists';
  END IF;
END;
$preflight$;

-- Queue the request or raise. Unlike the shared non-critical dispatcher, this
-- helper lets the caller preserve retry eligibility when configuration or the
-- HTTP queue operation fails.
CREATE FUNCTION public.dispatch_absence_notification_strict(
  p_manager_user_id UUID,
  p_employee_name TEXT,
  p_absence_date DATE,
  p_scheduled_start TIMESTAMPTZ,
  p_late_grace_minutes INTEGER
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_url TEXT;
  v_service_key TEXT;
  v_internal_secret TEXT;
  v_headers JSONB;
  v_body JSONB;
  v_request_id BIGINT;
BEGIN
  IF p_manager_user_id IS NULL THEN
    RAISE EXCEPTION 'Absence notification manager is required';
  END IF;

  SELECT value INTO v_url
  FROM public.internal_config
  WHERE key = 'supabase_url';

  SELECT value INTO v_service_key
  FROM public.internal_config
  WHERE key = 'service_role_key';

  SELECT value INTO v_internal_secret
  FROM public.internal_config
  WHERE key = 'internal_dispatch_secret';

  v_url := COALESCE(NULLIF(v_url, ''), NULLIF(current_setting('app.settings.supabase_url', true), ''));
  v_service_key := COALESCE(
    NULLIF(v_service_key, ''),
    NULLIF(current_setting('app.settings.service_role_key', true), '')
  );
  v_internal_secret := COALESCE(
    NULLIF(v_internal_secret, ''),
    NULLIF(current_setting('app.settings.internal_dispatch_secret', true), '')
  );

  IF v_url IS NULL THEN
    RAISE EXCEPTION 'Absence notification dispatch URL is not configured';
  END IF;

  IF v_internal_secret IS NULL AND v_service_key IS NULL THEN
    RAISE EXCEPTION 'Absence notification internal authentication is not configured';
  END IF;

  v_headers := jsonb_build_object('Content-Type', 'application/json');
  IF v_internal_secret IS NOT NULL THEN
    v_headers := v_headers || jsonb_build_object('x-internal-secret', v_internal_secret);
  ELSE
    v_headers := v_headers || jsonb_build_object('Authorization', 'Bearer ' || v_service_key);
  END IF;

  v_body := jsonb_build_object(
    'event_key', 'hr.attendance.absent',
    'user_ids', jsonb_build_array(p_manager_user_id),
    'variables', jsonb_build_object(
      'employee_name', p_employee_name,
      'date', to_char(p_absence_date, 'YYYY-MM-DD'),
      'scheduled_start_at', p_scheduled_start,
      'late_grace_minutes', p_late_grace_minutes
    ),
    'entity_type', 'hr_employee',
    'entity_id', NULL
  );

  SELECT net.http_post(
    url => v_url || '/functions/v1/dispatch-notification',
    headers => v_headers,
    body => v_body,
    timeout_milliseconds => 30000
  ) INTO v_request_id;

  IF v_request_id IS NULL THEN
    RAISE EXCEPTION 'Absence notification HTTP request was not queued';
  END IF;

  RETURN v_request_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.dispatch_absence_notification_strict(
  UUID, TEXT, DATE, TIMESTAMPTZ, INTEGER
) FROM PUBLIC, anon, authenticated, service_role;

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
  v_request_id BIGINT;
BEGIN
  SELECT GREATEST(0, COALESCE(value::INTEGER, 15))
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

      -- A partial permission elsewhere in the day must not hide a missed start.
      IF public.get_uncovered_attendance_permission_minutes(
           v_emp.employee_id,
           v_today,
           v_scheduled_start,
           v_scheduled_start + INTERVAL '1 minute'
         ) = 0 THEN
        CONTINUE;
      END IF;

      v_alert_key := 'hr.attendance.absent::'
        || v_emp.employee_id::TEXT
        || '::'
        || v_today::TEXT;

      -- Serialize one employee/date dispatch. Re-check the state only after the
      -- lock is held, then queue before persisting the dedupe record.
      PERFORM pg_advisory_xact_lock(hashtextextended(v_alert_key, 0));

      IF EXISTS (
        SELECT 1
        FROM public.notification_alert_state nas
        WHERE nas.alert_key = v_alert_key
      ) THEN
        CONTINUE;
      END IF;

      v_request_id := public.dispatch_absence_notification_strict(
        v_emp.manager_profile,
        v_emp.emp_name,
        v_today,
        v_scheduled_start,
        v_late_grace_minutes
      );

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
      RETURNING id INTO v_state_id;

      IF v_state_id IS NULL OR v_request_id IS NULL THEN
        RAISE EXCEPTION 'Absence notification state was not persisted after queueing';
      END IF;

      v_count := v_count + 1;
    EXCEPTION
      WHEN OTHERS THEN
        -- No state row is created when dispatch fails, so the next scan retries.
        RAISE WARNING '[notify_absent_employees_scheduled] employee % retryable error: %',
          v_emp.employee_id,
          SQLERRM;
        CONTINUE;
    END;
  END LOOP;

  RAISE NOTICE '[notify_absent_employees_scheduled] % notifications queued for %',
    v_count,
    v_today;
END;
$function$;

REVOKE ALL ON FUNCTION public.notify_absent_employees_scheduled()
  FROM PUBLIC, anon, authenticated, service_role;

-- Public wrapper remains internal/service-only as hardened earlier.
REVOKE ALL ON FUNCTION public.notify_absent_employees()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notify_absent_employees()
  TO service_role;

DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Absence delivery guard assertion failed: feature/readiness changed';
  END IF;

  SELECT pg_get_functiondef('public.notify_absent_employees_scheduled()'::regprocedure)
  INTO v_definition;

  IF v_definition ILIKE '%NOT EXISTS (%hr_permission_requests%'
     OR v_definition NOT ILIKE '%get_uncovered_attendance_permission_minutes%'
     OR v_definition NOT ILIKE '%pg_advisory_xact_lock%'
     OR strpos(v_definition, 'dispatch_absence_notification_strict') > strpos(v_definition, 'INSERT INTO public.notification_alert_state') THEN
    RAISE EXCEPTION 'Absence delivery guard assertion failed: permission/delivery ordering is incomplete';
  END IF;

  IF has_function_privilege(
       'authenticated',
       'public.dispatch_absence_notification_strict(uuid,text,date,timestamp with time zone,integer)',
       'EXECUTE'
     )
     OR has_function_privilege('anon', 'public.notify_absent_employees()', 'EXECUTE') THEN
    RAISE EXCEPTION 'Absence delivery guard assertion failed: internal notification path is exposed';
  END IF;
END;
$assertions$;

COMMIT;
