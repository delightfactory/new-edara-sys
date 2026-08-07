-- HR Variable Schedules V2 — Batch 3C
-- Public-holiday precedence in the central custom-schedule resolver only.
--
-- Safety boundary:
--   * preserve the resolver signature, zero-row fallback contract, RLS and grants;
--   * preserve the stored weekly schedule exactly;
--   * when p_date is an official public holiday, expose that effective date to
--     runtime consumers as a non-working official day (minutes=0, times=NULL);
--   * do not modify attendance rows, payroll, leave policy, settings or runtime gate.

BEGIN;

DO $guard$
DECLARE
  v_body text;
BEGIN
  SELECT p.prosrc
  INTO v_body
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'resolve_employee_custom_schedule'
    AND pg_get_function_identity_arguments(p.oid) = 'p_employee_id uuid, p_date date';

  IF v_body IS NULL
     OR position('hr_employee_work_schedules' in v_body) = 0
     OR position('hr_employee_work_schedule_days' in v_body) = 0
     OR position('COUNT(*)' in v_body) = 0
     OR position('work_days.is_working_day = true' in v_body) = 0 THEN
    RAISE EXCEPTION 'Batch 3C resolver baseline is missing or structurally drifted';
  END IF;

  IF position('hr_public_holidays' in v_body) > 0 THEN
    RAISE EXCEPTION 'Batch 3C expected pre-holiday resolver but holiday precedence is already present';
  END IF;
END;
$guard$;

CREATE OR REPLACE FUNCTION public.resolve_employee_custom_schedule(
  p_employee_id uuid,
  p_date date
)
RETURNS TABLE (
  schedule_id uuid,
  employee_id uuid,
  effective_from date,
  effective_to date,
  day_of_week smallint,
  is_working_day boolean,
  start_time time without time zone,
  end_time time without time zone,
  scheduled_minutes integer
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $function$
  SELECT
    s.id AS schedule_id,
    s.employee_id,
    s.effective_from,
    s.effective_to,
    d.day_of_week,
    CASE
      WHEN holiday.is_public_holiday THEN false
      ELSE d.is_working_day
    END AS is_working_day,
    CASE
      WHEN holiday.is_public_holiday THEN NULL::time without time zone
      ELSE d.start_time
    END AS start_time,
    CASE
      WHEN holiday.is_public_holiday THEN NULL::time without time zone
      ELSE d.end_time
    END AS end_time,
    CASE
      WHEN holiday.is_public_holiday THEN 0
      WHEN d.is_working_day
        THEN (EXTRACT(EPOCH FROM (d.end_time - d.start_time)) / 60)::integer
      ELSE 0
    END AS scheduled_minutes
  FROM public.hr_employee_work_schedules s
  JOIN public.hr_employee_work_schedule_days d
    ON d.schedule_id = s.id
   AND d.day_of_week = EXTRACT(DOW FROM p_date)::smallint
  CROSS JOIN LATERAL (
    SELECT EXISTS (
      SELECT 1
      FROM public.hr_public_holidays h
      WHERE h.holiday_date = p_date
    ) AS is_public_holiday
  ) holiday
  WHERE s.employee_id = p_employee_id
    AND p_date >= s.effective_from
    AND (s.effective_to IS NULL OR p_date <= s.effective_to)
    AND (
      SELECT COUNT(*)
      FROM public.hr_employee_work_schedule_days all_days
      WHERE all_days.schedule_id = s.id
    ) = 7
    AND EXISTS (
      SELECT 1
      FROM public.hr_employee_work_schedule_days work_days
      WHERE work_days.schedule_id = s.id
        AND work_days.is_working_day = true
    )
  ORDER BY s.effective_from DESC
  LIMIT 1;
$function$;

COMMENT ON FUNCTION public.resolve_employee_custom_schedule(uuid, date) IS
  'V2 custom-only resolver. Zero rows means caller must use the untouched legacy schedule path. Official public holidays override a configured custom weekday as a non-working official day.';

-- CREATE OR REPLACE preserves the existing function ACL; assert it explicitly
-- rather than broadening permissions in this correction batch.
DO $acl_guard$
BEGIN
  IF has_function_privilege('anon', 'public.resolve_employee_custom_schedule(uuid,date)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.resolve_employee_custom_schedule(uuid,date)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.resolve_employee_custom_schedule(uuid,date)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Batch 3C resolver execute ACL drifted';
  END IF;
END;
$acl_guard$;

COMMIT;
