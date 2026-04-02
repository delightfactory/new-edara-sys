-- ═══════════════════════════════════════════════════════════════
-- 39_hr_attendance_location_governance.sql
-- HR Attendance — Wave E: Location Governance & Permit Hardening
--
-- Additive & non-destructive. Safe to re-run (idempotent).
--
-- Changes:
--   1. resolve_employee_attendance_location_context
--      ★ field_allowed: تطبيق حد مسافة أقصى (hr.field_attendance_max_distance_meters)
--      ★ احترام allowed_ids للميداني إن وُجدت قبل fallback
--   2. record_attendance_gps_v2
--      ★ فحص دقة GPS (threshold من الموقع أو company_settings)
--      ★ رفض check_in/check_out إذا كانت دقة GPS أسوأ من threshold
--   3. record_attendance_location_ping
--      ★ منع تحويل GPS ضعيف إلى outside_zone
--      ★ تسجيل الـ ping مع requires_review=true بدل رفعه كخروج
--   4. sync_permission_request_operational_fields (trigger)
--      ★ تطبيق الحد الشهري على UPDATE أيضًا (استثناء السجل الحالي)
-- ═══════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────
-- 1) resolve_employee_attendance_location_context
--    ★ field_allowed: حد مسافة أقصى + احترام allowed_ids للميداني
-- ─────────────────────────────────────────────────────────────

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
  v_max_field_distance NUMERIC := 50000; -- 50km default
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

  -- ★ جلب حد المسافة الميدانية من company_settings
  SELECT COALESCE(value::NUMERIC, 50000)
  INTO v_max_field_distance
  FROM company_settings
  WHERE key = 'hr.field_attendance_max_distance_meters';

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

  -- ─────────────────────────────────────────────
  -- field_allowed: مسار الميدان
  -- ─────────────────────────────────────────────
  IF v_mode = 'field_allowed' THEN

    -- ★ إذا كان للموظف allowed_ids محددة → احترمها أولًا (لا نبحث كل المواقع)
    IF v_allowed_count > 0 THEN
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
    ELSE
      -- fallback: أقرب موقع نشط من الكل
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
    END IF;

    IF FOUND THEN
      v_distance := 6371000 * acos(LEAST(1.0,
        cos(radians(v_location.latitude)) * cos(radians(p_latitude))
        * cos(radians(p_longitude) - radians(v_location.longitude))
        + sin(radians(v_location.latitude)) * sin(radians(p_latitude))
      ));
    END IF;

    -- ★ تطبيق حد المسافة الأقصى للميدان
    IF NOT FOUND OR v_distance > v_max_field_distance THEN
      RETURN jsonb_build_object(
        'valid', false,
        'code', 'OUT_OF_RANGE',
        'error', format(
          'أنت خارج نطاق الحضور الميداني المسموح. المسافة الحالية %s كم والحد الأقصى %s كم',
          round(COALESCE(v_distance, 0) / 1000),
          round(v_max_field_distance / 1000)
        ),
        'location_id',           v_location.id,
        'location_name',         v_location.name,
        'distance_meters',       round(COALESCE(v_distance, 0)),
        'max_distance_meters',   round(v_max_field_distance),
        'is_field_employee',     v_employee.is_field_employee,
        'policy_mode',           v_mode,
        'inside_allowed_zone',   false
      );
    END IF;

    RETURN jsonb_build_object(
      'valid',                true,
      'location_id',          v_location.id,
      'location_name',        v_location.name,
      'distance_meters',      round(v_distance),
      'max_distance_meters',  round(v_max_field_distance),
      'is_field_employee',    v_employee.is_field_employee,
      'policy_mode',          v_mode,
      'inside_allowed_zone',  true
    );
  END IF;

  -- ─────────────────────────────────────────────
  -- assigned_only: مسار المكتب (بلا تغيير)
  -- ─────────────────────────────────────────────
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
      'location_id',          v_location.id,
      'location_name',        v_location.name,
      'distance_meters',      round(v_distance),
      'is_field_employee',    v_employee.is_field_employee,
      'policy_mode',          v_mode,
      'inside_allowed_zone',  false
    );
  END IF;

  RETURN jsonb_build_object(
    'valid',                true,
    'location_id',          v_location.id,
    'location_name',        v_location.name,
    'distance_meters',      round(v_distance),
    'is_field_employee',    v_employee.is_field_employee,
    'policy_mode',          v_mode,
    'inside_allowed_zone',  true
  );
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- 2) record_attendance_gps_v2
--    ★ فحص دقة GPS قبل أي كتابة
--    Threshold: موقع.gps_accuracy_threshold → fallback → company_settings
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
  v_tracking_status TEXT := 'idle';
  v_penalties_count INTEGER := 0;
  -- ★ GPS accuracy
  v_accuracy_threshold NUMERIC;
  v_location_threshold NUMERIC;
  v_default_threshold NUMERIC := 100; -- default 100m
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

  -- ★ فحص دقة GPS بعد نجاح resolve location
  -- Threshold hierarchy: موقع → company_setting → 100m
  SELECT COALESCE(value::NUMERIC, 100)
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

  -- p_gps_accuracy = الدقة بالمتر (كلما قل الرقم كلما كانت الدقة أفضل)
  -- نرفض إذا كانت القيمة أكبر من الحد المسموح (دقة أسوأ)
  IF COALESCE(p_gps_accuracy, 0) > v_accuracy_threshold THEN
    RETURN jsonb_build_object(
      'success',           false,
      'code',              'LOW_GPS_ACCURACY',
      'error',             format('دقة GPS غير كافية. الدقة الحالية ±%s متر والمطلوب ±%s متر أو أفضل', round(p_gps_accuracy), round(v_accuracy_threshold)),
      'required_accuracy', v_accuracy_threshold,
      'actual_accuracy',   p_gps_accuracy,
      'location_name',     v_location_name
    );
  END IF;

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

    v_scheduled_start := (v_shift_date::TEXT || ' ' || v_work_start::TEXT)::TIMESTAMP
                          AT TIME ZONE 'Africa/Cairo';
    v_late_minutes := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (v_event_time - v_scheduled_start)) / 60)::INTEGER - v_late_grace);
    v_attendance_status := CASE WHEN v_late_minutes > 0 THEN 'late' ELSE 'present' END;

    v_tracking_status := 'active';

    INSERT INTO hr_attendance_days (
      employee_id, shift_date, work_date, punch_in_time, location_in_id,
      gps_accuracy_in, status, late_minutes, review_status,
      tracking_started_at, last_tracking_ping_at,
      last_tracking_lat, last_tracking_lng, last_tracking_accuracy,
      tracking_status, tracking_ping_count
    ) VALUES (
      v_employee.id, v_shift_date, v_shift_date, v_event_time, v_location_id,
      LEAST(COALESCE(p_gps_accuracy, 0), 999999.99), v_attendance_status, v_late_minutes, 'ok',
      v_event_time, v_event_time, p_latitude, p_longitude,
      LEAST(COALESCE(p_gps_accuracy, 0), 999999.99), 'active', 1
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
        WHEN hr_attendance_days.review_status = 'reviewed' THEN 'reviewed'
        ELSE 'ok'
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
    -- ─── check_out ───
    IF NOT FOUND OR v_day.punch_in_time IS NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'NOT_CHECKED_IN', 'error', 'يجب تسجيل الحضور أولاً');
    END IF;

    IF v_day.punch_out_time IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'ALREADY_CHECKED_OUT', 'error', 'لقد سجلت انصرافك بالفعل اليوم');
    END IF;

    v_scheduled_end := (v_shift_date::TEXT || ' ' || v_work_end::TEXT)::TIMESTAMP
                        AT TIME ZONE 'Africa/Cairo';
    v_early_minutes := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (v_scheduled_end - v_event_time)) / 60)::INTEGER);
    v_overtime_minutes := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (v_event_time - v_scheduled_end)) / 60)::INTEGER);
    v_effective_hours := ROUND((EXTRACT(EPOCH FROM (v_event_time - v_day.punch_in_time)) / 3600)::NUMERIC, 2);
    v_checkout_status := CASE
      WHEN v_overtime_minutes > 0 THEN 'overtime'
      WHEN v_early_minutes > 0 THEN 'early_unauthorized'
      ELSE 'on_time'
    END;

    v_tracking_status := 'ended';

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

    -- إعادة معالجة الجزاءات — إذا فشلت تفشل العملية كاملاً (Wave D policy)
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
    'success',          true,
    'action',           p_log_type,
    'attendance_day_id', v_day_id,
    'log_id',           v_log_id,
    'location_name',    v_location_name,
    'location_id',      v_location_id,
    'shift_date',       v_shift_date,
    'event_time',       v_event_time,
    'tracking_status',  v_tracking_status,
    'penalties_applied', CASE WHEN p_log_type = 'check_out' THEN v_penalties_count ELSE NULL END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION record_attendance_gps_v2(NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ) TO authenticated;


