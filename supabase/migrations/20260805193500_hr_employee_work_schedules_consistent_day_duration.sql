-- =============================================================================
-- EDARA — Employee Work Schedules consistent day duration
--
-- V1 safety rule: start/end times may differ by weekday, but every working day
-- in one schedule version must have the same duration. This preserves the
-- existing salary-per-day model while allowing six-hour, eight-hour, or
-- nine-hour employees and minute-proportional within-day penalties.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  IF to_regclass('public.hr_employee_work_schedules') IS NULL
     OR to_regclass('public.hr_employee_work_schedule_days') IS NULL
     OR to_regprocedure('public.hr_employee_work_schedules_activation_ready()') IS NULL THEN
    RAISE EXCEPTION 'Duration guard preflight failed: schedule schema/activation guard is missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Duration guard preflight failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'Duration guard preflight failed: no schedule data is expected before rehearsal';
  END IF;

  IF to_regprocedure('public.guard_employee_work_schedule_activation_duration()') IS NOT NULL
     OR to_regprocedure('public.validate_employee_work_schedule_duration()') IS NOT NULL THEN
    RAISE EXCEPTION 'Duration guard preflight failed: duration guard functions already exist';
  END IF;
END;
$preflight$;

-- Immediate, clear error when a draft schedule is activated.
CREATE FUNCTION public.guard_employee_work_schedule_activation_duration()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $function$
DECLARE
  v_min_minutes INTEGER;
  v_max_minutes INTEGER;
  v_working_days INTEGER;
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
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_employee_work_schedule_activation_duration()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_hr_employee_work_schedule_activation_duration
  ON public.hr_employee_work_schedules;
CREATE TRIGGER trg_hr_employee_work_schedule_activation_duration
  BEFORE UPDATE OF status ON public.hr_employee_work_schedules
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_employee_work_schedule_activation_duration();

-- Deferred final-state check protects controlled future edits, where weekday
-- rows are replaced inside one transaction while the header remains active.
CREATE FUNCTION public.validate_employee_work_schedule_duration()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $function$
DECLARE
  v_schedule_id UUID;
  v_status TEXT;
  v_day_count INTEGER;
  v_working_days INTEGER;
  v_min_minutes INTEGER;
  v_max_minutes INTEGER;
BEGIN
  v_schedule_id := CASE
    WHEN TG_OP = 'DELETE' THEN OLD.schedule_id
    ELSE NEW.schedule_id
  END;

  SELECT s.status
  INTO v_status
  FROM public.hr_employee_work_schedules s
  WHERE s.id = v_schedule_id;

  -- Cascading deletion of a draft header leaves no schedule to validate.
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

  RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION public.validate_employee_work_schedule_duration()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_hr_employee_work_schedule_duration_consistency
  ON public.hr_employee_work_schedule_days;
CREATE CONSTRAINT TRIGGER trg_hr_employee_work_schedule_duration_consistency
  AFTER INSERT OR UPDATE OR DELETE ON public.hr_employee_work_schedule_days
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_employee_work_schedule_duration();

DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Duration guard assertion failed: feature/readiness changed';
  END IF;

  SELECT pg_get_functiondef('public.guard_employee_work_schedule_activation_duration()'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%min(d.scheduled_minutes)%'
     OR v_definition NOT ILIKE '%max(d.scheduled_minutes)%'
     OR v_definition NOT ILIKE '%same duration%' THEN
    RAISE EXCEPTION 'Duration guard assertion failed: activation guard is incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'hr_employee_work_schedule_days'
      AND t.tgname = 'trg_hr_employee_work_schedule_duration_consistency'
      AND t.tgdeferrable
      AND t.tginitdeferred
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'Duration guard assertion failed: deferred constraint trigger is missing';
  END IF;
END;
$assertions$;

COMMIT;
