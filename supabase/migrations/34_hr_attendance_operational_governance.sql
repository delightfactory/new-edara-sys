-- ============================================================
-- Migration 34: HR Attendance Operational Governance
-- يحكم مواقع الحضور، يتتبع الموقع دورياً، ويولد إنذارات تشغيلية
-- دون بناء محرك معقد متعدد المقاطع داخل اليوم
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1) سياسات الحضور والانصراف على مستوى الموظف
-- ─────────────────────────────────────────────────────────────

ALTER TABLE hr_employees
  ADD COLUMN IF NOT EXISTS attendance_checkin_mode TEXT NOT NULL DEFAULT 'assigned_only'
    CHECK (attendance_checkin_mode IN ('assigned_only', 'field_allowed'));

ALTER TABLE hr_employees
  ADD COLUMN IF NOT EXISTS attendance_checkout_mode TEXT NOT NULL DEFAULT 'assigned_only'
    CHECK (attendance_checkout_mode IN ('assigned_only', 'field_allowed'));

ALTER TABLE hr_employees
  ADD COLUMN IF NOT EXISTS allowed_checkin_location_ids UUID[] NOT NULL DEFAULT '{}';

ALTER TABLE hr_employees
  ADD COLUMN IF NOT EXISTS allowed_checkout_location_ids UUID[] NOT NULL DEFAULT '{}';

UPDATE hr_employees
SET
  allowed_checkin_location_ids = CASE
    WHEN work_location_id IS NOT NULL AND cardinality(allowed_checkin_location_ids) = 0
      THEN ARRAY[work_location_id]
    ELSE allowed_checkin_location_ids
  END,
  allowed_checkout_location_ids = CASE
    WHEN work_location_id IS NOT NULL AND cardinality(allowed_checkout_location_ids) = 0
      THEN ARRAY[work_location_id]
    ELSE allowed_checkout_location_ids
  END,
  attendance_checkin_mode = CASE
    WHEN is_field_employee AND attendance_checkin_mode = 'assigned_only' THEN 'field_allowed'
    ELSE attendance_checkin_mode
  END,
  attendance_checkout_mode = CASE
    WHEN is_field_employee AND attendance_checkout_mode = 'assigned_only' THEN 'field_allowed'
    ELSE attendance_checkout_mode
  END;

-- ─────────────────────────────────────────────────────────────
-- 2) توسيع يوم الحضور لاحتواء حالة التتبع
-- ─────────────────────────────────────────────────────────────

ALTER TABLE hr_attendance_days
  ADD COLUMN IF NOT EXISTS tracking_started_at TIMESTAMPTZ;

ALTER TABLE hr_attendance_days
  ADD COLUMN IF NOT EXISTS tracking_ended_at TIMESTAMPTZ;

ALTER TABLE hr_attendance_days
  ADD COLUMN IF NOT EXISTS last_tracking_ping_at TIMESTAMPTZ;

ALTER TABLE hr_attendance_days
  ADD COLUMN IF NOT EXISTS last_tracking_lat NUMERIC(10,7);

ALTER TABLE hr_attendance_days
  ADD COLUMN IF NOT EXISTS last_tracking_lng NUMERIC(10,7);

ALTER TABLE hr_attendance_days
  ADD COLUMN IF NOT EXISTS last_tracking_accuracy NUMERIC(8,2);

ALTER TABLE hr_attendance_days
  ADD COLUMN IF NOT EXISTS tracking_status TEXT NOT NULL DEFAULT 'idle'
    CHECK (tracking_status IN ('idle', 'active', 'ended', 'stale'));

ALTER TABLE hr_attendance_days
  ADD COLUMN IF NOT EXISTS tracking_ping_count INTEGER NOT NULL DEFAULT 0;

ALTER TABLE hr_attendance_days
  ADD COLUMN IF NOT EXISTS outside_zone_count INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_hr_att_tracking_status
  ON hr_attendance_days(tracking_status);

CREATE INDEX IF NOT EXISTS idx_hr_att_last_ping
  ON hr_attendance_days(last_tracking_ping_at DESC);

-- ─────────────────────────────────────────────────────────────
-- 3) إنذارات تشغيلية للحضور والتتبع
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS hr_attendance_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES hr_employees(id) ON DELETE CASCADE,
  attendance_day_id UUID REFERENCES hr_attendance_days(id) ON DELETE SET NULL,
  alert_type TEXT NOT NULL CHECK (
    alert_type IN (
      'tracking_gap',
      'outside_allowed_zone',
      'permission_no_return',
      'auto_checkout',
      'manual_correction',
      'missing_day'
    )
  ),
  severity TEXT NOT NULL DEFAULT 'medium'
    CHECK (severity IN ('low', 'medium', 'high')),
  status TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'resolved', 'dismissed')),
  title TEXT NOT NULL,
  details TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ,
  resolved_by UUID REFERENCES profiles(id),
  resolution_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hr_att_alerts_day
  ON hr_attendance_alerts(attendance_day_id);

