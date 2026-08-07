-- HR Variable Schedules V2 — Batch 3A1
-- Work-day classification seam only.
-- No absence timing, auto-checkout, penalty, leave, payroll, UI, or settings change.

BEGIN;

DO $guard$
DECLARE
  v_hash text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid))
  INTO v_hash
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'is_employee_work_day'
    AND pg_get_function_identity_arguments(p.oid) = 'p_employee_id uuid, p_date date';

  IF v_hash IS DISTINCT FROM '3e047334df57ad284bea8e9504724dd0' THEN
    RAISE EXCEPTION 'Batch 3A1 baseline mismatch for is_employee_work_day; review production drift before applying';
  END IF;

  IF to_regprocedure('public.is_employee_work_day_legacy(uuid,date)') IS NOT NULL THEN
    RAISE EXCEPTION 'Batch 3A1 helper function name collision';
  END IF;

  IF to_regprocedure('public.hr_variable_schedules_v2_runtime_enabled()') IS NULL
     OR to_regprocedure('public.resolve_employee_custom_schedule(uuid,date)') IS NULL THEN
    RAISE EXCEPTION 'Batch 3A1 requires Batch 1 resolver and Batch 2A fail-closed runtime gate';
  END IF;
END;
$guard$;

ALTER FUNCTION public.is_employee_work_day(uuid, date)
  RENAME TO is_employee_work_day_legacy;

REVOKE ALL ON FUNCTION public.is_employee_work_day_legacy(uuid, date)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.is_employee_work_day(
  p_employee_id uuid,
  p_date date
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_schedule record;
BEGIN
  -- Exact current path while V2 is disabled.
  IF NOT public.hr_variable_schedules_v2_runtime_enabled() THEN
    RETURN public.is_employee_work_day_legacy(p_employee_id, p_date);
  END IF;

  SELECT * INTO v_schedule
  FROM public.resolve_employee_custom_schedule(p_employee_id, p_date);

  -- No effective complete custom schedule means exact Legacy behavior, including
  -- employee weekly_off_day and company weekly-off fallback.
  IF NOT FOUND THEN
    RETURN public.is_employee_work_day_legacy(p_employee_id, p_date);
  END IF;

  -- Public holiday remains authoritative even when a custom weekday is configured
  -- as working. This preserves the current holiday precedence.
  IF EXISTS (
    SELECT 1
    FROM public.hr_public_holidays
    WHERE holiday_date = p_date
  ) THEN
    RETURN 'public_holiday';
  END IF;

  IF v_schedule.is_working_day THEN
    RETURN 'work_day';
  END IF;

  -- Reuse the existing public classification vocabulary; downstream callers already
  -- understand weekly_off as a non-working day and do not need a new enum/value.
  RETURN 'weekly_off';
END;
$function$;

COMMENT ON FUNCTION public.is_employee_work_day(uuid, date) IS
  'V2 compatibility classifier: exact Legacy path unless runtime is enabled and an effective complete custom employee schedule exists.';

REVOKE ALL ON FUNCTION public.is_employee_work_day(uuid, date)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_employee_work_day(uuid, date)
  TO PUBLIC, anon, authenticated, service_role;

COMMIT;
