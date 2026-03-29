-- ============================================================
-- Migration 19b: HR Core Hotfixes
-- EDARA v2 — Idempotent: آمن للتشغيل أكثر من مرة
--
-- الإصلاحات المعتمدة:
--   1. إضافة UNIQUE (attendance_day_id, penalty_type) لمنع تكرار الجزاء
--   2. تحديث process_attendance_penalties بـ ON CONFLICT DO NOTHING
--   3. قراءة hr.work_hours_per_day من company_settings (ديناميكي)
--   4. إصلاح القيد المحاسبي في approve_payroll_run — 3 سطور Dr، 4 سطور Cr:
--      Dr. 5310 = gross_earned - absence_deduction - penalty_deduction
--      Dr. 5320 = overtime_amount
--      Dr. 5330 = commission_amount
--      Cr. 2310 = net_salary
--      Cr. 2320 = advance_deduction
--      Cr. 2330 = social_insurance + health_insurance
--      Cr. 2340 = income_tax  ← Future-proof: يمنع توقف النظام عند تفعيل ضريبة الدخل
-- ============================================================


-- ════════════════════════════════════════════════════════════
-- 1. إصلاح جدول hr_penalty_instances
--    إضافة UNIQUE لمنع تكرار الجزاء لنفس اليوم ونفس النوع
-- ════════════════════════════════════════════════════════════

-- أولاً: تنظيف أي تكرارات موجودة (آمن على قاعدة فارغة)
DELETE FROM hr_penalty_instances pi1
WHERE EXISTS (
  SELECT 1 FROM hr_penalty_instances pi2
  WHERE pi2.attendance_day_id = pi1.attendance_day_id
    AND pi2.penalty_type      = pi1.penalty_type
    AND pi2.id                > pi1.id
);

-- ثانياً: إضافة القيد
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_penalty_day_type'
  ) THEN
    ALTER TABLE hr_penalty_instances
      ADD CONSTRAINT uq_penalty_day_type
      UNIQUE (attendance_day_id, penalty_type);
  END IF;
END; $$;


-- ════════════════════════════════════════════════════════════
-- 2. إصلاح دالة process_attendance_penalties
--    استخدام ON CONFLICT DO NOTHING لمنع التكرار عند إعادة التشغيل
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION process_attendance_penalties(
  p_attendance_day_id UUID
) RETURNS INTEGER
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_day          hr_attendance_days%ROWTYPE;
  v_rule         hr_penalty_rules%ROWTYPE;
  v_penalty_type hr_penalty_type;
  v_minutes      INTEGER;
  v_occurrence   INTEGER;
  v_deduct_days  NUMERIC;
  v_count        INTEGER := 0;
  v_month_start  DATE;
  v_month_end    DATE;
