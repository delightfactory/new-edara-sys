-- =============================================================================
-- EDARA — Company history resolution correction
--
-- Corrects two review findings from the company-history foundation:
--   1. daily company minutes are properties of the effective version and must
--      not become zero merely because the queried date is the weekly off day;
--   2. an employee-level weekly_off_day override remains authoritative when the
--      employee has no custom seven-day schedule.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  IF to_regclass('public.hr_company_work_schedules') IS NULL
     OR to_regprocedure('public.resolve_company_work_schedule_version(date)') IS NULL
     OR to_regprocedure('public.get_company_scheduled_minutes_for_date(date)') IS NULL
     OR to_regprocedure('public.resolve_employee_work_schedule_core(uuid,date,boolean)') IS NULL THEN
    RAISE EXCEPTION 'Company-history resolution-fix preflight failed: foundation is incomplete';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Company-history resolution-fix preflight failed: feature/readiness must remain false';
  END IF;

  IF to_regprocedure('public.resolve_company_work_schedule_for_employee(uuid,date)') IS NOT NULL THEN
    RAISE EXCEPTION 'Company-history resolution-fix preflight failed: employee fallback helper already exists';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.get_company_scheduled_minutes_for_date(
  p_target_date DATE
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_count INTEGER;
  v_minutes INTEGER;
BEGIN
  IF p_target_date IS NULL THEN
    RAISE EXCEPTION 'target_date is required';
  END IF;

  SELECT count(*)::INTEGER, min(s.scheduled_minutes)
  INTO v_count, v_minutes
  FROM public.hr_company_work_schedules s
  WHERE s.status IN ('active', 'retired')
    AND s.effective_range @> p_target_date;

  IF v_count <> 1 OR v_minutes IS NULL OR v_minutes <= 0 THEN
    RAISE EXCEPTION
      'Company schedule duration integrity error: % versions cover %',
      v_count,
      p_target_date;
  END IF;

  RETURN v_minutes;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_company_scheduled_minutes_for_date(DATE)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.resolve_company_work_schedule_for_employee(
  p_employee_id UUID,
  p_target_date DATE
)
RETURNS TABLE (
  day_kind TEXT,
  is_working_day BOOLEAN,
  scheduled_start_at TIMESTAMPTZ,
  scheduled_end_at TIMESTAMPTZ,
  scheduled_minutes INTEGER,
  schedule_source TEXT,
  work_schedule_id UUID
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_employee_off public.hr_day_of_week;
  v_target_day public.hr_day_of_week;
  v_count INTEGER;
  v_schedule public.hr_company_work_schedules%ROWTYPE;
  v_effective_off public.hr_day_of_week;
BEGIN
  IF p_employee_id IS NULL OR p_target_date IS NULL THEN
    RAISE EXCEPTION 'employee_id and target_date are required';
  END IF;

  SELECT e.weekly_off_day
  INTO v_employee_off
  FROM public.hr_employees e
  WHERE e.id = p_employee_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Employee % does not exist', p_employee_id;
  END IF;

  SELECT count(*)::INTEGER
  INTO v_count
  FROM public.hr_company_work_schedules s
  WHERE s.status IN ('active', 'retired')
    AND s.effective_range @> p_target_date;

  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'Company schedule integrity error: % versions cover %',
      v_count,
      p_target_date;
  END IF;

  SELECT * INTO v_schedule
  FROM public.hr_company_work_schedules s
  WHERE s.status IN ('active', 'retired')
    AND s.effective_range @> p_target_date;

  v_target_day := public.hr_day_of_week_for_date(p_target_date);
  v_effective_off := COALESCE(v_employee_off, v_schedule.weekly_off_day);

  IF v_target_day = v_effective_off THEN
    RETURN QUERY SELECT
      'weekly_off'::TEXT,
      false,
      NULL::TIMESTAMPTZ,
      NULL::TIMESTAMPTZ,
      0,
      'company'::TEXT,
      NULL::UUID;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    'work_day'::TEXT,
    true,
    (p_target_date + v_schedule.start_time) AT TIME ZONE 'Africa/Cairo',
    (p_target_date + v_schedule.end_time) AT TIME ZONE 'Africa/Cairo',
    v_schedule.scheduled_minutes,
    'company'::TEXT,
    NULL::UUID;
END;
$function$;

REVOKE ALL ON FUNCTION public.resolve_company_work_schedule_for_employee(UUID, DATE)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.resolve_employee_work_schedule_core(
  p_employee_id UUID,
  p_target_date DATE,
  p_use_custom BOOLEAN
)
RETURNS TABLE (
  day_kind TEXT,
  is_working_day BOOLEAN,
  scheduled_start_at TIMESTAMPTZ,
  scheduled_end_at TIMESTAMPTZ,
  scheduled_minutes INTEGER,
  schedule_source TEXT,
  work_schedule_id UUID
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_custom_count INTEGER;
BEGIN
  IF p_employee_id IS NULL OR p_target_date IS NULL THEN
    RAISE EXCEPTION 'employee_id and target_date are required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.hr_employees e WHERE e.id = p_employee_id
  ) THEN
    RAISE EXCEPTION 'Employee % does not exist', p_employee_id;
  END IF;

  IF NOT COALESCE(p_use_custom, false) THEN
    RETURN QUERY
    SELECT *
    FROM public.resolve_employee_work_schedule_core_pre_company_history_20260806(
      p_employee_id,
      p_target_date,
      false
    );
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_public_holidays h
    WHERE h.holiday_date = p_target_date
  ) THEN
    RETURN QUERY
    SELECT *
    FROM public.resolve_employee_work_schedule_core_pre_company_history_20260806(
      p_employee_id,
      p_target_date,
      true
    );
    RETURN;
  END IF;

  SELECT count(*)::INTEGER
  INTO v_custom_count
  FROM public.hr_employee_work_schedules s
  WHERE s.employee_id = p_employee_id
    AND s.status IN ('active', 'retired')
    AND s.effective_range @> p_target_date;

  IF v_custom_count > 0 THEN
    RETURN QUERY
    SELECT *
    FROM public.resolve_employee_work_schedule_core_pre_company_history_20260806(
      p_employee_id,
      p_target_date,
      true
    );
    RETURN;
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.resolve_company_work_schedule_for_employee(
    p_employee_id,
    p_target_date
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.resolve_employee_work_schedule_core(UUID, DATE, BOOLEAN)
  FROM PUBLIC, anon, authenticated, service_role;

DO $assertions$
DECLARE
  v_definition TEXT;
  v_baseline public.hr_company_work_schedules%ROWTYPE;
BEGIN
  SELECT * INTO v_baseline
  FROM public.hr_company_work_schedules
  WHERE is_system_baseline = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Company-history resolution-fix assertion failed: baseline is missing';
  END IF;

  IF public.get_company_scheduled_minutes_for_date(v_baseline.effective_from)
     IS DISTINCT FROM v_baseline.scheduled_minutes THEN
    RAISE EXCEPTION 'Company-history resolution-fix assertion failed: date duration is not version duration';
  END IF;

  SELECT pg_get_functiondef(
    'public.resolve_company_work_schedule_for_employee(uuid,date)'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%COALESCE(v_employee_off, v_schedule.weekly_off_day)%'
     OR v_definition NOT ILIKE '%v_schedule.scheduled_minutes%' THEN
    RAISE EXCEPTION 'Company-history resolution-fix assertion failed: employee fallback is incomplete';
  END IF;

  SELECT pg_get_functiondef(
    'public.resolve_employee_work_schedule_core(uuid,date,boolean)'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%resolve_company_work_schedule_for_employee%'
     OR v_definition NOT ILIKE '%resolve_employee_work_schedule_core_pre_company_history_20260806%' THEN
    RAISE EXCEPTION 'Company-history resolution-fix assertion failed: central resolver dispatch is incomplete';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.resolve_company_work_schedule_for_employee(uuid,date)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Company-history resolution-fix assertion failed: internal resolver is exposed';
  END IF;
END;
$assertions$;

COMMIT;
