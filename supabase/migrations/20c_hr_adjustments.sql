-- =============================================================
-- Migration 20c: HR Payroll Adjustments
-- إضافة جدول التعديلات (مكافآت/خصومات/جزاءات يدوية)
-- وتحديث calculate_employee_payroll لقراءتها
-- =============================================================


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  1. جدول التعديلات: hr_payroll_adjustments               ║
-- ║  مكافآت + خصومات + جزاءات يدوية مربوطة بتاريخ محدد      ║
-- ╚═══════════════════════════════════════════════════════════╝

CREATE TABLE IF NOT EXISTS hr_payroll_adjustments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id     UUID NOT NULL REFERENCES hr_employees(id),

  -- نوع التعديل
  type            TEXT NOT NULL CHECK (type IN ('bonus', 'deduction', 'penalty')),
  amount          NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  reason          TEXT NOT NULL,

  -- التاريخ المحدد (يندرج تحت الفترة المعنية)
  effective_date  DATE NOT NULL DEFAULT CURRENT_DATE,

  -- نظام الاعتماد
  status          TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'approved', 'rejected')),
  created_by      UUID REFERENCES profiles(id) DEFAULT auth.uid(),
  approved_by     UUID REFERENCES profiles(id),
  approved_at     TIMESTAMPTZ,
  rejection_reason TEXT,

  -- ربط بالمسير عند الحساب
  payroll_line_id UUID REFERENCES hr_payroll_lines(id) ON DELETE SET NULL,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_adj_employee    ON hr_payroll_adjustments(employee_id, effective_date DESC);
CREATE INDEX IF NOT EXISTS idx_adj_status      ON hr_payroll_adjustments(status, effective_date);
CREATE INDEX IF NOT EXISTS idx_adj_date        ON hr_payroll_adjustments(effective_date);

-- trigger لتحديث updated_at
DROP TRIGGER IF EXISTS trg_adj_updated_at ON hr_payroll_adjustments;
CREATE TRIGGER trg_adj_updated_at
  BEFORE UPDATE ON hr_payroll_adjustments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  2. إضافة is_manual لجدول hr_penalty_instances           ║
-- ║  للتمييز بين الجزاءات التلقائية واليدوية                 ║
-- ╚═══════════════════════════════════════════════════════════╝

ALTER TABLE hr_penalty_instances
  ADD COLUMN IF NOT EXISTS is_manual BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE hr_penalty_instances
  ADD COLUMN IF NOT EXISTS manual_reason TEXT;


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  3. RLS — صلاحيات جدول التعديلات                         ║
-- ╚═══════════════════════════════════════════════════════════╝

ALTER TABLE hr_payroll_adjustments ENABLE ROW LEVEL SECURITY;

-- القراءة: hr.payroll.read أو hr.adjustments.read
CREATE POLICY adj_select ON hr_payroll_adjustments
  FOR SELECT TO authenticated
  USING (
    check_permission(auth.uid(), 'hr.payroll.read')
    OR check_permission(auth.uid(), 'hr.adjustments.read')
  );

-- الإنشاء: hr.adjustments.create
CREATE POLICY adj_insert ON hr_payroll_adjustments
  FOR INSERT TO authenticated
  WITH CHECK (
    check_permission(auth.uid(), 'hr.adjustments.create')
  );

-- التعديل: hr.adjustments.approve (للاعتماد/الرفض)
CREATE POLICY adj_update ON hr_payroll_adjustments
  FOR UPDATE TO authenticated
  USING (
    check_permission(auth.uid(), 'hr.adjustments.approve')
    OR (created_by = auth.uid() AND status = 'pending')
  );


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  4. RPC: اعتماد / رفض تعديل                              ║
-- ╚═══════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION approve_payroll_adjustment(
  p_adjustment_id UUID,
  p_action        TEXT   -- 'approve' أو 'reject'
) RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_adj hr_payroll_adjustments%ROWTYPE;
BEGIN
  SELECT * INTO v_adj FROM hr_payroll_adjustments WHERE id = p_adjustment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'التعديل غير موجود'; END IF;
  IF v_adj.status <> 'pending' THEN RAISE EXCEPTION 'التعديل ليس في حالة انتظار'; END IF;

  IF NOT check_permission(auth.uid(), 'hr.adjustments.approve') THEN
    RAISE EXCEPTION 'لا تملك صلاحية اعتماد/رفض التعديلات';
  END IF;

  IF p_action = 'approve' THEN
    UPDATE hr_payroll_adjustments
    SET status = 'approved', approved_by = auth.uid(), approved_at = now()
    WHERE id = p_adjustment_id;
  ELSIF p_action = 'reject' THEN
    UPDATE hr_payroll_adjustments
    SET status = 'rejected', approved_by = auth.uid(), approved_at = now()
    WHERE id = p_adjustment_id;
  ELSE
    RAISE EXCEPTION 'الإجراء غير صالح — استخدم approve أو reject';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'adjustment_id', p_adjustment_id,
    'action', p_action
  );
