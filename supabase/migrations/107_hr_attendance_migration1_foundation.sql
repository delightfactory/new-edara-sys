-- ═══════════════════════════════════════════════════════════════
-- 107_hr_attendance_migration1_foundation.sql
-- Migration 1: Foundation, Manual Protection, and Payroll Blockers
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1) Add new columns to hr_attendance_days
-- ─────────────────────────────────────────────────────────────

ALTER TABLE hr_attendance_days
ADD COLUMN IF NOT EXISTS is_manually_locked BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS source_leave_request_id UUID REFERENCES hr_leave_requests(id),
ADD COLUMN IF NOT EXISTS leave_balance_restored BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS leave_balance_restored_at TIMESTAMPTZ;

-- ─────────────────────────────────────────────────────────────
-- 2) Update upsert_attendance_and_reprocess to lock day
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION upsert_attendance_and_reprocess(
  p_employee_id       UUID,
  p_shift_date        DATE,
  p_punch_in_time     TIMESTAMPTZ  DEFAULT NULL,
  p_punch_out_time    TIMESTAMPTZ  DEFAULT NULL,
  p_status            hr_attendance_status DEFAULT NULL,
  p_notes             TEXT         DEFAULT NULL,
  p_user_id           UUID         DEFAULT NULL
) RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_day_id          UUID;
  v_existing        hr_attendance_days%ROWTYPE;
  v_new_eff_hours   NUMERIC;
  v_new_late_min    INTEGER := 0;
  v_new_early_min   INTEGER := 0;
  v_new_ot_min      INTEGER := 0;
  v_new_status      hr_attendance_status;
  v_new_co_status   hr_checkout_status;
  v_work_start      TIME;
  v_work_end        TIME;
  v_grace_min       INTEGER;
  v_sched_start     TIMESTAMPTZ;
  v_sched_end       TIMESTAMPTZ;
  v_penalties_count INTEGER;
  v_payroll_status  TEXT;