BEGIN
  SELECT * INTO v_day FROM hr_attendance_days WHERE id = p_attendance_day_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  v_month_start := date_trunc('month', v_day.shift_date)::DATE;
  v_month_end   := (date_trunc('month', v_day.shift_date) + INTERVAL '1 month - 1 day')::DATE;

  -- ─── تأخير ───
  IF v_day.late_minutes > 0 AND v_day.status IN ('present', 'late', 'half_day') THEN
    v_penalty_type := 'late';
    v_minutes      := v_day.late_minutes;

    SELECT COUNT(*) + 1 INTO v_occurrence
    FROM hr_penalty_instances
    WHERE employee_id       = v_day.employee_id
      AND penalty_type      = v_penalty_type
      AND created_at::DATE  BETWEEN v_month_start AND v_month_end
      AND attendance_day_id <> p_attendance_day_id;

    SELECT * INTO v_rule
    FROM hr_penalty_rules
    WHERE penalty_type  = v_penalty_type AND is_active = true
      AND v_minutes     >= min_minutes
      AND (max_minutes IS NULL OR v_minutes < max_minutes)
      AND v_occurrence  >= occurrence_from
      AND (occurrence_to IS NULL OR v_occurrence <= occurrence_to)
    ORDER BY sort_order DESC LIMIT 1;

    IF FOUND THEN
      v_deduct_days := CASE v_rule.deduction_type
        WHEN 'quarter_day' THEN 0.25
        WHEN 'half_day'    THEN 0.5
        WHEN 'full_day'    THEN 1.0
        ELSE 0 END;

      -- ON CONFLICT DO NOTHING: إذا وُجد سجل بنفس اليوم/النوع → تجاهل
      INSERT INTO hr_penalty_instances (
        employee_id, attendance_day_id, penalty_rule_id,
        penalty_type, occurrence_in_month, deduction_type, deduction_days
      ) VALUES (
        v_day.employee_id, p_attendance_day_id, v_rule.id,
        v_penalty_type, v_occurrence, v_rule.deduction_type, v_deduct_days
      ) ON CONFLICT (attendance_day_id, penalty_type) DO NOTHING;

      IF FOUND THEN v_count := v_count + 1; END IF;
    END IF;
  END IF;

  -- ─── غياب بدون إذن ───
  IF v_day.status = 'absent_unauthorized' THEN
    v_penalty_type := 'absent_unauthorized';

    SELECT COUNT(*) + 1 INTO v_occurrence
    FROM hr_penalty_instances
    WHERE employee_id       = v_day.employee_id
      AND penalty_type      = v_penalty_type
      AND created_at::DATE  BETWEEN v_month_start AND v_month_end
      AND attendance_day_id <> p_attendance_day_id;

    SELECT * INTO v_rule
    FROM hr_penalty_rules
    WHERE penalty_type  = v_penalty_type AND is_active = true
      AND v_occurrence  >= occurrence_from
      AND (occurrence_to IS NULL OR v_occurrence <= occurrence_to)
    ORDER BY sort_order DESC LIMIT 1;

    IF FOUND THEN
      v_deduct_days := CASE v_rule.deduction_type
        WHEN 'quarter_day' THEN 0.25
        WHEN 'half_day'    THEN 0.5
        WHEN 'full_day'    THEN 1.0
        ELSE 0 END;

      INSERT INTO hr_penalty_instances (
        employee_id, attendance_day_id, penalty_rule_id,
        penalty_type, occurrence_in_month, deduction_type, deduction_days
      ) VALUES (
        v_day.employee_id, p_attendance_day_id, v_rule.id,
        v_penalty_type, v_occurrence, v_rule.deduction_type, v_deduct_days
      ) ON CONFLICT (attendance_day_id, penalty_type) DO NOTHING;

      IF FOUND THEN v_count := v_count + 1; END IF;
    END IF;
  END IF;

  -- ─── انصراف مبكر بلا إذن ───
  IF v_day.checkout_status = 'early_unauthorized' AND v_day.early_leave_minutes > 0 THEN
    v_penalty_type := 'early_leave_unauthorized';

    SELECT COUNT(*) + 1 INTO v_occurrence
    FROM hr_penalty_instances
    WHERE employee_id       = v_day.employee_id
      AND penalty_type      = v_penalty_type
      AND created_at::DATE  BETWEEN v_month_start AND v_month_end
      AND attendance_day_id <> p_attendance_day_id;

    SELECT * INTO v_rule
    FROM hr_penalty_rules
    WHERE penalty_type  = v_penalty_type AND is_active = true
      AND v_occurrence  >= occurrence_from
      AND (occurrence_to IS NULL OR v_occurrence <= occurrence_to)
    ORDER BY sort_order DESC LIMIT 1;

    IF FOUND THEN
      v_deduct_days := CASE v_rule.deduction_type
        WHEN 'quarter_day' THEN 0.25
        WHEN 'half_day'    THEN 0.5
        WHEN 'full_day'    THEN 1.0
        ELSE 0 END;

      INSERT INTO hr_penalty_instances (
        employee_id, attendance_day_id, penalty_rule_id,
        penalty_type, occurrence_in_month, deduction_type, deduction_days
      ) VALUES (
        v_day.employee_id, p_attendance_day_id, v_rule.id,
        v_penalty_type, v_occurrence, v_rule.deduction_type, v_deduct_days
      ) ON CONFLICT (attendance_day_id, penalty_type) DO NOTHING;

      IF FOUND THEN v_count := v_count + 1; END IF;
    END IF;
  END IF;

  RETURN v_count;
END; $$;


