-- =============================================================================
-- EDARA — Employee Work Schedules: remaining release-safety fixes
--
-- Narrow corrective scope only:
--   1. use one minute-coverage helper for overlapping permissions;
--   2. stop awarding a synthetic payroll day when no scheduled workday exists;
--   3. make an established attendance schedule snapshot immutable.
--
-- This migration does not enable the feature, seed schedules, backfill
-- attendance, recalculate payroll, or change public RPC signatures.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

DO $preflight$
BEGIN
  IF to_regprocedure('public.process_attendance_penalties_scheduled(uuid)') IS NULL
     OR to_regprocedure(
       'public.get_uncovered_attendance_permission_minutes(uuid,date,timestamp with time zone,timestamp with time zone)'
     ) IS NULL
     OR to_regprocedure('public.calculate_employee_payroll_scheduled(uuid,uuid)') IS NULL
     OR to_regclass('public.hr_attendance_days') IS NULL THEN
    RAISE EXCEPTION 'Release-safety preflight failed: required schedule-aware objects are missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Release-safety preflight failed: feature/readiness must remain false';
  END IF;

  IF to_regprocedure('public.guard_attendance_schedule_snapshot_immutable()') IS NOT NULL THEN
    RAISE EXCEPTION 'Release-safety preflight failed: snapshot immutability guard already exists';
  END IF;
END;
$preflight$;

-- -----------------------------------------------------------------------------
-- 1. Replace only the early-leave permission block. The shared helper counts
--    uncovered minutes once, even when approved permissions overlap.
-- -----------------------------------------------------------------------------
DO $patch_penalties$
DECLARE
  v_definition TEXT;
  v_start INTEGER;
  v_end INTEGER;
  v_start_marker TEXT := '  -- Unauthorized early leave: preserve permission-overlap semantics; replace';
  v_end_marker TEXT := E'\n  RETURN v_count;';
  v_replacement TEXT;
BEGIN
  SELECT pg_get_functiondef('public.process_attendance_penalties_scheduled(uuid)'::regprocedure)
  INTO v_definition;

  v_definition := replace(v_definition, E'\r\n', E'\n');
  v_definition := replace(v_definition, E'\r', E'\n');

  v_start := strpos(v_definition, v_start_marker);
  v_end := strpos(v_definition, v_end_marker);

  IF v_start = 0 OR v_end = 0 OR v_end <= v_start THEN
    RAISE EXCEPTION 'Release-safety penalty patch failed: early-leave block markers are missing';
  END IF;

  v_replacement := $replacement$
  -- Unauthorized early leave: calculate one union of approved permission time.
  IF v_day.checkout_status = 'early_unauthorized'
     AND COALESCE(v_day.early_leave_minutes, 0) > 0 THEN
    v_penalty_type := 'early_leave_unauthorized';

    v_minutes := public.get_uncovered_attendance_permission_minutes(
      v_day.employee_id,
      v_day.shift_date,
      v_day.punch_out_time,
      v_day.scheduled_end_at
    );

    IF v_minutes > 0 THEN
      SELECT COUNT(*) + 1 INTO v_occurrence
      FROM public.hr_penalty_instances pi
      JOIN public.hr_attendance_days ad ON ad.id = pi.attendance_day_id
      WHERE pi.employee_id = v_day.employee_id
        AND pi.penalty_type = v_penalty_type
        AND ad.shift_date BETWEEN v_month_start AND v_month_end
        AND pi.attendance_day_id <> p_attendance_day_id;

      v_deduct_days := ROUND(
        (v_minutes / v_day.scheduled_minutes::NUMERIC),
        4
      );

      INSERT INTO public.hr_penalty_instances (
        employee_id,
        attendance_day_id,
        penalty_rule_id,
        penalty_type,
        occurrence_in_month,
        deduction_type,
        deduction_days,
        deduction_minutes
      ) VALUES (
        v_day.employee_id,
        p_attendance_day_id,
        NULL,
        v_penalty_type,
        v_occurrence,
        'custom_minutes',
        v_deduct_days,
        v_minutes
      );

      v_count := v_count + 1;
    END IF;
  END IF;
$replacement$;

  v_definition := substr(v_definition, 1, v_start - 1)
    || v_replacement
    || substr(v_definition, v_end);

  IF v_definition NOT ILIKE '%get_uncovered_attendance_permission_minutes%'
     OR v_definition ILIKE '%v_covered_minutes INTEGER%'
     OR v_definition ILIKE '%FOR v_perm IN%' THEN
    RAISE EXCEPTION 'Release-safety penalty patch failed: overlapping-permission logic remains';
  END IF;

  EXECUTE v_definition;