BEGIN
  -- [SECURITY] صلاحية التعديل
  IF NOT check_permission(COALESCE(p_user_id, auth.uid()), 'hr.attendance.create') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تعديل الحضور';
  END IF;

  -- [GUARD] منع التعديل اليدوي داخل مسيرات معتمدة أو مدفوعة
  SELECT pr.status INTO v_payroll_status
  FROM hr_payroll_lines pl
  JOIN hr_payroll_runs pr ON pr.id = pl.payroll_run_id
  WHERE pl.employee_id = p_employee_id
    AND pr.period_id IN (
      SELECT id FROM hr_payroll_periods 
      WHERE p_shift_date BETWEEN start_date AND end_date
    );

  IF v_payroll_status IN ('approved', 'paid') THEN
    RAISE EXCEPTION 'لا يمكن تعديل الحضور لليوم % لأنه مرتبط بمسير رواتب في حالة %', p_shift_date, v_payroll_status;
  END IF;

  -- 1. إعدادات ساعات العمل
  SELECT value::TIME INTO v_work_start
  FROM company_settings WHERE key = 'hr.work_start_time';
  SELECT value::TIME INTO v_work_end
  FROM company_settings WHERE key = 'hr.work_end_time';
  SELECT COALESCE(value::INTEGER, 15) INTO v_grace_min
  FROM company_settings WHERE key = 'hr.late_grace_minutes';

  v_work_start := COALESCE(v_work_start, '09:00'::TIME);
  v_work_end   := COALESCE(v_work_end,   '17:00'::TIME);

  -- 2. حساب القيم المشتقة
  v_new_status    := COALESCE(p_status, 'present');
  v_new_co_status := NULL;

  IF p_punch_in_time IS NOT NULL AND p_punch_out_time IS NOT NULL THEN
    v_new_eff_hours := LEAST(
      ROUND(EXTRACT(EPOCH FROM (p_punch_out_time - p_punch_in_time)) / 3600.0, 2),
      24.00
    );

    v_sched_start := (p_shift_date + v_work_start) AT TIME ZONE 'Africa/Cairo';
    IF p_punch_in_time > v_sched_start + (v_grace_min || ' minutes')::INTERVAL THEN
      v_new_late_min := EXTRACT(EPOCH FROM (p_punch_in_time - v_sched_start))::INTEGER / 60;
      IF v_new_late_min > 0 THEN
        v_new_status := 'late';
      END IF;
    END IF;

    v_sched_end := (p_shift_date + v_work_end) AT TIME ZONE 'Africa/Cairo';
    IF p_punch_out_time > v_sched_end + INTERVAL '30 minutes' THEN
      v_new_ot_min := EXTRACT(EPOCH FROM (p_punch_out_time - v_sched_end))::INTEGER / 60;
      v_new_co_status := 'overtime';
    ELSIF p_punch_out_time < v_sched_end - INTERVAL '5 minutes' THEN
      v_new_early_min := EXTRACT(EPOCH FROM (v_sched_end - p_punch_out_time))::INTEGER / 60;
      IF EXISTS (
        SELECT 1 FROM hr_leave_requests
        WHERE employee_id = p_employee_id
          AND start_date <= p_shift_date AND end_date >= p_shift_date
          AND status = 'approved'
      ) OR EXISTS (
        SELECT 1 FROM hr_permission_requests
        WHERE employee_id = p_employee_id
          AND permission_date = p_shift_date
          AND status = 'approved'
      ) THEN
        v_new_co_status := 'early_authorized';
      ELSE
        v_new_co_status := 'early_unauthorized';
      END IF;
    ELSE
      v_new_co_status := 'on_time';
    END IF;
  ELSIF p_punch_in_time IS NOT NULL THEN
    v_sched_start := (p_shift_date + v_work_start) AT TIME ZONE 'Africa/Cairo';
    IF p_punch_in_time > v_sched_start + (v_grace_min || ' minutes')::INTERVAL THEN
      v_new_late_min := EXTRACT(EPOCH FROM (p_punch_in_time - v_sched_start))::INTEGER / 60;
      v_new_status := 'late';
    END IF;
  END IF;

  -- 3. UPSERT سجل الحضور
  INSERT INTO hr_attendance_days (
    employee_id, shift_date, work_date,
    punch_in_time, punch_out_time,
    status, checkout_status,
    late_minutes, early_leave_minutes, overtime_minutes,
    effective_hours, day_value,
    notes, review_status, is_manually_locked
  ) VALUES (
    p_employee_id, p_shift_date, p_shift_date,
    p_punch_in_time, p_punch_out_time,
    v_new_status, v_new_co_status,
    v_new_late_min, v_new_early_min, v_new_ot_min,
    v_new_eff_hours,
    CASE v_new_status
      WHEN 'half_day' THEN 0.5
      WHEN 'absent_unauthorized' THEN 0
      WHEN 'absent_authorized' THEN 0
      ELSE 1.0
    END,
    p_notes, 'reviewed', true
  )
  ON CONFLICT (employee_id, shift_date)
  DO UPDATE SET
    punch_in_time       = EXCLUDED.punch_in_time,
    punch_out_time      = EXCLUDED.punch_out_time,
    status              = EXCLUDED.status,
    checkout_status     = EXCLUDED.checkout_status,
    late_minutes        = EXCLUDED.late_minutes,
    early_leave_minutes = EXCLUDED.early_leave_minutes,
    overtime_minutes    = EXCLUDED.overtime_minutes,
    effective_hours     = EXCLUDED.effective_hours,
    day_value           = EXCLUDED.day_value,
    notes               = EXCLUDED.notes,
    review_status       = 'reviewed',
    is_manually_locked  = true,
    reviewed_by         = COALESCE(p_user_id, auth.uid()),
    reviewed_at         = now(),
    updated_at          = now()
  RETURNING id INTO v_day_id;

  -- 3.5. تسوية الإجازة إن وجدت قبل الجزاءات
  PERFORM settle_attendance_day_against_leave(v_day_id, true);

  -- 4. إعادة معالجة الجزاءات عبر الـ helper المركزية
  SELECT reprocess_attendance_day_penalties(v_day_id)
  INTO v_penalties_count;

  RETURN jsonb_build_object(
    'success',           true,
    'attendance_day_id', v_day_id,
    'status',            v_new_status,
    'checkout_status',   v_new_co_status,
    'late_minutes',      v_new_late_min,
    'early_leave_minutes', v_new_early_min,
    'overtime_minutes',  v_new_ot_min,
    'effective_hours',   v_new_eff_hours,
    'penalties_applied', v_penalties_count,
    'message',           format('تم تحديث الحضور إدارياً وتم قفل اليوم — %s جزاء/ات أُعيد حسابه', v_penalties_count)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION upsert_attendance_and_reprocess(UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ, hr_attendance_status, TEXT, UUID) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 3) Update record_attendance_gps_v2 to block on manual lock
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION record_attendance_gps_v2(
  p_latitude    NUMERIC,
  p_longitude   NUMERIC,
  p_gps_accuracy NUMERIC,
  p_log_type    TEXT,
  p_event_time  TIMESTAMPTZ DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee          hr_employees%ROWTYPE;
  v_event_time        TIMESTAMPTZ := COALESCE(p_event_time, now());
  v_shift_date        DATE        := (COALESCE(p_event_time, now()) AT TIME ZONE 'Africa/Cairo')::date;
  v_day               hr_attendance_days%ROWTYPE;
  v_day_exists        BOOLEAN := false;
  v_ctx               JSONB;
  v_location_id       UUID;
  v_location_name     TEXT;
  v_late_grace        INTEGER := 15;
  v_work_start        TIME    := '08:00';
  v_work_end          TIME    := '17:00';
  v_scheduled_start   TIMESTAMPTZ;
  v_scheduled_end     TIMESTAMPTZ;
  v_late_minutes      INTEGER := 0;
  v_early_minutes     INTEGER := 0;
  v_overtime_minutes  INTEGER := 0;
  v_effective_hours   NUMERIC(5,2) := NULL;
  v_checkout_status   hr_checkout_status := NULL;
  v_attendance_status hr_attendance_status := 'present';
  v_day_id            UUID;
  v_log_id            UUID;
  v_tracking_status   TEXT := 'idle';
  v_penalties_count   INTEGER := 0;
  v_accuracy_threshold NUMERIC;
  v_location_threshold NUMERIC;
  v_default_threshold  NUMERIC := 100;
BEGIN
  IF p_log_type NOT IN ('check_in', 'check_out') THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_LOG_TYPE', 'error', 'نوع الحركة غير مدعوم');
  END IF;

  SELECT * INTO v_employee
  FROM hr_employees
  WHERE user_id = auth.uid() AND status = 'active';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_EMPLOYEE', 'error', 'حسابك غير مرتبط بموظف نشط');
  END IF;

  IF v_event_time > now() + interval '5 minutes' THEN
    RETURN jsonb_build_object('success', false, 'code', 'FUTURE_TIME', 'error', 'لا يمكن تسجيل حدث في المستقبل');
  END IF;

  IF v_event_time < now() - interval '24 hours' THEN
    RETURN jsonb_build_object('success', false, 'code', 'TOO_OLD', 'error', 'الحدث أقدم من المسموح به');
  END IF;

  -- ★ Check for manual lock
  SELECT * INTO v_day
  FROM hr_attendance_days
  WHERE employee_id = v_employee.id AND shift_date = v_shift_date;

  v_day_exists := FOUND;

  IF v_day_exists AND COALESCE(v_day.is_manually_locked, false) = true THEN
    RETURN jsonb_build_object('success', false, 'code', 'MANUALLY_LOCKED', 'error', 'هذا اليوم مقفل إدارياً ولا يمكن تعديله آلياً');
  END IF;

  v_ctx := resolve_employee_attendance_location_context(v_employee.id, p_latitude, p_longitude, p_log_type);

  IF COALESCE((v_ctx->>'valid')::BOOLEAN, false) = false THEN
    RETURN jsonb_build_object(
      'success',           false,
      'code',              v_ctx->>'code',
      'error',             v_ctx->>'error',
      'nearest_location',  v_ctx->>'location_name',
      'distance_meters',   NULLIF(v_ctx->>'distance_meters', '')::NUMERIC
    );
  END IF;

  v_location_id   := NULLIF(v_ctx->>'location_id', '')::UUID;
  v_location_name := v_ctx->>'location_name';

  SELECT COALESCE(value::NUMERIC, 100)
  INTO v_default_threshold
  FROM company_settings
  WHERE key = 'hr.default_gps_accuracy_threshold_meters';

  IF v_location_id IS NOT NULL THEN
    SELECT gps_accuracy_threshold
    INTO v_location_threshold
    FROM hr_work_locations
    WHERE id = v_location_id;
  END IF;

  v_accuracy_threshold := COALESCE(v_location_threshold, v_default_threshold, 100);

  IF COALESCE(p_gps_accuracy, 0) > v_accuracy_threshold THEN
    RETURN jsonb_build_object(
      'success',           false,
      'code',              'LOW_GPS_ACCURACY',
      'error',             format('دقة GPS غير كافية. الدقة الحالية ±%s متر والمطلوب ±%s متر أو أفضل', round(p_gps_accuracy), round(v_accuracy_threshold)),
      'required_accuracy', v_accuracy_threshold,
      'actual_accuracy',   p_gps_accuracy,
      'location_name',     v_location_name
    );
  END IF;

  SELECT COALESCE(value::INTEGER, 15) INTO v_late_grace
  FROM company_settings WHERE key = 'hr.late_grace_minutes';

  SELECT COALESCE(value, '08:00')::TIME INTO v_work_start
  FROM company_settings WHERE key = 'hr.work_start_time';

  SELECT COALESCE(value, '17:00')::TIME INTO v_work_end
  FROM company_settings WHERE key = 'hr.work_end_time';

  IF p_log_type = 'check_in' THEN
    IF v_day_exists AND v_day.punch_in_time IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'ALREADY_CHECKED_IN', 'error', 'لقد سجلت حضورك بالفعل اليوم');
    END IF;

    v_scheduled_start   := (v_shift_date::TEXT || ' ' || v_work_start::TEXT)::TIMESTAMP AT TIME ZONE 'Africa/Cairo';
    v_late_minutes      := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (v_event_time - v_scheduled_start)) / 60)::INTEGER - v_late_grace);
    IF v_day_exists AND v_day.status = 'on_leave' THEN
      v_attendance_status := 'on_leave';
    ELSE
      v_attendance_status := CASE WHEN v_late_minutes > 0 THEN 'late' ELSE 'present' END;
    END IF;
    v_tracking_status   := 'active';

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
      punch_in_time          = EXCLUDED.punch_in_time,
      work_date              = EXCLUDED.work_date,
      location_in_id         = EXCLUDED.location_in_id,
      gps_accuracy_in        = EXCLUDED.gps_accuracy_in,
      status                 = EXCLUDED.status,
      late_minutes           = EXCLUDED.late_minutes,
      review_status          = CASE
        WHEN hr_attendance_days.review_status = 'reviewed' THEN 'reviewed'::hr_review_status
        ELSE 'ok'::hr_review_status
      END,
      tracking_started_at    = COALESCE(hr_attendance_days.tracking_started_at, EXCLUDED.tracking_started_at),
      last_tracking_ping_at  = EXCLUDED.last_tracking_ping_at,
      last_tracking_lat      = EXCLUDED.last_tracking_lat,
      last_tracking_lng      = EXCLUDED.last_tracking_lng,
      last_tracking_accuracy = EXCLUDED.last_tracking_accuracy,
      tracking_status        = 'active',
      tracking_ping_count    = GREATEST(hr_attendance_days.tracking_ping_count, 1),
      updated_at             = now()
    RETURNING id INTO v_day_id;

  ELSE
    IF NOT v_day_exists OR v_day.punch_in_time IS NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'NOT_CHECKED_IN', 'error', 'يجب تسجيل الحضور أولاً');
    END IF;

    IF v_day.punch_out_time IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'ALREADY_CHECKED_OUT', 'error', 'لقد سجلت انصرافك بالفعل اليوم');
    END IF;

    v_scheduled_end    := (v_shift_date::TEXT || ' ' || v_work_end::TEXT)::TIMESTAMP AT TIME ZONE 'Africa/Cairo';
    v_early_minutes    := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (v_scheduled_end - v_event_time)) / 60)::INTEGER);
    v_overtime_minutes := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (v_event_time - v_scheduled_end)) / 60)::INTEGER);
    v_effective_hours  := ROUND((EXTRACT(EPOCH FROM (v_event_time - v_day.punch_in_time)) / 3600)::NUMERIC, 2);

    IF v_overtime_minutes > 0 THEN
      v_checkout_status := 'overtime';
    ELSIF v_early_minutes > 0 THEN
      IF EXISTS (
        SELECT 1 FROM hr_leave_requests
        WHERE employee_id = v_employee.id
          AND start_date <= v_shift_date
          AND end_date   >= v_shift_date
          AND status = 'approved'
      )
      OR EXISTS (
        SELECT 1 FROM hr_permission_requests
        WHERE employee_id   = v_employee.id
          AND permission_date = v_shift_date
          AND status = 'approved'
      )
      THEN
        v_checkout_status := 'early_authorized';
      ELSE
        v_checkout_status := 'early_unauthorized';
      END IF;
    ELSE
      v_checkout_status := 'on_time';
    END IF;

    v_tracking_status := 'ended';

    UPDATE hr_attendance_days
    SET
      punch_out_time         = v_event_time,
      location_out_id        = v_location_id,
      gps_accuracy_out       = LEAST(COALESCE(p_gps_accuracy, 0), 999999.99),
      checkout_status        = v_checkout_status,
      early_leave_minutes    = v_early_minutes,
      overtime_minutes       = v_overtime_minutes,
      effective_hours        = v_effective_hours,
      tracking_ended_at      = v_event_time,
      tracking_status        = 'ended',
      last_tracking_ping_at  = v_event_time,
      last_tracking_lat      = p_latitude,
      last_tracking_lng      = p_longitude,
      last_tracking_accuracy = LEAST(COALESCE(p_gps_accuracy, 0), 999999.99),
      updated_at             = now()
    WHERE id = v_day.id
    RETURNING id INTO v_day_id;

    -- Leave settlement for full day work
    PERFORM settle_attendance_day_against_leave(v_day_id);

    SELECT reprocess_attendance_day_penalties(v_day_id)
    INTO v_penalties_count;

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
    'success',           true,
    'action',            p_log_type,
    'attendance_day_id', v_day_id,
    'log_id',            v_log_id,
    'location_name',     v_location_name,
    'location_id',       v_location_id,
    'shift_date',        v_shift_date,
    'event_time',        v_event_time,
    'tracking_status',   v_tracking_status,
    'penalties_applied', CASE WHEN p_log_type = 'check_out' THEN v_penalties_count ELSE NULL END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION record_attendance_gps_v2(NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 4) Update scan_attendance_daily_review_alerts to ignore locked
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION scan_attendance_daily_review_alerts()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_open_day_alerts INTEGER := 0;
  v_auto_resolved INTEGER := 0;
  v_work_end TIME := '17:00';
  v_delay_minutes INTEGER := 120;
  v_cutoff TIMESTAMPTZ;
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::date;
  r RECORD;