-- ─────────────────────────────────────────────────────────────
-- 3) record_attendance_location_ping
--    ★ GPS ضعيف → لا outside_zone + لا تنبيه مضلل
--    ★ تسجيل الـ ping مع requires_review=true فقط
--    ★ تحديث last_tracking_ping_at دائمًا (منع stale كاذبة)
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
  v_new_tracking_status TEXT;
  -- ★ GPS accuracy
  v_accuracy_threshold NUMERIC;
  v_location_threshold NUMERIC;
  v_default_threshold NUMERIC := 100;
  v_low_accuracy BOOLEAN := false;
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

  -- ★ تحديد threshold الدقة للـ ping
  SELECT COALESCE(value::NUMERIC, 100)
  INTO v_default_threshold
  FROM company_settings
  WHERE key = 'hr.default_gps_accuracy_threshold_meters';

  -- استخدام موقع الحضور إن وجد
  IF v_day.location_in_id IS NOT NULL THEN
    SELECT gps_accuracy_threshold
    INTO v_location_threshold
    FROM hr_work_locations
    WHERE id = v_day.location_in_id;
  END IF;

  v_accuracy_threshold := COALESCE(v_location_threshold, v_default_threshold, 100);
  v_low_accuracy := COALESCE(p_gps_accuracy, 0) > v_accuracy_threshold;

  -- ★ إذا كانت الدقة ضعيفة:
  --   - سجّل الـ ping مع requires_review=true
  --   - حدّث last_tracking_ping_at (منع stale كاذبة)
  --   - لا تحكم مكانيًا / لا تغير tracking_status
  IF v_low_accuracy THEN
    INSERT INTO hr_attendance_logs (
      employee_id, attendance_day_id, log_type,
      latitude, longitude, gps_accuracy, location_id,
      event_time, synced_at, requires_review, device_info
    ) VALUES (
      v_employee.id, v_day.id, 'location_ping',
      p_latitude, p_longitude,
      LEAST(COALESCE(p_gps_accuracy, 0), 999999.99),
      NULL, -- لا نسجل location_id عند دقة ضعيفة
      v_event_time, now(),
      true, -- ★ requires_review=true لأن الدقة ضعيفة
      p_device_info
    );

    -- ★ حدّث ping_at فقط لمنع stale كاذبة — لا تحدث lat/lng
    UPDATE hr_attendance_days
    SET
      last_tracking_ping_at = v_event_time,
      tracking_ping_count   = tracking_ping_count + 1,
      updated_at            = now()
    WHERE id = v_day.id;

    RETURN jsonb_build_object(
      'success',             true,
      'attendance_day_id',   v_day.id,
      'low_accuracy',        true,
      'actual_accuracy',     p_gps_accuracy,
      'required_accuracy',   v_accuracy_threshold,
      'tracking_status',     v_day.tracking_status, -- لا نغير الحالة
      'last_ping_at',        v_event_time
    );
  END IF;

  -- ─── دقة كافية: تقييم مكاني عادي ───
  v_ctx := resolve_employee_attendance_location_context(v_employee.id, p_latitude, p_longitude, 'track');
  v_location_id := NULLIF(v_ctx ->> 'location_id', '')::UUID;
  v_location_name := v_ctx ->> 'location_name';

  -- ★ الخروج من النطاق = OUT_OF_RANGE فقط (مع دقة كافية)
  v_outside_zone := (v_ctx ->> 'code') = 'OUT_OF_RANGE';

  IF v_outside_zone THEN
    v_new_tracking_status := 'outside_zone';
  ELSE
    v_new_tracking_status := 'active';
  END IF;

  INSERT INTO hr_attendance_logs (
    employee_id, attendance_day_id, log_type,
    latitude, longitude, gps_accuracy, location_id,
    event_time, synced_at, requires_review, device_info
  ) VALUES (
    v_employee.id, v_day.id, 'location_ping',
    p_latitude, p_longitude,
    LEAST(COALESCE(p_gps_accuracy, 0), 999999.99),
    v_location_id, v_event_time, now(),
    v_outside_zone, -- requires_review=true عند الخروج فقط
    p_device_info
  );

  UPDATE hr_attendance_days
  SET
    last_tracking_ping_at  = v_event_time,
    last_tracking_lat      = p_latitude,
    last_tracking_lng      = p_longitude,
    last_tracking_accuracy = LEAST(COALESCE(p_gps_accuracy, 0), 999999.99),
    tracking_status        = v_new_tracking_status,
    tracking_ping_count    = tracking_ping_count + 1,
    outside_zone_count     = outside_zone_count + CASE WHEN v_outside_zone THEN 1 ELSE 0 END,
    review_status = CASE
      WHEN v_outside_zone THEN 'needs_review'
      WHEN review_status = 'reviewed' THEN 'reviewed'
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
        'latitude',       p_latitude,
        'longitude',      p_longitude,
        'location_name',  v_location_name,
        'distance_meters', v_ctx ->> 'distance_meters'
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success',             true,
    'attendance_day_id',   v_day.id,
    'location_id',         v_location_id,
    'location_name',       v_location_name,
    'low_accuracy',        false,
    'outside_allowed_zone', v_outside_zone,
    'tracking_status',     v_new_tracking_status,
    'last_ping_at',        v_event_time
  );