CREATE INDEX IF NOT EXISTS idx_hr_att_alerts_open
  ON hr_attendance_alerts(status, alert_type, started_at DESC)
  WHERE status = 'open';

CREATE INDEX IF NOT EXISTS idx_hr_att_alerts_emp
  ON hr_attendance_alerts(employee_id, started_at DESC);

ALTER TABLE hr_attendance_alerts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS hr_attendance_alerts_select ON hr_attendance_alerts;
CREATE POLICY hr_attendance_alerts_select
ON hr_attendance_alerts
FOR SELECT
USING (
  employee_id IN (
    SELECT id FROM hr_employees WHERE user_id = auth.uid()
  )
  OR check_permission(auth.uid(), 'hr.attendance.read')
  OR check_permission(auth.uid(), 'hr.payroll.read')
  OR check_permission(auth.uid(), 'hr.permissions.approve')
);

DROP POLICY IF EXISTS hr_attendance_alerts_update ON hr_attendance_alerts;
CREATE POLICY hr_attendance_alerts_update
ON hr_attendance_alerts
FOR UPDATE
USING (
  check_permission(auth.uid(), 'hr.attendance.edit')
  OR check_permission(auth.uid(), 'hr.permissions.approve')
  OR check_permission(auth.uid(), 'hr.payroll.approve')
)
WITH CHECK (
  check_permission(auth.uid(), 'hr.attendance.edit')
  OR check_permission(auth.uid(), 'hr.permissions.approve')
  OR check_permission(auth.uid(), 'hr.payroll.approve')
);

-- ─────────────────────────────────────────────────────────────
-- 4) إعدادات تشغيلية جديدة
-- ─────────────────────────────────────────────────────────────

INSERT INTO company_settings (key, value, type, description, category, is_public) VALUES
  ('hr.tracking_enabled_office',      'true', 'boolean', 'تفعيل التتبع الدوري للمكتبيين أثناء يوم العمل', 'hr', false),
  ('hr.tracking_enabled_field',       'true', 'boolean', 'تفعيل التتبع الدوري للميدانيين أثناء يوم العمل', 'hr', false),
  ('hr.tracking_ping_minutes_moving', '5',    'number',  'عدد دقائق إرسال نقطة التتبع عند الحركة', 'hr', false),
  ('hr.tracking_ping_minutes_idle',   '10',   'number',  'عدد دقائق إرسال نقطة التتبع عند السكون', 'hr', false),
  ('hr.tracking_gap_minutes',         '20',   'number',  'عدد دقائق الانقطاع قبل رفع إنذار تتبع', 'hr', false)
ON CONFLICT (key) DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- 5) أدوات مساعدة
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION touch_updated_at_hr_attendance_alerts()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_hr_attendance_alerts_updated_at ON hr_attendance_alerts;
CREATE TRIGGER trg_hr_attendance_alerts_updated_at
  BEFORE UPDATE ON hr_attendance_alerts
  FOR EACH ROW
  EXECUTE FUNCTION touch_updated_at_hr_attendance_alerts();

