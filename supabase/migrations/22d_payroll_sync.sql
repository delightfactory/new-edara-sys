-- ============================================================
-- 22d_payroll_sync.sql — النسخة v4 (الإصلاح النهائي)
-- برهان التوازن الكامل (شامل other_deductions):
--   net = gross + OT + commission + bonus
--         - absence - penalty - other_ded - advance - ins - tax
--   salary_expense = gross - absence - penalty - other_ded  ← ★ مؤلف من هذا
--   Dr = salary_exp + OT + commission + bonus
--   Cr = net + advance + ins + tax
--      = (gross + OT + commission + bonus - absence - penalty
--         - other_ded - advance - ins - tax) + advance + ins + tax
--      = gross + OT + commission + bonus - absence - penalty - other_ded
--      = salary_exp + OT + commission + bonus = Dr ✓
-- الخلاصة: other_deductions تُقلّل مصروف الرواتب Dr.5310 لإغلاق التوازن
-- بدلاً من تركها داخل net_salary فقط (مما كان يسبب EXCEPTION)
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- FIX 1: RLS لشرائح وعملاء الأهداف (تشمل rewards.view)
-- ════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "trt_read"  ON public.target_reward_tiers;
DROP POLICY IF EXISTS "trt_write" ON public.target_reward_tiers;
DROP POLICY IF EXISTS "tc_read"   ON public.target_customers;
DROP POLICY IF EXISTS "tc_write"  ON public.target_customers;

CREATE POLICY "trt_read" ON public.target_reward_tiers FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.targets t WHERE t.id = target_id AND t.assigned_by = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.targets t JOIN hr_employees he ON he.id = t.scope_id
      WHERE t.id = target_id AND t.scope = 'individual' AND he.user_id = auth.uid()
    )
    OR check_permission(auth.uid(), 'targets.read_all')
    OR check_permission(auth.uid(), 'targets.rewards.view')
    OR check_permission(auth.uid(), 'targets.rewards.configure')
  );

CREATE POLICY "trt_write" ON public.target_reward_tiers FOR ALL
  USING (
    check_permission(auth.uid(), 'targets.create')
    OR check_permission(auth.uid(), 'targets.read_all')
    OR check_permission(auth.uid(), 'targets.rewards.configure')
  );

CREATE POLICY "tc_read" ON public.target_customers FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.targets t WHERE t.id = target_id AND t.assigned_by = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.targets t JOIN hr_employees he ON he.id = t.scope_id
      WHERE t.id = target_id AND t.scope = 'individual' AND he.user_id = auth.uid()
    )
    OR check_permission(auth.uid(), 'targets.read_all')
    OR check_permission(auth.uid(), 'targets.rewards.view')
    OR check_permission(auth.uid(), 'targets.rewards.configure')
  );

CREATE POLICY "tc_write" ON public.target_customers FOR ALL
  USING (
    check_permission(auth.uid(), 'targets.create')
    OR check_permission(auth.uid(), 'targets.read_all')
    OR check_permission(auth.uid(), 'targets.rewards.configure')
  );

-- ════════════════════════════════════════════════════════════
-- FIX 2: Trigger — منع upgrade_value بدون growth_pct
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_validate_upgrade_value_fn()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_type_code TEXT;
BEGIN
  SELECT tt.code INTO v_type_code
  FROM public.target_types tt WHERE tt.id = NEW.type_id;

  IF v_type_code = 'upgrade_value' THEN
    IF ((NEW.filter_criteria->>'growth_pct')::NUMERIC) IS NULL
    OR ((NEW.filter_criteria->>'growth_pct')::NUMERIC) <= 0 THEN
      RAISE EXCEPTION
        '[EDARA] هدف upgrade_value يتطلب filter_criteria.growth_pct > 0. '
        'مثال: {"growth_pct": 30}';
    END IF;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_validate_upgrade_value ON public.targets;
CREATE TRIGGER trg_validate_upgrade_value
  BEFORE INSERT OR UPDATE OF filter_criteria, type_id
  ON public.targets
  FOR EACH ROW EXECUTE FUNCTION public.trg_validate_upgrade_value_fn();

