-- =============================================================================
-- EDARA — Employee Work Schedules: attendance metric normalization
--
-- One narrow post-processing path makes live GPS and administrative correction
-- use the same late, early-leave, permission, and overtime rules without
-- rewriting the large reviewed attendance implementations.
--
-- Safety rules:
--   * no effect while the schedule feature is disabled;
--   * no automatic overtime from auto-checkout;
--   * a partial attendance during an approved full-day leave remains paid leave
--     unless the employee completed the full scheduled day;
--   * approved permissions authorize only the minutes they actually cover.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '90s';

DO $preflight$
BEGIN
  IF to_regprocedure('public.record_attendance_gps_v2_scheduled(numeric,numeric,numeric,text,timestamp with time zone)') IS NULL
     OR to_regprocedure('public.record_attendance_gps_legacy_20260805(numeric,numeric,numeric,text,timestamp with time zone)') IS NULL
     OR to_regprocedure('public.record_attendance_gps_v2_legacy_20260805(numeric,numeric,numeric,text,timestamp with time zone)') IS NULL
     OR to_regprocedure('public.upsert_attendance_and_reprocess_scheduled(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)') IS NULL
     OR to_regprocedure('public.run_auto_checkout_scheduled(date)') IS NULL THEN
    RAISE EXCEPTION 'Attendance normalization preflight failed: schedule-aware attendance functions are missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Attendance normalization preflight failed: feature/readiness must remain false';
  END IF;

  IF to_regprocedure('public.get_uncovered_attendance_permission_minutes(uuid,date,timestamp with time zone,timestamp with time zone)') IS NOT NULL
     OR to_regprocedure('public.normalize_attendance_day_schedule_metrics(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'Attendance normalization preflight failed: normalization helpers already exist';
  END IF;
END;
$preflight$;

-- -----------------------------------------------------------------------------
-- 1. Count only the integer minutes not covered by an approved permission.
--    Full-day approved leave covers the interval by definition.
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.get_uncovered_attendance_permission_minutes(
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
  FROM generate_series(0, v_total_minutes - 1) minute_offset
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.hr_permission_requests pr
    WHERE pr.employee_id = p_employee_id
      AND pr.permission_date = p_shift_date
      AND pr.status = 'approved'
      AND p_range_start + make_interval(mins => minute_offset) >=
        (p_shift_date + pr.leave_time) AT TIME ZONE 'Africa/Cairo'
      AND p_range_start + make_interval(mins => minute_offset) <
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

-- -----------------------------------------------------------------------------
-- 2. Central normalizer. It uses the immutable schedule snapshot and then calls
--    the existing leave/penalty engines once with the corrected metrics.
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.normalize_attendance_day_schedule_metrics(
  p_attendance_day_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_day public.hr_attendance_days%ROWTYPE;
  v_late_grace INTEGER := 15;
  v_late_minutes INTEGER := 0;
  v_early_minutes INTEGER := 0;
  v_overtime_minutes INTEGER := 0;
  v_uncovered_minutes INTEGER := 0;
  v_checkout_status public.hr_checkout_status := NULL;
  v_status public.hr_attendance_status;
  v_penalties_count INTEGER := 0;
BEGIN
  SELECT * INTO v_day
  FROM public.hr_attendance_days
  WHERE id = p_attendance_day_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Attendance day % does not exist', p_attendance_day_id;
  END IF;

  IF v_day.schedule_snapshot_at IS NULL THEN
    PERFORM public.ensure_attendance_schedule_snapshot(v_day.id);

    SELECT * INTO v_day
    FROM public.hr_attendance_days
    WHERE id = p_attendance_day_id
    FOR UPDATE;
  END IF;

  v_status := v_day.status;

  IF v_day.schedule_day_kind <> 'work_day' THEN
    UPDATE public.hr_attendance_days
    SET late_minutes = 0,
        early_leave_minutes = 0,
        overtime_minutes = 0,
        checkout_status = CASE
          WHEN punch_out_time IS NULL THEN NULL
          ELSE 'on_time'::public.hr_checkout_status
        END,
        updated_at = now()
    WHERE id = v_day.id;

    SELECT public.reprocess_attendance_day_penalties(v_day.id)
    INTO v_penalties_count;

    RETURN jsonb_build_object(
      'attendance_day_id', v_day.id,
      'status', v_status,
      'checkout_status', CASE WHEN v_day.punch_out_time IS NULL THEN NULL ELSE 'on_time' END,
      'late_minutes', 0,
      'early_leave_minutes', 0,
      'overtime_minutes', 0,
      'penalties_applied', COALESCE(v_penalties_count, 0)
    );
  END IF;

  IF v_day.scheduled_start_at IS NULL
     OR v_day.scheduled_end_at IS NULL
     OR v_day.scheduled_minutes IS NULL
     OR v_day.scheduled_minutes <= 0 THEN
    RAISE EXCEPTION 'Attendance day % has an invalid work schedule snapshot', v_day.id;
  END IF;

  SELECT GREATEST(0, COALESCE(value::INTEGER, 15))
  INTO v_late_grace
  FROM public.company_settings
  WHERE key = 'hr.late_grace_minutes';

  v_late_grace := GREATEST(0, COALESCE(v_late_grace, 15));

  IF v_day.punch_in_time IS NOT NULL THEN
    v_late_minutes := GREATEST(
      0,
      FLOOR(EXTRACT(EPOCH FROM (v_day.punch_in_time - v_day.scheduled_start_at)) / 60)::INTEGER
        - v_late_grace
    );

    IF v_status IN ('present', 'late') THEN
      v_status := CASE
        WHEN v_late_minutes > 0 THEN 'late'::public.hr_attendance_status
        ELSE 'present'::public.hr_attendance_status
      END;
    END IF;
  END IF;

  IF v_day.punch_out_time IS NOT NULL THEN
    IF v_day.punch_out_time > v_day.scheduled_end_at THEN
      -- GPS check-out may earn overtime. Auto-checkout never grants a financial
      -- overtime amount without a real employee checkout event.
      IF COALESCE(v_day.is_auto_checkout, false) THEN
        v_overtime_minutes := 0;
        v_checkout_status := 'on_time';
      ELSE
        v_overtime_minutes := GREATEST(
          0,
          FLOOR(EXTRACT(EPOCH FROM (v_day.punch_out_time - v_day.scheduled_end_at)) / 60)::INTEGER
        );
        v_checkout_status := CASE
          WHEN v_overtime_minutes > 0 THEN 'overtime'::public.hr_checkout_status
          ELSE 'on_time'::public.hr_checkout_status
        END;
      END IF;
    ELSIF v_day.punch_out_time < v_day.scheduled_end_at THEN
      v_early_minutes := GREATEST(
        0,
        FLOOR(EXTRACT(EPOCH FROM (v_day.scheduled_end_at - v_day.punch_out_time)) / 60)::INTEGER
      );

      IF v_early_minutes > 0 THEN
        v_uncovered_minutes := public.get_uncovered_attendance_permission_minutes(
          v_day.employee_id,
          v_day.shift_date,
          v_day.scheduled_end_at - make_interval(mins => v_early_minutes),
          v_day.scheduled_end_at
        );

        v_checkout_status := CASE
          WHEN v_uncovered_minutes = 0 THEN 'early_authorized'::public.hr_checkout_status
          ELSE 'early_unauthorized'::public.hr_checkout_status
        END;
      ELSE
        v_checkout_status := 'on_time';
      END IF;
    ELSE
      v_checkout_status := 'on_time';
    END IF;
  END IF;

  UPDATE public.hr_attendance_days
  SET status = v_status,
      late_minutes = v_late_minutes,
      early_leave_minutes = v_early_minutes,
      overtime_minutes = v_overtime_minutes,
      checkout_status = v_checkout_status,
      updated_at = now()
  WHERE id = v_day.id;

  IF v_day.punch_out_time IS NOT NULL THEN
    PERFORM public.settle_attendance_day_against_leave(
      v_day.id,
      COALESCE(v_day.is_manually_locked, false)
    );

    SELECT * INTO v_day
    FROM public.hr_attendance_days
    WHERE id = p_attendance_day_id
    FOR UPDATE;

    -- Safe V1 policy: partial work during an approved full-day leave stays a
    -- fully paid leave day. Only a completed scheduled day restores the balance.
    IF v_day.source_leave_request_id IS NOT NULL
       AND COALESCE(v_day.leave_balance_restored, false) = false
       AND COALESCE(v_day.effective_hours, 0) < (v_day.scheduled_minutes / 60.0) THEN
      UPDATE public.hr_attendance_days
      SET status = 'on_leave',
          day_value = 1.00,
          late_minutes = 0,
          early_leave_minutes = 0,
          overtime_minutes = 0,
          checkout_status = 'on_time',
          updated_at = now()
      WHERE id = v_day.id;
    END IF;

    SELECT public.reprocess_attendance_day_penalties(v_day.id)
    INTO v_penalties_count;
  END IF;

  SELECT * INTO v_day
  FROM public.hr_attendance_days
  WHERE id = p_attendance_day_id;

  RETURN jsonb_build_object(
    'attendance_day_id', v_day.id,
    'status', v_day.status,
    'checkout_status', v_day.checkout_status,
    'late_minutes', COALESCE(v_day.late_minutes, 0),
    'early_leave_minutes', COALESCE(v_day.early_leave_minutes, 0),
    'overtime_minutes', COALESCE(v_day.overtime_minutes, 0),
    'penalties_applied', COALESCE(v_penalties_count, 0)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.normalize_attendance_day_schedule_metrics(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3. Public GPS wrappers: exact legacy behavior while disabled; normalized
--    schedule metrics while enabled.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_attendance_gps_v2(
  p_latitude NUMERIC,
  p_longitude NUMERIC,
  p_gps_accuracy NUMERIC,
  p_log_type TEXT,
  p_event_time TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_result JSONB;
  v_metrics JSONB;
  v_day_id UUID;
BEGIN
  IF NOT public.hr_employee_work_schedules_enabled() THEN
    RETURN public.record_attendance_gps_v2_legacy_20260805(
      p_latitude,
      p_longitude,
      p_gps_accuracy,
      p_log_type,
      p_event_time
    );
  END IF;

  v_result := public.record_attendance_gps_v2_scheduled(
    p_latitude,
    p_longitude,
    p_gps_accuracy,
    p_log_type,
    p_event_time
  );

  IF COALESCE((v_result->>'success')::BOOLEAN, false) THEN
    v_day_id := NULLIF(v_result->>'attendance_day_id', '')::UUID;
    IF v_day_id IS NOT NULL THEN
      v_metrics := public.normalize_attendance_day_schedule_metrics(v_day_id);
      v_result := v_result || v_metrics;
    END IF;
  END IF;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_attendance_gps(
  p_latitude NUMERIC,
  p_longitude NUMERIC,
  p_gps_accuracy NUMERIC,
  p_log_type TEXT,
  p_event_time TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_result JSONB;
  v_metrics JSONB;
  v_day_id UUID;
BEGIN
  IF NOT public.hr_employee_work_schedules_enabled() THEN
    RETURN public.record_attendance_gps_legacy_20260805(
      p_latitude,
      p_longitude,
      p_gps_accuracy,
      p_log_type,
      p_event_time
    );
  END IF;

  v_result := public.record_attendance_gps_v2_scheduled(
    p_latitude,
    p_longitude,
    p_gps_accuracy,
    p_log_type,
    p_event_time
  );

  IF COALESCE((v_result->>'success')::BOOLEAN, false) THEN
    v_day_id := NULLIF(v_result->>'attendance_day_id', '')::UUID;
    IF v_day_id IS NOT NULL THEN
      v_metrics := public.normalize_attendance_day_schedule_metrics(v_day_id);
      v_result := v_result || v_metrics;
    END IF;
  END IF;

  RETURN v_result;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.record_attendance_gps_v2(
  NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ
) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_attendance_gps(
  NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ
) TO anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 4. Administrative wrapper: preserve the service-role actor guard and apply
--    exactly the same metric normalizer after the reviewed scheduled write.
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
  v_role TEXT := COALESCE(auth.role(), '');
  v_result JSONB;
  v_metrics JSONB;
  v_day_id UUID;
BEGIN
  IF v_role = 'service_role' THEN
    v_actor := p_user_id;
  END IF;

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'A verified attendance actor is required';
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

  v_result := public.upsert_attendance_and_reprocess_scheduled(
    p_employee_id,
    p_shift_date,
    p_punch_in_time,
    p_punch_out_time,
    p_status,
    p_notes,
    v_actor
  );

  IF COALESCE((v_result->>'success')::BOOLEAN, false) THEN
    v_day_id := NULLIF(v_result->>'attendance_day_id', '')::UUID;
    IF v_day_id IS NOT NULL THEN
      v_metrics := public.normalize_attendance_day_schedule_metrics(v_day_id);
      v_result := v_result || v_metrics;
    END IF;
  END IF;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.upsert_attendance_and_reprocess(
  UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ, public.hr_attendance_status, TEXT, UUID
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_attendance_and_reprocess(
  UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ, public.hr_attendance_status, TEXT, UUID
) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 5. Auto-checkout wrapper: normalize only open-period rows processed for the
--    target date. This removes unapproved overtime inferred from tracking pings.
-- -----------------------------------------------------------------------------
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
  v_day_id UUID;
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

  FOR v_day_id IN
    SELECT d.id
    FROM public.hr_attendance_days d
    WHERE d.shift_date = p_target_date
      AND COALESCE(d.is_auto_checkout, false)
      AND d.punch_out_time IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.hr_payroll_runs pr
        JOIN public.hr_payroll_periods pp ON pp.id = pr.period_id
        JOIN public.hr_payroll_lines pl ON pl.payroll_run_id = pr.id
        WHERE pl.employee_id = d.employee_id
          AND pr.status IN ('approved', 'paid')
          AND d.shift_date BETWEEN pp.start_date AND pp.end_date
      )
  LOOP
    PERFORM public.normalize_attendance_day_schedule_metrics(v_day_id);
  END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION public.run_auto_checkout(DATE)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.run_auto_checkout(DATE)
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 6. Assertions
-- -----------------------------------------------------------------------------
DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Attendance normalization assertion failed: feature/readiness changed';
  END IF;

  SELECT pg_get_functiondef('public.normalize_attendance_day_schedule_metrics(uuid)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%late_grace%'
     OR v_definition NOT ILIKE '%get_uncovered_attendance_permission_minutes%'
     OR v_definition NOT ILIKE '%is_auto_checkout%'
     OR v_definition NOT ILIKE '%status = ''on_leave''%' THEN
    RAISE EXCEPTION 'Attendance normalization assertion failed: normalizer contract is incomplete';
  END IF;

  SELECT pg_get_functiondef(
    'public.upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%normalize_attendance_day_schedule_metrics%'
     OR v_definition NOT ILIKE '%v_role = ''service_role''%'
     OR v_definition ILIKE '%COALESCE(p_user_id, auth.uid())%' THEN
    RAISE EXCEPTION 'Attendance normalization assertion failed: administrative wrapper is incomplete';
  END IF;

  SELECT pg_get_functiondef(
    'public.record_attendance_gps_v2(numeric,numeric,numeric,text,timestamp with time zone)'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%normalize_attendance_day_schedule_metrics%'
     OR v_definition NOT ILIKE '%record_attendance_gps_v2_legacy_20260805%' THEN
    RAISE EXCEPTION 'Attendance normalization assertion failed: GPS v2 wrapper is incomplete';
  END IF;

  IF has_function_privilege(
       'authenticated',
       'public.normalize_attendance_day_schedule_metrics(uuid)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'service_role',
       'public.get_uncovered_attendance_permission_minutes(uuid,date,timestamp with time zone,timestamp with time zone)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Attendance normalization assertion failed: internal helper is exposed';
  END IF;
END;
$assertions$;

COMMIT;