CREATE OR REPLACE FUNCTION upsert_attendance_alert(
  p_employee_id UUID,
  p_attendance_day_id UUID,
  p_alert_type TEXT,
  p_severity TEXT,
  p_title TEXT,
  p_details TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::jsonb
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_alert_id UUID;
BEGIN
  SELECT id
  INTO v_alert_id
  FROM hr_attendance_alerts
  WHERE employee_id = p_employee_id
    AND COALESCE(attendance_day_id, '00000000-0000-0000-0000-000000000000'::uuid)
      = COALESCE(p_attendance_day_id, '00000000-0000-0000-0000-000000000000'::uuid)
    AND alert_type = p_alert_type
    AND status = 'open'
  LIMIT 1;

  IF v_alert_id IS NULL THEN
    INSERT INTO hr_attendance_alerts (
      employee_id,
      attendance_day_id,
      alert_type,
      severity,
      title,
      details,
      metadata
    ) VALUES (
      p_employee_id,
      p_attendance_day_id,
      p_alert_type,
      p_severity,
      p_title,
      p_details,
      COALESCE(p_metadata, '{}'::jsonb)
    )
    RETURNING id INTO v_alert_id;
  ELSE
    UPDATE hr_attendance_alerts
    SET
      severity = p_severity,
      title = p_title,
      details = p_details,
      metadata = COALESCE(p_metadata, metadata),
      updated_at = now()
    WHERE id = v_alert_id;
  END IF;

  RETURN v_alert_id;
END;
$$;

CREATE OR REPLACE FUNCTION resolve_employee_attendance_location_context(
  p_employee_id UUID,
  p_latitude NUMERIC,
  p_longitude NUMERIC,
  p_action TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee hr_employees%ROWTYPE;
  v_mode TEXT;
  v_allowed_ids UUID[];
  v_location hr_work_locations%ROWTYPE;
  v_distance NUMERIC;
  v_allowed_count INTEGER := 0;
BEGIN
  SELECT *
  INTO v_employee
  FROM hr_employees
  WHERE id = p_employee_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'valid', false,
      'code', 'NO_EMPLOYEE',
      'error', 'تعذر تحديد الموظف'
    );
  END IF;

  IF p_action = 'check_out' THEN
    v_mode := COALESCE(v_employee.attendance_checkout_mode, 'assigned_only');
    v_allowed_ids := COALESCE(v_employee.allowed_checkout_location_ids, '{}');
  ELSIF p_action = 'track' THEN
    IF v_employee.is_field_employee THEN
      v_mode := 'field_allowed';
    ELSE
      v_mode := COALESCE(v_employee.attendance_checkin_mode, 'assigned_only');
    END IF;
    v_allowed_ids := (
      SELECT ARRAY(
        SELECT DISTINCT x
        FROM unnest(
          COALESCE(v_employee.allowed_checkin_location_ids, '{}')
          || COALESCE(v_employee.allowed_checkout_location_ids, '{}')
          || CASE
               WHEN v_employee.work_location_id IS NOT NULL THEN ARRAY[v_employee.work_location_id]
               ELSE ARRAY[]::UUID[]
             END
        ) AS x
      )
    );
  ELSE
    v_mode := COALESCE(v_employee.attendance_checkin_mode, 'assigned_only');
    v_allowed_ids := COALESCE(v_employee.allowed_checkin_location_ids, '{}');
  END IF;

  IF cardinality(v_allowed_ids) = 0 AND v_employee.work_location_id IS NOT NULL THEN
    v_allowed_ids := ARRAY[v_employee.work_location_id];
  END IF;

  v_allowed_count := COALESCE(cardinality(v_allowed_ids), 0);

  IF v_mode = 'field_allowed' THEN
    SELECT *
    INTO v_location
    FROM hr_work_locations
    WHERE is_active = true
    ORDER BY (
      6371000 * acos(LEAST(1.0,
        cos(radians(latitude)) * cos(radians(p_latitude))
        * cos(radians(p_longitude) - radians(longitude))
        + sin(radians(latitude)) * sin(radians(p_latitude))
      ))
    )
    LIMIT 1;

    IF FOUND THEN
      v_distance := 6371000 * acos(LEAST(1.0,
        cos(radians(v_location.latitude)) * cos(radians(p_latitude))
        * cos(radians(p_longitude) - radians(v_location.longitude))
        + sin(radians(v_location.latitude)) * sin(radians(p_latitude))
      ));
    END IF;

    RETURN jsonb_build_object(
      'valid', true,
      'location_id', v_location.id,
      'location_name', v_location.name,
      'distance_meters', COALESCE(round(v_distance), 0),
      'is_field_employee', v_employee.is_field_employee,
      'policy_mode', v_mode,
      'inside_allowed_zone', true
    );
  END IF;

  IF v_allowed_count = 0 THEN
    RETURN jsonb_build_object(
      'valid', false,
      'code', 'NO_ALLOWED_LOCATIONS',
      'error', 'لا توجد مواقع حضور مسموح بها لهذا الموظف',
      'is_field_employee', v_employee.is_field_employee,
      'policy_mode', v_mode
    );
  END IF;

  SELECT *
  INTO v_location
  FROM hr_work_locations
  WHERE is_active = true
    AND id = ANY(v_allowed_ids)
  ORDER BY (
    6371000 * acos(LEAST(1.0,
      cos(radians(latitude)) * cos(radians(p_latitude))
      * cos(radians(p_longitude) - radians(longitude))
      + sin(radians(latitude)) * sin(radians(p_latitude))
    ))
  )
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'valid', false,
      'code', 'NO_ALLOWED_LOCATIONS',
      'error', 'المواقع المسموح بها غير مفعلة أو غير موجودة',
      'is_field_employee', v_employee.is_field_employee,
      'policy_mode', v_mode
    );
  END IF;

  v_distance := 6371000 * acos(LEAST(1.0,
    cos(radians(v_location.latitude)) * cos(radians(p_latitude))
    * cos(radians(p_longitude) - radians(v_location.longitude))
    + sin(radians(v_location.latitude)) * sin(radians(p_latitude))
  ));

  IF v_distance > v_location.radius_meters THEN
    RETURN jsonb_build_object(
      'valid', false,
      'code', 'OUT_OF_RANGE',
      'error', format('أنت خارج النطاق المسموح. المسافة الحالية %s متر', round(v_distance)),
      'location_id', v_location.id,
      'location_name', v_location.name,
      'distance_meters', round(v_distance),
      'is_field_employee', v_employee.is_field_employee,
      'policy_mode', v_mode,
      'inside_allowed_zone', false
    );
  END IF;

  RETURN jsonb_build_object(
    'valid', true,
    'location_id', v_location.id,
    'location_name', v_location.name,
    'distance_meters', round(v_distance),
    'is_field_employee', v_employee.is_field_employee,
    'policy_mode', v_mode,
    'inside_allowed_zone', true
  );
