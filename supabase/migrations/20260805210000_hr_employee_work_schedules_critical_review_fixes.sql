-- =============================================================================
-- EDARA — Employee Work Schedules: critical code-review fixes
--
-- Narrow corrective migration only:
--   1. bind administrative attendance writes to auth.uid();
--   2. remove anonymous access from attendance automation RPCs;
--   3. prevent snapshotted non-working attendance from offsetting a scheduled
--      work-day absence or entering overtime/leave payroll aggregates.
--
-- This migration does not enable the feature, seed schedules, alter attendance
-- data, recalculate payroll, or change any public RPC signature.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '90s';

DO $preflight$
BEGIN
  IF to_regprocedure(
       'public.upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)'
     ) IS NULL
     OR to_regprocedure('public.mark_daily_absences(date)') IS NULL
     OR to_regprocedure('public.run_auto_checkout(date)') IS NULL
     OR to_regprocedure('public.scan_attendance_daily_review_alerts()') IS NULL
     OR to_regprocedure('public.run_attendance_operational_scan()') IS NULL
     OR to_regprocedure('public.notify_absent_employees()') IS NULL
     OR to_regprocedure('public.calculate_employee_payroll_scheduled(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'Critical-fix preflight failed: required schedule-aware functions are missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Critical-fix preflight failed: feature/readiness must remain false';
  END IF;
END;
$preflight$;

-- -----------------------------------------------------------------------------
-- 1. Administrative attendance correction: preserve the public signature but
--    never trust p_user_id as an authorization or audit identity.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_attendance_and_reprocess(
  p_employee_id UUID,
  p_shift_date DATE,
  p_punch_in_time TIMESTAMPTZ DEFAULT NULL,
  p_punch_out_time TIMESTAMPTZ DEFAULT NULL,
  p_status public.hr_attendance_status DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_actor UUID := auth.uid();
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT public.check_permission(v_actor, 'hr.attendance.create')
     AND NOT public.check_permission(v_actor, 'hr.attendance.edit')
     AND NOT public.check_permission(v_actor, 'hr.attendance.update')
     AND NOT public.check_permission(v_actor, 'hr.attendance.approve') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تعديل الحضور';
  END IF;

  IF NOT public.hr_employee_work_schedules_enabled() THEN
    RETURN public.upsert_attendance_and_reprocess_legacy_20260805(
      p_employee_id,
      p_shift_date,
      p_punch_in_time,
      p_punch_out_time,
      p_status,
      p_notes,
      v_actor
    );
  END IF;

  RETURN public.upsert_attendance_and_reprocess_scheduled(
    p_employee_id,
    p_shift_date,
    p_punch_in_time,
    p_punch_out_time,
    p_status,
    p_notes,
    v_actor
  );
END;
$function$;

COMMENT ON FUNCTION public.upsert_attendance_and_reprocess(
  UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ, public.hr_attendance_status, TEXT, UUID
) IS
  'Administrative attendance correction. Authorization and reviewed_by are always bound to auth.uid(); p_user_id remains only for backward signature compatibility.';

REVOKE ALL ON FUNCTION public.upsert_attendance_and_reprocess(
  UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ, public.hr_attendance_status, TEXT, UUID
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_attendance_and_reprocess(
  UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ, public.hr_attendance_status, TEXT, UUID
) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 2. Attendance automation wrappers: internal/service calls remain possible;
--    authenticated manual calls require an attendance-management permission.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_daily_absences(
  p_target_date DATE DEFAULT CURRENT_DATE
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_actor UUID := auth.uid();
BEGIN
  IF v_actor IS NOT NULL
     AND NOT public.check_permission(v_actor, 'hr.attendance.create')
     AND NOT public.check_permission(v_actor, 'hr.attendance.edit')
     AND NOT public.check_permission(v_actor, 'hr.attendance.update')
     AND NOT public.check_permission(v_actor, 'hr.attendance.approve') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تشغيل رصد الغياب';
  END IF;

  IF NOT public.hr_employee_work_schedules_enabled() THEN
    PERFORM public.mark_daily_absences_legacy_20260805(p_target_date);
    RETURN;
  END IF;

  PERFORM public.mark_daily_absences_scheduled(p_target_date);
END;
$function$;

CREATE OR REPLACE FUNCTION public.run_auto_checkout(
  p_target_date DATE DEFAULT CURRENT_DATE
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_actor UUID := auth.uid();
BEGIN
  IF v_actor IS NOT NULL
     AND NOT public.check_permission(v_actor, 'hr.attendance.edit')
     AND NOT public.check_permission(v_actor, 'hr.attendance.update')
     AND NOT public.check_permission(v_actor, 'hr.attendance.approve') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تشغيل الإغلاق التلقائي للحضور';
  END IF;

  IF NOT public.hr_employee_work_schedules_enabled() THEN
    PERFORM public.run_auto_checkout_legacy_20260805(p_target_date);
    RETURN;
  END IF;

  PERFORM public.run_auto_checkout_scheduled(p_target_date);
END;
$function$;

CREATE OR REPLACE FUNCTION public.scan_attendance_daily_review_alerts()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_actor UUID := auth.uid();
BEGIN
  IF v_actor IS NOT NULL
     AND NOT public.check_permission(v_actor, 'hr.attendance.edit')
     AND NOT public.check_permission(v_actor, 'hr.attendance.update')
     AND NOT public.check_permission(v_actor, 'hr.attendance.approve') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تشغيل مراجعة تنبيهات الحضور';
  END IF;

  IF NOT public.hr_employee_work_schedules_enabled() THEN
    RETURN public.scan_attendance_daily_review_alerts_legacy_20260805();
  END IF;

  RETURN public.scan_attendance_daily_review_alerts_scheduled();
END;
$function$;

CREATE OR REPLACE FUNCTION public.run_attendance_operational_scan()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_actor UUID := auth.uid();
BEGIN
  IF v_actor IS NOT NULL
     AND NOT public.check_permission(v_actor, 'hr.attendance.edit')
     AND NOT public.check_permission(v_actor, 'hr.attendance.update')
     AND NOT public.check_permission(v_actor, 'hr.attendance.approve') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تشغيل الفحص التشغيلي للحضور';
  END IF;

  IF NOT public.hr_employee_work_schedules_enabled() THEN
    RETURN public.run_attendance_operational_scan_legacy_20260805();
  END IF;

  RETURN public.run_attendance_operational_scan_scheduled();
END;
$function$;

REVOKE ALL ON FUNCTION public.mark_daily_absences(DATE)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.run_auto_checkout(DATE)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.scan_attendance_daily_review_alerts()
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.run_attendance_operational_scan()
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.mark_daily_absences(DATE)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.run_auto_checkout(DATE)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.scan_attendance_daily_review_alerts()
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.run_attendance_operational_scan()
  TO authenticated, service_role;

-- Absence notification is an internal scheduled operation, not a public RPC.
REVOKE ALL ON FUNCTION public.notify_absent_employees()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notify_absent_employees()
  TO service_role;

-- These mutation helpers are called only from reviewed SECURITY DEFINER paths.
REVOKE ALL ON FUNCTION public.process_attendance_penalties(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.settle_attendance_day_against_leave(UUID, BOOLEAN)
  FROM PUBLIC, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3. Scheduled payroll: only scheduled work-day rows may contribute attendance,
--    leave, authorized absence, or overtime. Unsnapshotted legacy/company rows
--    remain compatible; custom-schedule missing snapshots are already blocked.
-- -----------------------------------------------------------------------------
DO $patch_payroll$
DECLARE
  v_definition TEXT;
  v_old TEXT;
  v_new TEXT;
  v_occurrences INTEGER;
BEGIN
  SELECT pg_get_functiondef(
    'public.calculate_employee_payroll_scheduled(uuid,uuid)'::regprocedure
  ) INTO v_definition;

  v_definition := replace(v_definition, E'\r\n', E'\n');
  v_definition := replace(v_definition, E'\r', E'\n');

  v_old := $old$
  SELECT COALESCE(SUM(day_value), 0) INTO v_on_leave_days
  FROM hr_attendance_days
  WHERE employee_id = p_employee_id
    AND shift_date BETWEEN v_period.start_date AND v_calc_date
    AND status = 'on_leave';
$old$;
  v_new := $new$
  SELECT COALESCE(SUM(day_value), 0) INTO v_on_leave_days
  FROM hr_attendance_days
  WHERE employee_id = p_employee_id
    AND shift_date BETWEEN v_period.start_date AND v_calc_date
    AND status = 'on_leave'
    AND (schedule_day_kind = 'work_day' OR schedule_snapshot_at IS NULL);
$new$;

  v_occurrences := (length(v_definition) - length(replace(v_definition, v_old, ''))) / length(v_old);
  IF v_occurrences <> 1 THEN
    RAISE EXCEPTION 'Critical-fix payroll patch failed: on-leave marker count=%', v_occurrences;
  END IF;
  v_definition := replace(v_definition, v_old, v_new);

  v_old := $old$
  SELECT COALESCE(COUNT(*), 0) INTO v_authorized_absent
  FROM hr_attendance_days
  WHERE employee_id = p_employee_id
    AND shift_date BETWEEN v_period.start_date AND v_calc_date
    AND status = 'absent_authorized';
$old$;
  v_new := $new$
  SELECT COALESCE(COUNT(*), 0) INTO v_authorized_absent
  FROM hr_attendance_days
  WHERE employee_id = p_employee_id
    AND shift_date BETWEEN v_period.start_date AND v_calc_date
    AND status = 'absent_authorized'
    AND (schedule_day_kind = 'work_day' OR schedule_snapshot_at IS NULL);
$new$;

  v_occurrences := (length(v_definition) - length(replace(v_definition, v_old, ''))) / length(v_old);
  IF v_occurrences <> 1 THEN
    RAISE EXCEPTION 'Critical-fix payroll patch failed: authorized-absence marker count=%', v_occurrences;
  END IF;
  v_definition := replace(v_definition, v_old, v_new);

  v_old := $old$
  SELECT COALESCE(SUM(overtime_minutes), 0) INTO v_total_overtime_minutes
  FROM hr_attendance_days
  WHERE employee_id = p_employee_id
    AND shift_date BETWEEN v_period.start_date AND v_calc_date;
$old$;
  v_new := $new$
  SELECT COALESCE(SUM(overtime_minutes), 0) INTO v_total_overtime_minutes
  FROM hr_attendance_days
  WHERE employee_id = p_employee_id
    AND shift_date BETWEEN v_period.start_date AND v_calc_date
    AND (schedule_day_kind = 'work_day' OR schedule_snapshot_at IS NULL);
$new$;

  v_occurrences := (length(v_definition) - length(replace(v_definition, v_old, ''))) / length(v_old);
  IF v_occurrences <> 1 THEN
    RAISE EXCEPTION 'Critical-fix payroll patch failed: overtime marker count=%', v_occurrences;
  END IF;
  v_definition := replace(v_definition, v_old, v_new);

  v_old := $old$
  SELECT COALESCE(SUM(day_value), 0) INTO v_attended_days
  FROM hr_attendance_days
  WHERE employee_id = p_employee_id
    AND shift_date BETWEEN v_period.start_date AND v_calc_date
    AND status NOT IN ('weekly_off', 'public_holiday', 'on_leave');
$old$;
  v_new := $new$
  SELECT COALESCE(SUM(day_value), 0) INTO v_attended_days
  FROM hr_attendance_days
  WHERE employee_id = p_employee_id
    AND shift_date BETWEEN v_period.start_date AND v_calc_date
    AND status NOT IN ('weekly_off', 'public_holiday', 'on_leave')
    AND (schedule_day_kind = 'work_day' OR schedule_snapshot_at IS NULL);
$new$;

  v_occurrences := (length(v_definition) - length(replace(v_definition, v_old, ''))) / length(v_old);
  IF v_occurrences <> 1 THEN
    RAISE EXCEPTION 'Critical-fix payroll patch failed: attended-days marker count=%', v_occurrences;
  END IF;
  v_definition := replace(v_definition, v_old, v_new);

  IF v_definition NOT ILIKE '%schedule_day_kind = ''work_day'' OR schedule_snapshot_at IS NULL%' THEN
    RAISE EXCEPTION 'Critical-fix payroll patch failed: work-day eligibility predicate is missing';
  END IF;

  EXECUTE v_definition;
END;
$patch_payroll$;

REVOKE ALL ON FUNCTION public.calculate_employee_payroll_scheduled(UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 4. Assertions
-- -----------------------------------------------------------------------------
DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Critical-fix assertion failed: feature/readiness changed';
  END IF;

  SELECT pg_get_functiondef(
    'public.upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)'::regprocedure
  ) INTO v_definition;

  IF v_definition NOT ILIKE '%v_actor UUID := auth.uid()%'
     OR v_definition ILIKE '%check_permission(COALESCE(p_user_id, auth.uid())%'
     OR v_definition NOT ILIKE '%p_notes,%v_actor%' THEN
    RAISE EXCEPTION 'Critical-fix assertion failed: administrative actor binding is incomplete';
  END IF;

  SELECT pg_get_functiondef(
    'public.calculate_employee_payroll_scheduled(uuid,uuid)'::regprocedure
  ) INTO v_definition;

  IF (
    (length(v_definition) - length(replace(
      v_definition,
      'schedule_day_kind = ''work_day'' OR schedule_snapshot_at IS NULL',
      ''
    ))) / length('schedule_day_kind = ''work_day'' OR schedule_snapshot_at IS NULL')
  ) < 4 THEN
    RAISE EXCEPTION 'Critical-fix assertion failed: payroll work-day predicates are incomplete';
  END IF;

  IF has_function_privilege(
       'anon',
       'public.upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)',
       'EXECUTE'
     )
     OR has_function_privilege('anon', 'public.mark_daily_absences(date)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.run_auto_checkout(date)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.scan_attendance_daily_review_alerts()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.run_attendance_operational_scan()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.notify_absent_employees()', 'EXECUTE') THEN
    RAISE EXCEPTION 'Critical-fix assertion failed: anonymous attendance mutation access remains';
  END IF;
END;
$assertions$;

COMMIT;