BEGIN
  SELECT COALESCE(value, '17:00')::TIME
  INTO v_work_end
  FROM company_settings
  WHERE key = 'hr.work_end_time';

  SELECT COALESCE(value::INTEGER, 120)
  INTO v_delay_minutes
  FROM company_settings
  WHERE key = 'hr.open_day_review_delay_minutes';

  FOR r IN
    SELECT d.id, d.employee_id, d.shift_date, d.punch_in_time, d.review_status
    FROM hr_attendance_days d
    WHERE d.punch_in_time IS NOT NULL
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
      AND (
        d.shift_date < v_today
        OR (
          d.shift_date = v_today
          AND now() > (
            (v_today::TEXT || ' ' || v_work_end::TEXT)::TIMESTAMP
            AT TIME ZONE 'Africa/Cairo'
          ) + make_interval(mins => v_delay_minutes)
        )
      )
      AND NOT EXISTS (
        SELECT 1
        FROM hr_attendance_alerts a_prev
        WHERE a_prev.attendance_day_id = d.id
          AND a_prev.alert_type = 'open_day_unclosed'
          AND a_prev.status IN ('resolved', 'dismissed')
      )
  LOOP
    v_open_day_alerts := v_open_day_alerts + 1;

    IF r.review_status <> 'reviewed' THEN
      UPDATE hr_attendance_days
      SET review_status = 'needs_review', updated_at = now()
      WHERE id = r.id
        AND review_status <> 'reviewed';
    END IF;

    PERFORM upsert_attendance_alert(
      r.employee_id,
      r.id,
      'open_day_unclosed',
      'high',
      'يوم حضور غير مغلق',
      format('الموظف سجل حضوره يوم %s ولم يسجل انصرافه حتى الآن', r.shift_date),
      jsonb_build_object(
        'shift_date', r.shift_date,
        'punch_in_time', r.punch_in_time
      )
    );
  END LOOP;

  UPDATE hr_attendance_alerts a
  SET
    status = 'resolved',
    resolved_at = now(),
    resolution_note = 'تم إغلاق اليوم يدويًا — أُغلق التنبيه تلقائيًا',
    updated_at = now()
  FROM hr_attendance_days d
  WHERE a.alert_type = 'open_day_unclosed'
    AND a.status = 'open'
    AND a.attendance_day_id = d.id
    AND d.punch_out_time IS NOT NULL;

  GET DIAGNOSTICS v_auto_resolved = ROW_COUNT;

  RETURN jsonb_build_object(
    'success', true,
    'open_day_alerts_raised', v_open_day_alerts,
    'open_day_alerts_auto_resolved', v_auto_resolved
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 5) Refactor check_payroll_attendance_clearance and get_attendance_review_summary
-- ─────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS check_payroll_attendance_clearance(DATE, DATE);