END;
$$;

CREATE OR REPLACE FUNCTION validate_attendance_location(
  p_employee_id UUID,
  p_latitude NUMERIC,
  p_longitude NUMERIC,
  p_gps_accuracy NUMERIC DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN resolve_employee_attendance_location_context(
    p_employee_id,
    p_latitude,
    p_longitude,
    'check_in'
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 6) تسجيل الحضور والانصراف مع الحوكمة الجديدة
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION record_attendance_gps_v2(
  p_latitude NUMERIC,
  p_longitude NUMERIC,
  p_gps_accuracy NUMERIC,
  p_log_type TEXT,
  p_event_time TIMESTAMPTZ DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee hr_employees%ROWTYPE;
  v_event_time TIMESTAMPTZ := COALESCE(p_event_time, now());
  v_shift_date DATE := (COALESCE(p_event_time, now()) AT TIME ZONE 'Africa/Cairo')::date;
  v_day hr_attendance_days%ROWTYPE;
  v_ctx JSONB;
  v_location_id UUID;
  v_location_name TEXT;
  v_late_grace INTEGER := 15;
  v_work_start TIME := '08:00';
  v_work_end TIME := '17:00';
  v_scheduled_start TIMESTAMPTZ;
  v_scheduled_end TIMESTAMPTZ;
  v_late_minutes INTEGER := 0;
  v_early_minutes INTEGER := 0;
  v_overtime_minutes INTEGER := 0;
  v_effective_hours NUMERIC(5,2) := NULL;
  v_checkout_status hr_checkout_status := NULL;
  v_attendance_status hr_attendance_status := 'present';
  v_day_id UUID;
  v_log_id UUID;
BEGIN
  IF p_log_type NOT IN ('check_in', 'check_out') THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_LOG_TYPE', 'error', 'نوع الحركة غير مدعوم');
  END IF;

  SELECT *
  INTO v_employee
  FROM hr_employees
  WHERE user_id = auth.uid()
    AND status = 'active';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_EMPLOYEE', 'error', 'حسابك غير مرتبط بموظف نشط');
  END IF;

  IF v_event_time > now() + interval '5 minutes' THEN
    RETURN jsonb_build_object('success', false, 'code', 'FUTURE_TIME', 'error', 'لا يمكن تسجيل حدث في المستقبل');
  END IF;

  IF v_event_time < now() - interval '24 hours' THEN
    RETURN jsonb_build_object('success', false, 'code', 'TOO_OLD', 'error', 'الحدث أقدم من المسموح به');
  END IF;

  v_ctx := resolve_employee_attendance_location_context(v_employee.id, p_latitude, p_longitude, p_log_type);

  IF COALESCE((v_ctx ->> 'valid')::BOOLEAN, false) = false THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', v_ctx ->> 'code',
      'error', v_ctx ->> 'error',
      'nearest_location', v_ctx ->> 'location_name',
      'distance_meters', NULLIF(v_ctx ->> 'distance_meters', '')::NUMERIC
    );
  END IF;

  v_location_id := NULLIF(v_ctx ->> 'location_id', '')::UUID;
  v_location_name := v_ctx ->> 'location_name';

  SELECT COALESCE(value::INTEGER, 15) INTO v_late_grace
  FROM company_settings
  WHERE key = 'hr.late_grace_minutes';

  SELECT COALESCE(value, '08:00')::TIME INTO v_work_start
  FROM company_settings
  WHERE key = 'hr.work_start_time';

  SELECT COALESCE(value, '17:00')::TIME INTO v_work_end
  FROM company_settings
  WHERE key = 'hr.work_end_time';

  SELECT *
  INTO v_day
  FROM hr_attendance_days
  WHERE employee_id = v_employee.id
    AND shift_date = v_shift_date;

  IF p_log_type = 'check_in' THEN
    IF FOUND AND v_day.punch_in_time IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'ALREADY_CHECKED_IN', 'error', 'لقد سجلت حضورك بالفعل اليوم');
    END IF;

    v_scheduled_start := (v_shift_date::TEXT || ' ' || v_work_start::TEXT)::TIMESTAMPTZ;
    v_late_minutes := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (v_event_time - v_scheduled_start)) / 60)::INTEGER - v_late_grace);
    v_attendance_status := CASE WHEN v_late_minutes > 0 THEN 'late' ELSE 'present' END;

    INSERT INTO hr_attendance_days (
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
      tracking_ping_count
    ) VALUES (
      v_employee.id,
      v_shift_date,
      v_shift_date,
      v_event_time,
      v_location_id,
      LEAST(COALESCE(p_gps_accuracy, 0), 999999.99),
      v_attendance_status,
      v_late_minutes,
      'ok',
      v_event_time,
      v_event_time,
      p_latitude,
      p_longitude,
      LEAST(COALESCE(p_gps_accuracy, 0), 999999.99),
      'active',
      1
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
        WHEN hr_attendance_days.review_status = 'reviewed' THEN 'reviewed'::hr_review_status
        ELSE 'ok'::hr_review_status
      END,
      tracking_started_at = COALESCE(hr_attendance_days.tracking_started_at, EXCLUDED.tracking_started_at),
      last_tracking_ping_at = EXCLUDED.last_tracking_ping_at,
      last_tracking_lat = EXCLUDED.last_tracking_lat,
      last_tracking_lng = EXCLUDED.last_tracking_lng,
      last_tracking_accuracy = EXCLUDED.last_tracking_accuracy,
      tracking_status = 'active',
      tracking_ping_count = GREATEST(hr_attendance_days.tracking_ping_count, 1),
      updated_at = now()
    RETURNING id INTO v_day_id;

  ELSE
    IF NOT FOUND OR v_day.punch_in_time IS NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'NOT_CHECKED_IN', 'error', 'يجب تسجيل الحضور أولاً');
    END IF;

    IF v_day.punch_out_time IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'ALREADY_CHECKED_OUT', 'error', 'لقد سجلت انصرافك بالفعل اليوم');
    END IF;

    v_scheduled_end := (v_shift_date::TEXT || ' ' || v_work_end::TEXT)::TIMESTAMPTZ;
    v_early_minutes := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (v_scheduled_end - v_event_time)) / 60)::INTEGER);
    v_overtime_minutes := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (v_event_time - v_scheduled_end)) / 60)::INTEGER);
    v_effective_hours := ROUND((EXTRACT(EPOCH FROM (v_event_time - v_day.punch_in_time)) / 3600)::NUMERIC, 2);
    v_checkout_status := CASE
      WHEN v_overtime_minutes > 0 THEN 'overtime'
      WHEN v_early_minutes > 0 THEN 'early_unauthorized'
      ELSE 'on_time'
    END;

    UPDATE hr_attendance_days
    SET
      punch_out_time = v_event_time,
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
      updated_at = now()
    WHERE id = v_day.id
    RETURNING id INTO v_day_id;
  END IF;

  INSERT INTO hr_attendance_logs (
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
    false
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
    'event_time', v_event_time
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 7) تسجيل نقطة تتبع دورية أثناء يوم العمل
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION record_attendance_location_ping(
  p_latitude NUMERIC,
  p_longitude NUMERIC,
  p_gps_accuracy NUMERIC,
  p_event_time TIMESTAMPTZ DEFAULT NULL,
  p_device_info TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee hr_employees%ROWTYPE;
  v_event_time TIMESTAMPTZ := COALESCE(p_event_time, now());
  v_shift_date DATE := (COALESCE(p_event_time, now()) AT TIME ZONE 'Africa/Cairo')::date;
  v_day hr_attendance_days%ROWTYPE;
  v_ctx JSONB;
  v_location_id UUID;
  v_location_name TEXT;
  v_outside_zone BOOLEAN := false;
BEGIN
  SELECT *
  INTO v_employee
  FROM hr_employees
  WHERE user_id = auth.uid()
    AND status = 'active';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_EMPLOYEE', 'error', 'حسابك غير مرتبط بموظف نشط');
  END IF;

  SELECT *
  INTO v_day
  FROM hr_attendance_days
  WHERE employee_id = v_employee.id
    AND shift_date = v_shift_date
    AND punch_in_time IS NOT NULL
    AND punch_out_time IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_OPEN_DAY', 'error', 'لا يوجد يوم عمل مفتوح للتتبع');
  END IF;

  v_ctx := resolve_employee_attendance_location_context(v_employee.id, p_latitude, p_longitude, 'track');
  v_location_id := NULLIF(v_ctx ->> 'location_id', '')::UUID;
  v_location_name := v_ctx ->> 'location_name';
  v_outside_zone := COALESCE((v_ctx ->> 'valid')::BOOLEAN, false) = false;

  INSERT INTO hr_attendance_logs (
    employee_id,
    attendance_day_id,
    log_type,
    latitude,
    longitude,
    gps_accuracy,
    location_id,
    event_time,
    synced_at,
    requires_review,
    device_info
  ) VALUES (
    v_employee.id,
    v_day.id,
    'location_ping',
    p_latitude,
    p_longitude,
    LEAST(COALESCE(p_gps_accuracy, 0), 999999.99),
    v_location_id,
    v_event_time,
    now(),
    v_outside_zone,
    p_device_info
  );

  UPDATE hr_attendance_days
  SET
    last_tracking_ping_at = v_event_time,
    last_tracking_lat = p_latitude,
    last_tracking_lng = p_longitude,
    last_tracking_accuracy = LEAST(COALESCE(p_gps_accuracy, 0), 999999.99),
    tracking_status = CASE WHEN v_outside_zone THEN 'stale' ELSE 'active' END,
    tracking_ping_count = tracking_ping_count + 1,
    outside_zone_count = outside_zone_count + CASE WHEN v_outside_zone THEN 1 ELSE 0 END,
    review_status = CASE
      WHEN v_outside_zone THEN 'needs_review'::hr_review_status
      WHEN review_status = 'reviewed' THEN 'reviewed'::hr_review_status
      ELSE review_status
    END,
    updated_at = now()
  WHERE id = v_day.id;

  IF v_outside_zone THEN
    PERFORM upsert_attendance_alert(
      v_employee.id,
      v_day.id,
      'outside_allowed_zone',
      'high',
      'خروج من النطاق المسموح',
      COALESCE(v_ctx ->> 'error', 'تم اكتشاف نقطة تتبع خارج النطاق المسموح'),
      jsonb_build_object(
        'latitude', p_latitude,
        'longitude', p_longitude,
        'location_name', v_location_name,
        'distance_meters', v_ctx ->> 'distance_meters'
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'attendance_day_id', v_day.id,
    'location_id', v_location_id,
    'location_name', v_location_name,
    'outside_allowed_zone', v_outside_zone,
    'tracking_status', CASE WHEN v_outside_zone THEN 'stale' ELSE 'active' END,
    'last_ping_at', v_event_time
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 8) إغلاق إذن الخروج المؤقت فعلياً
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION sync_permission_request_operational_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max_permits INTEGER := 2;
  v_month_count INTEGER;
  v_start_ts TIMESTAMP;
  v_end_ts TIMESTAMP;
BEGIN
  SELECT COALESCE(value::INTEGER, 2)
  INTO v_max_permits
  FROM company_settings
  WHERE key = 'hr.max_early_leave_permits';

  SELECT COUNT(*)
  INTO v_month_count
  FROM hr_permission_requests
  WHERE employee_id = NEW.employee_id
    AND date_trunc('month', permission_date) = date_trunc('month', NEW.permission_date)
    AND status <> 'rejected'
    AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);

  NEW.month_permit_count := v_month_count + 1;

  IF TG_OP = 'INSERT' AND NEW.month_permit_count > v_max_permits THEN
    RAISE EXCEPTION 'تجاوز الموظف الحد الشهري المسموح لأذونات الانصراف (%).', v_max_permits;
  END IF;

  IF NEW.leave_time IS NOT NULL THEN
    v_start_ts := (NEW.permission_date::TEXT || ' ' || NEW.leave_time::TEXT)::TIMESTAMP;
    v_end_ts := CASE
      WHEN NEW.actual_return IS NOT NULL THEN (NEW.permission_date::TEXT || ' ' || NEW.actual_return::TEXT)::TIMESTAMP
      WHEN NEW.expected_return IS NOT NULL THEN (NEW.permission_date::TEXT || ' ' || NEW.expected_return::TEXT)::TIMESTAMP
      ELSE NULL
    END;

    IF v_end_ts IS NOT NULL THEN
      NEW.duration_minutes := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (v_end_ts - v_start_ts)) / 60)::INTEGER);
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_permission_request_operational_fields ON hr_permission_requests;
CREATE TRIGGER trg_sync_permission_request_operational_fields
  BEFORE INSERT OR UPDATE ON hr_permission_requests
  FOR EACH ROW
  EXECUTE FUNCTION sync_permission_request_operational_fields();