-- ════════════════════════════════════════════════════════════
-- FIX 3: create_target_with_rewards() — مزامنة الصلاحيات + Scope Guard
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.create_target_with_rewards(
  p_type_id         UUID,
  p_name            TEXT,
  p_description     TEXT        DEFAULT NULL,
  p_scope           TEXT        DEFAULT 'individual',
  p_scope_id        UUID        DEFAULT NULL,
  p_period          TEXT        DEFAULT 'monthly',
  p_period_start    DATE        DEFAULT NULL,
  p_period_end      DATE        DEFAULT NULL,
  p_target_value    NUMERIC     DEFAULT 0,
  p_min_value       NUMERIC     DEFAULT NULL,
  p_stretch_value   NUMERIC     DEFAULT NULL,
  p_product_id      UUID        DEFAULT NULL,
  p_category_id     UUID        DEFAULT NULL,
  p_governorate_id  UUID        DEFAULT NULL,
  p_city_id         UUID        DEFAULT NULL,
  p_area_id         UUID        DEFAULT NULL,
  p_dormancy_days   INTEGER     DEFAULT NULL,
  p_filter_criteria JSONB       DEFAULT '{}',
  p_notes           TEXT        DEFAULT NULL,
  p_reward_type         TEXT    DEFAULT NULL,
  p_reward_base_value   NUMERIC DEFAULT NULL,
  p_reward_pool_basis   TEXT    DEFAULT NULL,
  p_payout_month_offset INTEGER DEFAULT 0,
  p_tiers           JSONB       DEFAULT '[]',
  p_customers       JSONB       DEFAULT '[]',
  p_auto_payout     BOOLEAN     DEFAULT false,
  p_user_id         UUID        DEFAULT NULL
) RETURNS UUID
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_target_id        UUID;
  v_type_code        TEXT;
  v_type_cat         TEXT;
  v_tier             JSONB;
  v_customer         JSONB;
  v_seq              INTEGER := 0;
  v_caller_id        UUID;
  v_caller_branch_id UUID;
  v_has_read_all     BOOLEAN;
  v_scope_allowed    BOOLEAN := false;
