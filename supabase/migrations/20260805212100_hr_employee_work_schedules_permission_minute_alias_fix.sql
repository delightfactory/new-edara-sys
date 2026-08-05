-- =============================================================================
-- EDARA — Employee Work Schedules: permission minute-series alias correction
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  IF to_regprocedure(
       'public.get_uncovered_attendance_permission_minutes(uuid,date,timestamp with time zone,timestamp with time zone)'
     ) IS NULL THEN
    RAISE EXCEPTION 'Permission alias fix preflight failed: helper is missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Permission alias fix preflight failed: feature/readiness must remain false';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.get_uncovered_attendance_permission_minutes(
  p_employee_id UUID,
  p_shift_date DATE,
  p_range_start TIMESTAMPTZ,
  p_range_end TIMESTAMPTZ
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_total_minutes INTEGER;
  v_uncovered INTEGER;
BEGIN
  IF p_employee_id IS NULL
     OR p_shift_date IS NULL
     OR p_range_start IS NULL
     OR p_range_end IS NULL
     OR p_range_end <= p_range_start THEN
    RETURN 0;
  END IF;

  v_total_minutes := GREATEST(
    0,
    FLOOR(EXTRACT(EPOCH FROM (p_range_end - p_range_start)) / 60)::INTEGER
  );

  IF v_total_minutes <= 0 THEN
    RETURN 0;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_leave_requests lr
    WHERE lr.employee_id = p_employee_id
      AND lr.status = 'approved'
      AND p_shift_date BETWEEN lr.start_date AND lr.end_date
  ) THEN
    RETURN 0;
  END IF;

  SELECT count(*)::INTEGER
  INTO v_uncovered
  FROM generate_series(0, v_total_minutes - 1) AS offsets(minute_index)
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.hr_permission_requests pr
    WHERE pr.employee_id = p_employee_id
      AND pr.permission_date = p_shift_date
      AND pr.status = 'approved'
      AND p_range_start + make_interval(mins => offsets.minute_index) >=
        (p_shift_date + pr.leave_time) AT TIME ZONE 'Africa/Cairo'
      AND p_range_start + make_interval(mins => offsets.minute_index) <
        CASE
          WHEN pr.actual_return IS NOT NULL THEN
            (p_shift_date + pr.actual_return) AT TIME ZONE 'Africa/Cairo'
          WHEN pr.expected_return IS NOT NULL THEN
            (p_shift_date + pr.expected_return) AT TIME ZONE 'Africa/Cairo'
          ELSE
            ((p_shift_date + pr.leave_time) AT TIME ZONE 'Africa/Cairo')
              + make_interval(mins => GREATEST(0, COALESCE(pr.duration_minutes, 0)))
        END
  );

  RETURN COALESCE(v_uncovered, v_total_minutes);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_uncovered_attendance_permission_minutes(
  UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated, service_role;

DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  SELECT pg_get_functiondef(
    'public.get_uncovered_attendance_permission_minutes(uuid,date,timestamp with time zone,timestamp with time zone)'::regprocedure
  ) INTO v_definition;

  IF v_definition NOT ILIKE '%AS offsets(minute_index)%'
     OR v_definition NOT ILIKE '%offsets.minute_index%'
     OR v_definition ILIKE '%make_interval(mins => minute_offset)%' THEN
    RAISE EXCEPTION 'Permission alias fix assertion failed: series alias is invalid';
  END IF;
END;
$assertions$;

COMMIT;