CREATE OR REPLACE FUNCTION complete_permission_return(
  p_permission_id UUID,
  p_actual_return TIME,
  p_resolution_note TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_permission hr_permission_requests%ROWTYPE;
  v_employee_id UUID;
  v_day_id UUID;
BEGIN
  SELECT id
  INTO v_employee_id
  FROM hr_employees
  WHERE user_id = auth.uid()
    AND status = 'active'
  LIMIT 1;

  SELECT *
  INTO v_permission
  FROM hr_permission_requests
  WHERE id = p_permission_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'error', 'طلب الإذن غير موجود');
  END IF;

  IF v_permission.status <> 'approved' THEN
    RETURN jsonb_build_object('success', false, 'code', 'NOT_APPROVED', 'error', 'لا يمكن إغلاق إذن غير معتمد');
  END IF;

  IF v_permission.actual_return IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'ALREADY_CLOSED', 'error', 'تم تسجيل العودة الفعلية مسبقاً');
  END IF;

  IF v_permission.employee_id <> v_employee_id
     AND NOT check_permission(auth.uid(), 'hr.permissions.approve')
     AND NOT check_permission(auth.uid(), 'hr.attendance.edit') THEN
    RETURN jsonb_build_object('success', false, 'code', 'FORBIDDEN', 'error', 'غير مسموح لك بإغلاق هذا الإذن');
  END IF;

  UPDATE hr_permission_requests
  SET
    actual_return = p_actual_return,
    updated_at = now(),
    rejection_reason = COALESCE(rejection_reason, p_resolution_note)
  WHERE id = p_permission_id;

  SELECT id
  INTO v_day_id
  FROM hr_attendance_days
  WHERE employee_id = v_permission.employee_id
    AND shift_date = v_permission.permission_date;

  IF v_day_id IS NOT NULL AND v_permission.expected_return IS NOT NULL AND p_actual_return > v_permission.expected_return THEN
    UPDATE hr_attendance_days
    SET review_status = 'needs_review', updated_at = now()
    WHERE id = v_day_id;

    PERFORM upsert_attendance_alert(
      v_permission.employee_id,
      v_day_id,
      'permission_no_return',
      'medium',
      'عودة متأخرة من إذن الخروج',
      'تمت العودة الفعلية بعد الموعد المتوقع ويحتاج اليوم إلى مراجعة إدارية',
      jsonb_build_object(
        'expected_return', v_permission.expected_return,
        'actual_return', p_actual_return
      )
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'permission_id', p_permission_id, 'actual_return', p_actual_return);
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 9) فحص الانقطاعات والإذن غير المغلق
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION scan_attendance_tracking_alerts()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gap_minutes INTEGER := 20;
  v_tracking_alerts INTEGER := 0;
  v_permission_alerts INTEGER := 0;
