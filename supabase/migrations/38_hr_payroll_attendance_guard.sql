-- ═══════════════════════════════════════════════════════════════
-- 38_hr_payroll_attendance_guard.sql
-- HR Payroll — Wave D Closure: DB Guard + Reprocess Failure Handling
--
-- Additive & non-destructive. Safe to re-run (idempotent).
--
-- Changes:
--   1. approve_payroll_run — حقن فحص check_payroll_attendance_clearance
--      مباشرة بعد التحقق من حالة المسير (قبل أي عملية مالية)
--   2. record_attendance_gps_v2 — رفع خطأ صريح بدل ابتلاع فشل reprocess
-- ═══════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────
-- 1) approve_payroll_run — مع DB Guard فعلي داخل الدالة
--
-- التغيير الوحيد: إضافة STEP 0 (7 سطور) بعد SELECT v_period
-- بقية المنطق محفوظ بالكامل بلا تعديل
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION approve_payroll_run(
  p_run_id  UUID,
  p_user_id UUID
) RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_run          hr_payroll_runs%ROWTYPE;
  v_period       hr_payroll_periods%ROWTYPE;
  v_je_id        UUID;
  v_emp_id       UUID;

  -- COA
  v_coa_salaries UUID;  -- 5310
  v_coa_overtime UUID;  -- 5320
  v_coa_commiss  UUID;  -- 5330
  v_coa_bonus    UUID;  -- 5335
  v_coa_payable  UUID;  -- 2310
  v_coa_advances UUID;  -- 2320
  v_coa_insure   UUID;  -- 2330
  v_coa_tax      UUID;  -- 2340

  v_total_salary_expense NUMERIC;
  v_total_overtime       NUMERIC;
  v_total_commission     NUMERIC;
  v_total_net            NUMERIC;
  v_total_advance        NUMERIC;
  v_total_insurance      NUMERIC;
  v_total_tax            NUMERIC;
  v_total_bonus          NUMERIC := 0;
  v_total_debit          NUMERIC;
  v_total_credit         NUMERIC;

  -- ★ للـ guard
  v_clearance    JSONB;
  v_blockers     TEXT;