END;
$$;

GRANT EXECUTE ON FUNCTION record_attendance_location_ping(NUMERIC, NUMERIC, NUMERIC, TIMESTAMPTZ, TEXT) TO authenticated;


-- ─────────────────────────────────────────────────────────────
-- 4) sync_permission_request_operational_fields
--    ★ تطبيق حد الأذونات الشهري على INSERT و UPDATE معًا
--
-- المنطق:
--   INSERT: عد الموجود + السجل الجديد → رفض إذا > max
--   UPDATE: أعد العد مع استثناء السجل الحالي
--          ثم اعتبر حالة NEW فقط (pending/approved)
--          ورفض فقط إذا كانت حالة NEW تستهلك الحد
--
-- ما يُعتبر استهلاكًا: status <> 'rejected' AND status <> 'cancelled'
-- (نفس منطق INSERT الحالي)
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

  -- ★ عدّ السجلات الحالية المستهلِكة للحد — مع استثناء السجل نفسه عند UPDATE
  SELECT COUNT(*)
  INTO v_month_count
  FROM hr_permission_requests
  WHERE employee_id = NEW.employee_id
    AND date_trunc('month', permission_date) = date_trunc('month', NEW.permission_date)
    AND status NOT IN ('rejected', 'cancelled')
    AND id <> COALESCE(
      -- عند UPDATE: استثنِ السجل الحالي حتى لا يُعدّ مرتين
      -- عند INSERT: NEW.id هو null عادةً قبل الإدراج، لكن BEFORE INSERT يعطيه نفس uuid
      -- لذا نستخدم TG_OP للتمييز الصريح
      CASE WHEN TG_OP = 'UPDATE' THEN NEW.id ELSE '00000000-0000-0000-0000-000000000000'::uuid END,
      '00000000-0000-0000-0000-000000000000'::uuid
    );

  NEW.month_permit_count := v_month_count + 1;

  -- ★ المنطق النهائي — يعتمد على النتيجة بعد التعديل، لا على نوع التغيير:
  --
  --   INSERT: إذا كان السجل الجديد سيُحسب ضمن الحد (status مستهلك) وتجاوز العدد → رفض
  --   UPDATE: نفس المنطق — إذا كانت النتيجة النهائية (NEW) ستُحسب وتجاوز العدد → رفض
  --
  -- هذا يغلق جميع مسارات الالتفاف:
  --   - نقل إذن pending/approved إلى شهر ممتلئ
  --   - تغيير employee_id لموظف وصل للحد
  --   - إعادة تفعيل rejected/cancelled مع تجاوز الحد
  --   - أي تعديل آخر ينتج عنه count > max مع status مستهلك
  IF NEW.month_permit_count > v_max_permits
     AND NEW.status NOT IN ('rejected', 'cancelled') THEN
    RAISE EXCEPTION 'تجاوز الموظف الحد الشهري المسموح لأذونات الانصراف (%).', v_max_permits;
  END IF;

  -- حساب مدة الإذن
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


-- ─────────────────────────────────────────────────────────────
-- 5) إضافة company_settings defaults
--    (INSERT ON CONFLICT DO NOTHING — لا تكتب فوق قيم موجودة)
-- ─────────────────────────────────────────────────────────────

INSERT INTO company_settings (key, value, description)
VALUES
  ('hr.default_gps_accuracy_threshold_meters', '100',
   'الحد الافتراضي لدقة GPS المقبولة بالمتر — يُستخدم عند غياب threshold المحدد للموقع'),
  ('hr.field_attendance_max_distance_meters', '50000',
   'أقصى مسافة مسموح بها لحضور الموظف الميداني بالمتر (الافتراضي: 50 كم)')
ON CONFLICT (key) DO NOTHING;


-- ═══════════════════════════════════════════════════════════════
-- END OF MIGRATION 39
-- ═══════════════════════════════════════════════════════════════
