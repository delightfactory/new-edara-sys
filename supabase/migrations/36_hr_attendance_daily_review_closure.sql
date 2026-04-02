-- ═══════════════════════════════════════════════════════════════
-- 36_hr_attendance_daily_review_closure.sql
-- HR Attendance — Wave C: Daily Review & Open Day Detection
--
-- Additive & non-destructive. Safe to re-run (idempotent).
--
-- Changes:
--   1. Expand alert_type CHECK to include 'open_day_unclosed'
--   2. Add hr.open_day_review_delay_minutes setting
--   3. Create scan_attendance_daily_review_alerts() function
--   4. Create run_attendance_operational_scan() wrapper
--   5. Update get_attendance_review_summary() with open_day_unclosed count
--   6. Update pg_cron job to use wrapper
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1) توسيع CHECK constraint لـ alert_type ← open_day_unclosed
-- ─────────────────────────────────────────────────────────────

ALTER TABLE hr_attendance_alerts
  DROP CONSTRAINT IF EXISTS hr_attendance_alerts_alert_type_check;

ALTER TABLE hr_attendance_alerts
  ADD CONSTRAINT hr_attendance_alerts_alert_type_check
  CHECK (alert_type IN (
    'tracking_gap',
    'outside_allowed_zone',
    'permission_no_return',
    'auto_checkout',
    'manual_correction',
    'missing_day',
    'open_day_unclosed'
  ));

-- ─────────────────────────────────────────────────────────────
-- 2) إعداد عتبة مراجعة اليوم المفتوح (بالدقائق بعد نهاية الدوام)
-- ─────────────────────────────────────────────────────────────

INSERT INTO company_settings (key, value, description)
VALUES (
  'hr.open_day_review_delay_minutes',
  '120',
  'عدد الدقائق بعد نهاية الدوام الرسمي التي يُعتبر بعدها اليوم المفتوح بحاجة إلى مراجعة (افتراضي: 120 = ساعتين)'
)
ON CONFLICT (key) DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- 3) دالة فحص المراجعة اليومية — مستقلة عن tracking
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
  -- جلب نهاية الدوام الرسمي
  SELECT COALESCE(value, '17:00')::TIME
  INTO v_work_end
  FROM company_settings
  WHERE key = 'hr.work_end_time';

  -- جلب عتبة المراجعة
  SELECT COALESCE(value::INTEGER, 120)
  INTO v_delay_minutes
  FROM company_settings
  WHERE key = 'hr.open_day_review_delay_minutes';

  -- ════════════════════════════════════════════════════════
  -- الجزء 1: كشف الأيام غير المغلقة التي تجاوزت العتبة
  -- ════════════════════════════════════════════════════════
  --
  -- الشرط:
  --   - punch_in_time موجود
  --   - punch_out_time فارغ
  --   - تاريخ اليوم قبل اليوم الحالي (أيام سابقة)
  --     أو اليوم الحالي ولكن تجاوز (work_end + delay)
  --   - لا يوجد تنبيه مفتوح من النوع نفسه (يُدار بـ upsert)
  --
  -- لا نكتب punch_out_time ← ليس auto-checkout
  -- لا نغيّر is_auto_checkout

  FOR r IN
    SELECT d.id, d.employee_id, d.shift_date, d.punch_in_time, d.review_status
    FROM hr_attendance_days d
    WHERE d.punch_in_time IS NOT NULL
      AND d.punch_out_time IS NULL
      AND (
        -- أيام سابقة: مؤكد تجاوزت العتبة
        d.shift_date < v_today
        OR (
          -- اليوم الحالي: تجاوز (نهاية الدوام + delay)
          d.shift_date = v_today
          AND now() > (
            (v_today::TEXT || ' ' || v_work_end::TEXT)::TIMESTAMP
            AT TIME ZONE 'Africa/Cairo'
          ) + make_interval(mins => v_delay_minutes)
        )
      )
      -- ★ Suppression: تخطّ اليوم إذا كان قرار إداري سابق (resolved أو dismissed)
      -- يجب أن يكون القرار الإداري durable ولا يُكسر بكل scan جديدة
      AND NOT EXISTS (
        SELECT 1
        FROM hr_attendance_alerts a_prev
        WHERE a_prev.attendance_day_id = d.id
          AND a_prev.alert_type = 'open_day_unclosed'
          AND a_prev.status IN ('resolved', 'dismissed')
      )
  LOOP
    v_open_day_alerts := v_open_day_alerts + 1;

    -- تحديث review_status → needs_review (لا نكتب reviewed)
    IF r.review_status <> 'reviewed' THEN
      UPDATE hr_attendance_days
      SET review_status = 'needs_review', updated_at = now()
      WHERE id = r.id
        AND review_status <> 'reviewed';
    END IF;

    -- رفع تنبيه open_day_unclosed (upsert يمنع التكرار للتنبيهات المفتوحة)
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

  -- ════════════════════════════════════════════════════════
  -- الجزء 2: إغلاق تلقائي للتنبيهات التي أُصلح يومها
  -- ════════════════════════════════════════════════════════
  --
  -- إذا أضافت الإدارة punch_out_time يدويًا → التنبيه المفتوح
  -- يجب أن يُغلق تلقائيًا حتى لا يبقى مضللاً

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
-- 4) دالة wrapper تشغيلية تستدعي كل الفحوصات
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION run_attendance_operational_scan()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tracking JSONB;
  v_daily JSONB;