BEGIN
  v_caller_id := COALESCE(p_user_id, auth.uid());
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION '[EDARA] يجب تمرير p_user_id أو استدعاء الدالة من جلسة مُستَوثقة';
  END IF;
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- ★ مزامنة مع tgt_insert (21b L232): read_all OR (create/assign + scope check)
  v_has_read_all := check_permission(v_caller_id, 'targets.read_all');

  IF NOT v_has_read_all THEN
    IF NOT (check_permission(v_caller_id, 'targets.create')
         OR check_permission(v_caller_id, 'targets.assign')) THEN
      RAISE EXCEPTION 'ليس لديك صلاحية إنشاء الأهداف';
    END IF;

    -- Scope Guard: مطابق لـ tgt_insert
    SELECT branch_id INTO v_caller_branch_id
    FROM hr_employees WHERE user_id = v_caller_id LIMIT 1;

    v_scope_allowed := CASE p_scope
      WHEN 'individual' THEN
        EXISTS (SELECT 1 FROM hr_employees
                WHERE id = p_scope_id AND branch_id = v_caller_branch_id)
      WHEN 'branch' THEN
        p_scope_id = v_caller_branch_id
      WHEN 'department' THEN
        EXISTS (SELECT 1 FROM hr_departments
                WHERE id = p_scope_id AND branch_id = v_caller_branch_id)
      ELSE false  -- company: read_all فقط
    END;

    IF NOT v_scope_allowed THEN
      RAISE EXCEPTION '[EDARA] لا يمكنك إنشاء أهداف خارج نطاق فرعك';
    END IF;
  END IF;

  SELECT tt.code, tt.category INTO v_type_code, v_type_cat
  FROM public.target_types tt WHERE tt.id = p_type_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'نوع الهدف غير موجود'; END IF;

  IF NOT public.is_valid_reward_config(v_type_cat, v_type_code, p_reward_type, p_reward_pool_basis) THEN
    RAISE EXCEPTION '[EDARA] تركيبة المكافأة غير صالحة للهدف من نوع [%]', v_type_code;
  END IF;

  -- growth_pct إلزامي لـ upgrade_value
  IF v_type_code = 'upgrade_value' THEN
    IF ((COALESCE(p_filter_criteria,'{}')->>'growth_pct')::NUMERIC) IS NULL
    OR ((COALESCE(p_filter_criteria,'{}')->>'growth_pct')::NUMERIC) <= 0 THEN
      RAISE EXCEPTION '[EDARA] upgrade_value يتطلب filter_criteria.growth_pct > 0';
    END IF;
  END IF;

  IF p_auto_payout = true THEN
    IF p_reward_type IS NULL OR COALESCE(p_reward_base_value,0) <= 0 THEN
      RAISE EXCEPTION 'auto_payout يتطلب reward_type وreward_base_value > 0';
    END IF;
    IF jsonb_array_length(COALESCE(p_tiers,'[]')) = 0 THEN
      RAISE EXCEPTION 'auto_payout يتطلب شريحة واحدة على الأقل';
    END IF;
  END IF;

  INSERT INTO public.targets (
    type_id, name, description, scope, scope_id, period,
    period_start, period_end, target_value, min_value, stretch_value,
    product_id, category_id, governorate_id, city_id, area_id,
    dormancy_days, filter_criteria, notes,
    reward_type, reward_base_value, reward_pool_basis, payout_month_offset,
    auto_payout, assigned_by, is_active, is_paused
  ) VALUES (
    p_type_id, p_name, p_description, p_scope, p_scope_id, p_period,
    COALESCE(p_period_start, date_trunc('month', CURRENT_DATE)::DATE),
    COALESCE(p_period_end,   (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::DATE),
    p_target_value, p_min_value, p_stretch_value,
    p_product_id, p_category_id, p_governorate_id, p_city_id, p_area_id,
    p_dormancy_days, COALESCE(p_filter_criteria,'{}'), p_notes,
    p_reward_type, p_reward_base_value, p_reward_pool_basis, COALESCE(p_payout_month_offset,0),
    false, v_caller_id, true, false
  ) RETURNING id INTO v_target_id;

  FOR v_tier IN SELECT * FROM jsonb_array_elements(COALESCE(p_tiers,'[]'))
  LOOP
    v_seq := v_seq + 1;
    INSERT INTO public.target_reward_tiers (target_id, sequence, threshold_pct, reward_pct, label)
    VALUES (
      v_target_id,
      COALESCE((v_tier->>'sequence')::INTEGER, v_seq),
      (v_tier->>'threshold_pct')::NUMERIC,
      (v_tier->>'reward_pct')::NUMERIC,
      v_tier->>'label'
    );
  END LOOP;

  FOR v_customer IN SELECT * FROM jsonb_array_elements(COALESCE(p_customers,'[]'))
  LOOP
    INSERT INTO public.target_customers (
      target_id, customer_id, baseline_value, baseline_category_count,
      baseline_period_start, baseline_period_end
    ) VALUES (
      v_target_id,
      (v_customer->>'customer_id')::UUID,
      (v_customer->>'baseline_value')::NUMERIC,
      (v_customer->>'baseline_category_count')::INTEGER,
      (v_customer->>'baseline_period_start')::DATE,
      (v_customer->>'baseline_period_end')::DATE
    );
  END LOOP;

  IF p_auto_payout = true THEN
    UPDATE public.targets SET auto_payout = true, updated_at = now()
    WHERE id = v_target_id;
  END IF;

  PERFORM public.recalculate_target_progress(v_target_id, CURRENT_DATE);
  RETURN v_target_id;
END; $$;

-- ════════════════════════════════════════════════════════════
-- FIX 4 [P0 FINAL]: approve_payroll_run() — القيد المتوازن النهائي
--
-- المنطق الصحيح:
--   net_salary (من 20c) = gross + OT + commission + bonus - deductions
--   Dr.5310 = gross - absence - penalty  (salary_expense)
--   Dr.5320 = overtime
--   Dr.5330 = commission
--   ★ Dr.5335 = bonus                   ← يُضاف للمدين مباشرة (لا via helper)
--   Cr.2310 = net_salary                ← يشمل bonus بالفعل (لا نضيفه مرة ثانية!)
--   Cr.2320 = advance_deduction
--   Cr.2330 = insurance
--   Cr.2340 = tax
--
-- إثبات: Dr = Cr
--   Dr = salary_exp + OT + commission + bonus
--   Cr = (gross + OT + commission + bonus - absence - penalty - advance - ins - tax)
--        + advance + ins + tax
--      = gross + OT + commission + bonus - absence - penalty
--      = salary_exp + OT + commission + bonus = Dr ✓
-- ════════════════════════════════════════════════════════════

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
  v_coa_bonus    UUID;  -- 5335 ★
  v_coa_payable  UUID;  -- 2310
  v_coa_advances UUID;  -- 2320
  v_coa_insure   UUID;  -- 2330
  v_coa_tax      UUID;  -- 2340

  -- مجاميع من hr_payroll_lines (net_salary يشمل bonus)
  v_total_salary_expense NUMERIC;  -- gross - absence - penalty
  v_total_overtime       NUMERIC;
  v_total_commission     NUMERIC;
  v_total_net            NUMERIC;  -- صافي الرواتب (يشمل bonus)
  v_total_advance        NUMERIC;
  v_total_insurance      NUMERIC;
  v_total_tax            NUMERIC;

  -- ★ bonus منفصل للقيد المدين فقط (لا يُضاف للدائن — موجود في net_salary)
  v_total_bonus          NUMERIC := 0;

  v_total_debit          NUMERIC;
  v_total_credit         NUMERIC;
BEGIN
  SELECT * INTO v_run FROM hr_payroll_runs WHERE id = p_run_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'مسير الرواتب غير موجود'; END IF;
  IF v_run.status NOT IN ('review', 'calculating') THEN
    RAISE EXCEPTION 'المسير في حالة غير قابلة للاعتماد (الحالة: %)', v_run.status;
  END IF;

  SELECT * INTO v_period FROM hr_payroll_periods WHERE id = v_run.period_id;

  -- ══════════════════════════════════════════════════════════
  -- STEP 0أ: تثبيت مكافآت الأهداف (idempotent)
  -- ══════════════════════════════════════════════════════════
  PERFORM public.prepare_target_reward_payouts(v_run.period_id);

  -- ══════════════════════════════════════════════════════════
  -- STEP 0ب: إعادة حساب أسطر الرواتب للموظفين المتأثرين
  -- (calculate_employee_payroll يقرأ adjustments بـ effective_date)
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

  -- ★ [FINAL FIX] قراءة كل المكافآت التي دخلت فعلاً في net_salary
  -- hr_payroll_lines.bonus_amount = SUM(hr_payroll_adjustments.amount) للـ bonus المعتمد
  -- يشمل: مكافآت أهداف + مكافآت HR يدوية — كل ما أضافه calculate_employee_payroll
  SELECT COALESCE(SUM(bonus_amount), 0) INTO v_total_bonus
  FROM hr_payroll_lines
  WHERE payroll_run_id = p_run_id;

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

    -- إعادة جلب بعد تصحيح السلف (نفس فلتر other_deductions)
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
  -- ★ الإجماليات المتوازنة (برهان رياضي مثبَّت أعلاه)
  -- Dr = salary_expense + overtime + commission + bonus
  -- Cr = net_salary(يشمل bonus) + advance + insurance + tax
  -- ══════════════════════════════════════════════════════════
  v_total_debit  := v_total_salary_expense + v_total_overtime + v_total_commission + v_total_bonus;
  v_total_credit := v_total_net + v_total_advance + v_total_insurance + v_total_tax;

  -- جلب معرفات الحسابات
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

  -- فحص التوازن (يجب أن يكون صفراً بعد برهان الجبر)
  IF ABS(v_total_debit - v_total_credit) > 0.50 THEN
    RAISE EXCEPTION 'القيد غير متوازن: Dr=% Cr=% (Δ=%) — راجع بيانات المسير',
      v_total_debit, v_total_credit, ABS(v_total_debit - v_total_credit);
  END IF;

  -- فارق تقريب دقيق (< 0.5)
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

  -- ★ Dr.5335: مصروف مكافآت الأهداف (مدين فقط — الدائن موجود في net_salary)
  IF v_total_bonus > 0 AND v_coa_bonus IS NOT NULL THEN
    INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
    VALUES (v_je_id, v_coa_bonus, v_total_bonus, 0,
            'مكافآت أهداف الموظفين — ' || v_period.name);
  END IF;

  -- ─── الجانب الدائن (Cr) ───

  -- Cr.2310: صافي رواتب (يشمل bonus بالفعل من calculate_employee_payroll)
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

  -- 5900: فروق تقريب (يلتقط فقط ما تبقى من دقة الأرقام العشرية)
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

-- Grants
GRANT EXECUTE ON FUNCTION public.create_target_with_rewards TO authenticated;

-- ════════════════════════════════════════════════════════════
-- نهاية 22d_payroll_sync.sql v3 — القيد المتوازن النهائي ✅
-- Dr = Cr بدون ازدواج محاسبي
-- ════════════════════════════════════════════════════════════
