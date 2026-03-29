-- =============================================================
-- Migration 20a: Attendance GPS Recording RPC (CORRECTED v2)
-- EDARA v2 — تسجيل الحضور الذري عبر RPC واحدة
--
-- المشكلة: logAttendanceGPS كانت تكتب في hr_attendance_logs فقط
--          بدون إنشاء/تحديث hr_attendance_days
-- الحل: RPC واحدة SECURITY DEFINER تقوم بالعملية كاملة
--
-- التصحيحات في هذه النسخة:
--   1. نقل كل المتغيرات إلى DECLARE الرئيسية (DECLARE داخل IF غير مدعوم)
--   2. إضافة validation على p_log_type
--   3. إضافة hr.attendance_gps_required في الـ seed
--   4. case-insensitive boolean check
--   5. حذف v_validation غير المستخدم
-- =============================================================


-- =============================================================
-- إصلاح عاجل: day_value NUMERIC(4,4) لا تستوعب قيمة 1.0
-- النوع الصحيح: NUMERIC(5,4) يستوعب حتى 9.9999
-- =============================================================
ALTER TABLE hr_attendance_days
  ALTER COLUMN day_value TYPE NUMERIC(5,4)
  USING day_value::NUMERIC(5,4);

ALTER TABLE hr_attendance_days
  ALTER COLUMN day_value SET DEFAULT 1.0;


-- =============================================================
-- FUNCTION: record_attendance_gps
-- الوصف: تسجيل حضور/انصراف الموظف بشكل ذري في معاملة واحدة
-- المدخلات:
--   p_latitude     — خط العرض
--   p_longitude    — خط الطول
--   p_gps_accuracy — دقة GPS بالأمتار
--   p_log_type     — 'check_in' | 'check_out'
--   p_event_time   — وقت الحدث (NULL = now())
-- المخرجات: JSONB
--   { success, action, attendance_day_id, log_id,
--     location_name, location_id, shift_date, event_time }
--   أو { success:false, code, error }
-- =============================================================

CREATE OR REPLACE FUNCTION record_attendance_gps(
  p_latitude      NUMERIC,
  p_longitude     NUMERIC,
  p_gps_accuracy  NUMERIC,
  p_log_type      TEXT,         -- 'check_in' | 'check_out'
  p_event_time    TIMESTAMPTZ DEFAULT NULL
) RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  -- ─── هوية الموظف ───────────────────────────────────────────
  v_employee_id     UUID;
  v_is_field        BOOLEAN;

  -- ─── وقت ومكان ─────────────────────────────────────────────
  v_event_time      TIMESTAMPTZ;
  v_shift_date      DATE;

  -- ─── إعدادات ───────────────────────────────────────────────
  v_gps_required    BOOLEAN;
  v_threshold       INTEGER;
  v_work_start      TIME;
  v_work_end        TIME;

  -- ─── دقة GPS الآمنة ───────────────────────────────────
  -- NUMERIC(8,2) تستوعب حتى 999,999.99م — نحدّد القيمة لتجنب overflow
  -- المتصفح قد يرسل قيم كبيرة (شبكة خلوية = 100كم+)
  v_gps_safe        NUMERIC(8,2);

  -- ─── الموقع ────────────────────────────────────────────────
  v_location_id     UUID;
  v_location_name   TEXT;
  v_loc_row         hr_work_locations%ROWTYPE;
  v_distance        NUMERIC;

  -- ─── اليوم ─────────────────────────────────────────────────
  v_existing_day    hr_attendance_days%ROWTYPE;
  v_day_id          UUID;
  v_log_id          UUID;

  -- ─── حساب الحضور ───────────────────────────────────────────
  v_att_status      hr_attendance_status;
  v_late_min        INTEGER;
  v_scheduled_start TIMESTAMPTZ;

  -- ─── حساب الانصراف ─────────────────────────────────────────
  v_check_in_ts     TIMESTAMPTZ;
  v_eff_hours       NUMERIC;
  v_ot_min          INTEGER;
  v_early_min       INTEGER;
  v_sched_end       TIMESTAMPTZ;
  v_co_status       hr_checkout_status;

