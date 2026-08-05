-- =============================================================================
-- EDARA — Employee Work Schedules M3A
-- Schedule-aware live GPS attendance, manual attendance, and work-day resolution
--
-- SAFETY CONTRACT
--   * Requires M1 + all M2 migrations.
--   * The feature switch must remain FALSE while this migration is installed.
--   * Exact production implementations are cloned as private legacy helpers.
--   * Public callers delegate to the exact legacy helpers while the switch is off.
--   * No attendance, payroll, schedule, or setting row is modified by this file.
--   * The legacy record_attendance_gps RPC is intentionally untouched in M3A.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '90s';

-- ----------------------------------------------------------------------------
-- 0. Fail fast on schema drift or an unsafe rollout state
-- ----------------------------------------------------------------------------
DO $preflight$
DECLARE
  v_hash TEXT;
BEGIN
  IF to_regprocedure('public.hr_employee_work_schedules_enabled()') IS NULL
     OR to_regprocedure('public.resolve_employee_work_schedule(uuid,date)') IS NULL
     OR to_regprocedure('public.ensure_attendance_schedule_snapshot(uuid)') IS NULL THEN
    RAISE EXCEPTION 'M3A preflight failed: M2 resolver/snapshot helpers are missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'M3A preflight failed: feature switch must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'M3A preflight failed: no employee schedules are expected before rehearsal';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.hr_attendance_days
    WHERE schedule_snapshot_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'M3A preflight failed: no attendance snapshots are expected before caller rollout';
  END IF;

  IF to_regprocedure('public.record_attendance_gps_v2_legacy_20260805(numeric,numeric,numeric,text,timestamp with time zone)') IS NOT NULL
     OR to_regprocedure('public.record_attendance_gps_v2_scheduled(numeric,numeric,numeric,text,timestamp with time zone)') IS NOT NULL
     OR to_regprocedure('public.upsert_attendance_and_reprocess_legacy_20260805(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)') IS NOT NULL
     OR to_regprocedure('public.upsert_attendance_and_reprocess_scheduled(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)') IS NOT NULL
     OR to_regprocedure('public.is_employee_work_day_legacy_20260805(uuid,date)') IS NOT NULL THEN
    RAISE EXCEPTION 'M3A preflight failed: one or more M3A helper functions already exist';
  END IF;

  SELECT md5(pg_get_functiondef('public.record_attendance_gps_v2(numeric,numeric,numeric,text,timestamp with time zone)'::regprocedure))
  INTO v_hash;
  IF v_hash <> 'bd70c45984e188a38cceb45eea00fa00' THEN
    RAISE EXCEPTION 'M3A preflight failed: record_attendance_gps_v2 drifted (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)'::regprocedure))
  INTO v_hash;
  IF v_hash <> 'a0123e9ec343603dee9adf4ec73739b4' THEN
    RAISE EXCEPTION 'M3A preflight failed: upsert_attendance_and_reprocess drifted (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.is_employee_work_day(uuid,date)'::regprocedure))
  INTO v_hash;
  IF v_hash <> '3e047334df57ad284bea8e9504724dd0' THEN
    RAISE EXCEPTION 'M3A preflight failed: is_employee_work_day drifted (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.record_attendance_gps(numeric,numeric,numeric,text,timestamp with time zone)'::regprocedure))
  INTO v_hash;
  IF v_hash <> '41f47aaff1eced8e368bce61cbd7a1a4' THEN
    RAISE EXCEPTION 'M3A preflight failed: legacy record_attendance_gps drifted (%)', v_hash;
  END IF;
END;
$preflight$;

-- ----------------------------------------------------------------------------
-- 1. Clone the exact current production functions as internal legacy helpers.
--    Hash guards above make this deterministic and prevent cloning unknown code.
-- ----------------------------------------------------------------------------
DO $clone_legacy$
DECLARE
  v_definition TEXT;
BEGIN
  SELECT pg_get_functiondef(
    'public.record_attendance_gps_v2(numeric,numeric,numeric,text,timestamp with time zone)'::regprocedure
  ) INTO v_definition;
  v_definition := replace(
    v_definition,
    'FUNCTION public.record_attendance_gps_v2(',
    'FUNCTION public.record_attendance_gps_v2_legacy_20260805('
  );
  EXECUTE v_definition;

  SELECT pg_get_functiondef(
    'public.upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)'::regprocedure
  ) INTO v_definition;
  v_definition := replace(
    v_definition,
    'FUNCTION public.upsert_attendance_and_reprocess(',
    'FUNCTION public.upsert_attendance_and_reprocess_legacy_20260805('
  );
  EXECUTE v_definition;

  SELECT pg_get_functiondef(
    'public.is_employee_work_day(uuid,date)'::regprocedure
  ) INTO v_definition;
  v_definition := replace(
    v_definition,
    'FUNCTION public.is_employee_work_day(',
    'FUNCTION public.is_employee_work_day_legacy_20260805('
  );
  EXECUTE v_definition;
