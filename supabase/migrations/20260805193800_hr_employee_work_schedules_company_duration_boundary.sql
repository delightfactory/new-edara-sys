-- =============================================================================
-- EDARA — Employee Work Schedules company-duration boundary
--
-- The first custom schedule also has a predecessor: the company fallback.
-- If its daily minutes differ from the validated company day, it must begin on
-- day 1 of a month. Same-duration time changes may begin on any future date.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  IF to_regprocedure('public.guard_employee_work_schedule_activation_duration()') IS NULL
     OR to_regprocedure('public.validate_employee_work_schedule_duration()') IS NULL THEN
    RAISE EXCEPTION 'Company-duration preflight failed: duration guards are missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Company-duration preflight failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'Company-duration preflight failed: no schedule data is expected before rehearsal';
  END IF;

  IF to_regprocedure('public.get_company_default_scheduled_minutes()') IS NOT NULL THEN
    RAISE EXCEPTION 'Company-duration preflight failed: company minute helper already exists';
  END IF;
END;
$preflight$;

CREATE FUNCTION public.get_company_default_scheduled_minutes()
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_start_text TEXT;
  v_end_text TEXT;
  v_hours_text TEXT;
  v_start TIME;
  v_end TIME;
  v_hours NUMERIC;
  v_window_minutes INTEGER;
BEGIN
  SELECT
    max(value) FILTER (WHERE key = 'hr.work_start_time'),
    max(value) FILTER (WHERE key = 'hr.work_end_time'),
    max(value) FILTER (WHERE key = 'hr.work_hours_per_day')
  INTO v_start_text, v_end_text, v_hours_text
  FROM public.company_settings
  WHERE key IN (
    'hr.work_start_time',
    'hr.work_end_time',
    'hr.work_hours_per_day'
  );

  IF v_start_text IS NULL OR v_end_text IS NULL OR v_hours_text IS NULL THEN
    RAISE EXCEPTION 'Company work schedule settings are incomplete';
  END IF;

  BEGIN
    v_start := btrim(v_start_text)::TIME;
    v_end := btrim(v_end_text)::TIME;
    v_hours := btrim(v_hours_text)::NUMERIC;
  EXCEPTION
    WHEN invalid_text_representation OR datetime_field_overflow THEN
      RAISE EXCEPTION 'Company work schedule settings are invalid';
  END;

  IF v_end <= v_start THEN
    RAISE EXCEPTION 'Company overnight/non-positive schedules are not supported in V1';
  END IF;

  v_window_minutes := (EXTRACT(EPOCH FROM (v_end - v_start)) / 60)::INTEGER;

  IF v_hours <= 0 OR v_hours * 60 <> v_window_minutes THEN
    RAISE EXCEPTION
      'Company work-hours setting (%) does not match the start/end window (%)',
      v_hours * 60,
      v_window_minutes;
  END IF;

  RETURN v_window_minutes;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_company_default_scheduled_minutes()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.guard_employee_work_schedule_activation_duration()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $function$
DECLARE
  v_min_minutes INTEGER;
  v_max_minutes INTEGER;
  v_working_days INTEGER;
  v_previous_minutes INTEGER;
  v_previous_source TEXT;
BEGIN
  IF OLD.status = 'draft' AND NEW.status = 'active' THEN
    SELECT
      count(*) FILTER (WHERE d.is_working_day)::INTEGER,
      min(d.scheduled_minutes) FILTER (WHERE d.is_working_day),
      max(d.scheduled_minutes) FILTER (WHERE d.is_working_day)
    INTO v_working_days, v_min_minutes, v_max_minutes
    FROM public.hr_employee_work_schedule_days d
    WHERE d.schedule_id = NEW.id;

    IF v_working_days <= 0 THEN
      RAISE EXCEPTION 'An active schedule requires at least one working day';
    END IF;

    IF v_min_minutes IS DISTINCT FROM v_max_minutes THEN
      RAISE EXCEPTION
        'All working days in one schedule version must have the same duration; min=% max=%',
        v_min_minutes,
        v_max_minutes;
    END IF;

    SELECT min(d.scheduled_minutes) FILTER (WHERE d.is_working_day)
    INTO v_previous_minutes
    FROM public.hr_employee_work_schedules s
    JOIN public.hr_employee_work_schedule_days d ON d.schedule_id = s.id
    WHERE s.employee_id = NEW.employee_id
      AND s.status = 'retired'
      AND s.effective_to = NEW.effective_from - 1;

    IF v_previous_minutes IS NULL THEN
      v_previous_minutes := public.get_company_default_scheduled_minutes();
      v_previous_source := 'company';
    ELSE
      v_previous_source := 'employee';
    END IF;

    IF v_previous_minutes IS DISTINCT FROM v_min_minutes
       AND EXTRACT(DAY FROM NEW.effective_from)::INTEGER <> 1 THEN
      RAISE EXCEPTION
        'A daily-hours change from % to % minutes (% baseline) must start on the first day of a month',
        v_previous_minutes,
        v_min_minutes,
        v_previous_source;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_employee_work_schedule_activation_duration()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.validate_employee_work_schedule_duration()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $function$