CREATE OR REPLACE FUNCTION check_payroll_attendance_clearance(
  p_date_from DATE,
  p_date_to DATE,
  p_branch_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_unclosed_days INTEGER := 0;
  v_blockers JSONB := '[]'::jsonb;
BEGIN
  -- ★ Migration 1: The ONLY blocker is a true financially unresolved day
  -- (e.g. checked in but never checked out and not auto-resolved)
  SELECT COUNT(*)
  INTO v_unclosed_days
  FROM hr_attendance_days d
  JOIN hr_employees e ON e.id = d.employee_id
  WHERE d.shift_date BETWEEN p_date_from AND p_date_to
    AND d.punch_in_time IS NOT NULL
    AND d.punch_out_time IS NULL
    AND (p_branch_id IS NULL OR e.branch_id = p_branch_id);

  IF v_unclosed_days > 0 THEN
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object('type', 'unclosed_days', 'count', v_unclosed_days,
        'message', format('يوجد %s يوم غير محسوم مالياً (حضور بدون انصراف)', v_unclosed_days))
    );
  END IF;

  RETURN jsonb_build_object(
    'cleared', jsonb_array_length(v_blockers) = 0,
    'blockers', v_blockers
  );
END;
$$;

GRANT EXECUTE ON FUNCTION check_payroll_attendance_clearance(DATE, DATE, UUID) TO authenticated;

