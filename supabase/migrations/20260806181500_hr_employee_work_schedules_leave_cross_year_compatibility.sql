-- =============================================================================
-- EDARA — Employee Work Schedules: cross-year leave compatibility
--
-- The legacy leave module allows a request to cross 31 December and charges its
-- balance against the year in which the request starts. Preserve that existing
-- contract while still counting only resolved employee work days.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
DECLARE
  v_definition TEXT;
BEGIN
  IF to_regprocedure('public.calculate_employee_leave_workdays(uuid,date,date,boolean)') IS NULL
     OR to_regprocedure('public.preview_employee_leave_workday_count(uuid,date,date)') IS NULL THEN
    RAISE EXCEPTION 'Cross-year leave preflight failed: leave integration is missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Cross-year leave preflight failed: feature/readiness must remain false';
  END IF;

  SELECT pg_get_functiondef(
    'public.calculate_employee_leave_workdays(uuid,date,date,boolean)'::regprocedure
  ) INTO v_definition;

  IF v_definition NOT ILIKE '%A leave request cannot cross calendar years%' THEN
    RAISE EXCEPTION 'Cross-year leave preflight failed: expected temporary restriction is absent';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.calculate_employee_leave_workdays(
  p_employee_id UUID,
  p_start_date DATE,
  p_end_date DATE,
  p_use_custom BOOLEAN DEFAULT true
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_hire_date DATE;
  v_termination_date DATE;
  v_count INTEGER;
BEGIN
  IF p_employee_id IS NULL OR p_start_date IS NULL OR p_end_date IS NULL THEN
    RAISE EXCEPTION 'employee_id, start_date, and end_date are required';
  END IF;

  IF p_end_date < p_start_date THEN
    RAISE EXCEPTION 'Leave end date cannot be before start date';
  END IF;

  SELECT e.hire_date, e.termination_date
  INTO v_hire_date, v_termination_date
  FROM public.hr_employees e
  WHERE e.id = p_employee_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Employee % does not exist', p_employee_id;
  END IF;

  IF v_hire_date IS NOT NULL AND p_start_date < v_hire_date THEN
    RAISE EXCEPTION 'Leave cannot start before the employee hire date';
  END IF;

  IF v_termination_date IS NOT NULL AND p_end_date > v_termination_date THEN
    RAISE EXCEPTION 'Leave cannot extend beyond the employee termination date';
  END IF;

  SELECT count(*)::INTEGER
  INTO v_count
  FROM generate_series(p_start_date, p_end_date, INTERVAL '1 day') g(target_date)
  CROSS JOIN LATERAL public.resolve_employee_work_schedule_core(
    p_employee_id,
    g.target_date::DATE,
    COALESCE(p_use_custom, false)
  ) r
  WHERE r.day_kind = 'work_day';

  RETURN COALESCE(v_count, 0);
END;
$function$;

REVOKE ALL ON FUNCTION public.calculate_employee_leave_workdays(UUID, DATE, DATE, BOOLEAN)
  FROM PUBLIC, anon, authenticated, service_role;

DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Cross-year leave assertion failed: feature/readiness changed';
  END IF;

  SELECT pg_get_functiondef(
    'public.calculate_employee_leave_workdays(uuid,date,date,boolean)'::regprocedure
  ) INTO v_definition;

  IF v_definition ILIKE '%cannot cross calendar years%'
     OR v_definition NOT ILIKE '%resolve_employee_work_schedule_core%'
     OR v_definition NOT ILIKE '%WHERE r.day_kind = ''work_day''%'
     OR v_definition NOT ILIKE '%termination date%' THEN
    RAISE EXCEPTION 'Cross-year leave assertion failed: compatibility calculator is incomplete';
  END IF;
END;
$assertions$;

COMMIT;
