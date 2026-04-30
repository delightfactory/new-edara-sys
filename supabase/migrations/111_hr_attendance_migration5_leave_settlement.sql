-- ====================================================================
-- Migration 111: HR Attendance Migration 5 - Leave Settlement
-- ====================================================================

-- 1. Create settlement function
CREATE OR REPLACE FUNCTION settle_attendance_day_against_leave(
  p_attendance_day_id UUID,
  p_force BOOLEAN DEFAULT false
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_day hr_attendance_days%ROWTYPE;
  v_leave_req hr_leave_requests%ROWTYPE;
  v_work_hours NUMERIC;
  v_new_status hr_attendance_status;
BEGIN
  -- Fetch the attendance day
  SELECT * INTO v_day FROM hr_attendance_days WHERE id = p_attendance_day_id;
  
  -- If not found, or no source leave, or not checked out, do nothing
  IF NOT FOUND 
     OR v_day.source_leave_request_id IS NULL 
     OR v_day.punch_in_time IS NULL 
     OR v_day.punch_out_time IS NULL 
  THEN
    RETURN;
  END IF;

  -- Idempotency check
  IF COALESCE(v_day.leave_balance_restored, false) = true THEN
    RETURN;
  END IF;

  -- Manual lock check
  IF NOT p_force AND COALESCE(v_day.is_manually_locked, false) = true THEN
    RETURN;
  END IF;

  -- Payroll lock check
  IF EXISTS (
    SELECT 1 FROM hr_payroll_runs pr
    JOIN hr_payroll_periods pp ON pp.id = pr.period_id
    JOIN hr_payroll_lines pl ON pl.payroll_run_id = pr.id
    WHERE pl.employee_id = v_day.employee_id
      AND pr.status IN ('approved', 'paid')
      AND v_day.shift_date BETWEEN pp.start_date AND pp.end_date
  ) THEN
    RETURN;
  END IF;

  -- Fetch the linked leave request
  SELECT * INTO v_leave_req FROM hr_leave_requests WHERE id = v_day.source_leave_request_id;
  IF NOT FOUND OR v_leave_req.status <> 'approved' THEN
    RETURN;
  END IF;

  -- Determine required hours per day
  SELECT COALESCE((value)::NUMERIC, 8) INTO v_work_hours
  FROM company_settings WHERE key = 'hr.work_hours_per_day';

  -- Check if attended hours satisfy full day
  IF COALESCE(v_day.effective_hours, 0) >= v_work_hours THEN
    -- Restore balance
    UPDATE hr_leave_balances
    SET used_days = GREATEST(0, used_days - 1),
        updated_at = now()
    WHERE employee_id = v_day.employee_id
      AND leave_type_id = v_leave_req.leave_type_id
      AND year = EXTRACT(YEAR FROM v_leave_req.start_date)::INTEGER;

    -- Update attendance status to present or late
    v_new_status := 'present';
    IF COALESCE(v_day.late_minutes, 0) > 0 THEN
      v_new_status := 'late';
    END IF;

    UPDATE hr_attendance_days
    SET 
      status = v_new_status,
      leave_balance_restored = true,
      leave_balance_restored_at = now(),
      updated_at = now()
    WHERE id = p_attendance_day_id;
  ELSE
    -- Partial attendance: Do NOT restore leave balance, but calculate partial day_value and update status
    v_new_status := 'present';
    IF COALESCE(v_day.late_minutes, 0) > 0 THEN
      v_new_status := 'late';
    END IF;

    UPDATE hr_attendance_days
    SET 
      status = v_new_status,
      day_value = LEAST(1.00, ROUND((COALESCE(v_day.effective_hours, 0) / v_work_hours)::NUMERIC, 2)),
      leave_balance_restored = false,
      updated_at = now()
    WHERE id = p_attendance_day_id;
  END IF;
END;
$$;
