-- =============================================================================
-- EDARA — Employee Work Schedules: leave settlement balance consistency
--
-- Narrow follow-up to 20260806180000. When a linked leave day is fully worked,
-- the schedule-aware settlement already restores one used day; this migration
-- also refreshes remaining_days from the same post-update balance values.
-- Disabled/legacy behavior is unchanged.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
DECLARE
  v_definition TEXT;
BEGIN
  IF to_regprocedure('public.settle_attendance_day_against_leave_scheduled(uuid,boolean)') IS NULL
     OR to_regprocedure('public.calculate_employee_leave_workdays(uuid,date,date,boolean)') IS NULL THEN
    RAISE EXCEPTION 'Leave settlement preflight failed: required leave integration is missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Leave settlement preflight failed: feature/readiness must remain false';
  END IF;

  SELECT pg_get_functiondef(
    'public.settle_attendance_day_against_leave_scheduled(uuid,boolean)'::regprocedure
  ) INTO v_definition;

  IF v_definition NOT ILIKE '%SET used_days = GREATEST(0, used_days - 1)%'
     OR v_definition ILIKE '%remaining_days = GREATEST%used_days - 1%' THEN
    RAISE EXCEPTION 'Leave settlement preflight failed: unexpected settlement definition';
  END IF;
END;
$preflight$;

DO $patch_settlement$
DECLARE
  v_definition TEXT;
  v_old TEXT;
  v_new TEXT;
  v_occurrences INTEGER;
BEGIN
  SELECT pg_get_functiondef(
    'public.settle_attendance_day_against_leave_scheduled(uuid,boolean)'::regprocedure
  ) INTO v_definition;

  v_definition := replace(v_definition, E'\r\n', E'\n');
  v_definition := replace(v_definition, E'\r', E'\n');

  v_old := $old$
    UPDATE public.hr_leave_balances
    SET used_days = GREATEST(0, used_days - 1),
        updated_at = now()
    WHERE employee_id = v_day.employee_id
      AND leave_type_id = v_leave_req.leave_type_id
      AND year = EXTRACT(YEAR FROM v_leave_req.start_date)::INTEGER;
$old$;

  v_new := $new$
    UPDATE public.hr_leave_balances
    SET used_days = GREATEST(0, COALESCE(used_days, 0) - 1),
        remaining_days = GREATEST(0,
          COALESCE(total_days, 0) + COALESCE(carried_forward, 0)
          - GREATEST(0, COALESCE(used_days, 0) - 1)
          - COALESCE(pending_days, 0)
        ),
        updated_at = now()
    WHERE employee_id = v_day.employee_id
      AND leave_type_id = v_leave_req.leave_type_id
      AND year = EXTRACT(YEAR FROM v_leave_req.start_date)::INTEGER;
$new$;

  v_occurrences := (
    length(v_definition) - length(replace(v_definition, v_old, ''))
  ) / length(v_old);

  IF v_occurrences <> 1 THEN
    RAISE EXCEPTION 'Leave settlement patch failed: expected one balance update, found %', v_occurrences;
  END IF;

  v_definition := replace(v_definition, v_old, v_new);
  EXECUTE v_definition;
END;
$patch_settlement$;

REVOKE ALL ON FUNCTION public.settle_attendance_day_against_leave_scheduled(UUID, BOOLEAN)
  FROM PUBLIC, anon, authenticated, service_role;

DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Leave settlement assertion failed: feature/readiness changed';
  END IF;

  SELECT pg_get_functiondef(
    'public.settle_attendance_day_against_leave_scheduled(uuid,boolean)'::regprocedure
  ) INTO v_definition;

  IF v_definition NOT ILIKE '%remaining_days = GREATEST%'
     OR v_definition NOT ILIKE '%COALESCE(used_days, 0) - 1%'
     OR v_definition NOT ILIKE '%COALESCE(pending_days, 0)%' THEN
    RAISE EXCEPTION 'Leave settlement assertion failed: remaining balance update is incomplete';
  END IF;
END;
$assertions$;

COMMIT;