BEGIN
  SELECT * INTO v_run FROM hr_payroll_runs WHERE id = p_run_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'مسير الرواتب غير موجود'; END IF;
  IF v_run.status NOT IN ('review', 'calculating') THEN
    RAISE EXCEPTION 'المسير في حالة غير قابلة للاعتماد (الحالة: %)', v_run.status;
  END IF;

  SELECT * INTO v_period FROM hr_payroll_periods WHERE id = v_run.period_id;

  -- ══════════════════════════════════════════════════════════
  -- ★ STEP 0: DB Guard — فحص حالات الحضور قبل أي عملية مالية
  -- يمنع bypass الواجهة بالاستدعاء المباشر للـ RPC
  -- ══════════════════════════════════════════════════════════
  v_clearance := check_payroll_attendance_clearance(
    v_period.start_date,
    v_period.end_date
  );

  IF NOT (v_clearance ->> 'cleared')::BOOLEAN THEN
    -- بناء رسالة مختصرة من blockers
    SELECT string_agg((b ->> 'message'), ' | ')
    INTO   v_blockers
    FROM   jsonb_array_elements(v_clearance -> 'blockers') AS b;

    RAISE EXCEPTION
      'لا يمكن اعتماد المسير — توجد حالات حضور غير محسومة: %',
      v_blockers;
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- STEP 0أ: تثبيت مكافآت الأهداف (idempotent)
  -- ══════════════════════════════════════════════════════════
  PERFORM public.prepare_target_reward_payouts(v_run.period_id);

  -- ══════════════════════════════════════════════════════════
  -- STEP 0ب: إعادة حساب أسطر الرواتب للموظفين المتأثرين
  -- ══════════════════════════════════════════════════════════
  FOR v_emp_id IN
    SELECT DISTINCT pa.employee_id
    FROM hr_payroll_adjustments pa
    WHERE pa.effective_date BETWEEN v_period.start_date AND v_period.end_date
      AND pa.status = 'approved'
      AND pa.payroll_line_id IS NULL
      AND EXISTS (
        SELECT 1 FROM hr_payroll_lines pl
        WHERE pl.payroll_run_id = p_run_id AND pl.employee_id = pa.employee_id
      )
  LOOP
    PERFORM calculate_employee_payroll(v_emp_id, p_run_id);
  END LOOP;

  -- ─── جلب المجاميع بعد إعادة الحساب ───
  SELECT
    COALESCE(SUM(gross_earned - absence_deduction - penalty_deduction
                  - COALESCE(other_deductions, 0)), 0),
    COALESCE(SUM(overtime_amount), 0),
    COALESCE(SUM(commission_amount), 0),
    COALESCE(SUM(net_salary), 0),
    COALESCE(SUM(advance_deduction), 0),
    COALESCE(SUM(social_insurance + health_insurance), 0),
    COALESCE(SUM(income_tax), 0)
  INTO
    v_total_salary_expense, v_total_overtime, v_total_commission,
    v_total_net,            v_total_advance,  v_total_insurance, v_total_tax
  FROM hr_payroll_lines WHERE payroll_run_id = p_run_id;

  SELECT COALESCE(SUM(bonus_amount), 0) INTO v_total_bonus
  FROM hr_payroll_lines WHERE payroll_run_id = p_run_id;

  -- ══════════════════════════════════════════════════════════
  -- إعادة تحقق من أقساط السلف (AUDIT FIX)
  -- ══════════════════════════════════════════════════════════
  DECLARE
    v_line           RECORD;
    v_actual_advance NUMERIC;
    v_diff_advance   NUMERIC;
  BEGIN
    FOR v_line IN
      SELECT pl.id, pl.employee_id, pl.advance_deduction, pl.net_salary
      FROM hr_payroll_lines pl
      WHERE pl.payroll_run_id = p_run_id AND pl.advance_deduction > 0
      FOR UPDATE
    LOOP
      SELECT COALESCE(SUM(ai.amount), 0) INTO v_actual_advance
      FROM hr_advance_installments ai
      JOIN hr_advances adv ON adv.id = ai.advance_id
      WHERE adv.employee_id = v_line.employee_id
        AND ai.due_year = v_period.year AND ai.due_month = v_period.month
        AND ai.status = 'pending'
      FOR UPDATE;

      v_diff_advance := v_line.advance_deduction - v_actual_advance;
      IF v_diff_advance > 0.001 THEN
        UPDATE hr_payroll_lines
        SET advance_deduction = v_actual_advance,
            total_deductions  = total_deductions - v_diff_advance,
            net_salary        = net_salary + v_diff_advance
        WHERE id = v_line.id;
      END IF;
    END LOOP;

    SELECT
      COALESCE(SUM(gross_earned - absence_deduction - penalty_deduction
                    - COALESCE(other_deductions, 0)), 0),
      COALESCE(SUM(overtime_amount), 0),
      COALESCE(SUM(commission_amount), 0),
      COALESCE(SUM(net_salary), 0),
      COALESCE(SUM(advance_deduction), 0),
      COALESCE(SUM(social_insurance + health_insurance), 0),
      COALESCE(SUM(income_tax), 0)
    INTO
      v_total_salary_expense, v_total_overtime, v_total_commission,
      v_total_net,            v_total_advance,  v_total_insurance, v_total_tax
    FROM hr_payroll_lines WHERE payroll_run_id = p_run_id;
  END;

  -- ══════════════════════════════════════════════════════════
  -- الإجماليات المتوازنة (Dr = Cr — مثبَّت رياضيًا في 22d)
  -- ══════════════════════════════════════════════════════════
  v_total_debit  := v_total_salary_expense + v_total_overtime + v_total_commission + v_total_bonus;
  v_total_credit := v_total_net + v_total_advance + v_total_insurance + v_total_tax;

  SELECT id INTO v_coa_salaries FROM chart_of_accounts WHERE code = '5310' AND is_active = true;
  SELECT id INTO v_coa_overtime FROM chart_of_accounts WHERE code = '5320' AND is_active = true;
  SELECT id INTO v_coa_commiss  FROM chart_of_accounts WHERE code = '5330' AND is_active = true;
  SELECT id INTO v_coa_bonus    FROM chart_of_accounts WHERE code = '5335' AND is_active = true;
  SELECT id INTO v_coa_payable  FROM chart_of_accounts WHERE code = '2310' AND is_active = true;
  SELECT id INTO v_coa_advances FROM chart_of_accounts WHERE code = '2320' AND is_active = true;
  SELECT id INTO v_coa_insure   FROM chart_of_accounts WHERE code = '2330' AND is_active = true;
  SELECT id INTO v_coa_tax      FROM chart_of_accounts WHERE code = '2340' AND is_active = true;

  IF v_coa_salaries IS NULL OR v_coa_payable IS NULL THEN
    RAISE EXCEPTION 'الحسابات المحاسبية غير موجودة (5310, 2310)';
  END IF;

  IF ABS(v_total_debit - v_total_credit) > 0.50 THEN
    RAISE EXCEPTION 'القيد غير متوازن: Dr=% Cr=% (Δ=%) — راجع بيانات المسير',
      v_total_debit, v_total_credit, ABS(v_total_debit - v_total_credit);
  END IF;

  IF ABS(v_total_debit - v_total_credit) > 0.001 THEN
    IF v_total_debit > v_total_credit THEN
      v_total_credit := v_total_debit;
    ELSE
      v_total_debit  := v_total_credit;
    END IF;
  END IF;

  -- ─── إنشاء رأس القيد ───
  INSERT INTO journal_entries (
    source_type, source_id, description, entry_date,
    is_auto, status, total_debit, total_credit, created_by
  ) VALUES (
    'hr_payroll', p_run_id,
    'مسير رواتب ' || v_period.name,
    v_period.end_date, true, 'posted',
    v_total_debit, v_total_credit, p_user_id
  ) RETURNING id INTO v_je_id;

  -- ─── الجانب المدين (Dr) ───
  IF v_total_salary_expense > 0 THEN
    INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
    VALUES (v_je_id, v_coa_salaries, v_total_salary_expense, 0,
            'رواتب أساسية وبدلات — ' || v_period.name);
  END IF;

  IF v_total_overtime > 0 AND v_coa_overtime IS NOT NULL THEN
    INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
    VALUES (v_je_id, v_coa_overtime, v_total_overtime, 0,
            'ساعات إضافية — ' || v_period.name);
  END IF;

  IF v_total_commission > 0 AND v_coa_commiss IS NOT NULL THEN
    INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
    VALUES (v_je_id, v_coa_commiss, v_total_commission, 0,
            'عمولات موظفين — ' || v_period.name);
  END IF;

  IF v_total_bonus > 0 AND v_coa_bonus IS NOT NULL THEN
    INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
    VALUES (v_je_id, v_coa_bonus, v_total_bonus, 0,
            'مكافآت أهداف الموظفين — ' || v_period.name);
  END IF;

  -- ─── الجانب الدائن (Cr) ───
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  VALUES (v_je_id, v_coa_payable, 0, v_total_net,
          'صافي رواتب مستحقة الصرف للموظفين (شامل المكافآت)');

  IF v_total_advance > 0 THEN
    INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
    VALUES (v_je_id, v_coa_advances, 0, v_total_advance,
            'أقساط سلف مُستقطعة من الرواتب');
  END IF;

  IF v_total_insurance > 0 AND v_coa_insure IS NOT NULL THEN
    INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
    VALUES (v_je_id, v_coa_insure, 0, v_total_insurance,
            'تأمينات اجتماعية وصحية مستقطعة');
  END IF;

  IF v_total_tax > 0 AND v_coa_tax IS NOT NULL THEN
    INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
    VALUES (v_je_id, v_coa_tax, 0, v_total_tax,
            'ضريبة كسب العمل مستقطعة');
  END IF;

  -- 5900: فروق تقريب
  DECLARE
    v_coa_rounding UUID;
    v_rd NUMERIC;
  BEGIN
    SELECT COALESCE(SUM(debit),0) - COALESCE(SUM(credit),0)
    INTO v_rd FROM journal_entry_lines WHERE entry_id = v_je_id;

    IF ABS(v_rd) > 0.001 THEN
      SELECT id INTO v_coa_rounding
      FROM chart_of_accounts WHERE code = '5900' AND is_active = true;
      IF v_coa_rounding IS NOT NULL THEN
        INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
        VALUES (v_je_id, v_coa_rounding,
                CASE WHEN v_rd < 0 THEN ROUND(ABS(v_rd),2) ELSE 0 END,
                CASE WHEN v_rd > 0 THEN ROUND(v_rd,2)      ELSE 0 END,
                'فروق تقريب — مسير ' || v_period.name);
      END IF;
    END IF;
  END;

  -- ─── تحديث المسير ───
  UPDATE hr_payroll_runs
  SET status           = 'approved',
      approved_by      = p_user_id,
      approved_at      = now(),
      journal_entry_id = v_je_id,
      total_net        = (SELECT COALESCE(SUM(net_salary),0)       FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
      total_deductions = (SELECT COALESCE(SUM(total_deductions),0) FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
      updated_at       = now()
  WHERE id = p_run_id;

  -- ─── استقطاع الأقساط ───
  UPDATE hr_advance_installments ai
  SET status = 'deducted', deducted_in_run_id = p_run_id
  FROM hr_payroll_lines pl
  WHERE pl.payroll_run_id = p_run_id
    AND ai.advance_id IN (SELECT id FROM hr_advances WHERE employee_id = pl.employee_id)
    AND ai.due_year = v_period.year AND ai.due_month = v_period.month
    AND ai.status = 'pending';

  -- ─── ربط العمولات ───
  UPDATE hr_commission_records
  SET included_in_run = p_run_id
  WHERE period_id = v_run.period_id AND is_eligible = true AND included_in_run IS NULL;

  RETURN jsonb_build_object(
    'success',          true,
    'run_id',           p_run_id,
    'journal_entry_id', v_je_id,
    'accounting_summary', jsonb_build_object(
      'debit', jsonb_build_object(
        'dr_5310_salaries',   v_total_salary_expense,
        'dr_5320_overtime',   v_total_overtime,
        'dr_5330_commission', v_total_commission,
        'dr_5335_bonuses',    v_total_bonus,
        'total_debit',        v_total_debit
      ),
      'credit', jsonb_build_object(
        'cr_2310_net_payable', v_total_net,
        'cr_2320_advances',    v_total_advance,
        'cr_2330_insurance',   v_total_insurance,
        'cr_2340_income_tax',  v_total_tax,
        'total_credit',        v_total_credit
      ),
      'balanced', (ABS(v_total_debit - v_total_credit) <= 1)
    ),
    'total_employees', v_run.total_employees,
    'target_bonuses',  v_total_bonus
  );
END; $$;

GRANT EXECUTE ON FUNCTION approve_payroll_run(UUID, UUID) TO authenticated;


-- ─────────────────────────────────────────────────────────────
-- 2) record_attendance_gps_v2 — إغلاق silent failure بعد check_out
--
-- القرار المعتمد: الخيار المفضل — فشل العملية نفسها
-- السبب: الموجة الرابعة هي "موجة الحسم"، وليس التسامح
--   إذا فشل الربط المالي بعد check_out → لا يُسجَّل الانصراف
--   المستخدم يتلقى رسالة خطأ واضحة ويحاول مجدداً
--
-- ملاحظة: process_attendance_penalties تفشل إذا كانت قواعد الجزاءات
--   غير مهيأة أو البيانات غير مكتملة — في هذا الحالة التراجع محمي
--   بـ SAVEPOINT ويعود الانصراف برسالة واضحة
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

    -- check_in: لا نُعيد معالجة الجزاءات — اليوم لم يُغلق بعد

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

    -- ★ CHECK_OUT: إعادة معالجة الجزاءات — الخيار المفضل (فشل العملية كاملاً)
    -- إذا فشلت الجزاءات → نرفع EXCEPTION → يتراجع الـ UPDATE كذلك (atomic)
    -- الموجة D هي موجة حسم وليس تسامح
    SELECT reprocess_attendance_day_penalties(v_day_id)
    INTO v_penalties_count;

    -- ملاحظة: إذا فشل reprocess فإن PostgreSQL سيرفع EXCEPTION تلقائيًا
    -- ويتراجع عن كل العمليات السابقة في هذه الـ transaction
    -- المستخدم يتلقى رسالة واضحة ويعيد المحاولة

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
$$;

GRANT EXECUTE ON FUNCTION record_attendance_gps_v2(NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ) TO authenticated;

-- ═══════════════════════════════════════════════════════════════
-- END OF MIGRATION 38
-- ═══════════════════════════════════════════════════════════════
