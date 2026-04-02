-- ═══════════════════════════════════════════════════════════════
-- 41_hr_attendance_consistency_fixes.sql
-- HR Attendance Governance — Wave 41: Final Consistency Fixes
--                        (Revised after Codex audit)
--
-- Fixes 5 confirmed gaps ONLY:
--
--   FIX-1: total_blocking_items — عدد فئات الموانع لا جمع متداخل
--   FIX-2: early_authorized في check_out الذاتي
--   FIX-3: auto-resolve لـ tracking_gap عند عودة التتبع
--   FIX-4: low_accuracy ping: stale → active
--   FIX-5: auto-resolve لـ permission_no_return بعد actual_return
--
-- ضوابط التنفيذ:
--   ✅ منطق GPS النهائي من Wave 39 محفوظ حرفياً (gps_accuracy_threshold,
--      hr.default_gps_accuracy_threshold_meters, location_in_id)
--   ✅ إغلاق permission_no_return مقيّد بـ permission_id داخل metadata
--   ✅ open_day_unclosed يظل مستمداً من تنبيهات alert_type='open_day_unclosed'
--   ✅ reprocess_attendance_day_penalties محفوظ دون تغيير
--   ✅ approve_payroll_run / check_payroll_attendance_clearance لم يُمَسّا
--   ✅ idempotent / safe to re-run
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- FIX-1: get_attendance_review_summary
--
-- المشكلة: total_blocking_items = مجموع متداخل
--   (open_alerts يشمل permission_no_return + open_day_unclosed)
--
-- الحل: عدد فئات موانع مستقلة (0–4)، كل فئة تُحسب مرة واحدة
--   الفئة 1: unresolved_days   > 0
--   الفئة 2: open_day_unclosed > 0   ← مصدره تنبيه open_day_unclosed (لا يتغير)
--   الفئة 3: permission_no_return > 0
--   الفئة 4: open_alerts       > 0   ← يشملهم جميعاً، لكن يُعدّ مرة واحدة
--
-- لا يتغير: open_day_unclosed لا يزال يُحسب من hr_attendance_alerts
--           حتى يتسق مع check_payroll_attendance_clearance
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_attendance_review_summary(
  p_date_from DATE,
  p_date_to   DATE
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_open_alerts         INTEGER := 0;
  v_unresolved_days     INTEGER := 0;
  v_permission_no_return INTEGER := 0;
  v_auto_checkout_days  INTEGER := 0;
  v_tracking_gap_days   INTEGER := 0;
  v_open_day_unclosed   INTEGER := 0;
BEGIN
  IF NOT check_permission(auth.uid(), 'hr.payroll.read')
     AND NOT check_permission(auth.uid(), 'hr.payroll.approve')
     AND NOT check_permission(auth.uid(), 'hr.attendance.read') THEN
    RAISE EXCEPTION 'غير مسموح بعرض ملخص مراجعة الحضور';
  END IF;

  -- إجمالي التنبيهات المفتوحة في الفترة
  SELECT COUNT(*)
  INTO v_open_alerts
  FROM hr_attendance_alerts a
  WHERE a.status = 'open'
    AND EXISTS (
      SELECT 1 FROM hr_attendance_days d
      WHERE d.id = a.attendance_day_id
        AND d.shift_date BETWEEN p_date_from AND p_date_to
    );

  -- أيام تحتاج مراجعة إدارية
  SELECT COUNT(*)
  INTO v_unresolved_days
  FROM hr_attendance_days
  WHERE shift_date BETWEEN p_date_from AND p_date_to
    AND review_status = 'needs_review';

  -- أذونات مفتوحة بلا عودة (من التنبيهات — لا تغيير في المصدر)
  SELECT COUNT(*)
  INTO v_permission_no_return
  FROM hr_attendance_alerts a
  WHERE a.status = 'open'
    AND a.alert_type = 'permission_no_return'
    AND EXISTS (
      SELECT 1 FROM hr_attendance_days d
      WHERE d.id = a.attendance_day_id
        AND d.shift_date BETWEEN p_date_from AND p_date_to
    );

  -- أيام بإنهاء تلقائي
  SELECT COUNT(*)
  INTO v_auto_checkout_days
  FROM hr_attendance_days
  WHERE shift_date BETWEEN p_date_from AND p_date_to
    AND is_auto_checkout = true;

  -- أيام بها فجوة تتبع أو خروج من النطاق
  SELECT COUNT(DISTINCT attendance_day_id)
  INTO v_tracking_gap_days
  FROM hr_attendance_alerts a
  WHERE a.status = 'open'
    AND a.alert_type IN ('tracking_gap', 'outside_allowed_zone')
    AND EXISTS (
      SELECT 1 FROM hr_attendance_days d
      WHERE d.id = a.attendance_day_id
        AND d.shift_date BETWEEN p_date_from AND p_date_to
    );

  -- ★ أيام مفتوحة بلا انصراف — من تنبيهات (كما في Wave 37)
  -- الحفاظ على نفس مصدر check_payroll_attendance_clearance
  SELECT COUNT(*)
  INTO v_open_day_unclosed
  FROM hr_attendance_alerts a
  WHERE a.status = 'open'
    AND a.alert_type = 'open_day_unclosed'
    AND EXISTS (
      SELECT 1 FROM hr_attendance_days d
      WHERE d.id = a.attendance_day_id
        AND d.shift_date BETWEEN p_date_from AND p_date_to
    );

  RETURN jsonb_build_object(
    'open_alerts',           v_open_alerts,
    'unresolved_days',       v_unresolved_days,
    'permission_no_return',  v_permission_no_return,
    'auto_checkout_days',    v_auto_checkout_days,
    'tracking_gap_days',     v_tracking_gap_days,
    'open_day_unclosed',     v_open_day_unclosed,
    -- ★ FIX-1: عدد فئات (0-4) لا جمع متداخل
    -- القيمة صفر فقط عند غياب جميع الفئات → hasAttendanceRisk صادق
    'total_blocking_items', (
      CASE WHEN v_unresolved_days    > 0 THEN 1 ELSE 0 END +
      CASE WHEN v_open_day_unclosed  > 0 THEN 1 ELSE 0 END +
      CASE WHEN v_permission_no_return > 0 THEN 1 ELSE 0 END +
      CASE WHEN v_open_alerts        > 0 THEN 1 ELSE 0 END
    )
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- FIX-2: record_attendance_gps_v2
--
-- التغيير الوحيد: إضافة فحص early_authorized في مسار check_out
-- منطق GPS النهائي من Wave 39 محفوظ حرفياً:
--   - resolve location أولاً → ثم GPS accuracy بعده
--   - Threshold: موقع.gps_accuracy_threshold → hr.default_gps_accuracy_threshold_meters
--   - reprocess يُستدعى بـ SELECT INTO (لا BEGIN/EXCEPTION — كما في Wave 39)
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION record_attendance_gps_v2(
  p_latitude    NUMERIC,
  p_longitude   NUMERIC,
  p_gps_accuracy NUMERIC,
  p_log_type    TEXT,
  p_event_time  TIMESTAMPTZ DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee          hr_employees%ROWTYPE;
  v_event_time        TIMESTAMPTZ := COALESCE(p_event_time, now());
  v_shift_date        DATE        := (COALESCE(p_event_time, now()) AT TIME ZONE 'Africa/Cairo')::date;
  v_day               hr_attendance_days%ROWTYPE;
  v_ctx               JSONB;
  v_location_id       UUID;
  v_location_name     TEXT;
  v_late_grace        INTEGER := 15;
  v_work_start        TIME    := '08:00';
  v_work_end          TIME    := '17:00';
  v_scheduled_start   TIMESTAMPTZ;
  v_scheduled_end     TIMESTAMPTZ;
  v_late_minutes      INTEGER := 0;
  v_early_minutes     INTEGER := 0;
  v_overtime_minutes  INTEGER := 0;
  v_effective_hours   NUMERIC(5,2) := NULL;
  v_checkout_status   hr_checkout_status := NULL;
  v_attendance_status hr_attendance_status := 'present';
  v_day_id            UUID;
  v_log_id            UUID;
  v_tracking_status   TEXT := 'idle';
  v_penalties_count   INTEGER := 0;
  -- ★ GPS accuracy (Wave 39 variables — unchanged)
  v_accuracy_threshold NUMERIC;
  v_location_threshold NUMERIC;
  v_default_threshold  NUMERIC := 100;
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

  -- ★ Location resolution أولاً (Wave 39 order — unchanged)
  v_ctx := resolve_employee_attendance_location_context(v_employee.id, p_latitude, p_longitude, p_log_type);

  IF COALESCE((v_ctx->>'valid')::BOOLEAN, false) = false THEN
    RETURN jsonb_build_object(
      'success',           false,
      'code',              v_ctx->>'code',
      'error',             v_ctx->>'error',
      'nearest_location',  v_ctx->>'location_name',
      'distance_meters',   NULLIF(v_ctx->>'distance_meters', '')::NUMERIC
    );
  END IF;

  v_location_id   := NULLIF(v_ctx->>'location_id', '')::UUID;
  v_location_name := v_ctx->>'location_name';

  -- ★ GPS accuracy فحص بعد نجاح resolve (Wave 39 logic — unchanged)
  -- Threshold hierarchy: موقع.gps_accuracy_threshold → company_setting → 100m
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

  -- ── Work schedule settings ─────────────────────────────────
  SELECT COALESCE(value::INTEGER, 15) INTO v_late_grace
  FROM company_settings WHERE key = 'hr.late_grace_minutes';

  SELECT COALESCE(value, '08:00')::TIME INTO v_work_start
  FROM company_settings WHERE key = 'hr.work_start_time';

  SELECT COALESCE(value, '17:00')::TIME INTO v_work_end
  FROM company_settings WHERE key = 'hr.work_end_time';

  SELECT * INTO v_day
  FROM hr_attendance_days
  WHERE employee_id = v_employee.id AND shift_date = v_shift_date;

  -- ═══════════════════════════════════════════════════════════
  -- CHECK-IN (unchanged from Wave 39)
  -- ═══════════════════════════════════════════════════════════
  IF p_log_type = 'check_in' THEN
    IF FOUND AND v_day.punch_in_time IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'ALREADY_CHECKED_IN', 'error', 'لقد سجلت حضورك بالفعل اليوم');
    END IF;

    v_scheduled_start   := (v_shift_date::TEXT || ' ' || v_work_start::TEXT)::TIMESTAMP AT TIME ZONE 'Africa/Cairo';
    v_late_minutes      := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (v_event_time - v_scheduled_start)) / 60)::INTEGER - v_late_grace);
    v_attendance_status := CASE WHEN v_late_minutes > 0 THEN 'late' ELSE 'present' END;
    v_tracking_status   := 'active';

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
      updated_at             = now()
    RETURNING id INTO v_day_id;

  -- ═══════════════════════════════════════════════════════════
  -- CHECK-OUT
  -- ═══════════════════════════════════════════════════════════
  ELSE
    IF NOT FOUND OR v_day.punch_in_time IS NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'NOT_CHECKED_IN', 'error', 'يجب تسجيل الحضور أولاً');
    END IF;

    IF v_day.punch_out_time IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'ALREADY_CHECKED_OUT', 'error', 'لقد سجلت انصرافك بالفعل اليوم');
    END IF;

    v_scheduled_end    := (v_shift_date::TEXT || ' ' || v_work_end::TEXT)::TIMESTAMP AT TIME ZONE 'Africa/Cairo';
    v_early_minutes    := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (v_scheduled_end - v_event_time)) / 60)::INTEGER);
    v_overtime_minutes := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (v_event_time - v_scheduled_end)) / 60)::INTEGER);
    v_effective_hours  := ROUND((EXTRACT(EPOCH FROM (v_event_time - v_day.punch_in_time)) / 3600)::NUMERIC, 2);

    -- ★ FIX-2: حساب checkout_status مع فحص early_authorized
    -- يطابق منطق upsert_attendance_and_reprocess (Wave 37)
    IF v_overtime_minutes > 0 THEN
      v_checkout_status := 'overtime';
    ELSIF v_early_minutes > 0 THEN
      IF EXISTS (
        SELECT 1 FROM hr_leave_requests
        WHERE employee_id = v_employee.id
          AND start_date <= v_shift_date
          AND end_date   >= v_shift_date
          AND status = 'approved'
      )
      OR EXISTS (
        SELECT 1 FROM hr_permission_requests
        WHERE employee_id   = v_employee.id
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

    -- إعادة معالجة الجزاءات (Wave 39 pattern — SELECT INTO)
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
    'success',           true,
    'action',            p_log_type,
    'attendance_day_id', v_day_id,
    'log_id',            v_log_id,
    'location_name',     v_location_name,
    'location_id',       v_location_id,
    'shift_date',        v_shift_date,
    'event_time',        v_event_time,
    'tracking_status',   v_tracking_status,
    'penalties_applied', CASE WHEN p_log_type = 'check_out' THEN v_penalties_count ELSE NULL END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION record_attendance_gps_v2(NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- FIX-4: record_attendance_location_ping
--
-- التغيير الوحيد: في مسار v_low_accuracy
--   إضافة تحديث tracking_status: stale → active
--   لا يتغير أي شيء آخر في الدالة
--
-- منطق GPS النهائي محفوظ من Wave 39:
--   - location_in_id (لا work_location_id) كمرجع للـ threshold
--   - gps_accuracy_threshold عمود مباشر على hr_work_locations
--   - hr.default_gps_accuracy_threshold_meters كـ fallback
--   - v_low_accuracy path: لا lat/lng، لا outside_zone، لا location_id
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION record_attendance_location_ping(
  p_latitude    NUMERIC,
  p_longitude   NUMERIC,
  p_gps_accuracy NUMERIC,
  p_event_time  TIMESTAMPTZ DEFAULT NULL,
  p_device_info TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee           hr_employees%ROWTYPE;
  v_event_time         TIMESTAMPTZ := COALESCE(p_event_time, now());
  v_shift_date         DATE        := (COALESCE(p_event_time, now()) AT TIME ZONE 'Africa/Cairo')::date;
  v_day                hr_attendance_days%ROWTYPE;
  v_ctx                JSONB;
  v_location_id        UUID;
  v_location_name      TEXT;
  v_outside_zone       BOOLEAN := false;
  v_new_tracking_status TEXT;
  -- ★ GPS accuracy (Wave 39 variables — unchanged)
  v_accuracy_threshold NUMERIC;
  v_location_threshold NUMERIC;
  v_default_threshold  NUMERIC := 100;
  v_low_accuracy       BOOLEAN := false;
BEGIN
  SELECT * INTO v_employee
  FROM hr_employees
  WHERE user_id = auth.uid() AND status = 'active';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_EMPLOYEE', 'error', 'حسابك غير مرتبط بموظف نشط');
  END IF;

  SELECT * INTO v_day
  FROM hr_attendance_days
  WHERE employee_id = v_employee.id
    AND shift_date = v_shift_date
    AND punch_in_time IS NOT NULL
    AND punch_out_time IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_OPEN_DAY', 'error', 'لا يوجد يوم عمل مفتوح للتتبع');
  END IF;

  -- ★ GPS accuracy threshold (Wave 39 logic — unchanged)
  -- استخدام location_in_id من سجل اليوم (لا work_location_id من الموظف)
  SELECT COALESCE(value::NUMERIC, 100)
  INTO v_default_threshold
  FROM company_settings
  WHERE key = 'hr.default_gps_accuracy_threshold_meters';

  IF v_day.location_in_id IS NOT NULL THEN
    SELECT gps_accuracy_threshold
    INTO v_location_threshold
    FROM hr_work_locations
    WHERE id = v_day.location_in_id;
  END IF;

  v_accuracy_threshold := COALESCE(v_location_threshold, v_default_threshold, 100);
  v_low_accuracy := COALESCE(p_gps_accuracy, 0) > v_accuracy_threshold;

  -- ── low_accuracy path ─────────────────────────────────────
  IF v_low_accuracy THEN
    INSERT INTO hr_attendance_logs (
      employee_id, attendance_day_id, log_type,
      latitude, longitude, gps_accuracy, location_id,
      event_time, synced_at, requires_review, device_info
    ) VALUES (
      v_employee.id, v_day.id, 'location_ping',
      p_latitude, p_longitude,
      LEAST(COALESCE(p_gps_accuracy, 0), 999999.99),
      NULL, v_event_time, now(),
      true,   -- ★ requires_review=true لأن الدقة ضعيفة
      p_device_info
    );

    -- ★ FIX-4: تحديث last_tracking_ping_at + tracking_status إذا كانت stale
    -- stale + low_accuracy ping → active  (الجهاز يرسل فعلاً)
    -- active + low_accuracy ping → active (لا تغيير)
    -- outside_zone + low_accuracy → outside_zone (لا تغيير)
    -- ended → هذا المسار لا يُستدعى (شرط punch_out_time IS NULL أعلاه)
    UPDATE hr_attendance_days
    SET
      last_tracking_ping_at = v_event_time,
      tracking_ping_count   = tracking_ping_count + 1,
      tracking_status       = CASE
        WHEN tracking_status = 'stale' THEN 'active'
        ELSE tracking_status
      END,
      updated_at            = now()
    WHERE id = v_day.id;

    RETURN jsonb_build_object(
      'success',           true,
      'attendance_day_id', v_day.id,
      'low_accuracy',      true,
      'actual_accuracy',   p_gps_accuracy,
      'required_accuracy', v_accuracy_threshold,
      'tracking_status',   CASE
        WHEN v_day.tracking_status = 'stale' THEN 'active'
        ELSE v_day.tracking_status
      END,
      'last_ping_at',      v_event_time
    );
  END IF;

  -- ── normal accuracy path (unchanged from Wave 39) ─────────
  v_ctx := resolve_employee_attendance_location_context(v_employee.id, p_latitude, p_longitude, 'track');
  v_location_id   := NULLIF(v_ctx->>'location_id', '')::UUID;
  v_location_name := v_ctx->>'location_name';

  -- outside_zone = OUT_OF_RANGE فقط (مع دقة كافية)
  -- داخل النطاق قد لا يُرجع resolve أي code، لذا نطبع NULL إلى false
  v_outside_zone := COALESCE((v_ctx->>'code') = 'OUT_OF_RANGE', false);

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
    v_outside_zone, p_device_info
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
    review_status          = CASE
      WHEN v_outside_zone THEN 'needs_review'::hr_review_status
      WHEN review_status = 'reviewed' THEN 'reviewed'::hr_review_status
      ELSE review_status
    END,
    updated_at             = now()
  WHERE id = v_day.id;

  IF v_outside_zone THEN
    PERFORM upsert_attendance_alert(
      v_employee.id,
      v_day.id,
      'outside_allowed_zone',
      'high',
      'خروج من النطاق المسموح',
      COALESCE(v_ctx->>'error', 'تم اكتشاف نقطة تتبع خارج النطاق المسموح'),
      jsonb_build_object(
        'latitude',        p_latitude,
        'longitude',       p_longitude,
        'location_name',   v_location_name,
        'distance_meters', v_ctx->>'distance_meters'
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success',              true,
    'attendance_day_id',    v_day.id,
    'location_id',          v_location_id,
    'location_name',        v_location_name,
    'low_accuracy',         false,
    'outside_allowed_zone', v_outside_zone,
    'tracking_status',      v_new_tracking_status,
    'last_ping_at',         v_event_time
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- FIX-3: scan_attendance_tracking_alerts
--
-- الإضافة الوحيدة: auto-resolve لتنبيهات tracking_gap
-- المرجع: last_tracking_ping_at ضمن gap_minutes (لا tracking_status)
--
-- لا يتغير: منطق stale / outside_zone / permission_no_return
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION scan_attendance_tracking_alerts()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gap_minutes       INTEGER := 20;
  v_tracking_alerts   INTEGER := 0;
  v_permission_alerts INTEGER := 0;
BEGIN
  SELECT COALESCE(value::INTEGER, 20)
  INTO v_gap_minutes
  FROM company_settings
  WHERE key = 'hr.tracking_gap_minutes';

  -- ★ FIX-3: أغلق تنبيهات tracking_gap المفتوحة للأيام التي عادت إشارتها
  -- المرجع: last_tracking_ping_at حديثة (ضمن gap_minutes)
  -- يشمل كل أحوال اليوم المفتوح (active / outside_zone / stale)
  -- يُنفَّذ قبل كشف الانقطاعات الجديدة لتجنب فتح+إغلاق في نفس الدورة
  UPDATE hr_attendance_alerts a
  SET
    status          = 'resolved',
    resolved_at     = now(),
    resolution_note = 'عادت نقاط التتبع ضمن الحد الزمني — أُغلق التنبيه تلقائياً',
    updated_at      = now()
  FROM hr_attendance_days d
  WHERE a.alert_type          = 'tracking_gap'
    AND a.status              = 'open'
    AND a.attendance_day_id   = d.id
    AND d.punch_out_time      IS NULL
    AND d.last_tracking_ping_at IS NOT NULL
    AND d.last_tracking_ping_at >= now() - make_interval(mins => v_gap_minutes);

  -- ── كشف الانقطاعات الجديدة (unchanged from Wave 35) ─────
  -- active → stale (لا تكتب stale فوق outside_zone)
  WITH stale_days AS (
    SELECT id, employee_id, last_tracking_ping_at
    FROM hr_attendance_days
    WHERE punch_in_time IS NOT NULL
      AND punch_out_time IS NULL
      AND tracking_status = 'active'
      AND last_tracking_ping_at IS NOT NULL
      AND last_tracking_ping_at < now() - make_interval(mins => v_gap_minutes)
  )
  SELECT COUNT(*) INTO v_tracking_alerts FROM stale_days;

  UPDATE hr_attendance_days
  SET
    tracking_status = 'stale',
    review_status   = 'needs_review',
    updated_at      = now()
  WHERE id IN (
    SELECT id FROM hr_attendance_days
    WHERE punch_in_time IS NOT NULL
      AND punch_out_time IS NULL
      AND tracking_status = 'active'
      AND last_tracking_ping_at IS NOT NULL
      AND last_tracking_ping_at < now() - make_interval(mins => v_gap_minutes)
  );

  -- رفع تنبيه tracking_gap للأيام المنقطعة (stale)
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

  -- رفع tracking_gap للأيام outside_zone المنقطعة (unchanged from Wave 35)
  PERFORM upsert_attendance_alert(
    d.employee_id,
    d.id,
    'tracking_gap',
    'medium',
    'انقطاع في التتبع الدوري (خارج النطاق)',
    format('لم تصل نقاط تتبع منذ أكثر من %s دقيقة والموظف خارج النطاق', v_gap_minutes),
    jsonb_build_object('last_tracking_ping_at', d.last_tracking_ping_at, 'was_outside_zone', true)
  )
  FROM hr_attendance_days d
  WHERE d.punch_in_time IS NOT NULL
    AND d.punch_out_time IS NULL
    AND d.tracking_status = 'outside_zone'
    AND d.last_tracking_ping_at IS NOT NULL
    AND d.last_tracking_ping_at < now() - make_interval(mins => v_gap_minutes);

  -- ── أذونات بلا عودة (unchanged from Wave 35) ────────────
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
    AND p.expected_return IS NOT NULL
    AND d.employee_id = p.employee_id
    AND d.shift_date  = p.permission_date;

  PERFORM upsert_attendance_alert(
    p.employee_id,
    d.id,
    'permission_no_return',
    'high',
    'إذن خروج بلا عودة فعلية',
    'تم اعتماد إذن خروج ولم تُسجل عودة فعلية حتى الآن',
    jsonb_build_object(
      'permission_id',   p.id,
      'expected_return', p.expected_return,
      'permission_date', p.permission_date
    )
  )
  FROM hr_permission_requests p
  LEFT JOIN hr_attendance_days d
    ON d.employee_id = p.employee_id
   AND d.shift_date  = p.permission_date
  WHERE p.status = 'approved'
    AND p.actual_return IS NULL
    AND p.permission_date <= CURRENT_DATE
    AND p.expected_return IS NOT NULL;

  RETURN jsonb_build_object(
    'success',           true,
    'tracking_alerts',   v_tracking_alerts,
    'permission_alerts', v_permission_alerts
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- FIX-5: complete_permission_return
--
-- الإضافة الوحيدة: إغلاق تنبيه permission_no_return المفتوح
-- مقيّد بدقة بـ permission_id داخل metadata
-- (لا يغلق تنبيهات أذونات أخرى للموظف)
--
-- السلوك:
--   1. أغلق تنبيه permission_no_return المرتبط بهذا الطلب تحديداً
--   2. إذا كانت العودة متأخرة: فتح تنبيه جديد "عودة متأخرة"
--   3. إذا كانت العودة في الوقت أو مبكرة: لا تنبيه جديد
--
-- الحوكمة المحفوظة من Wave 35:
--   ✅ NULL check لـ v_employee_id
--   ✅ return_note بدل rejection_reason
--   ✅ FORBIDDEN guard
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION complete_permission_return(
  p_permission_id   UUID,
  p_actual_return   TIME,
  p_resolution_note TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_permission  hr_permission_requests%ROWTYPE;
  v_employee_id UUID;
  v_day_id      UUID;
BEGIN
  -- جلب سجل الموظف الحالي (قد يكون NULL لمستخدم إداري)
  SELECT id INTO v_employee_id
  FROM hr_employees
  WHERE user_id = auth.uid() AND status = 'active'
  LIMIT 1;

  SELECT * INTO v_permission
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

  -- فحص الصلاحية مع معالجة NULL صريحة (Wave 35)
  IF v_employee_id IS NULL THEN
    IF NOT check_permission(auth.uid(), 'hr.permissions.approve')
       AND NOT check_permission(auth.uid(), 'hr.attendance.edit') THEN
      RETURN jsonb_build_object('success', false, 'code', 'FORBIDDEN', 'error', 'غير مسموح لك بإغلاق هذا الإذن');
    END IF;
  ELSIF v_permission.employee_id <> v_employee_id THEN
    IF NOT check_permission(auth.uid(), 'hr.permissions.approve')
       AND NOT check_permission(auth.uid(), 'hr.attendance.edit') THEN
      RETURN jsonb_build_object('success', false, 'code', 'FORBIDDEN', 'error', 'غير مسموح لك بإغلاق هذا الإذن');
    END IF;
  END IF;

  -- تحديث actual_return (return_note — Wave 35)
  UPDATE hr_permission_requests
  SET
    actual_return = p_actual_return,
    updated_at    = now(),
    return_note   = p_resolution_note
  WHERE id = p_permission_id;

  -- جلب يوم الحضور المقابل
  SELECT id INTO v_day_id
  FROM hr_attendance_days
  WHERE employee_id = v_permission.employee_id
    AND shift_date  = v_permission.permission_date;

  -- ★ FIX-5: أغلق تنبيه permission_no_return المرتبط بهذا الطلب تحديداً
  -- مقيّد بـ permission_id داخل metadata لمنع إغلاق تنبيهات أذونات أخرى
  -- يشمل حالتين:
  --   أ) تنبيه مرتبط بيوم حضور (attendance_day_id = v_day_id)
  --   ب) تنبيه بدون يوم حضور (NULL) — مع تقييد بـ permission_id في metadata
  UPDATE hr_attendance_alerts
  SET
    status          = 'resolved',
    resolved_at     = now(),
    resolution_note = 'تم تسجيل العودة الفعلية — أُغلق التنبيه تلقائياً',
    updated_at      = now()
  WHERE employee_id  = v_permission.employee_id
    AND alert_type   = 'permission_no_return'
    AND status       = 'open'
    AND (
      -- ★ التقييد بـ permission_id من metadata يمنع إغلاق أذونات أخرى
      (metadata->>'permission_id') = p_permission_id::TEXT
      OR
      -- fallback للتنبيهات القديمة التي لم تُنشأ بـ permission_id في metadata
      -- مقيّدة بيوم الحضور الفعلي
      (
        (metadata->>'permission_id') IS NULL
        AND (
          (v_day_id IS NOT NULL AND attendance_day_id = v_day_id)
          OR (v_day_id IS NULL  AND attendance_day_id IS NULL)
        )
      )
    );

  -- ── إذا كانت العودة متأخرة: فتح تنبيه جديد ─────────────
  IF v_day_id IS NOT NULL
     AND v_permission.expected_return IS NOT NULL
     AND p_actual_return > v_permission.expected_return
  THEN
    UPDATE hr_attendance_days
    SET review_status = 'needs_review', updated_at = now()
    WHERE id = v_day_id;

    -- تنبيه جديد يعبر عن "عودة متأخرة" — لا "بلا عودة"
    PERFORM upsert_attendance_alert(
      v_permission.employee_id,
      v_day_id,
      'permission_no_return',
      'medium',
      'عودة متأخرة من إذن الخروج',
      'تمت العودة الفعلية بعد الموعد المتوقع ويحتاج اليوم إلى مراجعة إدارية',
      jsonb_build_object(
        'permission_id',   p_permission_id,
        'expected_return', v_permission.expected_return,
        'actual_return',   p_actual_return,
        'late_return',     true
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success',       true,
    'permission_id', p_permission_id,
    'actual_return', p_actual_return
  );
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- COMMENTS
-- ═══════════════════════════════════════════════════════════════

COMMENT ON FUNCTION get_attendance_review_summary(DATE, DATE) IS
'Wave 41 FIX-1: total_blocking_items = عدد فئات (0-4) لا جمع متداخل.
 open_day_unclosed لا يزال من hr_attendance_alerts (لا من جدول الأيام مباشرة)
 للتسق مع check_payroll_attendance_clearance.';

COMMENT ON FUNCTION record_attendance_gps_v2(NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ) IS
'Wave 41 FIX-2: إضافة فحص early_authorized في check_out فقط.
 منطق GPS النهائي من Wave 39 محفوظ: gps_accuracy_threshold + hr.default_gps_accuracy_threshold_meters.';

COMMENT ON FUNCTION record_attendance_location_ping(NUMERIC, NUMERIC, NUMERIC, TIMESTAMPTZ, TEXT) IS
'Wave 41 FIX-4: في مسار low_accuracy: stale → active فقط.
 منطق Wave 39 محفوظ: location_in_id + gps_accuracy_threshold.';

COMMENT ON FUNCTION scan_attendance_tracking_alerts() IS
'Wave 41 FIX-3: auto-resolve tracking_gap عند عودة التتبع.
 المرجع: last_tracking_ping_at ضمن gap_minutes. لا يتغير باقي المنطق.';

COMMENT ON FUNCTION complete_permission_return(UUID, TIME, TEXT) IS
'Wave 41 FIX-5: إغلاق permission_no_return مقيّد بـ permission_id في metadata.
 يمنع إغلاق تنبيهات أذونات أخرى للموظف نفسه.';

-- ═══════════════════════════════════════════════════════════════
-- END OF MIGRATION 41 (REVISED)
-- ═══════════════════════════════════════════════════════════════
