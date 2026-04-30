-- ====================================================================
-- Migration 108: HR Attendance Migration 2 - Leave Sync & Payroll Fixes
-- ====================================================================

-- 1. Create Sync Function
CREATE OR REPLACE FUNCTION sync_approved_leave_to_attendance(p_leave_request_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_leave hr_leave_requests%ROWTYPE;
  v_date DATE;
  v_is_locked_or_worked BOOLEAN;
  v_in_closed_payroll BOOLEAN;
BEGIN
  SELECT * INTO v_leave FROM hr_leave_requests WHERE id = p_leave_request_id AND status = 'approved';
  IF NOT FOUND THEN RETURN; END IF;

  v_date := v_leave.start_date;

  WHILE v_date <= v_leave.end_date LOOP
    -- Check if manually locked or an actual working day (with punch_in and not on_leave)
    SELECT EXISTS (
      SELECT 1 FROM hr_attendance_days
      WHERE employee_id = v_leave.employee_id
        AND shift_date = v_date
        AND (
          COALESCE(is_manually_locked, false) = true
          OR (punch_in_time IS NOT NULL AND status <> 'on_leave')
        )
    ) INTO v_is_locked_or_worked;

    -- Check if in closed payroll
    SELECT EXISTS (
      SELECT 1 FROM hr_payroll_runs pr
      JOIN hr_payroll_periods pp ON pp.id = pr.period_id
      JOIN hr_payroll_lines pl ON pl.payroll_run_id = pr.id
      WHERE pl.employee_id = v_leave.employee_id
        AND pr.status IN ('approved', 'paid')
        AND v_date BETWEEN pp.start_date AND pp.end_date
    ) INTO v_in_closed_payroll;

    IF NOT v_is_locked_or_worked AND NOT v_in_closed_payroll THEN
      INSERT INTO hr_attendance_days (
        employee_id, shift_date, work_date, status, day_value, review_status, 
        source_leave_request_id, updated_at
      ) VALUES (
        v_leave.employee_id, v_date, v_date, 'on_leave', 1, 'ok',
        p_leave_request_id, now()
      )
      ON CONFLICT (employee_id, shift_date) DO UPDATE SET
        status = 'on_leave',
        day_value = 1,
        review_status = 'ok',
        source_leave_request_id = p_leave_request_id,
        updated_at = now()
      WHERE COALESCE(hr_attendance_days.is_manually_locked, false) = false
        AND hr_attendance_days.punch_in_time IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM hr_payroll_runs pr
          JOIN hr_payroll_periods pp ON pp.id = pr.period_id
          JOIN hr_payroll_lines pl ON pl.payroll_run_id = pr.id
          WHERE pl.employee_id = hr_attendance_days.employee_id
            AND pr.status IN ('approved', 'paid')
            AND hr_attendance_days.shift_date BETWEEN pp.start_date AND pp.end_date
        );
    END IF;

    v_date := v_date + 1;
  END LOOP;
END;
$$;