BEGIN
  SELECT COALESCE(value::INTEGER, 20)
  INTO v_gap_minutes
  FROM company_settings
  WHERE key = 'hr.tracking_gap_minutes';

  WITH stale_days AS (
    SELECT id, employee_id, last_tracking_ping_at
    FROM hr_attendance_days
    WHERE punch_in_time IS NOT NULL
      AND punch_out_time IS NULL
      AND tracking_status IN ('active', 'stale')
      AND last_tracking_ping_at IS NOT NULL
      AND last_tracking_ping_at < now() - make_interval(mins => v_gap_minutes)
  )
  SELECT COUNT(*) INTO v_tracking_alerts FROM stale_days;

  UPDATE hr_attendance_days
  SET
    tracking_status = 'stale',
    review_status = 'needs_review',
    updated_at = now()
  WHERE id IN (
    SELECT id
    FROM hr_attendance_days
    WHERE punch_in_time IS NOT NULL
      AND punch_out_time IS NULL
      AND tracking_status IN ('active', 'stale')
      AND last_tracking_ping_at IS NOT NULL
      AND last_tracking_ping_at < now() - make_interval(mins => v_gap_minutes)
  );

  PERFORM upsert_attendance_alert(
    d.employee_id,
    d.id,
    'tracking_gap',
    'medium',
    'انقطاع في التتبع الدوري',
    format('لم تصل نقاط تتبع منذ أكثر من %s دقيقة', v_gap_minutes),
    jsonb_build_object('last_tracking_ping_at', d.last_tracking_ping_at)
  )
  FROM hr_attendance_days d
  WHERE d.punch_in_time IS NOT NULL
    AND d.punch_out_time IS NULL
    AND d.tracking_status = 'stale'
    AND d.last_tracking_ping_at IS NOT NULL
    AND d.last_tracking_ping_at < now() - make_interval(mins => v_gap_minutes);

  SELECT COUNT(*) INTO v_permission_alerts
  FROM hr_permission_requests
  WHERE status = 'approved'
    AND actual_return IS NULL
    AND permission_date <= CURRENT_DATE
    AND expected_return IS NOT NULL;

  UPDATE hr_attendance_days d
  SET review_status = 'needs_review', updated_at = now()
  FROM hr_permission_requests p
  WHERE p.status = 'approved'
    AND p.actual_return IS NULL
    AND p.permission_date <= CURRENT_DATE
    AND expected_return IS NOT NULL
    AND d.employee_id = p.employee_id
    AND d.shift_date = p.permission_date;

  PERFORM upsert_attendance_alert(
    p.employee_id,
    d.id,
    'permission_no_return',
    'high',
    'إذن خروج بلا عودة فعلية',
    'تم اعتماد إذن خروج ولم تُسجل عودة فعلية حتى الآن',
    jsonb_build_object(
      'permission_id', p.id,
      'expected_return', p.expected_return,
      'permission_date', p.permission_date
    )
  )
  FROM hr_permission_requests p
  LEFT JOIN hr_attendance_days d
    ON d.employee_id = p.employee_id
   AND d.shift_date = p.permission_date
  WHERE p.status = 'approved'
    AND p.actual_return IS NULL
    AND p.permission_date <= CURRENT_DATE
    AND p.expected_return IS NOT NULL;

  RETURN jsonb_build_object(
    'success', true,
    'tracking_alerts', v_tracking_alerts,
    'permission_alerts', v_permission_alerts
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 10) ملخص مراجعة الحضور للمسير
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_attendance_review_summary(
  p_date_from DATE,
  p_date_to DATE
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_open_alerts INTEGER := 0;
  v_unresolved_days INTEGER := 0;
  v_permission_no_return INTEGER := 0;
  v_auto_checkout_days INTEGER := 0;
  v_tracking_gap_days INTEGER := 0;
BEGIN
  IF NOT check_permission(auth.uid(), 'hr.payroll.read')
     AND NOT check_permission(auth.uid(), 'hr.payroll.approve')
     AND NOT check_permission(auth.uid(), 'hr.attendance.read') THEN
    RAISE EXCEPTION 'غير مسموح بعرض ملخص مراجعة الحضور';
  END IF;

  SELECT COUNT(*)
  INTO v_open_alerts
  FROM hr_attendance_alerts a
  WHERE a.status = 'open'
    AND EXISTS (
      SELECT 1
      FROM hr_attendance_days d
      WHERE d.id = a.attendance_day_id
        AND d.shift_date BETWEEN p_date_from AND p_date_to
    );

  SELECT COUNT(*)
  INTO v_unresolved_days
  FROM hr_attendance_days
  WHERE shift_date BETWEEN p_date_from AND p_date_to
    AND review_status = 'needs_review';

  SELECT COUNT(*)
  INTO v_permission_no_return
  FROM hr_attendance_alerts a
  WHERE a.status = 'open'
    AND a.alert_type = 'permission_no_return'
    AND EXISTS (
      SELECT 1
      FROM hr_attendance_days d
      WHERE d.id = a.attendance_day_id
        AND d.shift_date BETWEEN p_date_from AND p_date_to
    );

  SELECT COUNT(*)
  INTO v_auto_checkout_days
  FROM hr_attendance_days
  WHERE shift_date BETWEEN p_date_from AND p_date_to
    AND is_auto_checkout = true;

  SELECT COUNT(DISTINCT attendance_day_id)
  INTO v_tracking_gap_days
  FROM hr_attendance_alerts a
  WHERE a.status = 'open'
    AND a.alert_type IN ('tracking_gap', 'outside_allowed_zone')
    AND EXISTS (
      SELECT 1
      FROM hr_attendance_days d
      WHERE d.id = a.attendance_day_id
        AND d.shift_date BETWEEN p_date_from AND p_date_to
    );

  RETURN jsonb_build_object(
    'open_alerts', v_open_alerts,
    'unresolved_days', v_unresolved_days,
    'permission_no_return', v_permission_no_return,
    'auto_checkout_days', v_auto_checkout_days,
    'tracking_gap_days', v_tracking_gap_days
  );
END;
$$;
