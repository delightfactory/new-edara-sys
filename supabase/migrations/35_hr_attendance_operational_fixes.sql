-- ═══════════════════════════════════════════════════════════════
-- 35_hr_attendance_operational_fixes.sql
-- HR Attendance Operational Fixes — Wave A+B
-- 
-- Additive & non-destructive. Safe to re-run (idempotent).
--
-- Fixes:
--   1. NULL-check in complete_permission_return (ownership bypass)
--   2. Separate return_note from rejection_reason
--   3. Explicit Cairo timezone in scheduled_start/end
--   4. Return tracking_status from record_attendance_gps_v2
--   5. Add outside_zone to tracking_status CHECK
--   6. Fix valid=false ≠ outside_zone in ping function
--   7. Update scan_attendance_tracking_alerts to respect outside_zone
--   8. Schedule pg_cron job for scan_attendance_tracking_alerts
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1) إضافة عمود return_note إلى hr_permission_requests
-- ─────────────────────────────────────────────────────────────

ALTER TABLE hr_permission_requests
  ADD COLUMN IF NOT EXISTS return_note TEXT;

-- Backfill: نقل القيم من rejection_reason → return_note
-- فقط للسجلات المعتمدة التي لها عودة فعلية ولها rejection_reason
-- (بمعنى أن rejection_reason كان يُستخدم كملاحظة عودة)
UPDATE hr_permission_requests
SET
  return_note = rejection_reason,
  rejection_reason = NULL
WHERE status = 'approved'
  AND actual_return IS NOT NULL
  AND rejection_reason IS NOT NULL
  AND return_note IS NULL;

-- ─────────────────────────────────────────────────────────────
-- 2) توسيع CHECK constraint لـ tracking_status ← outside_zone
-- ─────────────────────────────────────────────────────────────

ALTER TABLE hr_attendance_days
  DROP CONSTRAINT IF EXISTS hr_attendance_days_tracking_status_check;

ALTER TABLE hr_attendance_days
  ADD CONSTRAINT hr_attendance_days_tracking_status_check
  CHECK (tracking_status IN ('idle', 'active', 'ended', 'stale', 'outside_zone'));