-- ════════════════════════════════════════════════════════════
-- 3. إصلاح دالة calculate_employee_payroll
--    قراءة ساعات العمل من company_settings بدلاً من 8.0 المثبتة
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calculate_employee_payroll(
  p_employee_id  UUID,
  p_run_id       UUID
) RETURNS UUID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_run              hr_payroll_runs%ROWTYPE;
  v_period           hr_payroll_periods%ROWTYPE;
  v_emp              hr_employees%ROWTYPE;
  v_summary          JSONB;
  v_salary           RECORD;
  v_line_id          UUID;

  v_daily_rate       NUMERIC;
  v_gross_earned     NUMERIC;
  v_overtime_amount  NUMERIC;
  v_commission       NUMERIC;

  v_absence_deduct   NUMERIC;
  v_penalty_deduct   NUMERIC;
  v_advance_deduct   NUMERIC;
  v_si_deduct        NUMERIC;
  v_tax_deduct       NUMERIC;
  v_health_deduct    NUMERIC;

  v_si_enabled       BOOLEAN;
  v_si_rate          NUMERIC;
  v_tax_enabled      BOOLEAN;
  v_health_enabled   BOOLEAN;
  v_health_amount    NUMERIC;
  v_overtime_rate    NUMERIC;
  v_working_days     INTEGER;

  -- ─── الإصلاح: ساعات العمل من company_settings ───
  v_work_hours_per_day NUMERIC;

  -- ─── FIX-AUDIT-08: حساب أيام العمل التقويمية ───
  v_off_day_name     TEXT;
  v_off_dow          INTEGER;
  v_public_holidays  INTEGER;
  v_d                DATE;
  v_calendar_days    INTEGER;

  -- partial month
  v_partial_working  INTEGER;
  v_is_partial       BOOLEAN := false;
  v_entitled_days    INTEGER;

  -- auto-absence
  v_attended_days    NUMERIC;
  v_auto_absent      NUMERIC;

  v_net              NUMERIC;
