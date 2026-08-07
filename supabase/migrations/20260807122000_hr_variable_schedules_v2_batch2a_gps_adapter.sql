-- HR Variable Schedules V2 — Batch 2A
-- GPS attendance adapter only.
--
-- Safety model:
--   * the public RPC name/signature is preserved;
--   * the exact current production implementation is renamed and retained as Legacy;
--   * a fail-closed runtime gate returns FALSE, so installed code still executes Legacy
--     before performing any custom-schedule lookup;
--   * only a later release gate may make the custom path reachable;
--   * no existing attendance row is backfilled.

BEGIN;

-- Refuse to overwrite a production function that drifted after Batch 0 capture.
DO $guard$
DECLARE
  v_hash text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid))
  INTO v_hash
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'record_attendance_gps_v2'
    AND pg_get_function_identity_arguments(p.oid) =
      'p_latitude numeric, p_longitude numeric, p_gps_accuracy numeric, p_log_type text, p_event_time timestamp with time zone';

  IF v_hash IS DISTINCT FROM 'bd70c45984e188a38cceb45eea00fa00' THEN
    RAISE EXCEPTION 'Batch 2A baseline mismatch for record_attendance_gps_v2; review production drift before applying';
  END IF;

  IF to_regprocedure('public.record_attendance_gps_v2_legacy(numeric,numeric,numeric,text,timestamp with time zone)') IS NOT NULL
     OR to_regprocedure('public.record_attendance_gps_v2_custom_schedule(numeric,numeric,numeric,text,timestamp with time zone)') IS NOT NULL THEN
    RAISE EXCEPTION 'Batch 2A helper function name collision';
  END IF;
END;
$guard$;

-- Nullable snapshot fields. Existing rows remain all-NULL and are not reinterpreted.
ALTER TABLE public.hr_attendance_days
  ADD COLUMN custom_schedule_id uuid NULL
    REFERENCES public.hr_employee_work_schedules(id) ON DELETE RESTRICT,
  ADD COLUMN custom_scheduled_start time without time zone NULL,
  ADD COLUMN custom_scheduled_end time without time zone NULL,
  ADD COLUMN custom_scheduled_minutes integer NULL;

ALTER TABLE public.hr_attendance_days
  ADD CONSTRAINT hr_attendance_days_custom_schedule_snapshot_chk
  CHECK (
    (
      custom_schedule_id IS NULL
      AND custom_scheduled_start IS NULL
      AND custom_scheduled_end IS NULL
      AND custom_scheduled_minutes IS NULL
    )
    OR
    (
      custom_schedule_id IS NOT NULL
      AND custom_scheduled_minutes IS NOT NULL
      AND custom_scheduled_minutes >= 0
      AND (
        (
          custom_scheduled_minutes = 0
          AND custom_scheduled_start IS NULL
          AND custom_scheduled_end IS NULL
        )
        OR
        (
          custom_scheduled_minutes > 0
          AND custom_scheduled_start IS NOT NULL
          AND custom_scheduled_end IS NOT NULL
          AND custom_scheduled_end > custom_scheduled_start
        )
      )
    )
  );

COMMENT ON COLUMN public.hr_attendance_days.custom_schedule_id IS
  'V2 snapshot reference. NULL means this attendance row was not processed using a custom employee schedule.';
COMMENT ON COLUMN public.hr_attendance_days.custom_scheduled_start IS
  'V2 custom start-time snapshot; populated only when a custom working day governed this attendance row.';
COMMENT ON COLUMN public.hr_attendance_days.custom_scheduled_end IS
  'V2 custom end-time snapshot; populated only when a custom working day governed this attendance row.';
COMMENT ON COLUMN public.hr_attendance_days.custom_scheduled_minutes IS
  'V2 official custom minutes snapshot. Zero represents a custom non-working weekday.';

-- Fail closed during development. Release activation is a separate batch.
CREATE OR REPLACE FUNCTION public.hr_variable_schedules_v2_runtime_enabled()
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT false;
$function$;

COMMENT ON FUNCTION public.hr_variable_schedules_v2_runtime_enabled() IS
  'Fail-closed V2 runtime gate. Must remain false until the separately reviewed release gate.';