DECLARE
  v_schedule_id UUID;
  v_employee_id UUID;
  v_effective_from DATE;
  v_status TEXT;
  v_day_count INTEGER;
  v_working_days INTEGER;
  v_min_minutes INTEGER;
  v_max_minutes INTEGER;
  v_previous_minutes INTEGER;
  v_previous_source TEXT;
BEGIN
  v_schedule_id := CASE
    WHEN TG_OP = 'DELETE' THEN OLD.schedule_id
    ELSE NEW.schedule_id
  END;

  SELECT s.employee_id, s.effective_from, s.status
  INTO v_employee_id, v_effective_from, v_status
  FROM public.hr_employee_work_schedules s
  WHERE s.id = v_schedule_id;

  IF NOT FOUND OR v_status = 'draft' THEN
    RETURN NULL;
  END IF;

  SELECT
    count(*)::INTEGER,
    count(*) FILTER (WHERE d.is_working_day)::INTEGER,
    min(d.scheduled_minutes) FILTER (WHERE d.is_working_day),
    max(d.scheduled_minutes) FILTER (WHERE d.is_working_day)
  INTO v_day_count, v_working_days, v_min_minutes, v_max_minutes
  FROM public.hr_employee_work_schedule_days d
  WHERE d.schedule_id = v_schedule_id;

  IF v_day_count <> 7 THEN
    RAISE EXCEPTION
      'Schedule % must contain exactly seven weekday rows; found %',
      v_schedule_id,
      v_day_count;
  END IF;

  IF v_working_days <= 0 THEN
    RAISE EXCEPTION 'Schedule % requires at least one working day', v_schedule_id;
  END IF;

  IF v_min_minutes IS DISTINCT FROM v_max_minutes THEN
    RAISE EXCEPTION
      'Schedule % has mixed daily durations; min=% max=%',
      v_schedule_id,
      v_min_minutes,
      v_max_minutes;
  END IF;

  IF v_status = 'active' THEN
    SELECT min(d.scheduled_minutes) FILTER (WHERE d.is_working_day)
    INTO v_previous_minutes
    FROM public.hr_employee_work_schedules s
    JOIN public.hr_employee_work_schedule_days d ON d.schedule_id = s.id
    WHERE s.employee_id = v_employee_id
      AND s.status = 'retired'
      AND s.effective_to = v_effective_from - 1;

    IF v_previous_minutes IS NULL THEN
      v_previous_minutes := public.get_company_default_scheduled_minutes();
      v_previous_source := 'company';
    ELSE
      v_previous_source := 'employee';
    END IF;

    IF v_previous_minutes IS DISTINCT FROM v_min_minutes
       AND EXTRACT(DAY FROM v_effective_from)::INTEGER <> 1 THEN
      RAISE EXCEPTION
        'Schedule % changes daily minutes from % to % (% baseline) outside a month boundary',
        v_schedule_id,
        v_previous_minutes,
        v_min_minutes,
        v_previous_source;
    END IF;
  END IF;

  RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION public.validate_employee_work_schedule_duration()
  FROM PUBLIC, anon, authenticated, service_role;

DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.get_company_default_scheduled_minutes() <> 480 THEN
    RAISE EXCEPTION
      'Company-duration assertion failed: current validated company day is not 480 minutes';
  END IF;

  SELECT pg_get_functiondef('public.guard_employee_work_schedule_activation_duration()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%get_company_default_scheduled_minutes%'
     OR v_definition NOT ILIKE '%v_previous_source := ''company''%'
     OR v_definition NOT ILIKE '%first day of a month%' THEN
    RAISE EXCEPTION 'Company-duration assertion failed: activation fallback guard is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.validate_employee_work_schedule_duration()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%get_company_default_scheduled_minutes%'
     OR v_definition NOT ILIKE '%v_previous_source := ''company''%'
     OR v_definition NOT ILIKE '%outside a month boundary%' THEN
    RAISE EXCEPTION 'Company-duration assertion failed: deferred fallback guard is incomplete';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.get_company_default_scheduled_minutes()',
    'EXECUTE'
  ) OR has_function_privilege(
    'service_role',
    'public.get_company_default_scheduled_minutes()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Company-duration assertion failed: internal helper is exposed';
  END IF;
END;
$assertions$;

COMMIT;