END; $$;

GRANT EXECUTE ON FUNCTION approve_payroll_adjustment(UUID, TEXT) TO authenticated;


-- ╔═══════════════════════════════════════════════════════════╗
-- ║  5. تحديث calculate_employee_payroll — قراءة التعديلات   ║
-- ║  المعتمدة التي effective_date ضمن فترة المسير            ║
-- ╚═══════════════════════════════════════════════════════════╝
-- NOTE: هذا التحديث يُعدّل النسخة في 20b بإضافة STEP جديد
-- يقرأ من hr_payroll_adjustments ويضيف:
--   bonus → v_adj_bonus
--   deduction/penalty → v_adj_deduction
-- ثم يضيفهم للحسابات

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

  v_work_hours_per_day NUMERIC;

  -- calendar working days
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

  -- ★ NEW: adjustments (bonus/deduction/penalty)
  v_adj_bonus        NUMERIC := 0;
  v_adj_deduction    NUMERIC := 0;

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
  -- STEP 1: تحديد يوم العطلة الأسبوعية
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
    ELSE 5
  END;

  -- ════════════════════════════════════════════════════════
  -- STEP 2: حساب أيام العمل التقويمية في الفترة الكاملة
  -- ════════════════════════════════════════════════════════
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

  -- ════════════════════════════════════════════════════════
  -- STEP 3: ساعات العمل
  -- ════════════════════════════════════════════════════════
  SELECT COALESCE(value::NUMERIC, 8) INTO v_work_hours_per_day
  FROM company_settings WHERE key = 'hr.work_hours_per_day';

  -- ════════════════════════════════════════════════════════
  -- STEP 4: المستحق + Partial Month
  -- ════════════════════════════════════════════════════════
  v_gross_earned := COALESCE(v_salary.gross_salary, 0);
  v_entitled_days := v_working_days;

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
  -- STEP 5: حساب الغياب التلقائي
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

  -- ════════════════════════════════════════════════════════
  -- STEP 5a: ★ فك ربط التعديلات السابقة (عند إعادة الحساب)
  -- بدون هذه الخطوة، إعادة الحساب لن تجد التعديلات لأنها 
  -- مربوطة بالفعل بسطر المسير من الحساب السابق
  -- ════════════════════════════════════════════════════════
  UPDATE hr_payroll_adjustments
  SET payroll_line_id = NULL
  WHERE employee_id = p_employee_id
    AND status = 'approved'
    AND effective_date BETWEEN v_period.start_date AND v_period.end_date
    AND payroll_line_id IN (
      SELECT id FROM hr_payroll_lines
      WHERE payroll_run_id = p_run_id AND employee_id = p_employee_id
    );

  -- ════════════════════════════════════════════════════════
  -- STEP 5b: ★ قراءة التعديلات المعتمدة (مكافآت/خصومات/جزاءات)
  -- ════════════════════════════════════════════════════════
  SELECT
    COALESCE(SUM(CASE WHEN type = 'bonus' THEN amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN type IN ('deduction', 'penalty') THEN amount ELSE 0 END), 0)
  INTO v_adj_bonus, v_adj_deduction
  FROM hr_payroll_adjustments
  WHERE employee_id = p_employee_id
    AND status = 'approved'
    AND effective_date BETWEEN v_period.start_date AND v_period.end_date
    AND payroll_line_id IS NULL;  -- لم تُحتسب بعد (أو أُلغي ربطها)

  -- ════════════════════════════════════════════════════════
  -- STEP 6: الأوفرتايم
  -- ════════════════════════════════════════════════════════
  SELECT COALESCE(value::NUMERIC, 1.5) INTO v_overtime_rate
  FROM company_settings WHERE key = 'hr.overtime_rate';

  v_overtime_amount :=
    COALESCE((v_summary->>'total_overtime_minutes')::NUMERIC, 0) / 60.0
    * (COALESCE(v_salary.base_salary, 0) / (v_working_days * v_work_hours_per_day))
    * v_overtime_rate;

  -- ════════════════════════════════════════════════════════
  -- STEP 7: العمولات والسلف
  -- ════════════════════════════════════════════════════════
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

  -- ════════════════════════════════════════════════════════
  -- STEP 8: التأمينات والضرائب
  -- ════════════════════════════════════════════════════════
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

  -- ════════════════════════════════════════════════════════
  -- STEP 9: الصافي (★ يشمل التعديلات + معالجة العجز)
  -- ════════════════════════════════════════════════════════
  v_net := v_gross_earned + v_overtime_amount + v_commission + v_adj_bonus
         - v_absence_deduct - v_penalty_deduct - v_advance_deduct
         - v_si_deduct - v_tax_deduct - v_health_deduct - v_adj_deduction;

  -- ★ STEP 9a: معالجة العجز — ترحيل الفرق للشهر التالي
  -- عندما يكون الصافي سالباً: الموظف مدين للشركة بالفرق
  -- الحل: إنشاء خصم تلقائي على الشهر التالي
  DECLARE
    v_deficit          NUMERIC := 0;
    v_next_month_start DATE;
  BEGIN
    IF v_net < 0 THEN
      v_deficit := ABS(v_net);
      v_net     := 0;

      -- حساب أول يوم في الشهر التالي
      v_next_month_start := (v_period.end_date + INTERVAL '1 day')::DATE;

      -- ① حذف أي ترحيل تلقائي سابق لنفس الموظف/الفترة (idempotency عند إعادة الحساب)
      DELETE FROM hr_payroll_adjustments
      WHERE employee_id = p_employee_id
        AND reason LIKE '[ترحيل تلقائي]%'
        AND effective_date = v_next_month_start;

      -- ② إنشاء خصم تلقائي للشهر التالي
      INSERT INTO hr_payroll_adjustments (
        employee_id, type, amount, reason, effective_date, status, created_by
      ) VALUES (
        p_employee_id,
        'deduction',
        v_deficit,
        format('[ترحيل تلقائي] فرق خصومات من %s/%s — الراتب لم يكفِ لتغطية كل الخصومات (عجز: %s ج.م)',
               v_period.month, v_period.year, v_deficit),
        v_next_month_start,
        'approved',
        COALESCE(auth.uid(), p_employee_id)  -- system-generated
      );
    ELSE
      -- إذا لم يعد هناك عجز (مثلاً بعد إلغاء سلفة)، نحذف الترحيل السابق
      v_next_month_start := (v_period.end_date + INTERVAL '1 day')::DATE;
      DELETE FROM hr_payroll_adjustments
      WHERE employee_id = p_employee_id
        AND reason LIKE '[ترحيل تلقائي]%'
        AND effective_date = v_next_month_start;
    END IF;

  -- ════════════════════════════════════════════════════════
  -- STEP 10: حفظ النتائج
  -- ════════════════════════════════════════════════════════
  INSERT INTO hr_payroll_lines (
    payroll_run_id, employee_id, period_id,
    total_working_days, actual_work_days,
    absent_days, deducted_days, overtime_hours,
    base_salary, transport_allowance, housing_allowance, other_allowances,
    overtime_amount, commission_amount, bonus_amount, gross_earned,
    absence_deduction, penalty_deduction, advance_deduction,
    social_insurance, income_tax, health_insurance, other_deductions,
    total_deductions, net_salary, is_partial_month, deficit_carryover
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
    v_overtime_amount, v_commission, v_adj_bonus, v_gross_earned,
    v_absence_deduct, v_penalty_deduct, v_advance_deduct,
    v_si_deduct, v_tax_deduct, v_health_deduct, v_adj_deduction,
    v_absence_deduct + v_penalty_deduct + v_advance_deduct
      + v_si_deduct + v_tax_deduct + v_health_deduct + v_adj_deduction,
    v_net,
    v_is_partial,
    v_deficit
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
    bonus_amount       = EXCLUDED.bonus_amount,
    other_deductions   = EXCLUDED.other_deductions,
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
    is_partial_month   = EXCLUDED.is_partial_month,
    deficit_carryover  = EXCLUDED.deficit_carryover
  RETURNING id INTO v_line_id;

  -- ★ ربط التعديلات بسطر المسير
  UPDATE hr_payroll_adjustments
  SET payroll_line_id = v_line_id
  WHERE employee_id = p_employee_id
    AND status = 'approved'
    AND effective_date BETWEEN v_period.start_date AND v_period.end_date
    AND payroll_line_id IS NULL;

  -- تحديث إجماليات المسير
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
  END; -- نهاية كتلة DECLARE الداخلية
END; $$;

-- ════════════════════════════════════════════════════════
-- ★ إضافة عمود deficit_carryover لجدول hr_payroll_lines
-- يُسجّل المبلغ المُرحّل للشهر التالي عند عجز الراتب
-- ════════════════════════════════════════════════════════
ALTER TABLE hr_payroll_lines
  ADD COLUMN IF NOT EXISTS deficit_carryover NUMERIC(12,2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN hr_payroll_lines.deficit_carryover IS
  'المبلغ المُرحّل للشهر التالي كخصم تلقائي — يُنشأ عندما تتجاوز الخصومات الإجمالية مستحقات الموظف';

