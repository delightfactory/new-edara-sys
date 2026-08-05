-- =============================================================================
-- EDARA — Employee Work Schedules daily-duration change boundary
--
-- Start/end times may change on any future date when the daily duration remains
-- unchanged. A change in daily scheduled minutes must start on day 1 of a new
-- month, preserving the existing salary-per-day payroll model.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  IF to_regprocedure('public.guard_employee_work_schedule_activation_duration()') IS NULL
     OR to_regprocedure('public.validate_employee_work_schedule_duration()') IS NULL THEN
    RAISE EXCEPTION 'Duration-boundary preflight failed: consistent-duration guards are missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Duration-boundary preflight failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'Duration-boundary preflight failed: no schedule data is expected before rehearsal';
  END IF;
END;
$preflight$;

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

    IF v_previous_minutes IS NOT NULL
       AND v_previous_minutes IS DISTINCT FROM v_min_minutes
       AND EXTRACT(DAY FROM NEW.effective_from)::INTEGER <> 1 THEN
      RAISE EXCEPTION
        'A daily-hours change from % to % minutes must start on the first day of a month',
        v_previous_minutes,
        v_min_minutes;
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

    IF v_previous_minutes IS NOT NULL
       AND v_previous_minutes IS DISTINCT FROM v_min_minutes
       AND EXTRACT(DAY FROM v_effective_from)::INTEGER <> 1 THEN
      RAISE EXCEPTION
        'Schedule % changes daily minutes from % to % outside a month boundary',
        v_schedule_id,
        v_previous_minutes,
        v_min_minutes;
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
  SELECT pg_get_functiondef('public.guard_employee_work_schedule_activation_duration()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%s.effective_to = NEW.effective_from - 1%'
     OR v_definition NOT ILIKE '%EXTRACT(DAY FROM NEW.effective_from)%'
     OR v_definition NOT ILIKE '%must start on the first day of a month%' THEN
    RAISE EXCEPTION 'Duration-boundary assertion failed: activation boundary guard is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.validate_employee_work_schedule_duration()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%s.effective_to = v_effective_from - 1%'
     OR v_definition NOT ILIKE '%EXTRACT(DAY FROM v_effective_from)%'
     OR v_definition NOT ILIKE '%outside a month boundary%' THEN
    RAISE EXCEPTION 'Duration-boundary assertion failed: deferred boundary guard is incomplete';
  END IF;
END;
$assertions$;

COMMIT;