END;
$patch_penalties$;

-- -----------------------------------------------------------------------------
-- 2. Zero scheduled workdays in a partial employment interval means zero
--    entitlement for that interval. Remove the inherited synthetic-one-day
--    fallback without changing any other payroll formula.
-- -----------------------------------------------------------------------------
DO $patch_payroll$
DECLARE
  v_definition TEXT;
  v_old TEXT := 'IF v_partial_working <= 0 THEN v_partial_working := 1; END IF;';
  v_new TEXT := 'v_partial_working := GREATEST(COALESCE(v_partial_working, 0), 0);';
  v_occurrences INTEGER;
BEGIN
  SELECT pg_get_functiondef('public.calculate_employee_payroll_scheduled(uuid,uuid)'::regprocedure)
  INTO v_definition;

  v_occurrences := (
    length(v_definition) - length(replace(v_definition, v_old, ''))
  ) / length(v_old);

  IF v_occurrences <> 3 THEN
    RAISE EXCEPTION
      'Release-safety payroll patch failed: expected 3 synthetic-day fallbacks, found %',
      v_occurrences;
  END IF;

  v_definition := replace(v_definition, v_old, v_new);

  IF v_definition ILIKE '%' || v_old || '%'
     OR (
       (length(v_definition) - length(replace(v_definition, v_new, '')))
       / length(v_new)
     ) <> 3 THEN
    RAISE EXCEPTION 'Release-safety payroll patch failed: zero-day replacement is incomplete';
  END IF;

  EXECUTE v_definition;
END;
$patch_payroll$;

-- -----------------------------------------------------------------------------
-- 3. Once a complete schedule snapshot exists, no later UPDATE may reinterpret
--    that attendance date. Unrelated attendance fields remain fully editable.
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.guard_attendance_schedule_snapshot_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  IF OLD.schedule_snapshot_at IS NOT NULL
     AND (
       NEW.schedule_day_kind IS DISTINCT FROM OLD.schedule_day_kind
       OR NEW.scheduled_start_at IS DISTINCT FROM OLD.scheduled_start_at
       OR NEW.scheduled_end_at IS DISTINCT FROM OLD.scheduled_end_at
       OR NEW.scheduled_minutes IS DISTINCT FROM OLD.scheduled_minutes
       OR NEW.schedule_source IS DISTINCT FROM OLD.schedule_source
       OR NEW.work_schedule_id IS DISTINCT FROM OLD.work_schedule_id
       OR NEW.schedule_snapshot_at IS DISTINCT FROM OLD.schedule_snapshot_at
     ) THEN
    RAISE EXCEPTION
      'Attendance schedule snapshot is immutable for attendance day %',
      OLD.id;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_attendance_schedule_snapshot_immutable()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_hr_attendance_days_schedule_snapshot_immutable
  ON public.hr_attendance_days;
CREATE TRIGGER trg_hr_attendance_days_schedule_snapshot_immutable
  BEFORE UPDATE OF
    schedule_day_kind,
    scheduled_start_at,
    scheduled_end_at,
    scheduled_minutes,
    schedule_source,
    work_schedule_id,
    schedule_snapshot_at
  ON public.hr_attendance_days
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_attendance_schedule_snapshot_immutable();

-- -----------------------------------------------------------------------------
-- 4. Assertions
-- -----------------------------------------------------------------------------
DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Release-safety assertion failed: feature/readiness changed';
  END IF;

  SELECT pg_get_functiondef('public.process_attendance_penalties_scheduled(uuid)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%get_uncovered_attendance_permission_minutes%'
     OR v_definition ILIKE '%FOR v_perm IN%'
     OR v_definition ILIKE '%v_covered_minutes INTEGER%' THEN
    RAISE EXCEPTION 'Release-safety assertion failed: permission overlap fix is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.calculate_employee_payroll_scheduled(uuid,uuid)'::regprocedure)
  INTO v_definition;
  IF v_definition ILIKE '%v_partial_working := 1%'
     OR v_definition NOT ILIKE '%GREATEST(COALESCE(v_partial_working, 0), 0)%' THEN
    RAISE EXCEPTION 'Release-safety assertion failed: synthetic partial-day fallback remains';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'hr_attendance_days'
      AND t.tgname = 'trg_hr_attendance_days_schedule_snapshot_immutable'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'Release-safety assertion failed: snapshot immutability trigger is missing';
  END IF;
END;
$assertions$;

COMMIT;