END;
$clone_legacy$;

REVOKE ALL ON FUNCTION public.record_attendance_gps_v2_legacy_20260805(NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.upsert_attendance_and_reprocess_legacy_20260805(UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ, public.hr_attendance_status, TEXT, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.is_employee_work_day_legacy_20260805(UUID, DATE)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.record_attendance_gps_v2_legacy_20260805(NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ) IS
  'Internal exact pre-M3A production implementation. Used only while employee work schedules are disabled.';
COMMENT ON FUNCTION public.upsert_attendance_and_reprocess_legacy_20260805(UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ, public.hr_attendance_status, TEXT, UUID) IS
  'Internal exact pre-M3A production implementation. Used only while employee work schedules are disabled.';
COMMENT ON FUNCTION public.is_employee_work_day_legacy_20260805(UUID, DATE) IS
  'Internal exact pre-M3A production implementation. Used only while employee work schedules are disabled.';

-- ----------------------------------------------------------------------------
-- 2. Schedule-aware GPS implementation.
--    Existing GPS/location/manual-lock semantics are preserved.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.record_attendance_gps_v2_scheduled(
  p_latitude      NUMERIC,
  p_longitude     NUMERIC,
  p_gps_accuracy  NUMERIC,
  p_log_type      TEXT,
  p_event_time    TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_employee           public.hr_employees%ROWTYPE;
  v_event_time         TIMESTAMPTZ := COALESCE(p_event_time, now());
  v_shift_date         DATE := (COALESCE(p_event_time, now()) AT TIME ZONE 'Africa/Cairo')::DATE;
  v_day                public.hr_attendance_days%ROWTYPE;
  v_day_exists         BOOLEAN := false;
  v_ctx                JSONB;
  v_location_id        UUID;
  v_location_name      TEXT;
  v_late_grace         INTEGER := 15;
  v_scheduled_start    TIMESTAMPTZ;
  v_scheduled_end      TIMESTAMPTZ;
  v_scheduled_minutes  INTEGER;
  v_schedule_day_kind  TEXT;
  v_schedule_source    TEXT;
  v_work_schedule_id   UUID;
  v_schedule_snapshot_at TIMESTAMPTZ;
  v_is_working_day     BOOLEAN;
  v_late_minutes       INTEGER := 0;
  v_early_minutes      INTEGER := 0;
  v_overtime_minutes   INTEGER := 0;
  v_effective_hours    NUMERIC(5,2) := NULL;
  v_checkout_status    public.hr_checkout_status := NULL;
  v_attendance_status  public.hr_attendance_status := 'present';
  v_day_id             UUID;
  v_log_id             UUID;
  v_tracking_status    TEXT := 'idle';
  v_penalties_count    INTEGER := 0;
  v_accuracy_threshold NUMERIC;
  v_location_threshold NUMERIC;
  v_default_threshold  NUMERIC := 100;
BEGIN
  IF p_log_type NOT IN ('check_in', 'check_out') THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_LOG_TYPE', 'error', 'نوع الحركة غير مدعوم');
  END IF;

  SELECT * INTO v_employee
  FROM public.hr_employees
  WHERE user_id = auth.uid()
    AND status = 'active';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_EMPLOYEE', 'error', 'حسابك غير مرتبط بموظف نشط');
  END IF;

  IF v_event_time > now() + INTERVAL '5 minutes' THEN
    RETURN jsonb_build_object('success', false, 'code', 'FUTURE_TIME', 'error', 'لا يمكن تسجيل حدث في المستقبل');
  END IF;

  IF v_event_time < now() - INTERVAL '24 hours' THEN
    RETURN jsonb_build_object('success', false, 'code', 'TOO_OLD', 'error', 'الحدث أقدم من المسموح به');
  END IF;

  SELECT * INTO v_day
  FROM public.hr_attendance_days
  WHERE employee_id = v_employee.id
    AND shift_date = v_shift_date;

  v_day_exists := FOUND;

  IF v_day_exists AND COALESCE(v_day.is_manually_locked, false) THEN
    RETURN jsonb_build_object('success', false, 'code', 'MANUALLY_LOCKED', 'error', 'هذا اليوم مقفل إدارياً ولا يمكن تعديله آلياً');
  END IF;

  IF p_log_type = 'check_in' THEN
    IF v_day_exists AND v_day.punch_in_time IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'ALREADY_CHECKED_IN', 'error', 'لقد سجلت حضورك بالفعل اليوم');
    END IF;
  ELSE
    IF NOT v_day_exists OR v_day.punch_in_time IS NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'NOT_CHECKED_IN', 'error', 'يجب تسجيل الحضور أولاً');
    END IF;

    IF v_day.punch_out_time IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'ALREADY_CHECKED_OUT', 'error', 'لقد سجلت انصرافك بالفعل اليوم');
    END IF;
  END IF;

  v_ctx := public.resolve_employee_attendance_location_context(
    v_employee.id,
    p_latitude,
    p_longitude,
    p_log_type
  );

  IF COALESCE((v_ctx->>'valid')::BOOLEAN, false) = false THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', v_ctx->>'code',
      'error', v_ctx->>'error',
      'nearest_location', v_ctx->>'location_name',
      'distance_meters', NULLIF(v_ctx->>'distance_meters', '')::NUMERIC
    );
  END IF;

  v_location_id := NULLIF(v_ctx->>'location_id', '')::UUID;
  v_location_name := v_ctx->>'location_name';

  SELECT COALESCE(value::NUMERIC, 100)
  INTO v_default_threshold
  FROM public.company_settings
  WHERE key = 'hr.default_gps_accuracy_threshold_meters';

  IF v_location_id IS NOT NULL THEN
    SELECT gps_accuracy_threshold
    INTO v_location_threshold
    FROM public.hr_work_locations
    WHERE id = v_location_id;
  END IF;

  v_accuracy_threshold := COALESCE(v_location_threshold, v_default_threshold, 100);

  IF COALESCE(p_gps_accuracy, 0) > v_accuracy_threshold THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'LOW_GPS_ACCURACY',
      'error', format(
        'دقة GPS غير كافية. الدقة الحالية ±%s متر والمطلوب ±%s متر أو أفضل',
        round(p_gps_accuracy),
        round(v_accuracy_threshold)
      ),
      'required_accuracy', v_accuracy_threshold,
      'actual_accuracy', p_gps_accuracy,
      'location_name', v_location_name
    );
  END IF;

  SELECT COALESCE(value::INTEGER, 15)
  INTO v_late_grace
  FROM public.company_settings
  WHERE key = 'hr.late_grace_minutes';

  -- Existing rows reuse their immutable snapshot. Missing legacy snapshots are
  -- created only through the fail-closed M2 helper.
  IF v_day_exists THEN
    IF v_day.schedule_snapshot_at IS NULL THEN
      PERFORM public.ensure_attendance_schedule_snapshot(v_day.id);

      SELECT * INTO v_day
      FROM public.hr_attendance_days
      WHERE id = v_day.id;
    END IF;

    v_schedule_day_kind := v_day.schedule_day_kind;
    v_scheduled_start := v_day.scheduled_start_at;
    v_scheduled_end := v_day.scheduled_end_at;
    v_scheduled_minutes := v_day.scheduled_minutes;
    v_schedule_source := v_day.schedule_source;
    v_work_schedule_id := v_day.work_schedule_id;
    v_schedule_snapshot_at := v_day.schedule_snapshot_at;
  ELSE
    SELECT
      r.day_kind,
      r.scheduled_start_at,
      r.scheduled_end_at,
      r.scheduled_minutes,
      r.schedule_source,
      r.work_schedule_id
    INTO
      v_schedule_day_kind,
      v_scheduled_start,
      v_scheduled_end,
      v_scheduled_minutes,
      v_schedule_source,
      v_work_schedule_id
    FROM public.resolve_employee_work_schedule(v_employee.id, v_shift_date) r;

    v_schedule_snapshot_at := now();
  END IF;

  v_is_working_day := v_schedule_day_kind = 'work_day';

  IF p_log_type = 'check_in' THEN
    IF v_is_working_day THEN
      v_late_minutes := GREATEST(
        0,
        FLOOR(EXTRACT(EPOCH FROM (v_event_time - v_scheduled_start)) / 60)::INTEGER - v_late_grace
      );
    ELSE
      v_late_minutes := 0;
    END IF;

    IF v_day_exists AND v_day.status = 'on_leave' THEN
      v_attendance_status := 'on_leave';
    ELSE
      v_attendance_status := CASE
        WHEN v_late_minutes > 0 THEN 'late'::public.hr_attendance_status
        ELSE 'present'::public.hr_attendance_status
      END;
    END IF;

    v_tracking_status := 'active';

    INSERT INTO public.hr_attendance_days (
      employee_id,
      shift_date,
      work_date,
      punch_in_time,
      location_in_id,
      gps_accuracy_in,
      status,
      late_minutes,
      review_status,
      tracking_started_at,
      last_tracking_ping_at,
      last_tracking_lat,
      last_tracking_lng,
      last_tracking_accuracy,
      tracking_status,
      tracking_ping_count,
      schedule_day_kind,
      scheduled_start_at,
      scheduled_end_at,
      scheduled_minutes,
      schedule_source,
      work_schedule_id,
      schedule_snapshot_at
    ) VALUES (
      v_employee.id,
      v_shift_date,
      v_shift_date,
      v_event_time,
      v_location_id,
      LEAST(COALESCE(p_gps_accuracy, 0), 999999.99),
      v_attendance_status,
      v_late_minutes,
      CASE WHEN v_is_working_day THEN 'ok'::public.hr_review_status ELSE 'needs_review'::public.hr_review_status END,
      v_event_time,
      v_event_time,
      p_latitude,
      p_longitude,
      LEAST(COALESCE(p_gps_accuracy, 0), 999999.99),
      'active',
      1,
      v_schedule_day_kind,
      v_scheduled_start,
      v_scheduled_end,
      v_scheduled_minutes,
      v_schedule_source,
      v_work_schedule_id,
      v_schedule_snapshot_at
    )
    ON CONFLICT (employee_id, shift_date)
    DO UPDATE SET
      punch_in_time = EXCLUDED.punch_in_time,
      work_date = EXCLUDED.work_date,
      location_in_id = EXCLUDED.location_in_id,
      gps_accuracy_in = EXCLUDED.gps_accuracy_in,
      status = EXCLUDED.status,
      late_minutes = EXCLUDED.late_minutes,
      review_status = CASE
        WHEN public.hr_attendance_days.review_status = 'reviewed' THEN 'reviewed'::public.hr_review_status
        WHEN EXCLUDED.schedule_day_kind <> 'work_day' THEN 'needs_review'::public.hr_review_status
        ELSE 'ok'::public.hr_review_status
      END,
      tracking_started_at = COALESCE(public.hr_attendance_days.tracking_started_at, EXCLUDED.tracking_started_at),
      last_tracking_ping_at = EXCLUDED.last_tracking_ping_at,
      last_tracking_lat = EXCLUDED.last_tracking_lat,
      last_tracking_lng = EXCLUDED.last_tracking_lng,
      last_tracking_accuracy = EXCLUDED.last_tracking_accuracy,
      tracking_status = 'active',
      tracking_ping_count = GREATEST(public.hr_attendance_days.tracking_ping_count, 1),
      schedule_day_kind = COALESCE(public.hr_attendance_days.schedule_day_kind, EXCLUDED.schedule_day_kind),
      scheduled_start_at = COALESCE(public.hr_attendance_days.scheduled_start_at, EXCLUDED.scheduled_start_at),
      scheduled_end_at = COALESCE(public.hr_attendance_days.scheduled_end_at, EXCLUDED.scheduled_end_at),
      scheduled_minutes = COALESCE(public.hr_attendance_days.scheduled_minutes, EXCLUDED.scheduled_minutes),
      schedule_source = COALESCE(public.hr_attendance_days.schedule_source, EXCLUDED.schedule_source),
      work_schedule_id = COALESCE(public.hr_attendance_days.work_schedule_id, EXCLUDED.work_schedule_id),
      schedule_snapshot_at = COALESCE(public.hr_attendance_days.schedule_snapshot_at, EXCLUDED.schedule_snapshot_at),
      updated_at = now()
    RETURNING id INTO v_day_id;
  ELSE
    v_effective_hours := ROUND(
      (EXTRACT(EPOCH FROM (v_event_time - v_day.punch_in_time)) / 3600)::NUMERIC,
      2
    );

    IF v_is_working_day THEN
      v_early_minutes := GREATEST(
        0,
        FLOOR(EXTRACT(EPOCH FROM (v_scheduled_end - v_event_time)) / 60)::INTEGER
      );
      v_overtime_minutes := GREATEST(
        0,
        FLOOR(EXTRACT(EPOCH FROM (v_event_time - v_scheduled_end)) / 60)::INTEGER
      );

      IF v_overtime_minutes > 0 THEN
        v_checkout_status := 'overtime';
      ELSIF v_early_minutes > 0 THEN
        IF EXISTS (
          SELECT 1 FROM public.hr_leave_requests
          WHERE employee_id = v_employee.id
            AND start_date <= v_shift_date
            AND end_date >= v_shift_date
            AND status = 'approved'
        ) OR EXISTS (
          SELECT 1 FROM public.hr_permission_requests
          WHERE employee_id = v_employee.id
            AND permission_date = v_shift_date
            AND status = 'approved'
        ) THEN
          v_checkout_status := 'early_authorized';
        ELSE
          v_checkout_status := 'early_unauthorized';
        END IF;
      ELSE
        v_checkout_status := 'on_time';
      END IF;
    ELSE
      -- Unscheduled/off-day work is an administrative decision. Do not create
      -- automatic overtime or a deduction from an undefined working window.
      v_early_minutes := 0;
      v_overtime_minutes := 0;
      v_checkout_status := 'on_time';
    END IF;

    v_tracking_status := 'ended';

    UPDATE public.hr_attendance_days
    SET punch_out_time = v_event_time,
        location_out_id = v_location_id,
        gps_accuracy_out = LEAST(COALESCE(p_gps_accuracy, 0), 999999.99),
        checkout_status = v_checkout_status,
        early_leave_minutes = v_early_minutes,
        overtime_minutes = v_overtime_minutes,
        effective_hours = v_effective_hours,
        tracking_ended_at = v_event_time,
        tracking_status = 'ended',
        last_tracking_ping_at = v_event_time,
        last_tracking_lat = p_latitude,
        last_tracking_lng = p_longitude,
        last_tracking_accuracy = LEAST(COALESCE(p_gps_accuracy, 0), 999999.99),
        review_status = CASE
          WHEN review_status = 'reviewed' THEN 'reviewed'::public.hr_review_status
          WHEN v_is_working_day THEN review_status
          ELSE 'needs_review'::public.hr_review_status
        END,
        updated_at = now()
    WHERE id = v_day.id
    RETURNING id INTO v_day_id;

    IF v_is_working_day THEN
      PERFORM public.settle_attendance_day_against_leave(v_day_id);

      SELECT public.reprocess_attendance_day_penalties(v_day_id)
      INTO v_penalties_count;
    ELSE
      v_penalties_count := 0;
    END IF;
  END IF;

  INSERT INTO public.hr_attendance_logs (
    employee_id,
    attendance_day_id,
    log_type,
    latitude,
    longitude,
    gps_accuracy,
    location_id,
    event_time,
    synced_at,
    requires_review
  ) VALUES (
    v_employee.id,
    v_day_id,
    p_log_type,
    p_latitude,
    p_longitude,
    LEAST(COALESCE(p_gps_accuracy, 0), 999999.99),
    v_location_id,
    v_event_time,
    now(),
    NOT v_is_working_day
  )
  RETURNING id INTO v_log_id;

  RETURN jsonb_build_object(
    'success', true,
    'action', p_log_type,
    'attendance_day_id', v_day_id,
    'log_id', v_log_id,
    'location_name', v_location_name,
    'location_id', v_location_id,
    'shift_date', v_shift_date,
    'event_time', v_event_time,
    'tracking_status', v_tracking_status,
    'penalties_applied', CASE WHEN p_log_type = 'check_out' THEN v_penalties_count ELSE NULL END
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.record_attendance_gps_v2_scheduled(NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ)
  FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3. Schedule-aware administrative attendance correction.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.upsert_attendance_and_reprocess_scheduled(
  p_employee_id    UUID,
  p_shift_date     DATE,
  p_punch_in_time  TIMESTAMPTZ DEFAULT NULL,
  p_punch_out_time TIMESTAMPTZ DEFAULT NULL,
  p_status         public.hr_attendance_status DEFAULT NULL,
  p_notes          TEXT DEFAULT NULL,
  p_user_id        UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_day_id UUID;
  v_existing public.hr_attendance_days%ROWTYPE;
  v_existing_found BOOLEAN := false;
  v_new_eff_hours NUMERIC;
  v_new_late_min INTEGER := 0;
  v_new_early_min INTEGER := 0;
  v_new_ot_min INTEGER := 0;
  v_new_status public.hr_attendance_status;
  v_new_co_status public.hr_checkout_status;
  v_grace_min INTEGER;
  v_sched_start TIMESTAMPTZ;
  v_sched_end TIMESTAMPTZ;
  v_scheduled_minutes INTEGER;
  v_schedule_day_kind TEXT;
  v_schedule_source TEXT;
  v_work_schedule_id UUID;
  v_schedule_snapshot_at TIMESTAMPTZ;
  v_is_working_day BOOLEAN;
  v_penalties_count INTEGER := 0;
  v_payroll_status TEXT;
BEGIN
  IF NOT public.check_permission(COALESCE(p_user_id, auth.uid()), 'hr.attendance.create') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تعديل الحضور';
  END IF;

  SELECT pr.status::TEXT
  INTO v_payroll_status
  FROM public.hr_payroll_lines pl
  JOIN public.hr_payroll_runs pr ON pr.id = pl.payroll_run_id
  WHERE pl.employee_id = p_employee_id
    AND pr.period_id IN (
      SELECT id
      FROM public.hr_payroll_periods
      WHERE p_shift_date BETWEEN start_date AND end_date
    );

  IF v_payroll_status IN ('approved', 'paid') THEN
    RAISE EXCEPTION 'لا يمكن تعديل الحضور لليوم % لأنه مرتبط بمسير رواتب في حالة %', p_shift_date, v_payroll_status;
  END IF;

  SELECT * INTO v_existing
  FROM public.hr_attendance_days
  WHERE employee_id = p_employee_id
    AND shift_date = p_shift_date
  FOR UPDATE;

  v_existing_found := FOUND;

  IF v_existing_found THEN
    IF v_existing.schedule_snapshot_at IS NULL THEN
      PERFORM public.ensure_attendance_schedule_snapshot(v_existing.id);

      SELECT * INTO v_existing
      FROM public.hr_attendance_days
      WHERE id = v_existing.id;
    END IF;

    v_schedule_day_kind := v_existing.schedule_day_kind;
    v_sched_start := v_existing.scheduled_start_at;
    v_sched_end := v_existing.scheduled_end_at;
    v_scheduled_minutes := v_existing.scheduled_minutes;
    v_schedule_source := v_existing.schedule_source;
    v_work_schedule_id := v_existing.work_schedule_id;
    v_schedule_snapshot_at := v_existing.schedule_snapshot_at;
  ELSE
    SELECT
      r.day_kind,
      r.scheduled_start_at,
      r.scheduled_end_at,
      r.scheduled_minutes,
      r.schedule_source,
      r.work_schedule_id
    INTO
      v_schedule_day_kind,
      v_sched_start,
      v_sched_end,
      v_scheduled_minutes,
      v_schedule_source,
      v_work_schedule_id
    FROM public.resolve_employee_work_schedule(p_employee_id, p_shift_date) r;

    v_schedule_snapshot_at := now();
  END IF;

  v_is_working_day := v_schedule_day_kind = 'work_day';
  v_new_status := COALESCE(p_status, 'present'::public.hr_attendance_status);
  v_new_co_status := NULL;

  IF NOT v_is_working_day
     AND v_new_status IN ('absent_unauthorized', 'absent_authorized') THEN
    RAISE EXCEPTION 'لا يمكن تسجيل غياب في يوم غير مقرر للعمل؛ راجع جدول الموظف';
  END IF;

  SELECT COALESCE(value::INTEGER, 15)
  INTO v_grace_min
  FROM public.company_settings
  WHERE key = 'hr.late_grace_minutes';

  IF p_punch_in_time IS NOT NULL AND p_punch_out_time IS NOT NULL THEN
    v_new_eff_hours := LEAST(
      ROUND(EXTRACT(EPOCH FROM (p_punch_out_time - p_punch_in_time)) / 3600.0, 2),
      24.00
    );

    IF v_is_working_day THEN
      IF p_punch_in_time > v_sched_start + (v_grace_min || ' minutes')::INTERVAL THEN
        v_new_late_min := EXTRACT(EPOCH FROM (p_punch_in_time - v_sched_start))::INTEGER / 60;
        IF v_new_late_min > 0 THEN
          v_new_status := 'late';
        END IF;
      END IF;

      IF p_punch_out_time > v_sched_end + INTERVAL '30 minutes' THEN
        v_new_ot_min := EXTRACT(EPOCH FROM (p_punch_out_time - v_sched_end))::INTEGER / 60;
        v_new_co_status := 'overtime';
      ELSIF p_punch_out_time < v_sched_end - INTERVAL '5 minutes' THEN
        v_new_early_min := EXTRACT(EPOCH FROM (v_sched_end - p_punch_out_time))::INTEGER / 60;

        IF EXISTS (
          SELECT 1 FROM public.hr_leave_requests
          WHERE employee_id = p_employee_id
            AND start_date <= p_shift_date
            AND end_date >= p_shift_date
            AND status = 'approved'
        ) OR EXISTS (
          SELECT 1 FROM public.hr_permission_requests
          WHERE employee_id = p_employee_id
            AND permission_date = p_shift_date
            AND status = 'approved'
        ) THEN
          v_new_co_status := 'early_authorized';
        ELSE
          v_new_co_status := 'early_unauthorized';
        END IF;
      ELSE
        v_new_co_status := 'on_time';
      END IF;
    ELSE
      v_new_late_min := 0;
      v_new_early_min := 0;
      v_new_ot_min := 0;
      v_new_co_status := 'on_time';
    END IF;
  ELSIF p_punch_in_time IS NOT NULL THEN
    IF v_is_working_day
       AND p_punch_in_time > v_sched_start + (v_grace_min || ' minutes')::INTERVAL THEN
      v_new_late_min := EXTRACT(EPOCH FROM (p_punch_in_time - v_sched_start))::INTEGER / 60;
      v_new_status := 'late';
    END IF;
  END IF;

  INSERT INTO public.hr_attendance_days (
    employee_id,
    shift_date,
    work_date,
    punch_in_time,
    punch_out_time,
    status,
    checkout_status,
    late_minutes,
    early_leave_minutes,
    overtime_minutes,
    effective_hours,
    day_value,
    notes,
    review_status,
    is_manually_locked,
    schedule_day_kind,
    scheduled_start_at,
    scheduled_end_at,
    scheduled_minutes,
    schedule_source,
    work_schedule_id,
    schedule_snapshot_at
  ) VALUES (
    p_employee_id,
    p_shift_date,
    p_shift_date,
    p_punch_in_time,
    p_punch_out_time,
    v_new_status,
    v_new_co_status,
    v_new_late_min,
    v_new_early_min,
    v_new_ot_min,
    v_new_eff_hours,
    CASE v_new_status
      WHEN 'half_day' THEN 0.5
      WHEN 'absent_unauthorized' THEN 0
      WHEN 'absent_authorized' THEN 0
      ELSE 1.0
    END,
    p_notes,
    'reviewed',
    true,
    v_schedule_day_kind,
    v_sched_start,
    v_sched_end,
    v_scheduled_minutes,
    v_schedule_source,
    v_work_schedule_id,
    v_schedule_snapshot_at
  )
  ON CONFLICT (employee_id, shift_date)
  DO UPDATE SET
    punch_in_time = EXCLUDED.punch_in_time,
    punch_out_time = EXCLUDED.punch_out_time,
    status = EXCLUDED.status,
    checkout_status = EXCLUDED.checkout_status,
    late_minutes = EXCLUDED.late_minutes,
    early_leave_minutes = EXCLUDED.early_leave_minutes,
    overtime_minutes = EXCLUDED.overtime_minutes,
    effective_hours = EXCLUDED.effective_hours,
    day_value = EXCLUDED.day_value,
    notes = EXCLUDED.notes,
    review_status = 'reviewed',
    is_manually_locked = true,
    reviewed_by = COALESCE(p_user_id, auth.uid()),
    reviewed_at = now(),
    schedule_day_kind = COALESCE(public.hr_attendance_days.schedule_day_kind, EXCLUDED.schedule_day_kind),
    scheduled_start_at = COALESCE(public.hr_attendance_days.scheduled_start_at, EXCLUDED.scheduled_start_at),
    scheduled_end_at = COALESCE(public.hr_attendance_days.scheduled_end_at, EXCLUDED.scheduled_end_at),
    scheduled_minutes = COALESCE(public.hr_attendance_days.scheduled_minutes, EXCLUDED.scheduled_minutes),
    schedule_source = COALESCE(public.hr_attendance_days.schedule_source, EXCLUDED.schedule_source),
    work_schedule_id = COALESCE(public.hr_attendance_days.work_schedule_id, EXCLUDED.work_schedule_id),
    schedule_snapshot_at = COALESCE(public.hr_attendance_days.schedule_snapshot_at, EXCLUDED.schedule_snapshot_at),
    updated_at = now()
  RETURNING id INTO v_day_id;

  IF v_is_working_day THEN
    PERFORM public.settle_attendance_day_against_leave(v_day_id, true);

    SELECT public.reprocess_attendance_day_penalties(v_day_id)
    INTO v_penalties_count;
  ELSE
    v_penalties_count := 0;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'attendance_day_id', v_day_id,
    'status', v_new_status,
    'checkout_status', v_new_co_status,
    'late_minutes', v_new_late_min,
    'early_leave_minutes', v_new_early_min,
    'overtime_minutes', v_new_ot_min,
    'effective_hours', v_new_eff_hours,
    'penalties_applied', v_penalties_count,
    'message', format('تم تحديث الحضور إدارياً وتم قفل اليوم — %s جزاء/ات أُعيد حسابه', v_penalties_count)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.upsert_attendance_and_reprocess_scheduled(UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ, public.hr_attendance_status, TEXT, UUID)
  FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 4. Public wrappers. Disabled mode is the exact production implementation.
-- ----------------------------------------------------------------------------
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

  RETURN public.record_attendance_gps_v2_scheduled(
    p_latitude,
    p_longitude,
    p_gps_accuracy,
    p_log_type,
    p_event_time
  );
END;
$function$;

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
BEGIN
  IF NOT public.hr_employee_work_schedules_enabled() THEN
    RETURN public.upsert_attendance_and_reprocess_legacy_20260805(
      p_employee_id,
      p_shift_date,
      p_punch_in_time,
      p_punch_out_time,
      p_status,
      p_notes,
      p_user_id
    );
  END IF;

  RETURN public.upsert_attendance_and_reprocess_scheduled(
    p_employee_id,
    p_shift_date,
    p_punch_in_time,
    p_punch_out_time,
    p_status,
    p_notes,
    p_user_id
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.is_employee_work_day(
  p_employee_id UUID,
  p_date DATE
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_day_kind TEXT;
BEGIN
  IF NOT public.hr_employee_work_schedules_enabled() THEN
    RETURN public.is_employee_work_day_legacy_20260805(p_employee_id, p_date);
  END IF;

  SELECT r.day_kind
  INTO v_day_kind
  FROM public.resolve_employee_work_schedule(p_employee_id, p_date) r;

  RETURN v_day_kind;
END;
$function$;

-- CREATE OR REPLACE preserves the current public RPC ACLs. Reassert the
-- expected application access explicitly and keep internal helpers private.
GRANT EXECUTE ON FUNCTION public.record_attendance_gps_v2(NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.upsert_attendance_and_reprocess(UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ, public.hr_attendance_status, TEXT, UUID)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_employee_work_day(UUID, DATE)
  TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5. In-transaction assertions
-- ----------------------------------------------------------------------------
DO $assertions$
DECLARE
  v_definition TEXT;
  v_hash TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'M3A assertion failed: feature switch became enabled';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'M3A assertion failed: migration must not seed schedules';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.hr_attendance_days
    WHERE schedule_snapshot_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'M3A assertion failed: migration must not mutate attendance';
  END IF;

  SELECT pg_get_functiondef(
    'public.record_attendance_gps_v2(numeric,numeric,numeric,text,timestamp with time zone)'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%hr_employee_work_schedules_enabled%'
     OR v_definition NOT ILIKE '%record_attendance_gps_v2_legacy_20260805%'
     OR v_definition NOT ILIKE '%record_attendance_gps_v2_scheduled%' THEN
    RAISE EXCEPTION 'M3A assertion failed: GPS v2 wrapper is incomplete';
  END IF;

  SELECT pg_get_functiondef(
    'public.upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%hr_employee_work_schedules_enabled%'
     OR v_definition NOT ILIKE '%upsert_attendance_and_reprocess_legacy_20260805%'
     OR v_definition NOT ILIKE '%upsert_attendance_and_reprocess_scheduled%' THEN
    RAISE EXCEPTION 'M3A assertion failed: manual attendance wrapper is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.is_employee_work_day(uuid,date)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%hr_employee_work_schedules_enabled%'
     OR v_definition NOT ILIKE '%is_employee_work_day_legacy_20260805%'
     OR v_definition NOT ILIKE '%resolve_employee_work_schedule%' THEN
    RAISE EXCEPTION 'M3A assertion failed: work-day wrapper is incomplete';
  END IF;

  -- M3A deliberately does not alter the old GPS RPC.
  SELECT md5(pg_get_functiondef(
    'public.record_attendance_gps(numeric,numeric,numeric,text,timestamp with time zone)'::regprocedure
  )) INTO v_hash;
  IF v_hash <> '41f47aaff1eced8e368bce61cbd7a1a4' THEN
    RAISE EXCEPTION 'M3A assertion failed: legacy GPS RPC changed (%)', v_hash;
  END IF;

  IF has_function_privilege('authenticated', 'public.record_attendance_gps_v2_scheduled(numeric,numeric,numeric,text,timestamp with time zone)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.record_attendance_gps_v2_legacy_20260805(numeric,numeric,numeric,text,timestamp with time zone)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.upsert_attendance_and_reprocess_scheduled(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.upsert_attendance_and_reprocess_legacy_20260805(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'M3A assertion failed: an internal helper is exposed';
  END IF;
END;
$assertions$;

COMMIT;
