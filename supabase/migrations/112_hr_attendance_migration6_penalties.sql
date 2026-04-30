-- ====================================================================
-- Migration 112: HR Attendance Migration 6 - Penalties & Deductions
-- ====================================================================

-- 1. Add custom_minutes column to store actual deduction minutes
ALTER TABLE hr_penalty_instances
ADD COLUMN IF NOT EXISTS deduction_minutes INTEGER DEFAULT 0;

-- 2. Redefine process_attendance_penalties to handle double deduction and custom early leave
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
  v_deduct_days  NUMERIC(5,4);
  v_count        INTEGER := 0;
  v_month_start  DATE;
  v_month_end    DATE;
  v_work_hours   NUMERIC;
BEGIN
  SELECT * INTO v_day FROM hr_attendance_days WHERE id = p_attendance_day_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  v_month_start := date_trunc('month', v_day.shift_date)::DATE;
  v_month_end   := (date_trunc('month', v_day.shift_date) + INTERVAL '1 month - 1 day')::DATE;

  SELECT COALESCE((value)::NUMERIC, 8) INTO v_work_hours
  FROM company_settings WHERE key = 'hr.work_hours_per_day';

  -- Clear previous auto-generated penalties for this day
  DELETE FROM hr_penalty_instances
  WHERE attendance_day_id = p_attendance_day_id
    AND payroll_run_id IS NULL
    AND is_overridden = false
    AND COALESCE(is_manual, false) = false;

  -- ─── معالجة التأخير ───
  IF v_day.late_minutes > 0 AND v_day.status IN ('present', 'late', 'half_day') THEN
    v_penalty_type := 'late';
    
    -- Prevent double deduction if day is already half_day due to lateness
    IF v_day.status <> 'half_day' THEN
      v_minutes      := v_day.late_minutes;

      -- عدد مرات التأخير في هذا الشهر
      SELECT COUNT(*) + 1 INTO v_occurrence
      FROM hr_penalty_instances pi
      JOIN hr_attendance_days ad ON ad.id = pi.attendance_day_id
      WHERE pi.employee_id  = v_day.employee_id
        AND pi.penalty_type = v_penalty_type
        AND ad.shift_date   BETWEEN v_month_start AND v_month_end
        AND pi.attendance_day_id <> p_attendance_day_id;

      -- إيجاد القاعدة المناسبة
      SELECT * INTO v_rule
      FROM hr_penalty_rules
      WHERE penalty_type  = v_penalty_type
        AND is_active     = true
        AND v_minutes     >= min_minutes
        AND (max_minutes IS NULL OR v_minutes < max_minutes)
        AND v_occurrence  >= occurrence_from
        AND (occurrence_to IS NULL OR v_occurrence <= occurrence_to)
      ORDER BY sort_order DESC
      LIMIT 1;

      IF FOUND THEN
        v_deduct_days := CASE v_rule.deduction_type
          WHEN 'quarter_day' THEN 0.25
          WHEN 'half_day'    THEN 0.5
          WHEN 'full_day'    THEN 1.0
          ELSE 0
        END;

        INSERT INTO hr_penalty_instances (
          employee_id, attendance_day_id, penalty_rule_id,
          penalty_type, occurrence_in_month, deduction_type, deduction_days
        ) VALUES (
          v_day.employee_id, p_attendance_day_id, v_rule.id,
          v_penalty_type, v_occurrence, v_rule.deduction_type, v_deduct_days
        );
        v_count := v_count + 1;
      END IF;
    END IF;
  END IF;

  -- ─── معالجة الغياب بدون إذن ───
  IF v_day.status = 'absent_unauthorized' THEN
    v_penalty_type := 'absent_unauthorized';

    SELECT COUNT(*) + 1 INTO v_occurrence
    FROM hr_penalty_instances pi
    JOIN hr_attendance_days ad ON ad.id = pi.attendance_day_id
    WHERE pi.employee_id  = v_day.employee_id
      AND pi.penalty_type = v_penalty_type
      AND ad.shift_date   BETWEEN v_month_start AND v_month_end
      AND pi.attendance_day_id <> p_attendance_day_id;

    SELECT * INTO v_rule
    FROM hr_penalty_rules
    WHERE penalty_type  = v_penalty_type
      AND is_active     = true
      AND v_occurrence  >= occurrence_from
      AND (occurrence_to IS NULL OR v_occurrence <= occurrence_to)
    ORDER BY sort_order DESC
    LIMIT 1;

    IF FOUND THEN
      v_deduct_days := CASE v_rule.deduction_type
        WHEN 'quarter_day' THEN 0.25
        WHEN 'half_day'    THEN 0.5
        WHEN 'full_day'    THEN 1.0
        ELSE 0
      END;

      INSERT INTO hr_penalty_instances (
        employee_id, attendance_day_id, penalty_rule_id,
        penalty_type, occurrence_in_month, deduction_type, deduction_days
      ) VALUES (
        v_day.employee_id, p_attendance_day_id, v_rule.id,
        v_penalty_type, v_occurrence, v_rule.deduction_type, v_deduct_days
      );
      v_count := v_count + 1;
    END IF;
  END IF;

  -- ─── معالجة الانصراف المبكر بدون إذن ───
  IF v_day.checkout_status = 'early_unauthorized' AND COALESCE(v_day.early_leave_minutes, 0) > 0 THEN
    v_penalty_type := 'early_leave_unauthorized';

    -- حساب الدقائق غير المغطاة بناءً على التداخل
    DECLARE
      v_uncovered_minutes INTEGER := COALESCE(v_day.early_leave_minutes, 0);
      v_covered_minutes INTEGER := 0;
      v_perm RECORD;
      v_work_end TIME;
      v_early_start TIMESTAMPTZ;
      v_early_end TIMESTAMPTZ;
      v_perm_start TIMESTAMPTZ;
      v_perm_end TIMESTAMPTZ;
      v_overlap_start TIMESTAMPTZ;
      v_overlap_end TIMESTAMPTZ;
    BEGIN
      -- إيجاد نهاية الدوام
      SELECT COALESCE(value, '17:00')::TIME INTO v_work_end
      FROM company_settings WHERE key = 'hr.work_end_time';
      
      v_early_start := v_day.punch_out_time;
      v_early_end := (v_day.shift_date::TEXT || ' ' || v_work_end::TEXT)::TIMESTAMP AT TIME ZONE 'Africa/Cairo';

      -- إيجاد الأذونات المعتمدة وحساب التداخل الفعلي
      FOR v_perm IN 
        SELECT * FROM hr_permission_requests 
        WHERE employee_id = v_day.employee_id 
          AND permission_date = v_day.shift_date 
          AND status = 'approved'
      LOOP
        v_perm_start := (v_day.shift_date::TEXT || ' ' || v_perm.leave_time::TEXT)::TIMESTAMP AT TIME ZONE 'Africa/Cairo';
        
        IF v_perm.actual_return IS NOT NULL THEN
          v_perm_end := (v_day.shift_date::TEXT || ' ' || v_perm.actual_return::TEXT)::TIMESTAMP AT TIME ZONE 'Africa/Cairo';
        ELSIF v_perm.expected_return IS NOT NULL THEN
          v_perm_end := (v_day.shift_date::TEXT || ' ' || v_perm.expected_return::TEXT)::TIMESTAMP AT TIME ZONE 'Africa/Cairo';
        ELSE
          v_perm_end := v_perm_start + (COALESCE(v_perm.duration_minutes, 0) || ' minutes')::interval;
        END IF;

        -- حساب التداخل بين نافذة الانصراف المبكر ونافذة الإذن
        v_overlap_start := GREATEST(v_early_start, v_perm_start);
        v_overlap_end := LEAST(v_early_end, v_perm_end);

        IF v_overlap_start < v_overlap_end THEN
          v_covered_minutes := v_covered_minutes + EXTRACT(EPOCH FROM (v_overlap_end - v_overlap_start))/60::INTEGER;
        END IF;
      END LOOP;

      v_uncovered_minutes := GREATEST(0, COALESCE(v_day.early_leave_minutes, 0) - v_covered_minutes);

      IF v_uncovered_minutes > 0 THEN
        SELECT COUNT(*) + 1 INTO v_occurrence
        FROM hr_penalty_instances pi
        JOIN hr_attendance_days ad ON ad.id = pi.attendance_day_id
        WHERE pi.employee_id  = v_day.employee_id
          AND pi.penalty_type = v_penalty_type
          AND ad.shift_date   BETWEEN v_month_start AND v_month_end
          AND pi.attendance_day_id <> p_attendance_day_id;

        -- حساب نسبة الخصم المالي بالأيام (دقائق التأخير / دقائق الدوام الكلي)
        v_deduct_days := ROUND((v_uncovered_minutes / (v_work_hours * 60.0))::NUMERIC, 4);

        INSERT INTO hr_penalty_instances (
          employee_id, attendance_day_id, penalty_rule_id,
          penalty_type, occurrence_in_month, deduction_type, deduction_days, deduction_minutes
        ) VALUES (
          v_day.employee_id, p_attendance_day_id, NULL, 
          v_penalty_type, v_occurrence, 'custom_minutes', v_deduct_days, v_uncovered_minutes
        );
        v_count := v_count + 1;
      END IF;
    END;
  END IF;

  RETURN v_count;
END; $$;