BEGIN

  -- ─── 0. التحقق من صحة p_log_type ──────────────────────────
  IF p_log_type NOT IN ('check_in', 'check_out') THEN
    RETURN jsonb_build_object(
      'success', false,
      'code',    'INVALID_LOG_TYPE',
      'error',   format('نوع السجل غير صحيح: %s. المقبول: check_in أو check_out', p_log_type)
    );
  END IF;

  -- ─── 0b. تأمين دقة GPS من Overflow ─────────────────────────
  -- NUMERIC(8,2) تستوعب حتى 999,999.99م
  -- المتصفح يرسل احياناً 100,000م+ (شبكة خلوية بدون GPS)
  v_gps_safe := LEAST(COALESCE(ROUND(p_gps_accuracy::NUMERIC, 2), 0), 999999.99);

  -- ─── 1. التحقق من هوية المستخدم ────────────────────────────
  SELECT id, is_field_employee
  INTO   v_employee_id, v_is_field
  FROM   hr_employees
  WHERE  user_id = auth.uid()
    AND  status  = 'active';

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'code',    'NO_EMPLOYEE',
      'error',   'حسابك غير مرتبط بموظف نشط'
    );
  END IF;

  -- ─── 2. وقت الحدث والتاريخ ──────────────────────────────────
  v_event_time := COALESCE(p_event_time, now());
  v_shift_date := (v_event_time AT TIME ZONE 'Africa/Cairo')::DATE;

  -- ─── 3. هل التحقق من GPS إلزامي؟ ───────────────────────────
  SELECT COALESCE(
    (SELECT lower(value) = 'true'
     FROM   company_settings
     WHERE  key = 'hr.attendance_gps_required'),
    false
  ) INTO v_gps_required;

  -- ─── 4. التحقق من دقة GPS (إذا كان إلزامياً) ───────────────
  IF v_gps_required THEN
    SELECT COALESCE(
      (SELECT gps_accuracy_threshold
       FROM   hr_work_locations
       WHERE  is_active = true
       ORDER  BY id
       LIMIT  1),
      150
    ) INTO v_threshold;

    IF p_gps_accuracy IS NOT NULL AND p_gps_accuracy > v_threshold THEN
      RETURN jsonb_build_object(
        'success', false,
        'code',    'LOW_GPS_ACCURACY',
        'error',   format('دقة GPS منخفضة (%sم). الحد المسموح: %sم',
                          p_gps_accuracy::int, v_threshold)
      );
    END IF;
  END IF;

  -- ─── 5. التحقق من الموقع الجغرافي ──────────────────────────
  IF v_is_field THEN
    -- الموظف الميداني: يُسجَّل من أي موقع — نجلب أقرب موقع للتوثيق فقط
    SELECT id, name
    INTO   v_location_id, v_location_name
    FROM   hr_work_locations
    WHERE  is_active = true
    ORDER  BY (
      6371000 * acos(LEAST(1.0,
        cos(radians(latitude)) * cos(radians(p_latitude))
        * cos(radians(p_longitude) - radians(longitude))
        + sin(radians(latitude)) * sin(radians(p_latitude))
      ))
    ) ASC
    LIMIT 1;
    -- لا يُشترط وجود موقع — v_location_id قد يكون NULL

  ELSIF v_gps_required THEN
    -- موظف ثابت مع GPS إلزامي: يجب أن يكون ضمن النطاق
    SELECT *
    INTO   v_loc_row
    FROM   hr_work_locations
    WHERE  is_active = true
    ORDER  BY (
      6371000 * acos(LEAST(1.0,
        cos(radians(latitude)) * cos(radians(p_latitude))
        * cos(radians(p_longitude) - radians(longitude))
        + sin(radians(latitude)) * sin(radians(p_latitude))
      ))
    ) ASC
    LIMIT 1;

    IF NOT FOUND THEN
      RETURN jsonb_build_object(
        'success', false,
        'code',    'NO_LOCATION_FOUND',
        'error',   'لا توجد مواقع عمل نشطة في النظام'
      );
    END IF;

    -- حساب المسافة الفعلية
    v_distance := 6371000 * acos(LEAST(1.0,
      cos(radians(v_loc_row.latitude)) * cos(radians(p_latitude))
      * cos(radians(p_longitude) - radians(v_loc_row.longitude))
      + sin(radians(v_loc_row.latitude)) * sin(radians(p_latitude))
    ));

    IF v_distance > v_loc_row.radius_meters THEN
      RETURN jsonb_build_object(
        'success',          false,
        'code',             'OUT_OF_RANGE',
        'error',            format('أنت خارج النطاق. المسافة: %sم، الحد المسموح: %sم',
                                   round(v_distance), v_loc_row.radius_meters),
        'nearest_location', v_loc_row.name,
        'distance_meters',  round(v_distance)
      );
    END IF;

    v_location_id   := v_loc_row.id;
    v_location_name := v_loc_row.name;

  ELSE
    -- GPS غير إلزامي: نجلب الاسم للتوثيق فقط (بدون رفض)
    SELECT id, name
    INTO   v_location_id, v_location_name
    FROM   hr_work_locations
    WHERE  is_active = true
    ORDER  BY (
      6371000 * acos(LEAST(1.0,
        cos(radians(latitude)) * cos(radians(p_latitude))
        * cos(radians(p_longitude) - radians(longitude))
        + sin(radians(latitude)) * sin(radians(p_latitude))
      ))
    ) ASC
    LIMIT 1;
  END IF;

  -- ─── 6. التحقق من منطق الحضور/الانصراف ────────────────────
  SELECT *
  INTO   v_existing_day
  FROM   hr_attendance_days
  WHERE  employee_id = v_employee_id
    AND  shift_date  = v_shift_date;

  IF p_log_type = 'check_in' THEN
    -- منع تكرار الحضور
    IF FOUND AND v_existing_day.punch_in_time IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'code',    'ALREADY_CHECKED_IN',
        'error',   'لقد سجلت حضورك بالفعل اليوم'
      );
    END IF;

  ELSE -- check_out
    -- يجب أن يكون الموظف قد سجّل حضوره أولاً
    IF NOT FOUND OR v_existing_day.punch_in_time IS NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'code',    'NOT_CHECKED_IN',
        'error',   'يجب تسجيل الحضور أولاً قبل تسجيل الانصراف'
      );
    END IF;
    -- منع تكرار الانصراف
    IF v_existing_day.punch_out_time IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'code',    'ALREADY_CHECKED_OUT',
        'error',   'لقد سجلت انصرافك بالفعل اليوم'
      );
    END IF;
  END IF;

  -- ─── 7. check_in: حساب التأخير والحالة ─────────────────────
  v_late_min   := 0;
  v_att_status := 'present';

  IF p_log_type = 'check_in' THEN
    -- المفتاح الصحيح: hr.work_start_time (كما تحفظه صفحة إعدادات HR)
    SELECT value::TIME
    INTO   v_work_start
    FROM   company_settings
    WHERE  key = 'hr.work_start_time';

    IF v_work_start IS NOT NULL THEN
      v_scheduled_start := (v_shift_date + v_work_start) AT TIME ZONE 'Africa/Cairo';

      IF v_event_time > v_scheduled_start + INTERVAL '5 minutes' THEN
        v_late_min   := EXTRACT(EPOCH FROM (v_event_time - v_scheduled_start))::INTEGER / 60;
        v_att_status := CASE
          WHEN v_late_min > 120 THEN 'half_day'::hr_attendance_status
          ELSE                       'late'::hr_attendance_status
        END;
      END IF;
    END IF;

    -- ─── UPSERT hr_attendance_days (check_in) ───────────────
    -- day_value: قيمة يوم العمل (1.0=كامل, 0.5=نصف, 0.0=غياب)
    -- NUMERIC(5,4) بعد إصلاح النوع — كان NUMERIC(4,4) يمنع تخزين 1.0
    INSERT INTO hr_attendance_days (
      employee_id,    shift_date,      work_date,
      punch_in_time,  location_in_id,  gps_accuracy_in,
      status,         late_minutes,    day_value
    ) VALUES (
      v_employee_id,  v_shift_date,    v_shift_date,
      v_event_time,   v_location_id,   v_gps_safe,
      v_att_status,   v_late_min,
      CASE v_att_status
        WHEN 'half_day' THEN 0.5
        WHEN 'present'  THEN 1.0
        WHEN 'late'     THEN 1.0
        ELSE                 1.0
      END
    )
    ON CONFLICT (employee_id, shift_date) DO UPDATE SET
      punch_in_time   = EXCLUDED.punch_in_time,
      location_in_id  = EXCLUDED.location_in_id,
      gps_accuracy_in = EXCLUDED.gps_accuracy_in,
      status          = EXCLUDED.status,
      late_minutes    = EXCLUDED.late_minutes,
      day_value       = EXCLUDED.day_value,
      updated_at      = now()
    RETURNING id INTO v_day_id;

  ELSE
    -- ─── 8. check_out: حساب ساعات العمل والأوفرتايم ─────────
    v_check_in_ts := v_existing_day.punch_in_time;
    -- NUMERIC(4,2) تستوعب حتى 99.99 ساعة — نحدّد لتجنب overflow
    v_eff_hours   := LEAST(
      ROUND(EXTRACT(EPOCH FROM (v_event_time - v_check_in_ts)) / 3600.0, 2),
      99.99
    );
    v_ot_min      := 0;
    v_early_min   := 0;
    v_co_status   := 'on_time';

    -- المفتاح الصحيح: hr.work_end_time (كما تحفظه صفحة إعدادات HR)
    SELECT value::TIME
    INTO   v_work_end
    FROM   company_settings
    WHERE  key = 'hr.work_end_time';

    IF v_work_end IS NOT NULL THEN
      v_sched_end := (v_shift_date + v_work_end) AT TIME ZONE 'Africa/Cairo';

      IF v_event_time > v_sched_end + INTERVAL '30 minutes' THEN
        -- أوفرتايم
        v_ot_min    := EXTRACT(EPOCH FROM (v_event_time - v_sched_end))::INTEGER / 60;
        v_co_status := 'overtime';
      ELSIF v_event_time < v_sched_end - INTERVAL '5 minutes' THEN
        -- انصراف مبكر
        v_early_min := EXTRACT(EPOCH FROM (v_sched_end - v_event_time))::INTEGER / 60;
        v_co_status := 'early_unauthorized';
      END IF;
    END IF;

    -- ─── UPDATE hr_attendance_days (check_out) ──────────────
    UPDATE hr_attendance_days SET
      punch_out_time      = v_event_time,
      location_out_id     = v_location_id,
      gps_accuracy_out    = v_gps_safe,
      effective_hours     = v_eff_hours,
      overtime_minutes    = v_ot_min,
      early_leave_minutes = v_early_min,
      checkout_status     = v_co_status,
      -- تحديث day_value: يبقى 0.5 إذا كان half_day، وإلا 1.0
      day_value           = CASE (SELECT status FROM hr_attendance_days
                                  WHERE employee_id = v_employee_id AND shift_date = v_shift_date)
                              WHEN 'half_day' THEN 0.5
                              ELSE                 1.0
                            END,
      updated_at          = now()
    WHERE  employee_id = v_employee_id
      AND  shift_date  = v_shift_date
    RETURNING id INTO v_day_id;

  END IF;

  -- ─── 9. إدراج سجل GPS في hr_attendance_logs ─────────────────
  INSERT INTO hr_attendance_logs (
    employee_id,     attendance_day_id,
    log_type,        latitude,         longitude,
    gps_accuracy,    location_id,
    is_offline_sync, event_time
  ) VALUES (
    v_employee_id,   v_day_id,
    p_log_type,      p_latitude,       p_longitude,
    v_gps_safe,      v_location_id,
    false,           v_event_time
  )
  RETURNING id INTO v_log_id;

  -- ─── 10. إرجاع النتيجة ───────────────────────────────────────
  RETURN jsonb_build_object(
    'success',           true,
    'action',            p_log_type,
    'attendance_day_id', v_day_id,
    'log_id',            v_log_id,
    'location_name',     v_location_name,
    'location_id',       v_location_id,
    'shift_date',        v_shift_date,
    'event_time',        v_event_time
  );

