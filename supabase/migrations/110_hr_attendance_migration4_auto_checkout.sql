-- ====================================================================
-- Migration 110: HR Attendance Migration 4 - Auto Checkout
-- ====================================================================

CREATE OR REPLACE FUNCTION run_auto_checkout(p_target_date DATE DEFAULT CURRENT_DATE)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_day hr_attendance_days%ROWTYPE;
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::date;
  v_work_end TIME;
  v_grace_minutes INTEGER;
  v_cutoff_time TIMESTAMPTZ;
  v_auto_checkout_time TIMESTAMPTZ;
  v_early_leave_minutes INTEGER;
  v_overtime_minutes INTEGER;
  v_effective_hours NUMERIC(5,2);
  v_checkout_status hr_checkout_status;
  v_scheduled_end TIMESTAMPTZ;
BEGIN
  -- 1. Time Guard: Prevent running for a day that hasn't finished yet
  IF p_target_date > v_today THEN
    RAISE EXCEPTION 'لا يمكن الإغلاق التلقائي لأيام في المستقبل';
  END IF;

  IF p_target_date = v_today THEN
    SELECT COALESCE(value, '17:00')::TIME INTO v_work_end
    FROM company_settings WHERE key = 'hr.work_end_time';
    
    SELECT COALESCE(value, '15')::INTEGER INTO v_grace_minutes
    FROM company_settings WHERE key = 'hr.auto_checkout_minutes';
    
    v_cutoff_time := (p_target_date::TEXT || ' ' || v_work_end::TEXT)::TIMESTAMP AT TIME ZONE 'Africa/Cairo' + (v_grace_minutes || ' minutes')::interval;
    
    IF now() < v_cutoff_time THEN
      RAISE EXCEPTION 'لا يمكن تشغيل الإغلاق التلقائي لليوم الحالي إلا بعد نهاية الدوام بمهلة % دقيقة', v_grace_minutes;
    END IF;
  END IF;

  -- Default work_end for the logic
  SELECT COALESCE(value, '17:00')::TIME INTO v_work_end
  FROM company_settings WHERE key = 'hr.work_end_time';

  -- 2. Process open days
  FOR v_day IN 
    SELECT d.* FROM hr_attendance_days d
    WHERE d.shift_date = p_target_date
      AND d.punch_in_time IS NOT NULL
      AND d.punch_out_time IS NULL
      AND COALESCE(d.is_manually_locked, false) = false
      AND NOT EXISTS (
        SELECT 1 FROM hr_payroll_runs pr
        JOIN hr_payroll_periods pp ON pp.id = pr.period_id
        JOIN hr_payroll_lines pl ON pl.payroll_run_id = pr.id
        WHERE pl.employee_id = d.employee_id
          AND pr.status IN ('approved', 'paid')
          AND d.shift_date BETWEEN pp.start_date AND pp.end_date
      )
  LOOP
    -- 3. Determine auto checkout time
    v_scheduled_end := (v_day.shift_date::TEXT || ' ' || v_work_end::TEXT)::TIMESTAMP AT TIME ZONE 'Africa/Cairo';
    
    IF v_day.last_tracking_ping_at IS NOT NULL AND v_day.last_tracking_ping_at > v_day.punch_in_time THEN
      v_auto_checkout_time := v_day.last_tracking_ping_at;
    ELSE
      v_auto_checkout_time := v_scheduled_end;
    END IF;

    -- Safety check: don't checkout before checkin
    IF v_auto_checkout_time < v_day.punch_in_time THEN
      v_auto_checkout_time := v_day.punch_in_time;
    END IF;

    -- Calculate metrics
    v_early_leave_minutes := 0;
    v_overtime_minutes := 0;
    
    IF v_auto_checkout_time < v_scheduled_end THEN
      v_early_leave_minutes := GREATEST(0, EXTRACT(EPOCH FROM (v_scheduled_end - v_auto_checkout_time))/60)::INTEGER;
    ELSIF v_auto_checkout_time > v_scheduled_end THEN
      v_overtime_minutes := GREATEST(0, EXTRACT(EPOCH FROM (v_auto_checkout_time - v_scheduled_end))/60)::INTEGER;
    END IF;

    v_effective_hours := GREATEST(0, EXTRACT(EPOCH FROM (v_auto_checkout_time - v_day.punch_in_time)) / 3600.0);

    -- Determine checkout status
    IF v_overtime_minutes > 0 THEN
      v_checkout_status := 'overtime';
    ELSIF v_early_leave_minutes > 0 THEN
      IF EXISTS (
        SELECT 1 FROM hr_leave_requests
        WHERE employee_id = v_day.employee_id
          AND start_date <= v_day.shift_date
          AND end_date   >= v_day.shift_date
          AND status = 'approved'
      ) OR EXISTS (
        SELECT 1 FROM hr_permission_requests
        WHERE employee_id = v_day.employee_id
          AND permission_date = v_day.shift_date
          AND status = 'approved'
      ) THEN
        v_checkout_status := 'early_authorized';
      ELSE
        v_checkout_status := 'early_unauthorized';
      END IF;
    ELSE
      v_checkout_status := 'on_time';
    END IF;

    -- 4. Update the record
    UPDATE hr_attendance_days
    SET 
      punch_out_time = v_auto_checkout_time,
      checkout_status = v_checkout_status,
      early_leave_minutes = v_early_leave_minutes,
      overtime_minutes = v_overtime_minutes,
      effective_hours = v_effective_hours,
      is_auto_checkout = true,
      tracking_status = 'ended',
      tracking_ended_at = v_auto_checkout_time,
      updated_at = now()
    WHERE id = v_day.id;

    -- 5. Create Operational Alert
    INSERT INTO hr_attendance_alerts (
      employee_id, attendance_day_id, alert_type, severity, status, title, details
    ) VALUES (
      v_day.employee_id, v_day.id, 'auto_checkout', 'medium', 'open', 'إغلاق تلقائي للدوام', 
      'تم إغلاق الدوام تلقائياً لعدم وجود بصمة انصراف. يرجى المراجعة.'
    );

    -- 6. Insert Log Record
    INSERT INTO hr_attendance_logs (
      employee_id, attendance_day_id, log_type,
      latitude, longitude, gps_accuracy, location_id,
      event_time, synced_at, requires_review
    ) VALUES (
      v_day.employee_id, v_day.id, 'auto_checkout',
      COALESCE(v_day.last_tracking_lat, 0), 
      COALESCE(v_day.last_tracking_lng, 0), 
      COALESCE(v_day.last_tracking_accuracy, 0), 
      v_day.location_in_id,
      v_auto_checkout_time, now(), true
    );

    -- 7. Settle against leave if full day attended
    PERFORM settle_attendance_day_against_leave(v_day.id);

    -- 8. Reprocess penalties in case the day status changed
    PERFORM reprocess_attendance_day_penalties(v_day.id);

  END LOOP;
END;
$$;
