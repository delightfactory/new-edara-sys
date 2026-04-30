-- ====================================================================
-- Migration 109: HR Attendance Migration 3 - Daily Absence
-- ====================================================================

-- 1. Insert the new setting for the delay if it doesn't exist
INSERT INTO company_settings (key, value, type, description, category, is_public)
VALUES (
  'hr.absence_run_delay_minutes',
  '120',
  'number',
  'مهلة بالدقائق بعد نهاية الدوام قبل السماح برصد الغياب الآلي',
  'hr',
  false
)
ON CONFLICT (key) DO NOTHING;

-- 2. Create function to mark daily absences
CREATE OR REPLACE FUNCTION mark_daily_absences(p_target_date DATE DEFAULT CURRENT_DATE)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp hr_employees%ROWTYPE;
  v_is_worked BOOLEAN;
  v_has_leave BOOLEAN;
  v_is_locked BOOLEAN;
  v_in_closed_payroll BOOLEAN;
  
  -- Time guard variables
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::date;
  v_work_end TIME;
  v_grace_minutes INTEGER;
  v_cutoff_time TIMESTAMPTZ;
BEGIN
  -- Time Guard: Prevent running for a day that hasn't finished yet
  IF p_target_date > v_today THEN
    RAISE EXCEPTION 'لا يمكن رصد الغياب لأيام في المستقبل';
  END IF;

  IF p_target_date = v_today THEN
    SELECT COALESCE(value, '17:00')::TIME INTO v_work_end
    FROM company_settings WHERE key = 'hr.work_end_time';
    
    SELECT COALESCE(value, '120')::INTEGER INTO v_grace_minutes
    FROM company_settings WHERE key = 'hr.absence_run_delay_minutes';
    
    v_cutoff_time := (p_target_date::TEXT || ' ' || v_work_end::TEXT)::TIMESTAMP AT TIME ZONE 'Africa/Cairo' + (v_grace_minutes || ' minutes')::interval;
    
    IF now() < v_cutoff_time THEN
      RAISE EXCEPTION 'لا يمكن رصد الغياب لليوم الحالي إلا بعد نهاية الدوام بمهلة % دقيقة', v_grace_minutes;
    END IF;
  END IF;

  -- Loop through all active employees
  FOR v_emp IN SELECT * FROM hr_employees WHERE status = 'active'
  LOOP
    -- Hire Date Guard: Do not process employees who were hired after the target date
    IF v_emp.hire_date IS NOT NULL AND v_emp.hire_date > p_target_date THEN
      CONTINUE;
    END IF;

    -- Termination Guard: Do not process employees whose termination date is strictly before the target date
    IF v_emp.termination_date IS NOT NULL AND v_emp.termination_date < p_target_date THEN
      CONTINUE;
    END IF;

    -- 1. Check if the day is an actual work day for the employee
    IF is_employee_work_day(v_emp.id, p_target_date) = 'work_day' THEN
      
      -- 2. Check if there is an existing valid attendance record
      -- An existing record is valid if it's NOT 'absent_unauthorized'.
      SELECT EXISTS (
        SELECT 1 FROM hr_attendance_days 
        WHERE employee_id = v_emp.id 
          AND shift_date = p_target_date
          AND status <> 'absent_unauthorized'
      ) INTO v_is_worked;

      -- 3. Check if there is an approved leave overlapping this date (Prevents race conditions)
      SELECT EXISTS (
        SELECT 1 FROM hr_leave_requests 
        WHERE employee_id = v_emp.id 
          AND status = 'approved' 
          AND p_target_date BETWEEN start_date AND end_date
      ) INTO v_has_leave;

      -- 4. Check if the day is manually locked
      SELECT EXISTS (
        SELECT 1 FROM hr_attendance_days 
        WHERE employee_id = v_emp.id 
          AND shift_date = p_target_date
          AND COALESCE(is_manually_locked, false) = true
      ) INTO v_is_locked;

      -- 5. Check if the day falls within an approved or paid payroll run
      SELECT EXISTS (
        SELECT 1 FROM hr_payroll_runs pr
        JOIN hr_payroll_periods pp ON pp.id = pr.period_id
        JOIN hr_payroll_lines pl ON pl.payroll_run_id = pr.id
        WHERE pl.employee_id = v_emp.id
          AND pr.status IN ('approved', 'paid')
          AND p_target_date BETWEEN pp.start_date AND pp.end_date
      ) INTO v_in_closed_payroll;

      -- If all conditions are met, mark the day as absent
      IF NOT v_is_worked AND NOT v_has_leave AND NOT v_is_locked AND NOT v_in_closed_payroll THEN
        INSERT INTO hr_attendance_days (
          employee_id, shift_date, work_date, status, day_value, review_status, updated_at
        ) VALUES (
          v_emp.id, p_target_date, p_target_date, 'absent_unauthorized', 0, 'ok', now()
        )
        ON CONFLICT (employee_id, shift_date) DO UPDATE SET
          status = 'absent_unauthorized',
          day_value = 0,
          updated_at = now()
        WHERE COALESCE(hr_attendance_days.is_manually_locked, false) = false
          AND hr_attendance_days.status NOT IN ('absent_unauthorized', 'on_leave')
          AND hr_attendance_days.source_leave_request_id IS NULL
          AND hr_attendance_days.punch_in_time IS NULL; 
      END IF;

    END IF;
  END LOOP;
END;
$$;