EXCEPTION

  -- overflow رقمي — نتعرف عليه بشكل منفصل مع بيانات تشخيصية
  WHEN numeric_value_out_of_range THEN
    RETURN jsonb_build_object(
      'success',      false,
      'code',         'NUMERIC_OVERFLOW',
      'error',        SQLERRM,
      '_debug', jsonb_build_object(
        'gps_raw',        COALESCE(p_gps_accuracy::TEXT, 'null'),
        'gps_safe',       COALESCE(v_gps_safe::TEXT,     'null'),
        'latitude',       COALESCE(p_latitude::TEXT,     'null'),
        'longitude',      COALESCE(p_longitude::TEXT,    'null'),
        'late_min',       COALESCE(v_late_min::TEXT,     'null'),
        'day_created',    CASE WHEN v_day_id IS NOT NULL THEN 'YES' ELSE 'NO - failed in days INSERT' END,
        'log_created',    CASE WHEN v_log_id IS NOT NULL THEN 'YES' ELSE 'NO - failed in logs INSERT' END,
        'eff_hours_raw',  COALESCE(v_eff_hours::TEXT,    'null')
      )
    );

  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'code',    'INTERNAL_ERROR',
      'error',   SQLERRM
    );

END; $$;

-- =============================================================
-- صلاحية التنفيذ: المستخدمون المصادق عليهم فقط
-- =============================================================
GRANT EXECUTE ON FUNCTION record_attendance_gps(NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ)
  TO authenticated;

-- =============================================================
-- إعدادات وقت الدوام والمفاتيح المتعلقة بالحضور
-- =============================================================
INSERT INTO company_settings (key, value, type, description, category, is_public) VALUES
  -- ── وقت الدوام (المفاتيح الفعلية التى تستخدمها صفحة الإعدادات) ──
  ('hr.work_start_time',         '09:00', 'text',    'وقت بدء الدوام الرسمي (HH:MM)',      'hr', false),
  ('hr.work_end_time',           '17:00', 'text',    'وقت انتهاء الدوام الرسمي (HH:MM)',   'hr', false),
  -- ── إلزامية GPS ──
  ('hr.attendance_gps_required', 'false', 'boolean', 'هل يُشترط التحقق من الموقع الجغرافي للحضور', 'hr', false)
ON CONFLICT (key) DO NOTHING;
