-- =============================================================
-- Migration 20b: Audit Fixes — إصلاحات التدقيق النهائي
-- EDARA v2
--
-- هذا الملف يُطبِّق جميع إصلاحات التدقيق في مكان واحد:
--
-- DDL CHANGES:
--   • ALTER TABLE hr_payroll_lines ADD updated_at (كان مفقوداً)
--
-- FUNCTION PATCHES (CREATE OR REPLACE — آمن على DB موجودة):
--   • FIX-AUDIT-01: record_attendance_gps — إضافة ±24h timestamp validation
--   • FIX-AUDIT-02: record_attendance_gps — إضافة hr_permission_requests check
--   • FIX-AUDIT-04: create_auto_journal_entry — إضافة p_amount > 0 guard
--
-- NEW FUNCTIONS:
--   • FIX-AUDIT-06: update_payroll_line_adjustments — إعادة حساب net_salary
--   • FIX-AUDIT-07: upsert_attendance_and_reprocess — إعادة تشغيل الجزاءات
-- =============================================================


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  DDL: إضافة عمود updated_at في hr_payroll_lines          ║
-- ║  (الجدول كان يحتوي فقط على created_at)                   ║
-- ╚═══════════════════════════════════════════════════════════╝

ALTER TABLE hr_payroll_lines
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- trigger لتحديث updated_at تلقائياً
DROP TRIGGER IF EXISTS trg_payroll_lines_updated_at ON hr_payroll_lines;
CREATE TRIGGER trg_payroll_lines_updated_at
  BEFORE UPDATE ON hr_payroll_lines
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  FIX-AUDIT-04: create_auto_journal_entry                 ║
-- ║  إضافة فحص p_amount > 0 لمنع القيود الصفرية/السالبة    ║
-- ╚═══════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION create_auto_journal_entry(
  p_source_type   TEXT,
  p_source_id     UUID,
  p_description   TEXT,
  p_debit_account TEXT,     -- كود الحساب المدين
  p_credit_account TEXT,    -- كود الحساب الدائن
  p_amount        NUMERIC,
  p_user_id       UUID
) RETURNS UUID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_entry_id    UUID;
  v_debit_acct  UUID;
  v_credit_acct UUID;
BEGIN
  -- FIX-AUDIT-04: رفض مبالغ صفرية أو سالبة
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'create_auto_journal_entry: المبلغ يجب أن يكون أكبر من صفر (القيمة: %)', COALESCE(p_amount, 0);
  END IF;

  -- جلب معرّفات الحسابات من الأكواد
  SELECT id INTO v_debit_acct FROM chart_of_accounts WHERE code = p_debit_account;
  IF v_debit_acct IS NULL THEN
    RAISE EXCEPTION 'حساب مدين غير موجود: %', p_debit_account;
  END IF;

  SELECT id INTO v_credit_acct FROM chart_of_accounts WHERE code = p_credit_account;
  IF v_credit_acct IS NULL THEN
    RAISE EXCEPTION 'حساب دائن غير موجود: %', p_credit_account;
  END IF;

  -- إنشاء القيد (total_debit = total_credit → يمر من CHECK constraint)
  INSERT INTO journal_entries (
    source_type, source_id, description, is_auto,
    total_debit, total_credit, created_by
  ) VALUES (
    p_source_type, p_source_id, p_description, true,
    p_amount, p_amount, p_user_id
  )
  RETURNING id INTO v_entry_id;

  -- إدراج السطر المدين
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  VALUES (v_entry_id, v_debit_acct, p_amount, 0, p_description);

  -- إدراج السطر الدائن
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  VALUES (v_entry_id, v_credit_acct, 0, p_amount, p_description);

  RETURN v_entry_id;