-- 2. Create Cleanup Function
CREATE OR REPLACE FUNCTION cleanup_approved_leave_sync(p_leave_request_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_leave hr_leave_requests%ROWTYPE;
  v_date DATE;
  v_in_closed_payroll BOOLEAN;
BEGIN
  -- We don't filter by status here because it might already be 'cancelled'
  SELECT * INTO v_leave FROM hr_leave_requests WHERE id = p_leave_request_id;
  IF NOT FOUND THEN RETURN; END IF;

  v_date := v_leave.start_date;

  WHILE v_date <= v_leave.end_date LOOP
    -- Check if in closed payroll
    SELECT EXISTS (
      SELECT 1 FROM hr_payroll_runs pr
      JOIN hr_payroll_periods pp ON pp.id = pr.period_id
      JOIN hr_payroll_lines pl ON pl.payroll_run_id = pr.id
      WHERE pl.employee_id = v_leave.employee_id
        AND pr.status IN ('approved', 'paid')
        AND v_date BETWEEN pp.start_date AND pp.end_date
    ) INTO v_in_closed_payroll;

    IF NOT v_in_closed_payroll THEN
      -- Remove auto-generated days that have no punch times
      DELETE FROM hr_attendance_days
      WHERE employee_id = v_leave.employee_id
        AND shift_date = v_date
        AND source_leave_request_id = p_leave_request_id
        AND COALESCE(is_manually_locked, false) = false
        AND punch_in_time IS NULL;

      -- Revert only the source link for days that have punch times (actual work)
      UPDATE hr_attendance_days
      SET source_leave_request_id = NULL,
          updated_at = now()
      WHERE employee_id = v_leave.employee_id
        AND shift_date = v_date
        AND source_leave_request_id = p_leave_request_id
        AND COALESCE(is_manually_locked, false) = false
        AND punch_in_time IS NOT NULL;
    END IF;

    v_date := v_date + 1;
  END LOOP;
END;
$$;

-- 3. Modify `handle_leave_approval` trigger
CREATE OR REPLACE FUNCTION handle_leave_approval()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_approval_levels INTEGER;
BEGIN
  SELECT approval_levels INTO v_approval_levels
  FROM hr_leave_types WHERE id = NEW.leave_type_id;

  -- Audit fields
  IF NEW.status = 'approved_supervisor' AND OLD.status = 'pending_supervisor' THEN
    NEW.supervisor_action_at := COALESCE(NEW.supervisor_action_at, now());
  END IF;

  IF NEW.status = 'approved' AND OLD.status = 'pending_hr' THEN
    NEW.hr_action_at := COALESCE(NEW.hr_action_at, now());
  END IF;

  IF NEW.status = 'rejected' AND OLD.status <> 'rejected' THEN
    NEW.rejected_at := COALESCE(NEW.rejected_at, now());
    IF NEW.rejected_by IS NULL THEN
      SELECT id INTO NEW.rejected_by FROM hr_employees WHERE user_id = auth.uid() LIMIT 1;
    END IF;
  END IF;

  -- State Machine
  IF NEW.status = 'approved_supervisor' AND v_approval_levels = 1 THEN
    NEW.status := 'approved';
  END IF;

  IF NEW.status = 'approved_supervisor' AND v_approval_levels = 2 THEN
    NEW.status := 'pending_hr';
  END IF;

  -- ─── Balances & Sync ───

  -- 1. Final Approval -> deduct from pending, add to used, and SYNC
  IF NEW.status = 'approved' AND OLD.status <> 'approved' THEN
    UPDATE hr_leave_balances
    SET
      used_days    = used_days + NEW.days_count,
      pending_days = GREATEST(0, pending_days - NEW.days_count),
      updated_at   = now()
    WHERE employee_id  = NEW.employee_id
      AND leave_type_id = NEW.leave_type_id
      AND year          = EXTRACT(YEAR FROM NEW.start_date)::INTEGER;

    -- Sync to attendance
    PERFORM sync_approved_leave_to_attendance(NEW.id);
  END IF;

  -- 2. Reject/Cancel from pending -> return pending to balance
  IF NEW.status IN ('rejected', 'cancelled')
     AND OLD.status IN ('pending_supervisor', 'approved_supervisor', 'pending_hr')
  THEN
    UPDATE hr_leave_balances
    SET
      pending_days = GREATEST(0, pending_days - NEW.days_count),
      updated_at   = now()
    WHERE employee_id  = NEW.employee_id
      AND leave_type_id = NEW.leave_type_id
      AND year          = EXTRACT(YEAR FROM NEW.start_date)::INTEGER;
  END IF;

  -- 3. Cancel from APPROVED -> return used to balance and CLEANUP
  IF NEW.status = 'cancelled' AND OLD.status = 'approved' THEN
    -- Prevent cancellation if it overlaps with an approved/paid payroll run
    IF EXISTS (
      SELECT 1 FROM hr_payroll_runs pr
      JOIN hr_payroll_periods pp ON pp.id = pr.period_id
      JOIN hr_payroll_lines pl ON pl.payroll_run_id = pr.id
      WHERE pl.employee_id = NEW.employee_id
        AND pr.status IN ('approved', 'paid')
        AND pp.start_date <= NEW.end_date
        AND pp.end_date >= NEW.start_date
    ) THEN
      RAISE EXCEPTION 'لا يمكن إلغاء إجازة تتقاطع مع مسير رواتب معتمد أو مدفوع';
    END IF;

    -- Prevent cancellation if any linked day has been settled or has actual attendance
    IF EXISTS (
      SELECT 1 FROM hr_attendance_days
      WHERE source_leave_request_id = NEW.id
        AND (COALESCE(leave_balance_restored, false) = true OR punch_in_time IS NOT NULL)
    ) THEN
      RAISE EXCEPTION 'لا يمكن إلغاء إجازة تحتوي على أيام تم حضورها فعليًا أو تمت تسويتها';
    END IF;

    UPDATE hr_leave_balances
    SET
      used_days = GREATEST(0, used_days - NEW.days_count),
      updated_at = now()
    WHERE employee_id  = NEW.employee_id
      AND leave_type_id = NEW.leave_type_id
      AND year          = EXTRACT(YEAR FROM NEW.start_date)::INTEGER;

    -- Cleanup sync
    PERFORM cleanup_approved_leave_sync(NEW.id);
  END IF;

  RETURN NEW;
END; $$;

-- (The trigger itself is already attached to hr_leave_requests, but recreating OR REPLACE handles the function)

-- 4. Payroll calculation fix
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

  -- ★ MIGRATION 2 FIX: Exclude 'on_leave' from basic day_value summation
  SELECT COALESCE(SUM(day_value), 0) INTO v_attended_days
  FROM hr_attendance_days
  WHERE employee_id = p_employee_id
    AND shift_date BETWEEN v_period.start_date AND v_period.end_date
    AND status NOT IN ('weekly_off', 'public_holiday', 'on_leave');

  v_attended_days := v_attended_days
    + COALESCE((v_summary->>'on_leave_days')::NUMERIC, 0)
    + COALESCE((v_summary->>'absent_authorized')::NUMERIC, 0);

  v_auto_absent := GREATEST(0, v_entitled_days - v_attended_days);
  v_absence_deduct := v_auto_absent * v_daily_rate;
  v_penalty_deduct := COALESCE((v_summary->>'penalty_deduction_days')::NUMERIC, 0) * v_daily_rate;

  UPDATE hr_payroll_adjustments
  SET payroll_line_id = NULL
  WHERE employee_id = p_employee_id
    AND status = 'approved'
    AND effective_date BETWEEN v_period.start_date AND v_period.end_date
    AND payroll_line_id IN (
      SELECT id FROM hr_payroll_lines
      WHERE payroll_run_id = p_run_id AND employee_id = p_employee_id
    );

  SELECT COALESCE(SUM(CASE WHEN type = 'bonus' THEN amount ELSE 0 END), 0),
         COALESCE(SUM(CASE WHEN type IN ('deduction', 'penalty') THEN amount ELSE 0 END), 0)
  INTO v_adj_bonus, v_adj_deduction
  FROM hr_payroll_adjustments
  WHERE employee_id = p_employee_id
    AND status = 'approved'
    AND effective_date BETWEEN v_period.start_date AND v_period.end_date
    AND payroll_line_id IS NULL;

  SELECT COALESCE(value::NUMERIC, 1.5) INTO v_overtime_rate FROM company_settings WHERE key = 'hr.overtime_rate';

  v_overtime_amount := COALESCE((v_summary->>'total_overtime_minutes')::NUMERIC, 0) / 60.0
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

    INSERT INTO hr_payroll_lines (
      payroll_run_id, employee_id, period_id, total_working_days, actual_work_days,
      absent_days, deducted_days, overtime_hours, base_salary, transport_allowance, housing_allowance, other_allowances,
      overtime_amount, commission_amount, bonus_amount, gross_earned, absence_deduction, penalty_deduction, advance_deduction,
      social_insurance, income_tax, health_insurance, other_deductions, total_deductions, net_salary, is_partial_month, deficit_carryover
    ) VALUES (
      p_run_id, p_employee_id, v_run.period_id, v_working_days, v_attended_days, v_auto_absent,
      COALESCE((v_summary->>'penalty_deduction_days')::NUMERIC, 0), COALESCE((v_summary->>'total_overtime_minutes')::NUMERIC, 0) / 60.0,
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

    UPDATE hr_payroll_adjustments
    SET payroll_line_id = v_line_id
    WHERE employee_id = p_employee_id AND status = 'approved'
      AND effective_date BETWEEN v_period.start_date AND v_period.end_date AND payroll_line_id IS NULL;

    UPDATE hr_payroll_runs
    SET total_gross = (SELECT COALESCE(SUM(gross_earned), 0) FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
        total_deductions = (SELECT COALESCE(SUM(total_deductions), 0) FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
        total_net = (SELECT COALESCE(SUM(net_salary), 0) FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
        total_employees = (SELECT COUNT(*) FROM hr_payroll_lines WHERE payroll_run_id = p_run_id),
        calculated_by = auth.uid(), calculated_at = now(), status = 'review', updated_at = now()
    WHERE id = p_run_id;

    RETURN v_line_id;
  END;
END; $$;