BEGIN
  SELECT * INTO v_run    FROM hr_payroll_runs    WHERE id = p_run_id;
  SELECT * INTO v_period FROM hr_payroll_periods WHERE id = v_run.period_id;
  SELECT * INTO v_emp    FROM hr_employees        WHERE id = p_employee_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'بيانات غير مكتملة'; END IF;

  SELECT * INTO v_salary
  FROM get_employee_salary_at_date(p_employee_id, v_period.start_date);

  v_summary := get_monthly_attendance_summary(p_employee_id, v_period.year, v_period.month);

  -- ════════════════════════════════════════════════════════
  -- FIX-AUDIT-08: حساب أيام العمل التقويمية
  -- ════════════════════════════════════════════════════════
  v_off_day_name := COALESCE(v_emp.weekly_off_day::TEXT, NULL);
  IF v_off_day_name IS NULL THEN
    SELECT value INTO v_off_day_name
    FROM company_settings WHERE key = 'hr.weekly_off_day';
  END IF;
  v_off_day_name := COALESCE(v_off_day_name, 'friday');

  v_off_dow := CASE lower(v_off_day_name)
    WHEN 'sunday'    THEN 0
    WHEN 'monday'    THEN 1
    WHEN 'tuesday'   THEN 2
    WHEN 'wednesday' THEN 3
    WHEN 'thursday'  THEN 4
    WHEN 'friday'    THEN 5
    WHEN 'saturday'  THEN 6
    ELSE 5 END;

  v_calendar_days := 0;
  v_d := v_period.start_date;
  WHILE v_d <= v_period.end_date LOOP
    IF EXTRACT(DOW FROM v_d)::INTEGER <> v_off_dow THEN
      v_calendar_days := v_calendar_days + 1;
    END IF;
    v_d := v_d + 1;
  END LOOP;

  SELECT COUNT(*) INTO v_public_holidays
  FROM hr_public_holidays
  WHERE holiday_date BETWEEN v_period.start_date AND v_period.end_date
    AND EXTRACT(DOW FROM holiday_date)::INTEGER <> v_off_dow;

  v_calendar_days := v_calendar_days - COALESCE(v_public_holidays, 0);
  IF v_calendar_days <= 0 THEN v_calendar_days := 26; END IF;

  v_working_days := v_calendar_days;

  v_daily_rate := COALESCE(v_salary.gross_salary, 0) / v_working_days;

  -- ─── قراءة ساعات العمل من الإعدادات ───
  SELECT COALESCE(value::NUMERIC, 8) INTO v_work_hours_per_day
  FROM company_settings WHERE key = 'hr.work_hours_per_day';

  -- ════════════════════════════════════════════════════════
  -- المستحق الإجمالي + Partial Month (أيام عمل فقط)
  -- ════════════════════════════════════════════════════════
  v_gross_earned := COALESCE(v_salary.gross_salary, 0);
  v_entitled_days := v_working_days;
  v_is_partial := false;

  IF v_emp.hire_date > v_period.start_date AND v_emp.hire_date <= v_period.end_date THEN
    v_is_partial := true;
    v_partial_working := 0;
    v_d := v_emp.hire_date;
    WHILE v_d <= v_period.end_date LOOP
      IF EXTRACT(DOW FROM v_d)::INTEGER <> v_off_dow THEN
        IF NOT EXISTS (SELECT 1 FROM hr_public_holidays WHERE holiday_date = v_d) THEN
          v_partial_working := v_partial_working + 1;
        END IF;
      END IF;
      v_d := v_d + 1;
    END LOOP;
    IF v_partial_working <= 0 THEN v_partial_working := 1; END IF;
    v_gross_earned := v_daily_rate * v_partial_working;
    v_entitled_days := v_partial_working;
  END IF;

  IF v_emp.termination_date IS NOT NULL
    AND v_emp.termination_date >= v_period.start_date
    AND v_emp.termination_date <= v_period.end_date THEN
    v_is_partial := true;
    v_partial_working := 0;
    v_d := GREATEST(v_period.start_date, v_emp.hire_date);
    WHILE v_d <= v_emp.termination_date LOOP
      IF EXTRACT(DOW FROM v_d)::INTEGER <> v_off_dow THEN
        IF NOT EXISTS (SELECT 1 FROM hr_public_holidays WHERE holiday_date = v_d) THEN
          v_partial_working := v_partial_working + 1;
        END IF;
      END IF;
      v_d := v_d + 1;
    END LOOP;
    IF v_partial_working <= 0 THEN v_partial_working := 1; END IF;
    v_gross_earned := v_daily_rate * v_partial_working;
    v_entitled_days := v_partial_working;
  END IF;

  -- ════════════════════════════════════════════════════════
  -- حساب الغياب التلقائي
  -- ════════════════════════════════════════════════════════
  SELECT COALESCE(SUM(day_value), 0) INTO v_attended_days
  FROM hr_attendance_days
  WHERE employee_id = p_employee_id
    AND shift_date BETWEEN v_period.start_date AND v_period.end_date
    AND status NOT IN ('weekly_off', 'public_holiday');

  v_attended_days := v_attended_days
    + COALESCE((v_summary->>'on_leave_days')::NUMERIC, 0)
    + COALESCE((v_summary->>'absent_authorized')::NUMERIC, 0);

  v_auto_absent := GREATEST(0, v_entitled_days - v_attended_days);
  v_absence_deduct := v_auto_absent * v_daily_rate;
  v_penalty_deduct := COALESCE((v_summary->>'penalty_deduction_days')::NUMERIC, 0) * v_daily_rate;

  -- ─── الأوفرتايم ───
  SELECT COALESCE(value::NUMERIC, 1.5) INTO v_overtime_rate
  FROM company_settings WHERE key = 'hr.overtime_rate';

  v_overtime_amount :=
    COALESCE((v_summary->>'total_overtime_minutes')::NUMERIC, 0) / 60.0
    * (COALESCE(v_salary.base_salary, 0) / (v_working_days * v_work_hours_per_day))
    * v_overtime_rate;

  SELECT COALESCE(SUM(commission_amount), 0) INTO v_commission
  FROM hr_commission_records
  WHERE employee_id = p_employee_id AND period_id = v_run.period_id
    AND is_eligible = true AND included_in_run IS NULL;

  SELECT COALESCE(SUM(ai.amount), 0) INTO v_advance_deduct
  FROM hr_advance_installments ai
  JOIN hr_advances adv ON adv.id = ai.advance_id
  WHERE adv.employee_id = p_employee_id
    AND ai.due_year = v_period.year AND ai.due_month = v_period.month
    AND ai.status = 'pending';

  SELECT COALESCE(value::BOOLEAN, false) INTO v_si_enabled
  FROM company_settings WHERE key = 'hr.social_insurance.enabled';
  SELECT COALESCE(value::NUMERIC, 11) INTO v_si_rate
  FROM company_settings WHERE key = 'hr.social_insurance.employee_rate';
  SELECT COALESCE(value::BOOLEAN, false) INTO v_tax_enabled
  FROM company_settings WHERE key = 'hr.income_tax.enabled';
  SELECT COALESCE(value::BOOLEAN, false) INTO v_health_enabled
  FROM company_settings WHERE key = 'hr.health_insurance.enabled';
  SELECT COALESCE(value::NUMERIC, 0) INTO v_health_amount
  FROM company_settings WHERE key = 'hr.health_insurance.amount';

  v_si_deduct     := CASE WHEN v_si_enabled    THEN v_gross_earned * (v_si_rate / 100) ELSE 0 END;
  v_tax_deduct    := 0;
  v_health_deduct := CASE WHEN v_health_enabled THEN v_health_amount ELSE 0 END;

  v_net := v_gross_earned + v_overtime_amount + v_commission
         - v_absence_deduct - v_penalty_deduct - v_advance_deduct
         - v_si_deduct - v_tax_deduct - v_health_deduct;
  v_net := GREATEST(0, v_net);

  INSERT INTO hr_payroll_lines (
    payroll_run_id, employee_id, period_id,
    total_working_days, actual_work_days,
    absent_days, deducted_days, overtime_hours,
    base_salary, transport_allowance, housing_allowance, other_allowances,
    overtime_amount, commission_amount, gross_earned,
    absence_deduction, penalty_deduction, advance_deduction,
    social_insurance, income_tax, health_insurance,
    total_deductions, net_salary, is_partial_month
  ) VALUES (
    p_run_id, p_employee_id, v_run.period_id,
    v_working_days,
    v_attended_days,
    v_auto_absent,
    COALESCE((v_summary->>'penalty_deduction_days')::NUMERIC, 0),
    COALESCE((v_summary->>'total_overtime_minutes')::NUMERIC, 0) / 60.0,
    COALESCE(v_salary.base_salary, 0),
    COALESCE(v_salary.transport_allowance, 0),
    COALESCE(v_salary.housing_allowance, 0),
    COALESCE(v_salary.other_allowances, 0),
    v_overtime_amount, v_commission, v_gross_earned,
    v_absence_deduct, v_penalty_deduct, v_advance_deduct,
    v_si_deduct, v_tax_deduct, v_health_deduct,
    v_absence_deduct + v_penalty_deduct + v_advance_deduct
      + v_si_deduct + v_tax_deduct + v_health_deduct,
    v_net,
    v_is_partial
  )
  ON CONFLICT (payroll_run_id, employee_id)
  DO UPDATE SET
    total_working_days = EXCLUDED.total_working_days,
    actual_work_days   = EXCLUDED.actual_work_days,
    absent_days        = EXCLUDED.absent_days,
    deducted_days      = EXCLUDED.deducted_days,
    overtime_hours     = EXCLUDED.overtime_hours,
    base_salary        = EXCLUDED.base_salary,
    transport_allowance= EXCLUDED.transport_allowance,
    housing_allowance  = EXCLUDED.housing_allowance,
    other_allowances   = EXCLUDED.other_allowances,
    gross_earned       = EXCLUDED.gross_earned,
    total_deductions   = EXCLUDED.total_deductions,
    net_salary         = EXCLUDED.net_salary,
    absence_deduction  = EXCLUDED.absence_deduction,
    penalty_deduction  = EXCLUDED.penalty_deduction,
    advance_deduction  = EXCLUDED.advance_deduction,
    commission_amount  = EXCLUDED.commission_amount,
    overtime_amount    = EXCLUDED.overtime_amount,
    social_insurance   = EXCLUDED.social_insurance,
    income_tax         = EXCLUDED.income_tax,
    health_insurance   = EXCLUDED.health_insurance,
    is_partial_month   = EXCLUDED.is_partial_month
  RETURNING id INTO v_line_id;

  UPDATE hr_payroll_runs
  SET
    total_gross      = (SELECT COALESCE(SUM(gross_earned),     0) FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
    total_deductions = (SELECT COALESCE(SUM(total_deductions), 0) FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
    total_net        = (SELECT COALESCE(SUM(net_salary),       0) FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
    total_employees  = (SELECT COUNT(*)                            FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
    calculated_by    = auth.uid(),
    calculated_at    = now(),
    status           = 'review',
    updated_at       = now()
  WHERE id = p_run_id;

  RETURN v_line_id;
END; $$;


-- ════════════════════════════════════════════════════════════
-- 4. إصلاح دالة approve_payroll_run — القيد المحاسبي الاحترافي المفصل
--    + Future-proof: إضافة حساب 2340 لضرائب الدخل
--
-- الجانب المدين (Dr) — 3 سطور:
--   Dr. 5310 = SUM(gross_earned - absence_deduction - penalty_deduction)
--   Dr. 5320 = SUM(overtime_amount)
--   Dr. 5330 = SUM(commission_amount)
--
-- الجانب الدائن (Cr) — 4 سطور:
--   Cr. 2310 = SUM(net_salary)                          (صافي يُصرف للموظف)
--   Cr. 2320 = SUM(advance_deduction)                  (أقساط سلف)
--   Cr. 2330 = SUM(social_insurance + health_insurance) (تأمينات)
--   Cr. 2340 = SUM(income_tax)                          ← Future-proof!
--
-- لماذا 2340 ضروري؟
--   net_salary = gross + ot + comm - absence - penalty - advance - insurance - TAX
--   إذا TAX > 0 → Cr يقل بقيمة TAX → القيد يختل → صمام ABS يوقف الرواتب!
--   الحل: Cr. 2340 = TAX → توازن دائم بغض النظر عن الضريبة
--
-- تحقق:
--   Dr = (gross - absence - penalty) + overtime + commission
--   Cr = net + advance + insurance + tax
--      = (gross + ot + comm - absence - penalty - advance - insurance - tax)
--        + advance + insurance + tax
--      = gross + ot + comm - absence - penalty
--      = Dr ✓ متوازن دائماً حتى مع الضريبة
-- ════════════════════════════════════════════════════════════

-- 4a. إضافة حساب 2340 (ضرائب مستحقة) إلى شجرة الحسابات
INSERT INTO chart_of_accounts (code, name, name_en, type, sort_order)
VALUES ('2340', 'ضرائب مستحقة الدفع', 'Income Tax Payable', 'liability', 19)
ON CONFLICT (code) DO NOTHING;

-- ربط الأب (2300)
UPDATE chart_of_accounts
SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '2300')
WHERE code = '2340' AND parent_id IS NULL;

CREATE OR REPLACE FUNCTION approve_payroll_run(
  p_run_id  UUID,
  p_user_id UUID
) RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_run          hr_payroll_runs%ROWTYPE;
  v_period       hr_payroll_periods%ROWTYPE;
  v_je_id        UUID;

  -- حسابات COA — الجانب المدين
  v_coa_salaries UUID;  -- 5310 رواتب أساسية
  v_coa_overtime UUID;  -- 5320 بدلات وإضافي
  v_coa_commiss  UUID;  -- 5330 عمولات موظفين

  -- حسابات COA — الجانب الدائن
  v_coa_payable  UUID;  -- 2310 رواتب مستحقة
  v_coa_advances UUID;  -- 2320 سلف الموظفين
  v_coa_insure   UUID;  -- 2330 تأمينات
  v_coa_tax      UUID;  -- 2340 ضرائب مستحقة (Future-proof)

  -- ─── مجاميع الجانب المدين (Dr) ───
  v_total_salary_expense  NUMERIC;  -- Dr. 5310
  v_total_overtime        NUMERIC;  -- Dr. 5320
  v_total_commission      NUMERIC;  -- Dr. 5330
  v_total_debit           NUMERIC;  -- Dr. إجمالي

  -- ─── مجاميع الجانب الدائن (Cr) ───
  v_total_net             NUMERIC;  -- Cr. 2310
  v_total_advance         NUMERIC;  -- Cr. 2320
  v_total_insurance       NUMERIC;  -- Cr. 2330
  v_total_tax             NUMERIC;  -- Cr. 2340 (صفر حالياً — يتفعل مع الضريبة)
  v_total_credit          NUMERIC;  -- Cr. إجمالي
BEGIN
  SELECT * INTO v_run FROM hr_payroll_runs WHERE id = p_run_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'مسير الرواتب غير موجود'; END IF;
  IF v_run.status NOT IN ('review', 'calculating') THEN
    RAISE EXCEPTION 'المسير يجب أن يكون في مرحلة المراجعة (الحالة الحالية: %)', v_run.status;
  END IF;

  SELECT * INTO v_period FROM hr_payroll_periods WHERE id = v_run.period_id;

  -- ─── جلب المجاميع المفصلة من تفاصيل المسير ───
  SELECT
    COALESCE(SUM(gross_earned - absence_deduction - penalty_deduction), 0),
    COALESCE(SUM(overtime_amount), 0),
    COALESCE(SUM(commission_amount), 0),
    COALESCE(SUM(net_salary), 0),
    COALESCE(SUM(advance_deduction), 0),
    COALESCE(SUM(social_insurance + health_insurance), 0),
    COALESCE(SUM(income_tax), 0)   -- Future-proof: يشمل الضريبة حين تُفعَّل
  INTO
    v_total_salary_expense,
    v_total_overtime,
    v_total_commission,
    v_total_net,
    v_total_advance,
    v_total_insurance,
    v_total_tax
  FROM hr_payroll_lines
  WHERE payroll_run_id = p_run_id;

  -- ─── إجماليات للتحقق (Dr = Cr دائماً) ───
  v_total_debit  := v_total_salary_expense + v_total_overtime + v_total_commission;
  v_total_credit := v_total_net + v_total_advance + v_total_insurance + v_total_tax;

  -- ─── جلب معرّفات الحسابات ───
  SELECT id INTO v_coa_salaries FROM chart_of_accounts WHERE code = '5310' AND is_active = true;
  SELECT id INTO v_coa_overtime FROM chart_of_accounts WHERE code = '5320' AND is_active = true;
  SELECT id INTO v_coa_commiss  FROM chart_of_accounts WHERE code = '5330' AND is_active = true;
  SELECT id INTO v_coa_payable  FROM chart_of_accounts WHERE code = '2310' AND is_active = true;
  SELECT id INTO v_coa_advances FROM chart_of_accounts WHERE code = '2320' AND is_active = true;
  SELECT id INTO v_coa_insure   FROM chart_of_accounts WHERE code = '2330' AND is_active = true;
  SELECT id INTO v_coa_tax      FROM chart_of_accounts WHERE code = '2340' AND is_active = true;

  IF v_coa_salaries IS NULL OR v_coa_payable IS NULL THEN
    RAISE EXCEPTION 'الحسابات المحاسبية للرواتب غير موجودة في شجرة الحسابات (5310, 2310)';
  END IF;

  -- ─── التحقق من التوازن (Dr = Cr) ───
  -- Dr = salary_expense + overtime + commission
  -- Cr = net + advance + insurance + tax
  -- الفرق <= 1 مقبول لتقريب الأعشار
  IF ABS(v_total_debit - v_total_credit) > 1 THEN
    RAISE EXCEPTION
      'القيد المحاسبي غير متوازن: مدين=% دائن=% (فرق=%). راجع بيانات المسير.',
      v_total_debit,
      v_total_credit,
      ABS(v_total_debit - v_total_credit);
  END IF;

  -- ─── إنشاء رأس القيد المحاسبي ───
  INSERT INTO journal_entries (
    source_type, source_id, description, entry_date,
    is_auto, status, total_debit, total_credit, created_by
  ) VALUES (
    'manual', p_run_id,
    'مسير رواتب ' || v_period.name,
    v_period.end_date,
    true, 'posted',
    v_total_debit,   -- إجمالي مدين
    v_total_credit,  -- إجمالي دائن (= مدين بعد التحقق)
    p_user_id
  ) RETURNING id INTO v_je_id;

  -- ─── الجانب المدين (Dr) — 3 سطور مفصلة ───

  -- Dr. 5310: رواتب أساسية (مطروح منها الغياب والجزاءات)
  IF v_total_salary_expense > 0 THEN
    INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
    VALUES (v_je_id, v_coa_salaries, v_total_salary_expense, 0,
            'رواتب أساسية وبدلات — ' || v_period.name);
  END IF;

  -- Dr. 5320: مصروف ساعات إضافية
  IF v_total_overtime > 0 AND v_coa_overtime IS NOT NULL THEN
    INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
    VALUES (v_je_id, v_coa_overtime, v_total_overtime, 0,
            'ساعات إضافية — ' || v_period.name);
  END IF;

  -- Dr. 5330: مصروف عمولات موظفين
  IF v_total_commission > 0 AND v_coa_commiss IS NOT NULL THEN
    INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
    VALUES (v_je_id, v_coa_commiss, v_total_commission, 0,
            'عمولات موظفين — ' || v_period.name);
  END IF;

  -- ─── الجانب الدائن (Cr) — 3 سطور مفصلة ───

  -- Cr. 2310: رواتب مستحقة الصرف (الصافي)
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  VALUES (v_je_id, v_coa_payable, 0, v_total_net,
          'صافي رواتب مستحقة الصرف للموظفين');

  -- Cr. 2320: أقساط سلف مستقطعة (تخفيض التزام)
  IF v_total_advance > 0 THEN
    INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
    VALUES (v_je_id, v_coa_advances, 0, v_total_advance,
            'أقساط سلف مُستقطعة من الرواتب');
  END IF;

  -- Cr. 2330: تأمينات اجتماعية وصحية (التزام للجهات الحكومية)
  IF v_total_insurance > 0 AND v_coa_insure IS NOT NULL THEN
    INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
    VALUES (v_je_id, v_coa_insure, 0, v_total_insurance,
            'تأمينات اجتماعية وصحية مستقطعة');
  END IF;

  -- Cr. 2340: ضرائب دخل مستحقة (صفر حالياً — يتفعل عند تشغيل hr.income_tax.enabled)
  IF v_total_tax > 0 AND v_coa_tax IS NOT NULL THEN
    INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
    VALUES (v_je_id, v_coa_tax, 0, v_total_tax,
            'ضريبة كسب العمل مستقطعة');
  END IF;

  -- ─── تحديث المسير ───
  UPDATE hr_payroll_runs
  SET
    status           = 'approved',
    approved_by      = p_user_id,
    approved_at      = now(),
    journal_entry_id = v_je_id,
    updated_at       = now()
  WHERE id = p_run_id;

  -- ─── استقطاع الأقساط ───
  UPDATE hr_advance_installments ai
  SET status             = 'deducted',
      deducted_in_run_id = p_run_id
  FROM hr_payroll_lines pl
  WHERE pl.payroll_run_id = p_run_id
    AND ai.advance_id IN (
      SELECT id FROM hr_advances WHERE employee_id = pl.employee_id
    )
    AND ai.due_year  = v_period.year
    AND ai.due_month = v_period.month
    AND ai.status    = 'pending';

  -- ─── ربط العمولات بالمسير ───
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
    'total_employees', v_run.total_employees
  );
END; $$;


-- ════════════════════════════════════════════════════════════
-- مثال حسابي للتحقق — مع وبدون ضريبة الدخل
--
-- ○ حالة A: بدون ضريبة (الحالة الراهنة)
--   موظف: راتب 5000، أوفرتايم 500، عمولة 300
--          غياب 192، سلفة 400، تأمين 550 (11%)
--   net_salary = 5000+500+300 - 192 - 400 - 550 - 0 = 4658
--   Dr: 5310=4808 + 5320=500 + 5330=300 = إجمالي 5608
--   Cr: 2310=4658 + 2320=400 + 2330=550 + 2340=0 = إجمالي 5608 ✓
--
-- ○ حالة B: مع ضريبة 10% (مستقبلاً)
--   income_tax = 5000 * 10% = 500
--   net_salary = 5000+500+300 - 192 - 400 - 550 - 500 = 4158
--   Dr: 5310=4808 + 5320=500 + 5330=300 = إجمالي 5608
--   Cr: 2310=4158 + 2320=400 + 2330=550 + 2340=500 = إجمالي 5608 ✓
--
-- في كلتا الحالتين: Dr = Cr → صمام ABS لن يثار أبداً
-- ============================================================