REVOKE ALL ON FUNCTION public.hr_variable_schedules_v2_runtime_enabled() FROM PUBLIC, anon, authenticated, service_role;

-- Keep the exact current implementation as the authoritative Legacy path.
ALTER FUNCTION public.record_attendance_gps_v2(
  numeric, numeric, numeric, text, timestamp with time zone
) RENAME TO record_attendance_gps_v2_legacy;

-- The alias did not exist previously and must not become a new externally callable RPC.
REVOKE ALL ON FUNCTION public.record_attendance_gps_v2_legacy(
  numeric, numeric, numeric, text, timestamp with time zone
) FROM PUBLIC, anon, authenticated, service_role;

-- Custom-only implementation. Unrelated GPS, location, tracking, leave and penalty
-- behavior intentionally follows the captured Legacy implementation.
CREATE OR REPLACE FUNCTION public.record_attendance_gps_v2_custom_schedule(
  p_latitude numeric,
  p_longitude numeric,
  p_gps_accuracy numeric,
  p_log_type text,
  p_event_time timestamp with time zone DEFAULT NULL::timestamp with time zone
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_employee           hr_employees%ROWTYPE;
  v_event_time         timestamptz := COALESCE(p_event_time, now());
  v_shift_date         date := (COALESCE(p_event_time, now()) AT TIME ZONE 'Africa/Cairo')::date;
  v_day                hr_attendance_days%ROWTYPE;
  v_day_exists         boolean := false;
  v_ctx                jsonb;
  v_location_id        uuid;
  v_location_name      text;
  v_late_grace         integer := 15;
  v_work_start         time;
  v_work_end           time;
  v_scheduled_start    timestamptz;
  v_scheduled_end      timestamptz;
  v_late_minutes       integer := 0;
  v_early_minutes      integer := 0;
  v_overtime_minutes   integer := 0;
  v_effective_hours    numeric(5,2) := NULL;
  v_checkout_status    hr_checkout_status := NULL;
  v_attendance_status  hr_attendance_status := 'present';
  v_day_id             uuid;
  v_log_id             uuid;
  v_tracking_status    text := 'idle';
  v_penalties_count    integer := 0;
  v_accuracy_threshold numeric;
  v_location_threshold numeric;
  v_default_threshold  numeric := 100;
  v_schedule           record;
  v_schedule_id        uuid;
  v_scheduled_minutes  integer;
  v_custom_working_day boolean;
BEGIN
  IF p_log_type NOT IN ('check_in', 'check_out') THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_LOG_TYPE', 'error', 'نوع الحركة غير مدعوم');
  END IF;

  SELECT * INTO v_employee
  FROM hr_employees
  WHERE user_id = auth.uid() AND status = 'active';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_EMPLOYEE', 'error', 'حسابك غير مرتبط بموظف نشط');
  END IF;

  IF v_event_time > now() + interval '5 minutes' THEN
    RETURN jsonb_build_object('success', false, 'code', 'FUTURE_TIME', 'error', 'لا يمكن تسجيل حدث في المستقبل');
  END IF;

  IF v_event_time < now() - interval '24 hours' THEN
    RETURN jsonb_build_object('success', false, 'code', 'TOO_OLD', 'error', 'الحدث أقدم من المسموح به');
  END IF;

  SELECT * INTO v_day
  FROM hr_attendance_days
  WHERE employee_id = v_employee.id AND shift_date = v_shift_date;

  v_day_exists := FOUND;

  IF v_day_exists AND COALESCE(v_day.is_manually_locked, false) = true THEN
    RETURN jsonb_build_object('success', false, 'code', 'MANUALLY_LOCKED', 'error', 'هذا اليوم مقفل إدارياً ولا يمكن تعديله آلياً');
  END IF;

  SELECT * INTO v_schedule
  FROM public.resolve_employee_custom_schedule(v_employee.id, v_shift_date);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'V2 custom GPS path invoked without a complete effective custom schedule';
  END IF;

  v_schedule_id := v_schedule.schedule_id;
  v_custom_working_day := v_schedule.is_working_day;
  v_scheduled_minutes := v_schedule.scheduled_minutes;
  v_work_start := v_schedule.start_time;
  v_work_end := v_schedule.end_time;

  -- If check-in already snapshotted the custom context, checkout uses that immutable
  -- interpretation rather than reinterpreting the day from current schedule rows.
  IF p_log_type = 'check_out' AND v_day_exists AND v_day.custom_schedule_id IS NOT NULL THEN
    v_schedule_id := v_day.custom_schedule_id;
    v_scheduled_minutes := v_day.custom_scheduled_minutes;
    v_work_start := v_day.custom_scheduled_start;
    v_work_end := v_day.custom_scheduled_end;
    v_custom_working_day := COALESCE(v_scheduled_minutes, 0) > 0;
  END IF;

  v_ctx := resolve_employee_attendance_location_context(v_employee.id, p_latitude, p_longitude, p_log_type);

  IF COALESCE((v_ctx->>'valid')::boolean, false) = false THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', v_ctx->>'code',
      'error', v_ctx->>'error',
      'nearest_location', v_ctx->>'location_name',
      'distance_meters', NULLIF(v_ctx->>'distance_meters', '')::numeric
    );
  END IF;

  v_location_id := NULLIF(v_ctx->>'location_id', '')::uuid;
  v_location_name := v_ctx->>'location_name';

  SELECT COALESCE(value::numeric, 100)
  INTO v_default_threshold
  FROM company_settings
  WHERE key = 'hr.default_gps_accuracy_threshold_meters';

  IF v_location_id IS NOT NULL THEN
    SELECT gps_accuracy_threshold
    INTO v_location_threshold
    FROM hr_work_locations
    WHERE id = v_location_id;
  END IF;

  v_accuracy_threshold := COALESCE(v_location_threshold, v_default_threshold, 100);

  IF COALESCE(p_gps_accuracy, 0) > v_accuracy_threshold THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'LOW_GPS_ACCURACY',
      'error', format('دقة GPS غير كافية. الدقة الحالية ±%s متر والمطلوب ±%s متر أو أفضل', round(p_gps_accuracy), round(v_accuracy_threshold)),
      'required_accuracy', v_accuracy_threshold,
      'actual_accuracy', p_gps_accuracy,
      'location_name', v_location_name
    );
  END IF;

  SELECT COALESCE(value::integer, 15) INTO v_late_grace
  FROM company_settings WHERE key = 'hr.late_grace_minutes';

  IF p_log_type = 'check_in' THEN
    IF v_day_exists AND v_day.punch_in_time IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'ALREADY_CHECKED_IN', 'error', 'لقد سجلت حضورك بالفعل اليوم');
    END IF;

    IF v_custom_working_day THEN
      v_scheduled_start := (v_shift_date::text || ' ' || v_work_start::text)::timestamp AT TIME ZONE 'Africa/Cairo';
      v_late_minutes := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (v_event_time - v_scheduled_start)) / 60)::integer - v_late_grace);
    ELSE
      -- Working on a configured non-working weekday is not classified as late.
      -- Off-day compensation policy belongs to the payroll batch, not attendance timing.
      v_late_minutes := 0;
    END IF;

    IF v_day_exists AND v_day.status = 'on_leave' THEN
      v_attendance_status := 'on_leave';
    ELSE
      v_attendance_status := CASE WHEN v_late_minutes > 0 THEN 'late' ELSE 'present' END;
    END IF;
    v_tracking_status := 'active';

    INSERT INTO hr_attendance_days (
      employee_id, shift_date, work_date, punch_in_time, location_in_id,
      gps_accuracy_in, status, late_minutes, review_status,
      tracking_started_at, last_tracking_ping_at,
      last_tracking_lat, last_tracking_lng, last_tracking_accuracy,
      tracking_status, tracking_ping_count,
      custom_schedule_id, custom_scheduled_start, custom_scheduled_end, custom_scheduled_minutes
    ) VALUES (
      v_employee.id, v_shift_date, v_shift_date, v_event_time, v_location_id,
      LEAST(COALESCE(p_gps_accuracy, 0), 999999.99), v_attendance_status, v_late_minutes, 'ok',
      v_event_time, v_event_time, p_latitude, p_longitude,
      LEAST(COALESCE(p_gps_accuracy, 0), 999999.99), 'active', 1,
      v_schedule_id,
      CASE WHEN v_custom_working_day THEN v_work_start ELSE NULL END,
      CASE WHEN v_custom_working_day THEN v_work_end ELSE NULL END,
      v_scheduled_minutes
    )
    ON CONFLICT (employee_id, shift_date)
    DO UPDATE SET
      punch_in_time          = EXCLUDED.punch_in_time,
      work_date              = EXCLUDED.work_date,
      location_in_id         = EXCLUDED.location_in_id,
      gps_accuracy_in        = EXCLUDED.gps_accuracy_in,
      status                 = EXCLUDED.status,
      late_minutes           = EXCLUDED.late_minutes,
      review_status          = CASE
        WHEN hr_attendance_days.review_status = 'reviewed' THEN 'reviewed'::hr_review_status
        ELSE 'ok'::hr_review_status
      END,
      tracking_started_at    = COALESCE(hr_attendance_days.tracking_started_at, EXCLUDED.tracking_started_at),
      last_tracking_ping_at  = EXCLUDED.last_tracking_ping_at,
      last_tracking_lat      = EXCLUDED.last_tracking_lat,
      last_tracking_lng      = EXCLUDED.last_tracking_lng,
      last_tracking_accuracy = EXCLUDED.last_tracking_accuracy,
      tracking_status        = 'active',
      tracking_ping_count    = GREATEST(hr_attendance_days.tracking_ping_count, 1),
      custom_schedule_id       = EXCLUDED.custom_schedule_id,
      custom_scheduled_start   = EXCLUDED.custom_scheduled_start,
      custom_scheduled_end     = EXCLUDED.custom_scheduled_end,
      custom_scheduled_minutes = EXCLUDED.custom_scheduled_minutes,
      updated_at             = now()
    RETURNING id INTO v_day_id;

  ELSE
    IF NOT v_day_exists OR v_day.punch_in_time IS NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'NOT_CHECKED_IN', 'error', 'يجب تسجيل الحضور أولاً');
    END IF;

    IF v_day.punch_out_time IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'ALREADY_CHECKED_OUT', 'error', 'لقد سجلت انصرافك بالفعل اليوم');
    END IF;

    IF v_custom_working_day THEN
      v_scheduled_end := (v_shift_date::text || ' ' || v_work_end::text)::timestamp AT TIME ZONE 'Africa/Cairo';
      v_early_minutes := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (v_scheduled_end - v_event_time)) / 60)::integer);
      v_overtime_minutes := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (v_event_time - v_scheduled_end)) / 60)::integer);
    ELSE
      -- Do not generate company-time early/late classifications on a custom off-day.
      v_early_minutes := 0;
      v_overtime_minutes := 0;
    END IF;

    v_effective_hours := ROUND((EXTRACT(EPOCH FROM (v_event_time - v_day.punch_in_time)) / 3600)::numeric, 2);

    IF NOT v_custom_working_day THEN
      v_checkout_status := 'on_time';
    ELSIF v_overtime_minutes > 0 THEN
      v_checkout_status := 'overtime';
    ELSIF v_early_minutes > 0 THEN
      IF EXISTS (
        SELECT 1 FROM hr_leave_requests
        WHERE employee_id = v_employee.id
          AND start_date <= v_shift_date
          AND end_date >= v_shift_date
          AND status = 'approved'
      )
      OR EXISTS (
        SELECT 1 FROM hr_permission_requests
        WHERE employee_id = v_employee.id
          AND permission_date = v_shift_date
          AND status = 'approved'
      )
      THEN
        v_checkout_status := 'early_authorized';
      ELSE
        v_checkout_status := 'early_unauthorized';
      END IF;
    ELSE
      v_checkout_status := 'on_time';
    END IF;

    v_tracking_status := 'ended';

    UPDATE hr_attendance_days
    SET
      punch_out_time         = v_event_time,
      location_out_id        = v_location_id,
      gps_accuracy_out       = LEAST(COALESCE(p_gps_accuracy, 0), 999999.99),
      checkout_status        = v_checkout_status,
      early_leave_minutes    = v_early_minutes,
      overtime_minutes       = v_overtime_minutes,
      effective_hours        = v_effective_hours,
      tracking_ended_at      = v_event_time,
      tracking_status        = 'ended',
      last_tracking_ping_at  = v_event_time,
      last_tracking_lat      = p_latitude,
      last_tracking_lng      = p_longitude,
      last_tracking_accuracy = LEAST(COALESCE(p_gps_accuracy, 0), 999999.99),
      updated_at             = now()
    WHERE id = v_day.id
    RETURNING id INTO v_day_id;

    -- These downstream helpers remain Legacy in Batch 2A. The fail-closed runtime
    -- gate guarantees this custom path cannot be activated until their custom-day
    -- dependencies are reviewed in Batch 3.
    PERFORM settle_attendance_day_against_leave(v_day_id);

    SELECT reprocess_attendance_day_penalties(v_day_id)
    INTO v_penalties_count;
  END IF;

  INSERT INTO hr_attendance_logs (
    employee_id, attendance_day_id, log_type,
    latitude, longitude, gps_accuracy, location_id,
    event_time, synced_at, requires_review
  ) VALUES (
    v_employee.id, v_day_id, p_log_type,
    p_latitude, p_longitude,
    LEAST(COALESCE(p_gps_accuracy, 0), 999999.99),
    v_location_id, v_event_time, now(), false
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

REVOKE ALL ON FUNCTION public.record_attendance_gps_v2_custom_schedule(
  numeric, numeric, numeric, text, timestamp with time zone
) FROM PUBLIC, anon, authenticated, service_role;

-- Public compatibility wrapper. With the Batch 2A gate false, it immediately calls
-- the exact Legacy implementation and performs no V2 schedule query.
CREATE OR REPLACE FUNCTION public.record_attendance_gps_v2(
  p_latitude numeric,
  p_longitude numeric,
  p_gps_accuracy numeric,
  p_log_type text,
  p_event_time timestamp with time zone DEFAULT NULL::timestamp with time zone
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_employee_id uuid;
  v_shift_date date := (COALESCE(p_event_time, now()) AT TIME ZONE 'Africa/Cairo')::date;
BEGIN
  IF NOT public.hr_variable_schedules_v2_runtime_enabled() THEN
    RETURN public.record_attendance_gps_v2_legacy(
      p_latitude, p_longitude, p_gps_accuracy, p_log_type, p_event_time
    );
  END IF;

  SELECT id INTO v_employee_id
  FROM public.hr_employees
  WHERE user_id = auth.uid() AND status = 'active';

  IF v_employee_id IS NULL THEN
    RETURN public.record_attendance_gps_v2_legacy(
      p_latitude, p_longitude, p_gps_accuracy, p_log_type, p_event_time
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.resolve_employee_custom_schedule(v_employee_id, v_shift_date)
  ) THEN
    RETURN public.record_attendance_gps_v2_custom_schedule(
      p_latitude, p_longitude, p_gps_accuracy, p_log_type, p_event_time
    );
  END IF;

  RETURN public.record_attendance_gps_v2_legacy(
    p_latitude, p_longitude, p_gps_accuracy, p_log_type, p_event_time
  );
END;
$function$;

COMMENT ON FUNCTION public.record_attendance_gps_v2(numeric, numeric, numeric, text, timestamp with time zone) IS
  'Compatibility wrapper: exact Legacy path while V2 gate is false or no custom schedule exists.';

-- Restore the captured public RPC execution contract exactly. Internal helpers remain private.
REVOKE ALL ON FUNCTION public.record_attendance_gps_v2(
  numeric, numeric, numeric, text, timestamp with time zone
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_attendance_gps_v2(
  numeric, numeric, numeric, text, timestamp with time zone
) TO PUBLIC, anon, authenticated, service_role;

COMMIT;