-- ─────────────────────────────────────────────────────────────
-- 3) إعادة تعريف complete_permission_return — سد ثغرة NULL
-- ─────────────────────────────────────────────────────────────

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
  -- جلب سجل الموظف الحالي (قد يكون NULL)
  SELECT id
  INTO v_employee_id
  FROM hr_employees
  WHERE user_id = auth.uid()
    AND status = 'active'
  LIMIT 1;

  -- جلب الإذن
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

  -- ★ فحص الصلاحية مع معالجة NULL صريحة
  IF v_employee_id IS NULL THEN
    -- ليس موظفاً → يحتاج صلاحية إدارية
    IF NOT check_permission(auth.uid(), 'hr.permissions.approve')
       AND NOT check_permission(auth.uid(), 'hr.attendance.edit') THEN
      RETURN jsonb_build_object('success', false, 'code', 'FORBIDDEN', 'error', 'غير مسموح لك بإغلاق هذا الإذن');
    END IF;
  ELSIF v_permission.employee_id <> v_employee_id THEN
    -- موظف مختلف → يحتاج صلاحية إدارية
    IF NOT check_permission(auth.uid(), 'hr.permissions.approve')
       AND NOT check_permission(auth.uid(), 'hr.attendance.edit') THEN
      RETURN jsonb_build_object('success', false, 'code', 'FORBIDDEN', 'error', 'غير مسموح لك بإغلاق هذا الإذن');
    END IF;
  END IF;

  -- تحديث الإذن — ★ return_note بدل rejection_reason
  UPDATE hr_permission_requests
  SET
    actual_return = p_actual_return,
    updated_at = now(),
    return_note = p_resolution_note
  WHERE id = p_permission_id;

  -- تحديث يوم الحضور إذا وُجد
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
-- 4) إعادة تعريف record_attendance_gps_v2
--    ★ تثبيت timezone صريحاً
--    ★ إرجاع tracking_status في الاستجابة
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

    -- ★ تثبيت التوقيت صراحة بتوقيت القاهرة
    v_scheduled_start := (v_shift_date::TEXT || ' ' || v_work_start::TEXT)::TIMESTAMP
                          AT TIME ZONE 'Africa/Cairo';
    v_late_minutes := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (v_event_time - v_scheduled_start)) / 60)::INTEGER - v_late_grace);
    v_attendance_status := CASE WHEN v_late_minutes > 0 THEN 'late' ELSE 'present' END;

    v_tracking_status := 'active';

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

    -- ★ تثبيت التوقيت صراحة بتوقيت القاهرة
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

  -- ★ إرجاع tracking_status ضمن الاستجابة
  RETURN jsonb_build_object(
    'success', true,
    'action', p_log_type,
    'attendance_day_id', v_day_id,
    'log_id', v_log_id,
    'location_name', v_location_name,
    'location_id', v_location_id,
    'shift_date', v_shift_date,
    'event_time', v_event_time,
    'tracking_status', v_tracking_status
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 5) إعادة تعريف record_attendance_location_ping
--    ★ outside_zone بدل stale عند الخروج من النطاق
--    ★ valid=false لا يعني بالضرورة خروج من النطاق
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

  -- ★ الخروج من النطاق = OUT_OF_RANGE فقط
  -- لا نعتبر NO_EMPLOYEE أو NO_ALLOWED_LOCATIONS خروجاً من النطاق
  v_outside_zone := (v_ctx ->> 'code') = 'OUT_OF_RANGE';

  -- ★ تحديد tracking_status الجديدة
  IF v_outside_zone THEN
    v_new_tracking_status := 'outside_zone';
  ELSE
    v_new_tracking_status := 'active';
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
    tracking_status = v_new_tracking_status,
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
    'tracking_status', v_new_tracking_status,
    'last_ping_at', v_event_time
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 6) إعادة تعريف scan_attendance_tracking_alerts
--    ★ لا تكتب stale فوق outside_zone
--    ★ الانقطاع الزمني فقط = stale
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

  -- ★ الانقطاع الزمني يحول active → stale فقط
  -- لا نكتب stale فوق outside_zone
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
    review_status = 'needs_review',
    updated_at = now()
  WHERE id IN (
    SELECT id
    FROM hr_attendance_days
    WHERE punch_in_time IS NOT NULL
      AND punch_out_time IS NULL
      AND tracking_status = 'active'
      AND last_tracking_ping_at IS NOT NULL
      AND last_tracking_ping_at < now() - make_interval(mins => v_gap_minutes)
  );

  -- رفع تنبيه tracking_gap للأيام المنقطعة
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

  -- ★ رفع tracking_gap أيضاً للأيام outside_zone المنقطعة
  -- لكن بدون تغيير tracking_status (يبقى outside_zone)
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

  -- فحص الأذونات المفتوحة بلا عودة
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
-- 7) جدولة pg_cron — فحص التنبيهات كل 15 دقيقة
-- ─────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- حذف أي job قديم بنفس الاسم لتجنب التكرار
    BEGIN
      PERFORM cron.unschedule('scan-attendance-alerts');
    EXCEPTION WHEN OTHERS THEN
      NULL; -- تجاهل إذا لم تكن موجودة
    END;

    PERFORM cron.schedule(
      'scan-attendance-alerts',
      '*/15 * * * *',
      'SELECT public.scan_attendance_tracking_alerts();'
    );
    RAISE NOTICE '[EDARA] ✅ تم جدولة فحص تنبيهات الحضور كل 15 دقيقة';
  ELSE
    RAISE NOTICE '[EDARA] ⚠️ pg_cron غير مفعل — يُرجى جدولة يدوياً من Supabase Dashboard:';
    RAISE NOTICE 'SELECT cron.schedule(''scan-attendance-alerts'', ''*/15 * * * *'', ''SELECT public.scan_attendance_tracking_alerts();'');';
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════
-- END OF MIGRATION 35
-- ═══════════════════════════════════════════════════════════════