END; $$;


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  FIX-AUDIT-01 + FIX-AUDIT-02: record_attendance_gps      ║
-- ║  ① إضافة ±24h timestamp validation                       ║
-- ║  ② إضافة hr_permission_requests في فحص الانصراف المبكر   ║
-- ║                                                           ║
-- ║  ⚠ هذه نسخة كاملة من الدالة — كل السطر الأصلي + التعديل  ║
-- ║    التوقيع مطابق 100% للأصلي                              ║
-- ╚═══════════════════════════════════════════════════════════╝

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

  -- ─── FIX-01: فترة السماح بالتأخير (من الإعدادات) ──────────
  v_grace_min       INTEGER;

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

  -- FIX-AUDIT-01: رفض أوقات مستقبلية أو أقدم من 24 ساعة
  -- يمنع التلاعب بالحضور عبر إرسال p_event_time مزوّر
  IF v_event_time > now() + INTERVAL '5 minutes' THEN
    RETURN jsonb_build_object(
      'success', false,
      'code',    'FUTURE_TIME',
      'error',   'لا يمكن تسجيل حضور في المستقبل'
    );
  END IF;
  IF v_event_time < now() - INTERVAL '24 hours' THEN
    RETURN jsonb_build_object(
      'success', false,
      'code',    'TOO_OLD',
      'error',   'لا يمكن تسجيل حضور أقدم من 24 ساعة'
    );
  END IF;

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

  ELSIF v_gps_required THEN
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
    IF FOUND AND v_existing_day.punch_in_time IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'code',    'ALREADY_CHECKED_IN',
        'error',   'لقد سجلت حضورك بالفعل اليوم'
      );
    END IF;

  ELSE -- check_out
    IF NOT FOUND OR v_existing_day.punch_in_time IS NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'code',    'NOT_CHECKED_IN',
        'error',   'يجب تسجيل الحضور أولاً قبل تسجيل الانصراف'
      );
    END IF;
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
    -- FIX-01: قراءة فترة السماح بالتأخير من إعدادات HR
    SELECT COALESCE(value::INTEGER, 15)
    INTO   v_grace_min
    FROM   company_settings
    WHERE  key = 'hr.late_grace_minutes';
    IF v_grace_min IS NULL THEN v_grace_min := 15; END IF;

    SELECT value::TIME
    INTO   v_work_start
    FROM   company_settings
    WHERE  key = 'hr.work_start_time';

    IF v_work_start IS NOT NULL THEN
      v_scheduled_start := (v_shift_date + v_work_start) AT TIME ZONE 'Africa/Cairo';

      IF v_event_time > v_scheduled_start + (v_grace_min || ' minutes')::INTERVAL THEN
        v_late_min   := EXTRACT(EPOCH FROM (v_event_time - v_scheduled_start))::INTEGER / 60;
        v_att_status := CASE
          WHEN v_late_min > 120 THEN 'half_day'::hr_attendance_status
          ELSE                       'late'::hr_attendance_status
        END;
      END IF;
    END IF;

    -- ─── UPSERT hr_attendance_days (check_in) ───────────────
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
    v_eff_hours   := LEAST(
      ROUND(EXTRACT(EPOCH FROM (v_event_time - v_check_in_ts)) / 3600.0, 2),
      24.00
    );
    v_ot_min      := 0;
    v_early_min   := 0;
    v_co_status   := 'on_time';

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
        -- FIX-12 + FIX-AUDIT-02: التحقق من إجازة أو إذن انصراف مبكر
        -- يشمل: إجازة نصف يوم (hr_leave_requests) + إذن رسمي (hr_permission_requests)
        IF EXISTS (
          SELECT 1 FROM hr_leave_requests
          WHERE employee_id = v_employee_id
            AND start_date  <= v_shift_date
            AND end_date    >= v_shift_date
            AND status      = 'approved'
        ) OR EXISTS (
          SELECT 1 FROM hr_permission_requests
          WHERE employee_id = v_employee_id
            AND permission_date = v_shift_date
            AND status = 'approved'
        ) THEN
          v_co_status := 'early_authorized';
        ELSE
          v_co_status := 'early_unauthorized';
        END IF;
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


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  FIX-AUDIT-06: update_payroll_line_adjustments           ║
-- ║                                                           ║
-- ║  المشكلة: updatePayrollLine في الـ Frontend يُحدّث        ║
-- ║  bonus_amount / other_deductions / override_net فقط       ║
-- ║  بدون إعادة حساب net_salary.                              ║
-- ║  → approve_payroll_run يقرأ net_salary القديم             ║
-- ║  → القيد المحاسبي لا يعكس المكافآت/الخصومات الإضافية    ║
-- ║                                                           ║
-- ║  الإصلاح: RPC ذري يُعيد حساب net_salary تلقائياً        ║
-- ╚═══════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION update_payroll_line_adjustments(
  p_line_id          UUID,
  p_bonus_amount     NUMERIC DEFAULT NULL,   -- NULL = لا تغيير
  p_other_deductions NUMERIC DEFAULT NULL,   -- NULL = لا تغيير
  p_override_net     NUMERIC DEFAULT NULL,   -- NULL = لا تغيير (استخدم 0 لإزالة override)
  p_override_reason  TEXT    DEFAULT NULL,
  p_notes            TEXT    DEFAULT NULL,
  p_user_id          UUID    DEFAULT NULL
) RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_line         hr_payroll_lines%ROWTYPE;
  v_run_status   TEXT;
  v_new_bonus    NUMERIC;
  v_new_deduct   NUMERIC;
  v_new_override NUMERIC;
  v_new_net      NUMERIC;
  v_new_total_d  NUMERIC;
