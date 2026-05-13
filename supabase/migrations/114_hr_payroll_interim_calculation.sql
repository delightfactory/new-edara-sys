-- ====================================================================
-- Migration 114: HR Payroll Interim Calculation
-- ====================================================================

-- 1. إضافة الأعمدة المطلوبة للحساب المبدئي
ALTER TABLE hr_payroll_runs
  ADD COLUMN IF NOT EXISTS calculation_mode TEXT CHECK (calculation_mode IN ('interim', 'final')),
  ADD COLUMN IF NOT EXISTS calculated_through_date DATE;


-- 2. تعديل Trigger الإشعارات لمنع إرسال إشعار المراجعة في الحساب المبدئي
CREATE OR REPLACE FUNCTION public.notify_on_payroll_paid()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line             RECORD;
  v_month_name       text;
  v_recipient_ids    uuid[];
  v_total_net_text   text;
BEGIN
  -- ── Branch 1: status → 'review' ─────────────────────────────────────────
  IF NEW.status = 'review' AND OLD.status IS DISTINCT FROM 'review' THEN
    -- لا ترسل الإشعار إذا كان الحساب مبدئياً
    IF COALESCE(NEW.calculation_mode, 'final') = 'interim' THEN
       RETURN NEW;
    END IF;

    BEGIN
      SELECT to_char(make_date(pp.year, pp.month, 1), 'Month YYYY')
      INTO v_month_name
      FROM hr_payroll_periods pp
      WHERE pp.id = NEW.period_id
      LIMIT 1;

      v_month_name     := COALESCE(trim(v_month_name), 'هذا الشهر');
      v_total_net_text := to_char(NEW.total_net, 'FM999,999,999.00') || ' ج.م';

      SELECT ARRAY(
        SELECT DISTINCT ur.user_id
        FROM user_roles ur
        JOIN role_permissions rp ON rp.role_id = ur.role_id
        WHERE rp.permission IN ('hr.payroll.calculate', '*')
          AND ur.is_active = true
        LIMIT 15
      ) INTO v_recipient_ids;

      IF v_recipient_ids IS NOT NULL
         AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.call_dispatch_notification(
          'hr.payroll.ready_for_review',
          v_recipient_ids,
          jsonb_build_object(
            'month',          v_month_name,
            'total_net',      v_total_net_text,
            'employee_count', NEW.total_employees::text,
            'payroll_run_id', NEW.id::text
          ),
          'hr_payroll_run',
          NEW.id
        );
      END IF;

    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '[notify_on_payroll_paid] review branch non-critical: %', SQLERRM;
    END;

    RETURN NEW;
  END IF;

  -- ── Branch 2: status → 'paid' ────────────────────────────────────────────
  IF NEW.status <> 'paid' OR OLD.status = 'paid' THEN
    RETURN NEW;
  END IF;

  BEGIN
    SELECT to_char(make_date(pp.year, pp.month, 1), 'Month YYYY')
    INTO   v_month_name
    FROM   hr_payroll_periods pp
    WHERE  pp.id = NEW.period_id
    LIMIT  1;

    v_month_name := COALESCE(trim(v_month_name), 'هذا الشهر');

    FOR v_line IN
      SELECT
        pl.net_salary,
        he.user_id AS employee_profile
      FROM   hr_payroll_lines pl
      JOIN   hr_employees he ON he.id = pl.employee_id
      WHERE  pl.payroll_run_id = NEW.id
        AND  he.user_id IS NOT NULL
    LOOP
      BEGIN
        PERFORM public.call_dispatch_notification(
          'hr.payroll.processed',
          ARRAY[v_line.employee_profile],
          jsonb_build_object(
            'month',          v_month_name,
            'net_salary',     to_char(v_line.net_salary, 'FM999,999,999.00') || ' ج.م',
            'total_amount',   to_char(v_line.net_salary, 'FM999,999,999.00') || ' ج.م',
            'payroll_run_id', NEW.id::text
          ),
          'hr_payroll_run',
          NEW.id
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[notify_on_payroll_paid] per-employee error: %', SQLERRM;
      END;
    END LOOP;

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[notify_on_payroll_paid] non-critical: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$;


-- 3. تقوية calculate_employee_payroll
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

  v_off_day_name     TEXT;
  v_off_dow          INTEGER;
  v_public_holidays  INTEGER;
  v_d                DATE;
  v_calendar_days    INTEGER;

  v_partial_working  INTEGER;
  v_is_partial       BOOLEAN := false;
  v_entitled_days    INTEGER;

  v_attended_days    NUMERIC;
  v_auto_absent      NUMERIC;
  v_on_leave_days    NUMERIC := 0;
  v_authorized_absent NUMERIC := 0;

  v_total_overtime_minutes INTEGER := 0;
  v_penalty_deduction_days NUMERIC := 0;

  v_adj_bonus        NUMERIC := 0;
  v_adj_deduction    NUMERIC := 0;

  v_net              NUMERIC;
  
  v_clearance        JSONB;
  
  -- حساب مبدئي
  v_today            DATE := (now() AT TIME ZONE 'Africa/Cairo')::date;
  v_calc_date        DATE;
  v_is_interim       BOOLEAN := false;
BEGIN
  -- ★ GUARDS
  IF NOT check_permission(auth.uid(), 'hr.payroll.calculate') AND NOT check_permission(auth.uid(), 'hr.payroll.approve') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية حساب مسير الرواتب';
  END IF;

  SELECT * INTO v_run FROM hr_payroll_runs WHERE id = p_run_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'مسير الرواتب غير موجود'; END IF;

  IF v_run.status IN ('approved', 'paid', 'cancelled') THEN
    RAISE EXCEPTION 'لا يمكن إعادة حساب مسير رواتب معتمد أو مدفوع أو ملغي';
  END IF;

  SELECT * INTO v_period FROM hr_payroll_periods WHERE id = v_run.period_id;

  -- تحديد هل الحساب مبدئي أم نهائي
  IF v_today < v_period.start_date THEN
    RAISE EXCEPTION 'لا يمكن حساب مسير لفترة لم تبدأ بعد.';
  END IF;

  IF v_period.end_date >= v_today THEN
    IF v_today <= v_period.start_date THEN
      RAISE EXCEPTION 'لا يمكن حساب مسير مبدئي قبل اكتمال أول يوم في الفترة.';
    END IF;

    v_is_interim := true;
    -- الحساب المبدئي يجب أن يقف عند آخر يوم مكتمل، لا اليوم الحالي المفتوح تشغيلياً.
    v_calc_date := v_today - 1;
  ELSE
    v_calc_date := v_period.end_date;
  END IF;

  SELECT * INTO v_emp FROM hr_employees WHERE id = p_employee_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'الموظف غير موجود'; END IF;

  IF v_run.branch_id IS NOT NULL AND v_emp.branch_id IS DISTINCT FROM v_run.branch_id THEN
    RAISE EXCEPTION 'الموظف لا يتبع لفرع المسير';
  END IF;

  IF v_emp.hire_date > v_calc_date THEN
    RAISE EXCEPTION 'الموظف تم تعيينه بعد تاريخ الحساب الحالي';
  END IF;

  IF v_emp.termination_date IS NOT NULL AND v_emp.termination_date < v_period.start_date THEN
    RAISE EXCEPTION 'الموظف تم إنهاء خدمته قبل بداية فترة المسير';
  END IF;

  -- استخدام v_calc_date بدلاً من v_period.end_date للحساب المبدئي
  v_clearance := check_payroll_attendance_clearance(v_period.start_date, v_calc_date, v_run.branch_id);
  IF NOT (v_clearance ->> 'cleared')::BOOLEAN THEN
    RAISE EXCEPTION 'لا يمكن الحساب — توجد أيام حضور مفتوحة أو معلقة حتى %', v_calc_date;
  END IF;
  -- ★ END GUARDS

  SELECT * INTO v_salary
  FROM get_employee_salary_at_date(p_employee_id, v_period.start_date);

  v_off_day_name := COALESCE(v_emp.weekly_off_day::TEXT, NULL);
  IF v_off_day_name IS NULL THEN
    SELECT value INTO v_off_day_name FROM company_settings WHERE key = 'hr.weekly_off_day';
  END IF;
  v_off_day_name := COALESCE(v_off_day_name, 'friday');

  v_off_dow := CASE lower(v_off_day_name)
    WHEN 'sunday'    THEN 0 WHEN 'monday'    THEN 1 WHEN 'tuesday'   THEN 2
    WHEN 'wednesday' THEN 3 WHEN 'thursday'  THEN 4 WHEN 'friday'    THEN 5
    WHEN 'saturday'  THEN 6 ELSE 5 END;

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

  SELECT COALESCE(value::NUMERIC, 8) INTO v_work_hours_per_day
  FROM company_settings WHERE key = 'hr.work_hours_per_day';

  -- استخراج البيانات يدوياً بدلاً من get_monthly_attendance_summary 
  -- حتى نحصرها من start_date إلى v_calc_date
  SELECT COALESCE(SUM(day_value), 0) INTO v_on_leave_days
  FROM hr_attendance_days
  WHERE employee_id = p_employee_id
    AND shift_date BETWEEN v_period.start_date AND v_calc_date
    AND status = 'on_leave';

  SELECT COALESCE(COUNT(*), 0) INTO v_authorized_absent
  FROM hr_attendance_days
  WHERE employee_id = p_employee_id
    AND shift_date BETWEEN v_period.start_date AND v_calc_date
    AND status = 'absent_authorized';

  SELECT COALESCE(SUM(overtime_minutes), 0) INTO v_total_overtime_minutes
  FROM hr_attendance_days
  WHERE employee_id = p_employee_id
    AND shift_date BETWEEN v_period.start_date AND v_calc_date;

  SELECT COALESCE(SUM(deduction_days), 0) INTO v_penalty_deduction_days
  FROM hr_penalty_instances
  WHERE employee_id = p_employee_id
    AND payroll_run_id IS NULL
    AND COALESCE(is_overridden, false) = false
    AND attendance_day_id IN (
      SELECT id FROM hr_attendance_days 
      WHERE employee_id = p_employee_id 
        AND shift_date BETWEEN v_period.start_date AND v_calc_date
    );

  v_entitled_days := v_working_days;

  -- حساب الأيام المستحقة في الحساب المبدئي (لا يحتسب ما بعد v_calc_date كغياب)
  IF v_is_interim THEN
    v_is_partial := true;
    v_partial_working := 0;
    v_d := GREATEST(v_period.start_date, v_emp.hire_date);
    WHILE v_d <= LEAST(v_calc_date, COALESCE(v_emp.termination_date, v_calc_date)) LOOP
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
  ELSE
    v_gross_earned := COALESCE(v_salary.gross_salary, 0);

    -- Partial month logic (hire or termination) for final calculation
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

    IF v_emp.termination_date IS NOT NULL AND v_emp.termination_date >= v_period.start_date AND v_emp.termination_date <= v_period.end_date THEN
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
  END IF;

  SELECT COALESCE(SUM(day_value), 0) INTO v_attended_days
  FROM hr_attendance_days
  WHERE employee_id = p_employee_id
    AND shift_date BETWEEN v_period.start_date AND v_calc_date
    AND status NOT IN ('weekly_off', 'public_holiday', 'on_leave');

  v_attended_days := v_attended_days + v_on_leave_days + v_authorized_absent;

  v_auto_absent := GREATEST(0, v_entitled_days - v_attended_days);
  v_absence_deduct := v_auto_absent * v_daily_rate;
  v_penalty_deduct := v_penalty_deduction_days * v_daily_rate;

  -- فك ربط التعديلات فقط إذا كنا في الحساب النهائي، أما في المبدئي فلا نربطها ولا نفكها
  IF NOT v_is_interim THEN
    UPDATE hr_payroll_adjustments
    SET payroll_line_id = NULL
    WHERE employee_id = p_employee_id
      AND status = 'approved'
      AND effective_date BETWEEN v_period.start_date AND v_period.end_date
      AND payroll_line_id IN (
        SELECT id FROM hr_payroll_lines
        WHERE payroll_run_id = p_run_id AND employee_id = p_employee_id
      );
  END IF;

  -- جمع المكافآت والخصومات اليدوية حتى calc_date
  SELECT COALESCE(SUM(CASE WHEN type = 'bonus' THEN amount ELSE 0 END), 0),
         COALESCE(SUM(CASE WHEN type IN ('deduction', 'penalty') THEN amount ELSE 0 END), 0)
  INTO v_adj_bonus, v_adj_deduction
  FROM hr_payroll_adjustments
  WHERE employee_id = p_employee_id
    AND status = 'approved'
    AND effective_date BETWEEN v_period.start_date AND v_calc_date
    AND payroll_line_id IS NULL;

  SELECT COALESCE(value::NUMERIC, 1.5) INTO v_overtime_rate FROM company_settings WHERE key = 'hr.overtime_rate';

  v_overtime_amount := (v_total_overtime_minutes / 60.0)
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

  SELECT COALESCE(value::BOOLEAN, false) INTO v_si_enabled FROM company_settings WHERE key = 'hr.social_insurance.enabled';
  SELECT COALESCE(value::NUMERIC, 11) INTO v_si_rate FROM company_settings WHERE key = 'hr.social_insurance.employee_rate';
  SELECT COALESCE(value::BOOLEAN, false) INTO v_tax_enabled FROM company_settings WHERE key = 'hr.income_tax.enabled';
  SELECT COALESCE(value::BOOLEAN, false) INTO v_health_enabled FROM company_settings WHERE key = 'hr.health_insurance.enabled';
  SELECT COALESCE(value::NUMERIC, 0) INTO v_health_amount FROM company_settings WHERE key = 'hr.health_insurance.amount';

  v_si_deduct     := CASE WHEN v_si_enabled    THEN v_gross_earned * (v_si_rate / 100) ELSE 0 END;
  v_tax_deduct    := 0;
  v_health_deduct := CASE WHEN v_health_enabled THEN v_health_amount ELSE 0 END;

  v_net := v_gross_earned + v_overtime_amount + v_commission + v_adj_bonus
         - v_absence_deduct - v_penalty_deduct - v_advance_deduct
         - v_si_deduct - v_tax_deduct - v_health_deduct - v_adj_deduction;

  DECLARE
    v_deficit          NUMERIC := 0;
    v_next_month_start DATE;
  BEGIN
    -- العجز يتم ترحيله فقط في الحساب النهائي
    IF NOT v_is_interim THEN
      IF v_net < 0 THEN
        v_deficit := ABS(v_net); v_net := 0;
        v_next_month_start := (v_period.end_date + INTERVAL '1 day')::DATE;

        DELETE FROM hr_payroll_adjustments
        WHERE employee_id = p_employee_id AND reason LIKE '[ترحيل تلقائي]%' AND effective_date = v_next_month_start;

        INSERT INTO hr_payroll_adjustments (employee_id, type, amount, reason, effective_date, status, created_by)
        VALUES (p_employee_id, 'deduction', v_deficit,
          format('[ترحيل تلقائي] فرق خصومات من %s/%s — الراتب لم يكفِ لتغطية كل الخصومات (عجز: %s ج.م)', v_period.month, v_period.year, v_deficit),
          v_next_month_start, 'approved', COALESCE(auth.uid(), p_employee_id));
      ELSE
        v_next_month_start := (v_period.end_date + INTERVAL '1 day')::DATE;
        DELETE FROM hr_payroll_adjustments
        WHERE employee_id = p_employee_id AND reason LIKE '[ترحيل تلقائي]%' AND effective_date = v_next_month_start;
      END IF;
    ELSE
      -- في الحساب المبدئي: إذا كان الراتب بالسالب، نصفّره شكلياً بدون إنشاء أو عرض عجز مرحّل فعلي.
      IF v_net < 0 THEN
        v_deficit := 0;
        v_net := 0;
      END IF;
    END IF;

    INSERT INTO hr_payroll_lines (
      payroll_run_id, employee_id, period_id, total_working_days, actual_work_days,
      absent_days, deducted_days, overtime_hours, base_salary, transport_allowance, housing_allowance, other_allowances,
      overtime_amount, commission_amount, bonus_amount, gross_earned, absence_deduction, penalty_deduction, advance_deduction,
      social_insurance, income_tax, health_insurance, other_deductions, total_deductions, net_salary, is_partial_month, deficit_carryover
    ) VALUES (
      p_run_id, p_employee_id, v_run.period_id, v_working_days, v_attended_days, v_auto_absent,
      v_penalty_deduction_days, v_total_overtime_minutes / 60.0,
      COALESCE(v_salary.base_salary, 0), COALESCE(v_salary.transport_allowance, 0), COALESCE(v_salary.housing_allowance, 0), COALESCE(v_salary.other_allowances, 0),
      v_overtime_amount, v_commission, v_adj_bonus, v_gross_earned, v_absence_deduct, v_penalty_deduct, v_advance_deduct,
      v_si_deduct, v_tax_deduct, v_health_deduct, v_adj_deduction,
      v_absence_deduct + v_penalty_deduct + v_advance_deduct + v_si_deduct + v_tax_deduct + v_health_deduct + v_adj_deduction,
      v_net, v_is_partial, v_deficit
    )
    ON CONFLICT (payroll_run_id, employee_id) DO UPDATE SET
      total_working_days = EXCLUDED.total_working_days, actual_work_days = EXCLUDED.actual_work_days, absent_days = EXCLUDED.absent_days,
      deducted_days = EXCLUDED.deducted_days, overtime_hours = EXCLUDED.overtime_hours, base_salary = EXCLUDED.base_salary,
      transport_allowance = EXCLUDED.transport_allowance, housing_allowance = EXCLUDED.housing_allowance, other_allowances = EXCLUDED.other_allowances,
      gross_earned = EXCLUDED.gross_earned, bonus_amount = EXCLUDED.bonus_amount, other_deductions = EXCLUDED.other_deductions,
      total_deductions = EXCLUDED.total_deductions, net_salary = EXCLUDED.net_salary, absence_deduction = EXCLUDED.absence_deduction,
      penalty_deduction = EXCLUDED.penalty_deduction, advance_deduction = EXCLUDED.advance_deduction, commission_amount = EXCLUDED.commission_amount,
      overtime_amount = EXCLUDED.overtime_amount, social_insurance = EXCLUDED.social_insurance, income_tax = EXCLUDED.income_tax,
      health_insurance = EXCLUDED.health_insurance, is_partial_month = EXCLUDED.is_partial_month, deficit_carryover = EXCLUDED.deficit_carryover
    RETURNING id INTO v_line_id;

    -- ربط التعديلات يتم حصراً في الحساب النهائي
    IF NOT v_is_interim THEN
      UPDATE hr_payroll_adjustments
      SET payroll_line_id = v_line_id
      WHERE employee_id = p_employee_id AND status = 'approved'
        AND effective_date BETWEEN v_period.start_date AND v_period.end_date AND payroll_line_id IS NULL;
    END IF;

    -- تحديث حالة المسير لتشمل mode و calc_date
    UPDATE hr_payroll_runs
    SET total_gross = (SELECT COALESCE(SUM(gross_earned), 0) FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
        total_deductions = (SELECT COALESCE(SUM(total_deductions), 0) FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
        total_net = (SELECT COALESCE(SUM(net_salary), 0) FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
        total_employees = (SELECT COUNT(*) FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
        calculated_by = auth.uid(), calculated_at = now(), status = 'review', updated_at = now(),
        calculation_mode = CASE WHEN v_is_interim THEN 'interim' ELSE 'final' END,
        calculated_through_date = v_calc_date
    WHERE id = p_run_id;

    RETURN v_line_id;
  END;
END; $$;


-- 4. تقوية calculate_payroll_run
CREATE OR REPLACE FUNCTION calculate_payroll_run(p_run_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_run hr_payroll_runs%ROWTYPE;
  v_period hr_payroll_periods%ROWTYPE;
  v_clearance JSONB;
  v_emp_id UUID;
  v_total_employees INTEGER := 0;
  v_calculated INTEGER := 0;
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::date;
  v_calc_date DATE;
  v_is_interim BOOLEAN := false;
BEGIN
  IF NOT check_permission(auth.uid(), 'hr.payroll.calculate') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية حساب مسير الرواتب';
  END IF;

  SELECT * INTO v_run FROM hr_payroll_runs WHERE id = p_run_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'مسير الرواتب غير موجود'; END IF;

  IF v_run.status IN ('approved', 'paid', 'cancelled') THEN
    RAISE EXCEPTION 'لا يمكن حساب مسير رواتب معتمد أو مدفوع أو ملغي';
  END IF;

  SELECT * INTO v_period FROM hr_payroll_periods WHERE id = v_run.period_id;

  IF v_today < v_period.start_date THEN
    RAISE EXCEPTION 'لا يمكن حساب مسير لفترة لم تبدأ بعد.';
  END IF;

  IF v_period.end_date >= v_today THEN
    IF v_today <= v_period.start_date THEN
      RAISE EXCEPTION 'لا يمكن حساب مسير مبدئي قبل اكتمال أول يوم في الفترة.';
    END IF;

    v_is_interim := true;
    -- الحساب المبدئي يجب أن يقف عند آخر يوم مكتمل، لا اليوم الحالي المفتوح تشغيلياً.
    v_calc_date := v_today - 1;
  ELSE
    v_calc_date := v_period.end_date;
  END IF;

  v_clearance := check_payroll_attendance_clearance(v_period.start_date, v_calc_date, v_run.branch_id);
  IF NOT (v_clearance ->> 'cleared')::BOOLEAN THEN
    RAISE EXCEPTION 'لا يمكن الحساب — توجد أيام حضور مفتوحة أو معلقة حتى %', v_calc_date;
  END IF;

  UPDATE hr_payroll_runs SET status = 'calculating', updated_at = now() WHERE id = p_run_id;

  FOR v_emp_id IN
    SELECT id FROM hr_employees e
    WHERE e.status = 'active'
      AND (v_run.branch_id IS NULL OR e.branch_id = v_run.branch_id)
      AND e.hire_date <= v_calc_date
      AND (e.termination_date IS NULL OR e.termination_date >= v_period.start_date)
  LOOP
    v_total_employees := v_total_employees + 1;
    PERFORM calculate_employee_payroll(v_emp_id, p_run_id);
    v_calculated := v_calculated + 1;
  END LOOP;

  UPDATE hr_payroll_runs 
  SET status = 'review', 
      updated_at = now(),
      calculation_mode = CASE WHEN v_is_interim THEN 'interim' ELSE 'final' END,
      calculated_through_date = v_calc_date
  WHERE id = p_run_id;

  RETURN jsonb_build_object(
    'success', true,
    'run_id', p_run_id,
    'calculated', v_calculated,
    'total_employees', v_total_employees,
    'calculation_mode', CASE WHEN v_is_interim THEN 'interim' ELSE 'final' END,
    'calculated_through_date', v_calc_date
  );
EXCEPTION
  WHEN OTHERS THEN
    UPDATE hr_payroll_runs SET status = COALESCE(v_run.status, 'draft'), updated_at = now() WHERE id = p_run_id;
    RAISE;
END;
$$;


-- 5. تقوية approve_payroll_run ودمج إصلاح 100
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

  v_clearance    JSONB;
  v_blockers     TEXT;
  v_missing_count INTEGER;
BEGIN
  -- ★ GUARDS
  IF p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'المعرف لا يتطابق مع المستخدم الحالي';
  END IF;

  IF NOT check_permission(auth.uid(), 'hr.payroll.approve') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية اعتماد الرواتب';
  END IF;

  SELECT * INTO v_run FROM hr_payroll_runs WHERE id = p_run_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'مسير الرواتب غير موجود'; END IF;
  IF v_run.status NOT IN ('review', 'calculating') THEN
    RAISE EXCEPTION 'المسير في حالة غير قابلة للاعتماد (الحالة: %)', v_run.status;
  END IF;

  SELECT * INTO v_period FROM hr_payroll_periods WHERE id = v_run.period_id;

  IF v_period.end_date > (now() AT TIME ZONE 'Africa/Cairo')::date THEN
    RAISE EXCEPTION 'لا يمكن اعتماد المسير قبل نهاية الفترة الزمنية المحددة';
  END IF;

  IF COALESCE(v_run.calculation_mode, 'final') = 'interim'
     OR (v_run.calculated_through_date IS NOT NULL 
         AND v_run.calculated_through_date < v_period.end_date) THEN
    RAISE EXCEPTION 'لا يمكن اعتماد حساب مبدئي. يرجى إعادة الحساب النهائي بعد انتهاء الفترة.';
  END IF;

  v_clearance := check_payroll_attendance_clearance(
    v_period.start_date,
    v_period.end_date,
    v_run.branch_id
  );

  IF NOT (v_clearance ->> 'cleared')::BOOLEAN THEN
    SELECT string_agg((b ->> 'message'), ' | ')
    INTO   v_blockers
    FROM   jsonb_array_elements(v_clearance -> 'blockers') AS b;

    RAISE EXCEPTION
      'لا يمكن اعتماد المسير — توجد حالات حضور غير محسومة: %',
      v_blockers;
  END IF;

  -- التأكد من وجود أسطر رواتب لكل الموظفين المؤهلين
  SELECT COUNT(*) INTO v_missing_count
  FROM hr_employees e
  WHERE e.status = 'active'
    AND (v_run.branch_id IS NULL OR e.branch_id = v_run.branch_id)
    AND e.hire_date <= v_period.end_date
    AND (e.termination_date IS NULL OR e.termination_date >= v_period.start_date)
    AND NOT EXISTS (
      SELECT 1 FROM hr_payroll_lines pl 
      WHERE pl.payroll_run_id = p_run_id AND pl.employee_id = e.id
    );

  IF v_missing_count > 0 THEN
    RAISE EXCEPTION 'يوجد عدد % موظف مؤهل لم يتم حساب رواتبهم في هذا المسير. يرجى إعادة الحساب.', v_missing_count;
  END IF;

  -- قبل الاعتماد، اربط الجزاءات بهذا المسير
  UPDATE hr_penalty_instances pi
  SET payroll_run_id = p_run_id
  FROM hr_attendance_days ad
  WHERE pi.attendance_day_id = ad.id
    AND ad.shift_date BETWEEN v_period.start_date AND v_period.end_date
    AND pi.payroll_run_id IS NULL
    AND COALESCE(pi.is_overridden, false) = false
    AND pi.employee_id IN (SELECT employee_id FROM hr_payroll_lines WHERE payroll_run_id = p_run_id);

  -- ★ GUARD: منع الاعتماد ببيانات قديمة لفترة تصحيح أبريل
  DECLARE
    v_last_backfill TIMESTAMPTZ;
    v_audit_exists BOOLEAN;
  BEGIN
    IF v_period.start_date <= '2026-04-30' AND v_period.end_date >= '2026-04-05' THEN
      SELECT EXISTS (
        SELECT FROM pg_tables
        WHERE schemaname = 'public' AND tablename = 'hr_penalty_instances_audit_20260428_early_leave_minutes_backfill'
      ) INTO v_audit_exists;
      
      IF v_audit_exists THEN
        EXECUTE 'SELECT MAX(created_at) FROM hr_penalty_instances_audit_20260428_early_leave_minutes_backfill' INTO v_last_backfill;
        IF v_last_backfill IS NOT NULL AND (v_run.calculated_at IS NULL OR v_run.calculated_at < v_last_backfill) THEN
          RAISE EXCEPTION 'يجب إعادة حساب المسير بعد تصحيح جزاءات الانصراف المبكر قبل الاعتماد.';
        END IF;
      END IF;
    END IF;
  END;
  -- ★ END GUARDS

  PERFORM public.prepare_target_reward_payouts(v_run.period_id);

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
      -- دمج تعديل aggregate FOR UPDATE الخاص بـ 100
      WITH locked_advance_installments AS (
        SELECT ai.amount
        FROM hr_advance_installments ai
        JOIN hr_advances adv ON adv.id = ai.advance_id
        WHERE adv.employee_id = v_line.employee_id
          AND ai.due_year = v_period.year AND ai.due_month = v_period.month
          AND ai.status = 'pending'
        FOR UPDATE OF ai
      )
      SELECT COALESCE(SUM(amount), 0) INTO v_actual_advance
      FROM locked_advance_installments;

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

  INSERT INTO journal_entries (
    source_type, source_id, description, entry_date,
    is_auto, status, total_debit, total_credit, created_by
  ) VALUES (
    'hr_payroll', p_run_id,
    'مسير رواتب ' || v_period.name,
    v_period.end_date, true, 'posted',
    v_total_debit, v_total_credit, p_user_id
  ) RETURNING id INTO v_je_id;

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

  UPDATE hr_payroll_runs
  SET status           = 'approved',
      approved_by      = p_user_id,
      approved_at      = now(),
      journal_entry_id = v_je_id,
      total_net        = (SELECT COALESCE(SUM(net_salary),0)       FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
      total_deductions = (SELECT COALESCE(SUM(total_deductions),0) FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
      updated_at       = now()
  WHERE id = p_run_id;

  UPDATE hr_advance_installments ai
  SET status = 'deducted', deducted_in_run_id = p_run_id
  FROM hr_payroll_lines pl
  WHERE pl.payroll_run_id = p_run_id
    AND ai.advance_id IN (SELECT id FROM hr_advances WHERE employee_id = pl.employee_id)
    AND ai.due_year = v_period.year AND ai.due_month = v_period.month
    AND ai.status = 'pending';

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