DROP FUNCTION IF EXISTS get_attendance_review_summary(DATE, DATE);

CREATE OR REPLACE FUNCTION get_attendance_review_summary(
  p_date_from DATE,
  p_date_to   DATE,
  p_branch_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_open_alerts         INTEGER := 0;
  v_unresolved_days     INTEGER := 0;
  v_permission_no_return INTEGER := 0;
  v_auto_checkout_days  INTEGER := 0;
  v_tracking_gap_days   INTEGER := 0;
  v_open_day_unclosed   INTEGER := 0;
  v_unclosed_days       INTEGER := 0;
BEGIN
  IF NOT check_permission(auth.uid(), 'hr.payroll.read')
     AND NOT check_permission(auth.uid(), 'hr.payroll.approve')
     AND NOT check_permission(auth.uid(), 'hr.attendance.read') THEN
    RAISE EXCEPTION 'غير مسموح بعرض ملخص مراجعة الحضور';
  END IF;

  SELECT COUNT(*) INTO v_open_alerts
  FROM hr_attendance_alerts a
  JOIN hr_employees e ON e.id = a.employee_id
  WHERE a.status = 'open'
    AND (p_branch_id IS NULL OR e.branch_id = p_branch_id)
    AND EXISTS (
      SELECT 1 FROM hr_attendance_days d
      WHERE d.id = a.attendance_day_id
        AND d.shift_date BETWEEN p_date_from AND p_date_to
    );

  SELECT COUNT(*) INTO v_unresolved_days
  FROM hr_attendance_days d
  JOIN hr_employees e ON e.id = d.employee_id
  WHERE d.shift_date BETWEEN p_date_from AND p_date_to
    AND d.review_status = 'needs_review'
    AND (p_branch_id IS NULL OR e.branch_id = p_branch_id);

  SELECT COUNT(*) INTO v_permission_no_return
  FROM hr_attendance_alerts a
  JOIN hr_employees e ON e.id = a.employee_id
  WHERE a.status = 'open'
    AND a.alert_type = 'permission_no_return'
    AND (p_branch_id IS NULL OR e.branch_id = p_branch_id)
    AND EXISTS (
      SELECT 1 FROM hr_attendance_days d
      WHERE d.id = a.attendance_day_id
        AND d.shift_date BETWEEN p_date_from AND p_date_to
    );

  SELECT COUNT(*) INTO v_auto_checkout_days
  FROM hr_attendance_days d
  JOIN hr_employees e ON e.id = d.employee_id
  WHERE d.shift_date BETWEEN p_date_from AND p_date_to
    AND d.is_auto_checkout = true
    AND (p_branch_id IS NULL OR e.branch_id = p_branch_id);

  SELECT COUNT(DISTINCT a.attendance_day_id) INTO v_tracking_gap_days
  FROM hr_attendance_alerts a
  JOIN hr_employees e ON e.id = a.employee_id
  WHERE a.status = 'open'
    AND a.alert_type IN ('tracking_gap', 'outside_allowed_zone')
    AND (p_branch_id IS NULL OR e.branch_id = p_branch_id)
    AND EXISTS (
      SELECT 1 FROM hr_attendance_days d
      WHERE d.id = a.attendance_day_id
        AND d.shift_date BETWEEN p_date_from AND p_date_to
    );

  SELECT COUNT(*) INTO v_open_day_unclosed
  FROM hr_attendance_alerts a
  JOIN hr_employees e ON e.id = a.employee_id
  WHERE a.status = 'open'
    AND a.alert_type = 'open_day_unclosed'
    AND (p_branch_id IS NULL OR e.branch_id = p_branch_id)
    AND EXISTS (
      SELECT 1 FROM hr_attendance_days d
      WHERE d.id = a.attendance_day_id
        AND d.shift_date BETWEEN p_date_from AND p_date_to
    );

  -- ★ The true blocker count
  SELECT COUNT(*) INTO v_unclosed_days
  FROM hr_attendance_days d
  JOIN hr_employees e ON e.id = d.employee_id
  WHERE d.shift_date BETWEEN p_date_from AND p_date_to
    AND d.punch_in_time IS NOT NULL
    AND d.punch_out_time IS NULL
    AND (p_branch_id IS NULL OR e.branch_id = p_branch_id);

  RETURN jsonb_build_object(
    'open_alerts',           v_open_alerts,
    'unresolved_days',       v_unresolved_days,
    'permission_no_return',  v_permission_no_return,
    'auto_checkout_days',    v_auto_checkout_days,
    'tracking_gap_days',     v_tracking_gap_days,
    'open_day_unclosed',     v_open_day_unclosed,
    'unclosed_days',         v_unclosed_days,
    -- ★ Migration 1: blocking items only reflect true financial unclosed days
    'total_blocking_items', v_unclosed_days
  );
END;
$$;