BEGIN
  -- [SECURITY GUARD] تحقق من الهوية
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;

  -- 1. قفل الصف لمنع التزامن
  SELECT * INTO v_line
  FROM hr_payroll_lines
  WHERE id = p_line_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'سطر الراتب غير موجود';
  END IF;

  -- 2. التحقق من أن المسير في حالة المراجعة (لا تعديل بعد الاعتماد)
  SELECT status INTO v_run_status
  FROM hr_payroll_runs
  WHERE id = v_line.payroll_run_id;

  IF v_run_status NOT IN ('review', 'calculating') THEN
    RAISE EXCEPTION 'لا يمكن التعديل — المسير في حالة: %', v_run_status;
  END IF;

  -- 3. حساب القيم الجديدة (COALESCE يحافظ على القيمة الحالية إذا لم تُمرر)
  v_new_bonus    := COALESCE(p_bonus_amount,     v_line.bonus_amount,     0);
  v_new_deduct   := COALESCE(p_other_deductions, v_line.other_deductions, 0);
  -- override_net: نستخدم p_override_net إذا مُرر، وإلا نحافظ على الحالي
  v_new_override := CASE
    WHEN p_override_net IS NOT NULL THEN p_override_net
    ELSE v_line.override_net
  END;
  -- إذا كان override_net = 0 نعتبره إلغاء
  IF v_new_override = 0 THEN v_new_override := NULL; END IF;

  -- 4. ★ إعادة حساب net_salary ★
  -- المعادلة الأصلية من calculate_employee_payroll (19b_hr_core_hotfixes.sql L309-311):
  --   net = gross_earned + overtime + commission
  --       - absence - penalty - advance - si - tax - health
  -- الآن نُضيف bonus ونطرح other_deductions:
  --   net = gross_earned + overtime + commission + bonus
  --       - absence - penalty - advance - si - tax - health - other_deductions
  IF v_new_override IS NOT NULL THEN
    -- override_net يتجاوز كل الحسابات — يُستخدم كصافٍ نهائي
    v_new_net := v_new_override;
  ELSE
    v_new_net := COALESCE(v_line.gross_earned, 0)
               + COALESCE(v_line.overtime_amount, 0)
               + COALESCE(v_line.commission_amount, 0)
               + v_new_bonus
               - COALESCE(v_line.absence_deduction, 0)
               - COALESCE(v_line.penalty_deduction, 0)
               - COALESCE(v_line.advance_deduction, 0)
               - COALESCE(v_line.social_insurance, 0)
               - COALESCE(v_line.income_tax, 0)
               - COALESCE(v_line.health_insurance, 0)
               - v_new_deduct;
    v_new_net := GREATEST(0, v_new_net);
  END IF;

  -- 5. حساب total_deductions الجديد
  v_new_total_d := COALESCE(v_line.absence_deduction, 0)
                 + COALESCE(v_line.penalty_deduction, 0)
                 + COALESCE(v_line.advance_deduction, 0)
                 + COALESCE(v_line.social_insurance, 0)
                 + COALESCE(v_line.income_tax, 0)
                 + COALESCE(v_line.health_insurance, 0)
                 + v_new_deduct;

  -- 6. تحديث الصف
  UPDATE hr_payroll_lines SET
    bonus_amount     = v_new_bonus,
    other_deductions = v_new_deduct,
    override_net     = v_new_override,
    override_reason  = COALESCE(p_override_reason, override_reason),
    notes            = COALESCE(p_notes, notes),
    net_salary       = v_new_net,
    total_deductions = v_new_total_d,
    updated_at       = now()
  WHERE id = p_line_id;

  -- 7. تحديث مجاميع المسير
  UPDATE hr_payroll_runs SET
    total_gross      = (SELECT COALESCE(SUM(gross_earned), 0) FROM hr_payroll_lines WHERE payroll_run_id = v_line.payroll_run_id),
    total_deductions = (SELECT COALESCE(SUM(total_deductions), 0) FROM hr_payroll_lines WHERE payroll_run_id = v_line.payroll_run_id),
    total_net        = (SELECT COALESCE(SUM(net_salary), 0) FROM hr_payroll_lines WHERE payroll_run_id = v_line.payroll_run_id),
    updated_at       = now()
  WHERE id = v_line.payroll_run_id;

  RETURN jsonb_build_object(
    'success',        true,
    'line_id',        p_line_id,
    'bonus_amount',   v_new_bonus,
    'other_deductions', v_new_deduct,
    'override_net',   v_new_override,
    'net_salary',     v_new_net,
    'total_deductions', v_new_total_d,
    'message',        'تم تحديث سطر الراتب وإعادة حساب الصافي'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION update_payroll_line_adjustments(UUID, NUMERIC, NUMERIC, NUMERIC, TEXT, TEXT, UUID) TO authenticated;


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  FIX-AUDIT-07: upsert_attendance_and_reprocess           ║
-- ║                                                           ║
-- ║  المشكلة: التعديل اليدوي للحضور (upsertAttendanceDay)   ║
-- ║  يُحدّث أوقات الدخول/الخروج لكن:                        ║
-- ║    ① لا يحذف الجزاءات القديمة المرتبطة بالقيم السابقة   ║
-- ║    ② لا يُعيد تشغيل process_attendance_penalties         ║
-- ║  → الموظف يُخصم ظلماً من راتبه رغم التصحيح              ║
-- ║                                                           ║
-- ║  الإصلاح: RPC ذري يُعدّل الحضور ثم يُعيد الجزاءات      ║
-- ╚═══════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION upsert_attendance_and_reprocess(
  p_employee_id       UUID,
  p_shift_date        DATE,
  p_punch_in_time     TIMESTAMPTZ  DEFAULT NULL,
  p_punch_out_time    TIMESTAMPTZ  DEFAULT NULL,
  p_status            hr_attendance_status DEFAULT NULL,
  p_notes             TEXT         DEFAULT NULL,
  p_user_id           UUID         DEFAULT NULL
) RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_day_id          UUID;
  v_existing        hr_attendance_days%ROWTYPE;
  v_new_eff_hours   NUMERIC;
  v_new_late_min    INTEGER := 0;
  v_new_early_min   INTEGER := 0;
  v_new_ot_min      INTEGER := 0;
  v_new_status      hr_attendance_status;
  v_new_co_status   hr_checkout_status;
  v_work_start      TIME;
  v_work_end        TIME;
  v_grace_min       INTEGER;
  v_sched_start     TIMESTAMPTZ;
  v_sched_end       TIMESTAMPTZ;
  v_penalties_count INTEGER;
BEGIN
  -- [SECURITY] صلاحية التعديل
  IF NOT check_permission(COALESCE(p_user_id, auth.uid()), 'hr.attendance.create') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تعديل الحضور';
  END IF;

  -- 1. جلب إعدادات ساعات العمل
  SELECT value::TIME INTO v_work_start
  FROM company_settings WHERE key = 'hr.work_start_time';
  SELECT value::TIME INTO v_work_end
  FROM company_settings WHERE key = 'hr.work_end_time';
  SELECT COALESCE(value::INTEGER, 15) INTO v_grace_min
  FROM company_settings WHERE key = 'hr.late_grace_minutes';

  v_work_start := COALESCE(v_work_start, '09:00'::TIME);
  v_work_end   := COALESCE(v_work_end,   '17:00'::TIME);

  -- 2. حساب القيم المشتقة
  v_new_status    := COALESCE(p_status, 'present');
  v_new_co_status := NULL;

  IF p_punch_in_time IS NOT NULL AND p_punch_out_time IS NOT NULL THEN
    -- ساعات فعلية
    v_new_eff_hours := LEAST(
      ROUND(EXTRACT(EPOCH FROM (p_punch_out_time - p_punch_in_time)) / 3600.0, 2),
      24.00
    );

    -- تأخير
    v_sched_start := (p_shift_date + v_work_start) AT TIME ZONE 'Africa/Cairo';
    IF p_punch_in_time > v_sched_start + (v_grace_min || ' minutes')::INTERVAL THEN
      v_new_late_min := EXTRACT(EPOCH FROM (p_punch_in_time - v_sched_start))::INTEGER / 60;
      IF v_new_late_min > 0 THEN
        v_new_status := 'late';
      END IF;
    END IF;

    -- انصراف مبكر / أوفرتايم
    v_sched_end := (p_shift_date + v_work_end) AT TIME ZONE 'Africa/Cairo';
    IF p_punch_out_time > v_sched_end + INTERVAL '30 minutes' THEN
      v_new_ot_min := EXTRACT(EPOCH FROM (p_punch_out_time - v_sched_end))::INTEGER / 60;
      v_new_co_status := 'overtime';
    ELSIF p_punch_out_time < v_sched_end - INTERVAL '5 minutes' THEN
      v_new_early_min := EXTRACT(EPOCH FROM (v_sched_end - p_punch_out_time))::INTEGER / 60;
      -- فحص إجازة أو إذن انصراف مبكر
      IF EXISTS (
        SELECT 1 FROM hr_leave_requests
        WHERE employee_id = p_employee_id
          AND start_date <= p_shift_date AND end_date >= p_shift_date
          AND status = 'approved'
      ) OR EXISTS (
        SELECT 1 FROM hr_permission_requests
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
  ELSIF p_punch_in_time IS NOT NULL THEN
    -- دخول فقط بدون خروج
    v_sched_start := (p_shift_date + v_work_start) AT TIME ZONE 'Africa/Cairo';
    IF p_punch_in_time > v_sched_start + (v_grace_min || ' minutes')::INTERVAL THEN
      v_new_late_min := EXTRACT(EPOCH FROM (p_punch_in_time - v_sched_start))::INTEGER / 60;
      v_new_status := 'late';
    END IF;
  END IF;

  -- 3. UPSERT سجل الحضور
  INSERT INTO hr_attendance_days (
    employee_id, shift_date, work_date,
    punch_in_time, punch_out_time,
    status, checkout_status,
    late_minutes, early_leave_minutes, overtime_minutes,
    effective_hours, day_value,
    notes, review_status
  ) VALUES (
    p_employee_id, p_shift_date, p_shift_date,
    p_punch_in_time, p_punch_out_time,
    v_new_status, v_new_co_status,
    v_new_late_min, v_new_early_min, v_new_ot_min,
    v_new_eff_hours,
    CASE v_new_status
      WHEN 'half_day' THEN 0.5
      WHEN 'absent_unauthorized' THEN 0
      WHEN 'absent_authorized' THEN 0
      ELSE 1.0
    END,
    p_notes, 'reviewed'
  )
  ON CONFLICT (employee_id, shift_date)
  DO UPDATE SET
    punch_in_time       = EXCLUDED.punch_in_time,
    punch_out_time      = EXCLUDED.punch_out_time,
    status              = EXCLUDED.status,
    checkout_status     = EXCLUDED.checkout_status,
    late_minutes        = EXCLUDED.late_minutes,
    early_leave_minutes = EXCLUDED.early_leave_minutes,
    overtime_minutes    = EXCLUDED.overtime_minutes,
    effective_hours     = EXCLUDED.effective_hours,
    day_value           = EXCLUDED.day_value,
    notes               = EXCLUDED.notes,
    review_status       = 'reviewed',
    reviewed_by         = COALESCE(p_user_id, auth.uid()),
    reviewed_at         = now(),
    updated_at          = now()
  RETURNING id INTO v_day_id;

  -- 4. ★ حذف الجزاءات القديمة غير المتجاوزة لهذا اليوم ★
  DELETE FROM hr_penalty_instances
  WHERE attendance_day_id = v_day_id
    AND is_overridden = false
    AND payroll_run_id IS NULL;  -- لم تُدرج في مسير بعد

  -- 5. ★ إعادة تشغيل محرك الجزاءات ★
  SELECT process_attendance_penalties(v_day_id) INTO v_penalties_count;

  RETURN jsonb_build_object(
    'success',           true,
    'attendance_day_id', v_day_id,
    'status',            v_new_status,
    'checkout_status',   v_new_co_status,
    'late_minutes',      v_new_late_min,
    'early_leave_minutes', v_new_early_min,
    'overtime_minutes',  v_new_ot_min,
    'effective_hours',   v_new_eff_hours,
    'penalties_applied', v_penalties_count,
    'message',           format('تم تحديث الحضور — %s جزاء/ات أُعيد حسابها', v_penalties_count)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION upsert_attendance_and_reprocess(UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ, hr_attendance_status, TEXT, UUID) TO authenticated;