BEGIN
  -- فحص التتبع (tracking gaps + permissions)
  v_tracking := scan_attendance_tracking_alerts();

  -- فحص المراجعة اليومية (أيام غير مغلقة)
  v_daily := scan_attendance_daily_review_alerts();

  RETURN jsonb_build_object(
    'success', true,
    'tracking', v_tracking,
    'daily_review', v_daily
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 5) تحديث get_attendance_review_summary — إضافة open_day_unclosed
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_attendance_review_summary(
  p_date_from DATE,
  p_date_to DATE
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_open_alerts INTEGER := 0;
  v_unresolved_days INTEGER := 0;
  v_permission_no_return INTEGER := 0;
  v_auto_checkout_days INTEGER := 0;
  v_tracking_gap_days INTEGER := 0;
  v_open_day_unclosed INTEGER := 0;
BEGIN
  IF NOT check_permission(auth.uid(), 'hr.payroll.read')
     AND NOT check_permission(auth.uid(), 'hr.payroll.approve')
     AND NOT check_permission(auth.uid(), 'hr.attendance.read') THEN
    RAISE EXCEPTION 'غير مسموح بعرض ملخص مراجعة الحضور';
  END IF;

  SELECT COUNT(*)
  INTO v_open_alerts
  FROM hr_attendance_alerts a
  WHERE a.status = 'open'
    AND EXISTS (
      SELECT 1
      FROM hr_attendance_days d
      WHERE d.id = a.attendance_day_id
        AND d.shift_date BETWEEN p_date_from AND p_date_to
    );

  SELECT COUNT(*)
  INTO v_unresolved_days
  FROM hr_attendance_days
  WHERE shift_date BETWEEN p_date_from AND p_date_to
    AND review_status = 'needs_review';

  SELECT COUNT(*)
  INTO v_permission_no_return
  FROM hr_attendance_alerts a
  WHERE a.status = 'open'
    AND a.alert_type = 'permission_no_return'
    AND EXISTS (
      SELECT 1
      FROM hr_attendance_days d
      WHERE d.id = a.attendance_day_id
        AND d.shift_date BETWEEN p_date_from AND p_date_to
    );

  SELECT COUNT(*)
  INTO v_auto_checkout_days
  FROM hr_attendance_days
  WHERE shift_date BETWEEN p_date_from AND p_date_to
    AND is_auto_checkout = true;

  SELECT COUNT(DISTINCT attendance_day_id)
  INTO v_tracking_gap_days
  FROM hr_attendance_alerts a
  WHERE a.status = 'open'
    AND a.alert_type IN ('tracking_gap', 'outside_allowed_zone')
    AND EXISTS (
      SELECT 1
      FROM hr_attendance_days d
      WHERE d.id = a.attendance_day_id
        AND d.shift_date BETWEEN p_date_from AND p_date_to
    );

  -- ★ عدد الأيام غير المغلقة بتنبيه مفتوح
  SELECT COUNT(*)
  INTO v_open_day_unclosed
  FROM hr_attendance_alerts a
  WHERE a.status = 'open'
    AND a.alert_type = 'open_day_unclosed'
    AND EXISTS (
      SELECT 1
      FROM hr_attendance_days d
      WHERE d.id = a.attendance_day_id
        AND d.shift_date BETWEEN p_date_from AND p_date_to
    );

  RETURN jsonb_build_object(
    'open_alerts', v_open_alerts,
    'unresolved_days', v_unresolved_days,
    'permission_no_return', v_permission_no_return,
    'auto_checkout_days', v_auto_checkout_days,
    'tracking_gap_days', v_tracking_gap_days,
    'open_day_unclosed', v_open_day_unclosed
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 6) تحديث pg_cron job ← wrapper بدل الدالة المفردة
-- ─────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- حذف الـ job القديم
    BEGIN
      PERFORM cron.unschedule('scan-attendance-alerts');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    -- جدولة الـ wrapper الجديد
    PERFORM cron.schedule(
      'scan-attendance-alerts',
      '*/15 * * * *',
      'SELECT public.run_attendance_operational_scan();'
    );
    RAISE NOTICE '[EDARA] ✅ تم تحديث جدولة فحص الحضور التشغيلي (wrapper)';
  ELSE
    RAISE NOTICE '[EDARA] ⚠️ pg_cron غير مفعل — يُرجى جدولة يدوياً:';
    RAISE NOTICE 'SELECT cron.schedule(''scan-attendance-alerts'', ''*/15 * * * *'', ''SELECT public.run_attendance_operational_scan();'');';
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════
-- END OF MIGRATION 36
-- ═══════════════════════════════════════════════════════════════
