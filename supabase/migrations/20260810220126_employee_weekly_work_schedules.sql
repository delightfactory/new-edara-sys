-- ============================================================================
-- Versioned per-employee weekly work schedules
--
-- Safety guarantees:
--   * no schedule version => the employee keeps the existing company schedule
--   * every change starts on an explicit future date; older dates keep history
--   * attendance stores an immutable schedule snapshot
--   * mature GPS/manual calculation semantics are preserved; only their
--     schedule source changes from company-wide hours to the employee resolver
--   * overnight shifts are intentionally rejected in this phase
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE TABLE public.hr_employee_work_schedules (
  employee_id          UUID NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  effective_from       DATE NOT NULL,
  day_of_week          public.hr_day_of_week NOT NULL,
  uses_company_defaults BOOLEAN NOT NULL DEFAULT false,
  is_working_day       BOOLEAN NOT NULL DEFAULT true,
  start_time           TIME,
  end_time             TIME,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (employee_id, effective_from, day_of_week),
  CONSTRAINT hr_employee_work_schedules_times_check CHECK (
    (uses_company_defaults = true AND is_working_day = false AND start_time IS NULL AND end_time IS NULL)
    OR
    (uses_company_defaults = false AND is_working_day = false AND start_time IS NULL AND end_time IS NULL)
    OR
    (uses_company_defaults = false AND is_working_day = true
      AND start_time IS NOT NULL AND end_time IS NOT NULL AND end_time > start_time)
  )
);

CREATE TRIGGER trg_hr_employee_work_schedules_updated_at
  BEFORE UPDATE ON public.hr_employee_work_schedules
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.hr_employee_work_schedules ENABLE ROW LEVEL SECURITY;

CREATE POLICY hr_employee_work_schedules_read
  ON public.hr_employee_work_schedules
  FOR SELECT
  TO authenticated
  USING (
    employee_id IN (
      SELECT e.id
      FROM public.hr_employees e
      WHERE e.user_id = (SELECT auth.uid())
    )
    OR (SELECT public.check_permission((SELECT auth.uid()), 'hr.employees.read'))
  );

REVOKE ALL ON public.hr_employee_work_schedules
  FROM anon, authenticated, service_role;
GRANT SELECT ON public.hr_employee_work_schedules TO authenticated, service_role;


-- Saves one complete future version. NULL means "follow company defaults" from
-- that date; history is never deleted.
CREATE OR REPLACE FUNCTION public.set_employee_weekly_schedule(
  p_employee_id UUID,
  p_schedule JSONB,
  p_effective_from DATE DEFAULT ((now() AT TIME ZONE 'Africa/Cairo')::DATE + 1)
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item JSONB;
  v_day public.hr_day_of_week;
  v_working BOOLEAN;
  v_start TIME;
  v_end TIME;
  v_tomorrow DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE + 1;
  v_refresh_from DATE;
BEGIN
  IF NOT COALESCE(public.check_permission((SELECT auth.uid()), 'hr.employees.create'), false) THEN
    RAISE EXCEPTION 'لا تملك صلاحية تعديل جدول عمل الموظف';
  END IF;

  IF p_effective_from IS NULL OR p_effective_from < v_tomorrow THEN
    RAISE EXCEPTION 'تاريخ بدء الجدول يجب أن يكون غداً أو بعده حتى لا تتغير أيام حضور سابقة أو مفتوحة';
  END IF;

  -- Serializes two administrators saving the same employee concurrently.
  PERFORM 1
  FROM public.hr_employees
  WHERE id = p_employee_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الموظف غير موجود';
  END IF;

  -- The editor intentionally supports one pending change per employee. Replacing
  -- it avoids hidden intermediate versions that the minimal UI cannot manage.
  SELECT MIN(s.effective_from) INTO v_refresh_from
  FROM public.hr_employee_work_schedules s
  WHERE s.employee_id = p_employee_id
    AND s.effective_from >= v_tomorrow;

  v_refresh_from := LEAST(COALESCE(v_refresh_from, p_effective_from), p_effective_from);

  DELETE FROM public.hr_employee_work_schedules
  WHERE employee_id = p_employee_id
    AND effective_from >= v_tomorrow;

  -- NULL/[] creates a dated return-to-company marker instead of deleting
  -- historical custom schedules.
  IF p_schedule IS NULL OR p_schedule = 'null'::JSONB OR p_schedule = '[]'::JSONB THEN
    INSERT INTO public.hr_employee_work_schedules (
      employee_id, effective_from, day_of_week,
      uses_company_defaults, is_working_day, start_time, end_time
    )
    SELECT
      p_employee_id,
      p_effective_from,
      d.day_of_week,
      true,
      false,
      NULL,
      NULL
    FROM unnest(ARRAY[
      'saturday'::public.hr_day_of_week,
      'sunday'::public.hr_day_of_week,
      'monday'::public.hr_day_of_week,
      'tuesday'::public.hr_day_of_week,
      'wednesday'::public.hr_day_of_week,
      'thursday'::public.hr_day_of_week,
      'friday'::public.hr_day_of_week
    ]) AS d(day_of_week);
    PERFORM public.refresh_future_attendance_schedule_snapshots(
      p_employee_id, v_refresh_from
    );
    RETURN;
  END IF;

  IF jsonb_typeof(p_schedule) <> 'array' OR jsonb_array_length(p_schedule) <> 7 THEN
    RAISE EXCEPTION 'يجب أن يحتوي جدول العمل الخاص على أيام الأسبوع السبعة';
  END IF;

  IF (
    SELECT COUNT(DISTINCT item->>'day_of_week')
    FROM jsonb_array_elements(p_schedule) item
  ) <> 7 THEN
    RAISE EXCEPTION 'لا يمكن تكرار يوم داخل جدول العمل';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_schedule)
  LOOP
    BEGIN
      v_day := (v_item->>'day_of_week')::public.hr_day_of_week;
    EXCEPTION WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'يوم غير صالح في جدول العمل: %', COALESCE(v_item->>'day_of_week', 'فارغ');
    END;

    v_working := COALESCE((v_item->>'is_working_day')::BOOLEAN, false);
    v_start := NULLIF(v_item->>'start_time', '')::TIME;
    v_end := NULLIF(v_item->>'end_time', '')::TIME;

    IF v_working AND (v_start IS NULL OR v_end IS NULL OR v_end <= v_start) THEN
      RAISE EXCEPTION 'وقت البداية والنهاية غير صالح ليوم %', v_day;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_schedule) item
    WHERE COALESCE((item->>'is_working_day')::BOOLEAN, false) = true
  ) THEN
    RAISE EXCEPTION 'يجب تحديد يوم عمل واحد على الأقل';
  END IF;

  INSERT INTO public.hr_employee_work_schedules (
    employee_id, effective_from, day_of_week,
    uses_company_defaults, is_working_day, start_time, end_time
  )
  SELECT
    p_employee_id,
    p_effective_from,
    (item->>'day_of_week')::public.hr_day_of_week,
    false,
    COALESCE((item->>'is_working_day')::BOOLEAN, false),
    CASE WHEN COALESCE((item->>'is_working_day')::BOOLEAN, false)
      THEN NULLIF(item->>'start_time', '')::TIME ELSE NULL END,
    CASE WHEN COALESCE((item->>'is_working_day')::BOOLEAN, false)
      THEN NULLIF(item->>'end_time', '')::TIME ELSE NULL END
  FROM jsonb_array_elements(p_schedule) item;

  PERFORM public.refresh_future_attendance_schedule_snapshots(
    p_employee_id, v_refresh_from
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_employee_weekly_schedule(UUID, JSONB, DATE)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_employee_weekly_schedule(UUID, JSONB, DATE)
  TO authenticated;


-- Central resolver. Rest days and public holidays deliberately retain the
-- existing company start/end timestamps for exceptional attendance, while
-- scheduled_minutes=0 keeps them excluded from absence and payroll workdays.
CREATE OR REPLACE FUNCTION public.get_employee_work_schedule(
  p_employee_id UUID,
  p_date DATE
) RETURNS TABLE (
  is_working_day BOOLEAN,
  scheduled_start_at TIMESTAMPTZ,
  scheduled_end_at TIMESTAMPTZ,
  scheduled_minutes INTEGER,
  schedule_source TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_day public.hr_day_of_week;
  v_row public.hr_employee_work_schedules%ROWTYPE;
  v_effective_from DATE;
  v_company_start TIME;
  v_company_end TIME;
  v_employee_off public.hr_day_of_week;
  v_company_off TEXT;
  v_is_holiday BOOLEAN := false;
  v_working BOOLEAN;
BEGIN
  IF p_employee_id IS NULL OR p_date IS NULL THEN
    RETURN QUERY SELECT false, NULL::TIMESTAMPTZ, NULL::TIMESTAMPTZ, 0, 'invalid'::TEXT;
    RETURN;
  END IF;

  SELECT COALESCE(value, '08:00')::TIME INTO v_company_start
  FROM public.company_settings WHERE key = 'hr.work_start_time';
  SELECT COALESCE(value, '17:00')::TIME INTO v_company_end
  FROM public.company_settings WHERE key = 'hr.work_end_time';
  v_company_start := COALESCE(v_company_start, '08:00'::TIME);
  v_company_end := COALESCE(v_company_end, '17:00'::TIME);

  v_day := CASE EXTRACT(DOW FROM p_date)::INTEGER
    WHEN 0 THEN 'sunday'::public.hr_day_of_week
    WHEN 1 THEN 'monday'::public.hr_day_of_week
    WHEN 2 THEN 'tuesday'::public.hr_day_of_week
    WHEN 3 THEN 'wednesday'::public.hr_day_of_week
    WHEN 4 THEN 'thursday'::public.hr_day_of_week
    WHEN 5 THEN 'friday'::public.hr_day_of_week
    ELSE 'saturday'::public.hr_day_of_week
  END;

  SELECT EXISTS (
    SELECT 1 FROM public.hr_public_holidays h WHERE h.holiday_date = p_date
  ) INTO v_is_holiday;

  IF v_is_holiday THEN
    RETURN QUERY SELECT
      false,
      (p_date + v_company_start) AT TIME ZONE 'Africa/Cairo',
      (p_date + v_company_end) AT TIME ZONE 'Africa/Cairo',
      0,
      'public_holiday'::TEXT;
    RETURN;
  END IF;

  SELECT MAX(s.effective_from) INTO v_effective_from
  FROM public.hr_employee_work_schedules s
  WHERE s.employee_id = p_employee_id AND s.effective_from <= p_date;

  IF v_effective_from IS NOT NULL THEN
    SELECT * INTO v_row
    FROM public.hr_employee_work_schedules s
    WHERE s.employee_id = p_employee_id
      AND s.effective_from = v_effective_from
      AND s.day_of_week = v_day;

    IF FOUND AND NOT v_row.uses_company_defaults THEN
      IF NOT v_row.is_working_day THEN
        RETURN QUERY SELECT
          false,
          (p_date + v_company_start) AT TIME ZONE 'Africa/Cairo',
          (p_date + v_company_end) AT TIME ZONE 'Africa/Cairo',
          0,
          'employee'::TEXT;
        RETURN;
      END IF;

      RETURN QUERY SELECT
        true,
        (p_date + v_row.start_time) AT TIME ZONE 'Africa/Cairo',
        (p_date + v_row.end_time) AT TIME ZONE 'Africa/Cairo',
        FLOOR(EXTRACT(EPOCH FROM (v_row.end_time - v_row.start_time)) / 60)::INTEGER,
        'employee'::TEXT;
      RETURN;
    END IF;
  END IF;

  SELECT e.weekly_off_day INTO v_employee_off
  FROM public.hr_employees e WHERE e.id = p_employee_id;

  IF v_employee_off IS NULL THEN
    SELECT value INTO v_company_off
    FROM public.company_settings WHERE key = 'hr.weekly_off_day';
  END IF;

  v_working := v_day::TEXT <> COALESCE(v_employee_off::TEXT, lower(v_company_off), 'friday');

  RETURN QUERY SELECT
    v_working,
    (p_date + v_company_start) AT TIME ZONE 'Africa/Cairo',
    (p_date + v_company_end) AT TIME ZONE 'Africa/Cairo',
    CASE WHEN v_working
      THEN FLOOR(EXTRACT(EPOCH FROM (v_company_end - v_company_start)) / 60)::INTEGER
      ELSE 0
    END,
    'company'::TEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.get_employee_work_schedule(UUID, DATE)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_employee_work_schedule(UUID, DATE)
  TO authenticated, service_role;


-- Returns either the latest saved version (including a pending one) or the
-- employee/company defaults. It prevents the UI from inventing hard-coded times.
CREATE OR REPLACE FUNCTION public.get_employee_weekly_schedule_for_editor(
  p_employee_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_effective_from DATE;
  v_uses_company BOOLEAN := true;
  v_company_start TIME;
  v_company_end TIME;
  v_employee_off public.hr_day_of_week;
  v_company_off TEXT;
  v_days JSONB;
BEGIN
  IF NOT (
    COALESCE(public.check_permission((SELECT auth.uid()), 'hr.employees.read'), false)
    OR COALESCE(public.check_permission((SELECT auth.uid()), 'hr.employees.create'), false)
  ) THEN
    RAISE EXCEPTION 'لا تملك صلاحية قراءة جدول عمل الموظف';
  END IF;

  IF p_employee_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.hr_employees WHERE id = p_employee_id) THEN
    RAISE EXCEPTION 'الموظف غير موجود';
  END IF;

  SELECT MAX(s.effective_from) INTO v_effective_from
  FROM public.hr_employee_work_schedules s
  WHERE s.employee_id = p_employee_id;

  IF v_effective_from IS NOT NULL THEN
    SELECT bool_and(s.uses_company_defaults) INTO v_uses_company
    FROM public.hr_employee_work_schedules s
    WHERE s.employee_id = p_employee_id AND s.effective_from = v_effective_from;
  END IF;

  IF v_effective_from IS NOT NULL AND NOT COALESCE(v_uses_company, false) THEN
    SELECT jsonb_agg(jsonb_build_object(
      'employee_id', s.employee_id,
      'effective_from', s.effective_from,
      'day_of_week', s.day_of_week,
      'is_working_day', s.is_working_day,
      'start_time', to_char(s.start_time, 'HH24:MI'),
      'end_time', to_char(s.end_time, 'HH24:MI')
    ) ORDER BY array_position(
      ARRAY['saturday','sunday','monday','tuesday','wednesday','thursday','friday'],
      s.day_of_week::TEXT
    )) INTO v_days
    FROM public.hr_employee_work_schedules s
    WHERE s.employee_id = p_employee_id AND s.effective_from = v_effective_from;
  ELSE
    SELECT COALESCE(value, '08:00')::TIME INTO v_company_start
    FROM public.company_settings WHERE key = 'hr.work_start_time';
    SELECT COALESCE(value, '17:00')::TIME INTO v_company_end
    FROM public.company_settings WHERE key = 'hr.work_end_time';
    v_company_start := COALESCE(v_company_start, '08:00'::TIME);
    v_company_end := COALESCE(v_company_end, '17:00'::TIME);

    IF p_employee_id IS NOT NULL THEN
      SELECT e.weekly_off_day INTO v_employee_off
      FROM public.hr_employees e WHERE e.id = p_employee_id;
    END IF;
    IF v_employee_off IS NULL THEN
      SELECT value INTO v_company_off
      FROM public.company_settings WHERE key = 'hr.weekly_off_day';
    END IF;

    SELECT jsonb_agg(jsonb_build_object(
      'employee_id', p_employee_id,
      'effective_from', v_effective_from,
      'day_of_week', d.day_of_week,
      'is_working_day', d.day_of_week::TEXT <>
        COALESCE(v_employee_off::TEXT, lower(v_company_off), 'friday'),
      'start_time', CASE WHEN d.day_of_week::TEXT <>
        COALESCE(v_employee_off::TEXT, lower(v_company_off), 'friday')
        THEN to_char(v_company_start, 'HH24:MI') END,
      'end_time', CASE WHEN d.day_of_week::TEXT <>
        COALESCE(v_employee_off::TEXT, lower(v_company_off), 'friday')
        THEN to_char(v_company_end, 'HH24:MI') END
    ) ORDER BY d.position) INTO v_days
    FROM unnest(ARRAY[
      'saturday'::public.hr_day_of_week,
      'sunday'::public.hr_day_of_week,
      'monday'::public.hr_day_of_week,
      'tuesday'::public.hr_day_of_week,
      'wednesday'::public.hr_day_of_week,
      'thursday'::public.hr_day_of_week,
      'friday'::public.hr_day_of_week
    ]) WITH ORDINALITY AS d(day_of_week, position);
  END IF;

  RETURN jsonb_build_object(
    'has_custom_schedule', v_effective_from IS NOT NULL AND NOT COALESCE(v_uses_company, false),
    'effective_from', v_effective_from,
    'schedule', COALESCE(v_days, '[]'::JSONB)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_employee_weekly_schedule_for_editor(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_employee_weekly_schedule_for_editor(UUID)
  TO authenticated;


CREATE OR REPLACE FUNCTION public.is_employee_work_day(
  p_employee_id UUID,
  p_date DATE
) RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_schedule RECORD;
BEGIN
  SELECT * INTO v_schedule
  FROM public.get_employee_work_schedule(p_employee_id, p_date);

  IF v_schedule.is_working_day THEN
    RETURN 'work_day';
  END IF;

  IF v_schedule.schedule_source = 'public_holiday' THEN
    RETURN 'public_holiday';
  END IF;

  RETURN 'weekly_off';
END;
$$;


ALTER TABLE public.hr_attendance_days
  ADD COLUMN IF NOT EXISTS scheduled_start_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS scheduled_end_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS scheduled_minutes INTEGER;

ALTER TABLE public.hr_attendance_days
  ADD CONSTRAINT hr_attendance_days_scheduled_minutes_check
  CHECK (scheduled_minutes IS NULL OR scheduled_minutes >= 0) NOT VALID;

-- Backfill only the three new columns. Existing attendance metrics/statuses are
-- deliberately not recalculated during migration.
WITH resolved AS (
  SELECT d.id, s.scheduled_start_at, s.scheduled_end_at, s.scheduled_minutes
  FROM public.hr_attendance_days d
  CROSS JOIN LATERAL public.get_employee_work_schedule(d.employee_id, d.shift_date) s
  WHERE d.scheduled_minutes IS NULL
)
UPDATE public.hr_attendance_days d
SET scheduled_start_at = r.scheduled_start_at,
    scheduled_end_at = r.scheduled_end_at,
    scheduled_minutes = r.scheduled_minutes
FROM resolved r
WHERE d.id = r.id;

ALTER TABLE public.hr_attendance_days
  VALIDATE CONSTRAINT hr_attendance_days_scheduled_minutes_check;


-- Snapshot only. Calculation remains inside the existing GPS/manual functions
-- so their different grace/threshold/status rules are preserved exactly.
CREATE OR REPLACE FUNCTION public.sync_attendance_day_schedule()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_schedule RECORD;
BEGIN
  IF TG_OP = 'INSERT'
     OR NEW.employee_id IS DISTINCT FROM OLD.employee_id
     OR NEW.shift_date IS DISTINCT FROM OLD.shift_date
     OR (
       -- The schedule RPC uses an all-NULL sentinel to refresh only untouched
       -- future placeholders (for example a leave row created in advance).
       NEW.scheduled_start_at IS NULL
       AND NEW.scheduled_end_at IS NULL
       AND NEW.scheduled_minutes IS NULL
       AND NEW.shift_date >= (now() AT TIME ZONE 'Africa/Cairo')::DATE + 1
       AND OLD.punch_in_time IS NULL AND OLD.punch_out_time IS NULL
       AND NEW.punch_in_time IS NULL AND NEW.punch_out_time IS NULL
       AND COALESCE(OLD.is_manually_locked, false) = false
       AND COALESCE(NEW.is_manually_locked, false) = false
     ) THEN
    SELECT * INTO v_schedule
    FROM public.get_employee_work_schedule(NEW.employee_id, NEW.shift_date);

    NEW.scheduled_start_at := v_schedule.scheduled_start_at;
    NEW.scheduled_end_at := v_schedule.scheduled_end_at;
    NEW.scheduled_minutes := v_schedule.scheduled_minutes;
  ELSE
    -- Past, started and manually locked attendance snapshots are immutable.
    NEW.scheduled_start_at := OLD.scheduled_start_at;
    NEW.scheduled_end_at := OLD.scheduled_end_at;
    NEW.scheduled_minutes := OLD.scheduled_minutes;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_attendance_day_schedule
  BEFORE INSERT OR UPDATE OF employee_id, shift_date,
    scheduled_start_at, scheduled_end_at, scheduled_minutes
  ON public.hr_attendance_days
  FOR EACH ROW EXECUTE FUNCTION public.sync_attendance_day_schedule();


-- Re-snapshot only future attendance placeholders that have never been worked,
-- manually locked or included in an approved/paid payroll. Historical and
-- operational attendance remains immutable.
CREATE OR REPLACE FUNCTION public.refresh_future_attendance_schedule_snapshots(
  p_employee_id UUID,
  p_from_date DATE
) RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  UPDATE public.hr_attendance_days d
  SET scheduled_start_at = NULL,
      scheduled_end_at = NULL,
      scheduled_minutes = NULL,
      updated_at = now()
  WHERE d.employee_id = p_employee_id
    AND d.shift_date >= GREATEST(
      p_from_date,
      (now() AT TIME ZONE 'Africa/Cairo')::DATE + 1
    )
    AND d.punch_in_time IS NULL
    AND d.punch_out_time IS NULL
    AND COALESCE(d.is_manually_locked, false) = false
    AND NOT EXISTS (
      SELECT 1
      FROM public.hr_payroll_runs pr
      JOIN public.hr_payroll_periods pp ON pp.id = pr.period_id
      JOIN public.hr_payroll_lines pl ON pl.payroll_run_id = pr.id
      WHERE pl.employee_id = d.employee_id
        AND pr.status IN ('approved', 'paid')
        AND d.shift_date BETWEEN pp.start_date AND pp.end_date
    );
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_future_attendance_schedule_snapshots(UUID, DATE)
  FROM PUBLIC, anon, authenticated, service_role;


-- Narrowly patch the three attendance writers. Their location checks, locks,
-- grace periods, five/30-minute thresholds, half-day behavior, logs, return
-- payloads and penalty calls stay byte-for-byte unchanged.
DO $$
DECLARE
  v_name TEXT;
  v_signature REGPROCEDURE;
  v_original TEXT;
  v_patched TEXT;
  v_expected_start INTEGER;
  v_start_matches INTEGER;
  v_end_matches INTEGER;
BEGIN
  FOREACH v_name IN ARRAY ARRAY[
    'record_attendance_gps',
    'record_attendance_gps_v2',
    'upsert_attendance_and_reprocess'
  ]
  LOOP
    v_signature := CASE v_name
      WHEN 'record_attendance_gps' THEN
        'public.record_attendance_gps(numeric,numeric,numeric,text,timestamp with time zone)'::regprocedure
      WHEN 'record_attendance_gps_v2' THEN
        'public.record_attendance_gps_v2(numeric,numeric,numeric,text,timestamp with time zone)'::regprocedure
      ELSE
        'public.upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,public.hr_attendance_status,text,uuid)'::regprocedure
    END;

    SELECT pg_get_functiondef(v_signature) INTO v_original;
    v_patched := v_original;

    IF v_name = 'record_attendance_gps' THEN
      v_expected_start := 1;
      SELECT COUNT(*) INTO v_start_matches FROM regexp_matches(v_original,
        'v_scheduled_start\s*:=\s*\(v_shift_date\s*\+\s*v_work_start\)\s+AT\s+TIME\s+ZONE\s+''Africa/Cairo''\s*;', 'gi');
      SELECT COUNT(*) INTO v_end_matches FROM regexp_matches(v_original,
        'v_sched_end\s*:=\s*\(v_shift_date\s*\+\s*v_work_end\)\s+AT\s+TIME\s+ZONE\s+''Africa/Cairo''\s*;', 'gi');
      v_patched := regexp_replace(v_patched,
        'v_scheduled_start\s*:=\s*\(v_shift_date\s*\+\s*v_work_start\)\s+AT\s+TIME\s+ZONE\s+''Africa/Cairo''\s*;',
        'SELECT scheduled_start_at INTO v_scheduled_start FROM public.get_employee_work_schedule(v_employee_id, v_shift_date);', 'i');
      v_patched := regexp_replace(v_patched,
        'v_sched_end\s*:=\s*\(v_shift_date\s*\+\s*v_work_end\)\s+AT\s+TIME\s+ZONE\s+''Africa/Cairo''\s*;',
        'SELECT scheduled_end_at INTO v_sched_end FROM public.get_employee_work_schedule(v_employee_id, v_shift_date);', 'i');
    ELSIF v_name = 'record_attendance_gps_v2' THEN
      v_expected_start := 1;
      SELECT COUNT(*) INTO v_start_matches FROM regexp_matches(v_original,
        'v_scheduled_start\s*:=\s*\(v_shift_date::TEXT\s*\|\|\s*''\s''\s*\|\|\s*v_work_start::TEXT\)::TIMESTAMP\s+AT\s+TIME\s+ZONE\s+''Africa/Cairo''\s*;', 'gi');
      SELECT COUNT(*) INTO v_end_matches FROM regexp_matches(v_original,
        'v_scheduled_end\s*:=\s*\(v_shift_date::TEXT\s*\|\|\s*''\s''\s*\|\|\s*v_work_end::TEXT\)::TIMESTAMP\s+AT\s+TIME\s+ZONE\s+''Africa/Cairo''\s*;', 'gi');
      v_patched := regexp_replace(v_patched,
        'v_scheduled_start\s*:=\s*\(v_shift_date::TEXT\s*\|\|\s*''\s''\s*\|\|\s*v_work_start::TEXT\)::TIMESTAMP\s+AT\s+TIME\s+ZONE\s+''Africa/Cairo''\s*;',
        'SELECT scheduled_start_at INTO v_scheduled_start FROM public.get_employee_work_schedule(v_employee.id, v_shift_date);', 'i');
      v_patched := regexp_replace(v_patched,
        'v_scheduled_end\s*:=\s*\(v_shift_date::TEXT\s*\|\|\s*''\s''\s*\|\|\s*v_work_end::TEXT\)::TIMESTAMP\s+AT\s+TIME\s+ZONE\s+''Africa/Cairo''\s*;',
        'SELECT scheduled_end_at INTO v_scheduled_end FROM public.get_employee_work_schedule(v_employee.id, v_shift_date);', 'i');
    ELSE
      v_expected_start := 2;
      SELECT COUNT(*) INTO v_start_matches FROM regexp_matches(v_original,
        'v_sched_start\s*:=\s*\(p_shift_date\s*\+\s*v_work_start\)\s+AT\s+TIME\s+ZONE\s+''Africa/Cairo''\s*;', 'gi');
      SELECT COUNT(*) INTO v_end_matches FROM regexp_matches(v_original,
        'v_sched_end\s*:=\s*\(p_shift_date\s*\+\s*v_work_end\)\s+AT\s+TIME\s+ZONE\s+''Africa/Cairo''\s*;', 'gi');
      v_patched := regexp_replace(v_patched,
        'v_sched_start\s*:=\s*\(p_shift_date\s*\+\s*v_work_start\)\s+AT\s+TIME\s+ZONE\s+''Africa/Cairo''\s*;',
        'SELECT scheduled_start_at INTO v_sched_start FROM public.get_employee_work_schedule(p_employee_id, p_shift_date);', 'gi');
      v_patched := regexp_replace(v_patched,
        'v_sched_end\s*:=\s*\(p_shift_date\s*\+\s*v_work_end\)\s+AT\s+TIME\s+ZONE\s+''Africa/Cairo''\s*;',
        'SELECT scheduled_end_at INTO v_sched_end FROM public.get_employee_work_schedule(p_employee_id, p_shift_date);', 'i');
    END IF;

    -- The exact occurrence checks make schema drift fail the whole transaction.
    IF v_start_matches <> v_expected_start OR v_end_matches <> 1 THEN
      RAISE EXCEPTION '% schedule assignment count changed (start %, end %)',
        v_name, v_start_matches, v_end_matches;
    END IF;
    IF v_patched = v_original THEN
      RAISE EXCEPTION '% schedule assignments were not replaced', v_name;
    END IF;

    EXECUTE v_patched;
  END LOOP;
END;
$$;


-- Daily absence is evaluated against each employee's own end time. Employees
-- whose shift has not ended are skipped; all existing leave/manual/payroll
-- guards remain unchanged.
CREATE OR REPLACE FUNCTION public.mark_daily_absences(
  p_target_date DATE DEFAULT CURRENT_DATE
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp public.hr_employees%ROWTYPE;
  v_schedule RECORD;
  v_is_worked BOOLEAN;
  v_has_leave BOOLEAN;
  v_is_locked BOOLEAN;
  v_in_closed_payroll BOOLEAN;
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_grace_minutes INTEGER := 120;
BEGIN
  IF p_target_date > v_today THEN
    RAISE EXCEPTION 'لا يمكن رصد الغياب لأيام في المستقبل';
  END IF;

  SELECT COALESCE(value::INTEGER, 120) INTO v_grace_minutes
  FROM public.company_settings WHERE key = 'hr.absence_run_delay_minutes';
  v_grace_minutes := COALESCE(v_grace_minutes, 120);

  FOR v_emp IN SELECT * FROM public.hr_employees WHERE status = 'active'
  LOOP
    IF (v_emp.hire_date IS NOT NULL AND v_emp.hire_date > p_target_date)
       OR (v_emp.termination_date IS NOT NULL AND v_emp.termination_date < p_target_date) THEN
      CONTINUE;
    END IF;

    SELECT * INTO v_schedule
    FROM public.get_employee_work_schedule(v_emp.id, p_target_date);

    IF NOT v_schedule.is_working_day THEN CONTINUE; END IF;
    IF p_target_date = v_today
       AND now() < v_schedule.scheduled_end_at + make_interval(mins => v_grace_minutes) THEN
      CONTINUE;
    END IF;

    SELECT EXISTS (
      SELECT 1 FROM public.hr_attendance_days d
      WHERE d.employee_id = v_emp.id AND d.shift_date = p_target_date
        AND d.status <> 'absent_unauthorized'
    ) INTO v_is_worked;

    SELECT EXISTS (
      SELECT 1 FROM public.hr_leave_requests l
      WHERE l.employee_id = v_emp.id AND l.status = 'approved'
        AND p_target_date BETWEEN l.start_date AND l.end_date
    ) INTO v_has_leave;

    SELECT EXISTS (
      SELECT 1 FROM public.hr_attendance_days d
      WHERE d.employee_id = v_emp.id AND d.shift_date = p_target_date
        AND COALESCE(d.is_manually_locked, false)
    ) INTO v_is_locked;

    SELECT EXISTS (
      SELECT 1
      FROM public.hr_payroll_runs pr
      JOIN public.hr_payroll_periods pp ON pp.id = pr.period_id
      JOIN public.hr_payroll_lines pl ON pl.payroll_run_id = pr.id
      WHERE pl.employee_id = v_emp.id
        AND pr.status IN ('approved', 'paid')
        AND p_target_date BETWEEN pp.start_date AND pp.end_date
    ) INTO v_in_closed_payroll;

    IF NOT v_is_worked AND NOT v_has_leave AND NOT v_is_locked AND NOT v_in_closed_payroll THEN
      INSERT INTO public.hr_attendance_days (
        employee_id, shift_date, work_date, status, day_value, review_status,
        scheduled_start_at, scheduled_end_at, scheduled_minutes, updated_at
      ) VALUES (
        v_emp.id, p_target_date, p_target_date, 'absent_unauthorized', 0, 'ok',
        v_schedule.scheduled_start_at, v_schedule.scheduled_end_at,
        v_schedule.scheduled_minutes, now()
      )
      ON CONFLICT (employee_id, shift_date) DO UPDATE SET
        status = 'absent_unauthorized', day_value = 0, updated_at = now()
      WHERE COALESCE(hr_attendance_days.is_manually_locked, false) = false
        AND hr_attendance_days.status NOT IN ('absent_unauthorized', 'on_leave')
        AND hr_attendance_days.source_leave_request_id IS NULL
        AND hr_attendance_days.punch_in_time IS NULL;
    END IF;
  END LOOP;
END;
$$;


-- Auto checkout remains operationally identical, but each open day has its own
-- cutoff. Metric columns remain named in UPDATE so the existing early-leave
-- notification trigger continues to fire exactly as before.
CREATE OR REPLACE FUNCTION public.run_auto_checkout(
  p_target_date DATE DEFAULT CURRENT_DATE
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_day public.hr_attendance_days%ROWTYPE;
  v_schedule RECORD;
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_grace_minutes INTEGER := 15;
  v_scheduled_end TIMESTAMPTZ;
  v_auto_checkout_time TIMESTAMPTZ;
  v_early_leave_minutes INTEGER;
  v_overtime_minutes INTEGER;
  v_effective_hours NUMERIC(5,2);
  v_checkout_status public.hr_checkout_status;
BEGIN
  IF p_target_date > v_today THEN
    RAISE EXCEPTION 'لا يمكن الإغلاق التلقائي لأيام في المستقبل';
  END IF;

  SELECT COALESCE(value::INTEGER, 15) INTO v_grace_minutes
  FROM public.company_settings WHERE key = 'hr.auto_checkout_minutes';
  v_grace_minutes := COALESCE(v_grace_minutes, 15);

  FOR v_day IN
    SELECT d.* FROM public.hr_attendance_days d
    WHERE d.shift_date = p_target_date
      AND d.punch_in_time IS NOT NULL
      AND d.punch_out_time IS NULL
      AND COALESCE(d.is_manually_locked, false) = false
      AND NOT EXISTS (
        SELECT 1 FROM public.hr_payroll_runs pr
        JOIN public.hr_payroll_periods pp ON pp.id = pr.period_id
        JOIN public.hr_payroll_lines pl ON pl.payroll_run_id = pr.id
        WHERE pl.employee_id = d.employee_id
          AND pr.status IN ('approved', 'paid')
          AND d.shift_date BETWEEN pp.start_date AND pp.end_date
      )
  LOOP
    v_scheduled_end := v_day.scheduled_end_at;
    IF v_scheduled_end IS NULL THEN
      SELECT * INTO v_schedule
      FROM public.get_employee_work_schedule(v_day.employee_id, v_day.shift_date);
      v_scheduled_end := v_schedule.scheduled_end_at;
    END IF;

    IF p_target_date = v_today
       AND now() < v_scheduled_end + make_interval(mins => v_grace_minutes) THEN
      CONTINUE;
    END IF;

    IF v_day.last_tracking_ping_at IS NOT NULL
       AND v_day.last_tracking_ping_at > v_day.punch_in_time THEN
      v_auto_checkout_time := v_day.last_tracking_ping_at;
    ELSE
      v_auto_checkout_time := v_scheduled_end;
    END IF;

    IF v_auto_checkout_time < v_day.punch_in_time THEN
      v_auto_checkout_time := v_day.punch_in_time;
    END IF;

    v_early_leave_minutes := 0;
    v_overtime_minutes := 0;

    IF v_auto_checkout_time < v_scheduled_end THEN
      v_early_leave_minutes := GREATEST(0,
        EXTRACT(EPOCH FROM (v_scheduled_end - v_auto_checkout_time)) / 60)::INTEGER;
    ELSIF v_auto_checkout_time > v_scheduled_end THEN
      v_overtime_minutes := GREATEST(0,
        EXTRACT(EPOCH FROM (v_auto_checkout_time - v_scheduled_end)) / 60)::INTEGER;
    END IF;

    v_effective_hours := GREATEST(0,
      EXTRACT(EPOCH FROM (v_auto_checkout_time - v_day.punch_in_time)) / 3600.0);

    IF v_overtime_minutes > 0 THEN
      v_checkout_status := 'overtime';
    ELSIF v_early_leave_minutes > 0 THEN
      IF EXISTS (
        SELECT 1 FROM public.hr_leave_requests
        WHERE employee_id = v_day.employee_id
          AND v_day.shift_date BETWEEN start_date AND end_date AND status = 'approved'
      ) OR EXISTS (
        SELECT 1 FROM public.hr_permission_requests
        WHERE employee_id = v_day.employee_id
          AND permission_date = v_day.shift_date AND status = 'approved'
      ) THEN
        v_checkout_status := 'early_authorized';
      ELSE
        v_checkout_status := 'early_unauthorized';
      END IF;
    ELSE
      v_checkout_status := 'on_time';
    END IF;

    UPDATE public.hr_attendance_days
    SET punch_out_time = v_auto_checkout_time,
        checkout_status = v_checkout_status,
        early_leave_minutes = v_early_leave_minutes,
        overtime_minutes = v_overtime_minutes,
        effective_hours = v_effective_hours,
        is_auto_checkout = true,
        tracking_status = 'ended',
        tracking_ended_at = v_auto_checkout_time,
        updated_at = now()
    WHERE id = v_day.id;

    INSERT INTO public.hr_attendance_alerts (
      employee_id, attendance_day_id, alert_type, severity, status, title, details
    ) VALUES (
      v_day.employee_id, v_day.id, 'auto_checkout', 'medium', 'open',
      'إغلاق تلقائي للدوام',
      'تم إغلاق الدوام تلقائياً لعدم وجود بصمة انصراف. يرجى المراجعة.'
    );

    INSERT INTO public.hr_attendance_logs (
      employee_id, attendance_day_id, log_type,
      latitude, longitude, gps_accuracy, location_id,
      event_time, synced_at, requires_review
    ) VALUES (
      v_day.employee_id, v_day.id, 'auto_checkout',
      COALESCE(v_day.last_tracking_lat, 0),
      COALESCE(v_day.last_tracking_lng, 0),
      COALESCE(v_day.last_tracking_accuracy, 0),
      v_day.location_in_id, v_auto_checkout_time, now(), true
    );

    PERFORM public.settle_attendance_day_against_leave(v_day.id);
    PERFORM public.reprocess_attendance_day_penalties(v_day.id);
  END LOOP;
END;
$$;


-- Open-day review alerts use the attendance snapshot, not the global end time.
CREATE OR REPLACE FUNCTION public.scan_attendance_daily_review_alerts()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_open_day_alerts INTEGER := 0;
  v_auto_resolved INTEGER := 0;
  v_delay_minutes INTEGER := 120;
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  r RECORD;
BEGIN
  SELECT COALESCE(value::INTEGER, 120) INTO v_delay_minutes
  FROM public.company_settings WHERE key = 'hr.open_day_review_delay_minutes';
  v_delay_minutes := COALESCE(v_delay_minutes, 120);

  FOR r IN
    SELECT d.id, d.employee_id, d.shift_date, d.punch_in_time, d.review_status
    FROM public.hr_attendance_days d
    CROSS JOIN LATERAL public.get_employee_work_schedule(d.employee_id, d.shift_date) s
    WHERE d.punch_in_time IS NOT NULL
      AND d.punch_out_time IS NULL
      AND COALESCE(d.is_manually_locked, false) = false
      AND NOT EXISTS (
        SELECT 1 FROM public.hr_payroll_runs pr
        JOIN public.hr_payroll_periods pp ON pp.id = pr.period_id
        JOIN public.hr_payroll_lines pl ON pl.payroll_run_id = pr.id
        WHERE pl.employee_id = d.employee_id
          AND pr.status IN ('approved', 'paid')
          AND d.shift_date BETWEEN pp.start_date AND pp.end_date
      )
      AND (
        d.shift_date < v_today
        OR (d.shift_date = v_today AND now() >
          COALESCE(d.scheduled_end_at, s.scheduled_end_at)
          + make_interval(mins => v_delay_minutes))
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.hr_attendance_alerts a_prev
        WHERE a_prev.attendance_day_id = d.id
          AND a_prev.alert_type = 'open_day_unclosed'
          AND a_prev.status IN ('resolved', 'dismissed')
      )
  LOOP
    v_open_day_alerts := v_open_day_alerts + 1;

    IF r.review_status <> 'reviewed' THEN
      UPDATE public.hr_attendance_days
      SET review_status = 'needs_review', updated_at = now()
      WHERE id = r.id AND review_status <> 'reviewed';
    END IF;

    PERFORM public.upsert_attendance_alert(
      r.employee_id, r.id, 'open_day_unclosed', 'high',
      'يوم حضور غير مغلق',
      format('الموظف سجل حضوره يوم %s ولم يسجل انصرافه حتى الآن', r.shift_date),
      jsonb_build_object('shift_date', r.shift_date, 'punch_in_time', r.punch_in_time)
    );
  END LOOP;

  UPDATE public.hr_attendance_alerts a
  SET status = 'resolved', resolved_at = now(),
      resolution_note = 'تم إغلاق اليوم يدويًا — أُغلق التنبيه تلقائيًا',
      updated_at = now()
  FROM public.hr_attendance_days d
  WHERE a.alert_type = 'open_day_unclosed' AND a.status = 'open'
    AND a.attendance_day_id = d.id AND d.punch_out_time IS NOT NULL;

  GET DIAGNOSTICS v_auto_resolved = ROW_COUNT;
  RETURN jsonb_build_object(
    'success', true,
    'open_day_alerts_raised', v_open_day_alerts,
    'open_day_alerts_auto_resolved', v_auto_resolved
  );
END;
$$;


-- Absence notifications now run frequently, wait for each employee's own
-- start plus the current production-equivalent six-hour delay, and use the
-- existing notification_alert_state table for atomic once-per-day deduping.
CREATE OR REPLACE FUNCTION public.notify_absent_employees()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp RECORD;
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_delay_minutes INTEGER := 360;
  v_alert_key TEXT;
  v_state_id UUID;
  v_count INTEGER := 0;
BEGIN
  SELECT COALESCE(value::INTEGER, 360) INTO v_delay_minutes
  FROM public.company_settings WHERE key = 'hr.absence_notification_delay_minutes';
  v_delay_minutes := COALESCE(v_delay_minutes, 360);

  FOR v_emp IN
    SELECT he.id AS employee_id, he.full_name AS emp_name,
           mgr.user_id AS manager_profile, s.scheduled_start_at
    FROM public.hr_employees he
    LEFT JOIN public.hr_employees mgr ON mgr.id = he.direct_manager_id
    CROSS JOIN LATERAL public.get_employee_work_schedule(he.id, v_today) s
    WHERE he.status = 'active'
      AND s.is_working_day
      AND now() >= s.scheduled_start_at + make_interval(mins => v_delay_minutes)
      AND mgr.user_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.hr_leave_requests lr
        WHERE lr.employee_id = he.id
          AND lr.status IN ('approved_supervisor', 'approved_hr', 'approved')
          AND v_today BETWEEN lr.start_date AND lr.end_date
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.hr_permission_requests pr
        WHERE pr.employee_id = he.id AND pr.permission_date = v_today
          AND pr.status = 'approved'
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.hr_attendance_days ad
        WHERE ad.employee_id = he.id AND ad.shift_date = v_today
      )
  LOOP
    BEGIN
      v_alert_key := 'hr.attendance.absent::' || v_emp.employee_id::TEXT
                     || '::' || v_today::TEXT;
      v_state_id := NULL;

      INSERT INTO public.notification_alert_state (
        alert_key, event_key, entity_type, entity_id,
        last_sent_at, resolved_at, send_count, cooldown_hours
      ) VALUES (
        v_alert_key, 'hr.attendance.absent', 'hr_employee', v_emp.employee_id,
        now(), NULL, 1, 24
      )
      ON CONFLICT (alert_key) DO NOTHING
      RETURNING id INTO v_state_id;

      IF v_state_id IS NULL THEN CONTINUE; END IF;

      PERFORM public.call_dispatch_notification(
        'hr.attendance.absent', ARRAY[v_emp.manager_profile],
        jsonb_build_object(
          'employee_name', v_emp.emp_name,
          'date', to_char(v_today, 'YYYY-MM-DD'),
          'employee_id', v_emp.employee_id::TEXT
        ),
        'hr_attendance_day', NULL
      );
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '[notify_absent_employees] employee % error: %',
                    v_emp.employee_id, SQLERRM;
    END;
  END LOOP;

  RAISE NOTICE '[notify_absent_employees] % notifications dispatched for %', v_count, v_today;
END;
$$;

DO $$
DECLARE
  v_job_id BIGINT;
BEGIN
  FOR v_job_id IN
    SELECT jobid FROM cron.job
    WHERE lower(command) LIKE '%notify_absent_employees%'
  LOOP
    PERFORM cron.alter_job(v_job_id, schedule := '*/15 * * * *');
  END LOOP;
END;
$$;


-- Full-day leave settlement uses the snapshot's planned hours. Rest-day work
-- intentionally falls back to the existing company-hours behavior.
DO $$
DECLARE
  v_original TEXT;
  v_patched TEXT;
  v_matches INTEGER;
BEGIN
  SELECT pg_get_functiondef('public.settle_attendance_day_against_leave(uuid,boolean)'::regprocedure)
  INTO v_original;

  SELECT COUNT(*) INTO v_matches
  FROM regexp_matches(
    v_original,
    'SELECT\s+COALESCE\(\(value\)::NUMERIC,\s*8\)\s+INTO\s+v_work_hours\s+FROM\s+company_settings\s+WHERE\s+key\s*=\s*''hr\.work_hours_per_day''\s*;',
    'gi'
  );

  IF v_matches <> 1 THEN
    RAISE EXCEPTION 'settle_attendance_day_against_leave work-hours lookup count changed (%)',
      v_matches;
  END IF;

  v_patched := regexp_replace(
    v_original,
    'SELECT\s+COALESCE\(\(value\)::NUMERIC,\s*8\)\s+INTO\s+v_work_hours\s+FROM\s+company_settings\s+WHERE\s+key\s*=\s*''hr\.work_hours_per_day''\s*;',
    'v_work_hours := COALESCE(NULLIF(v_day.scheduled_minutes, 0) / 60.0, (SELECT COALESCE(value::NUMERIC, 8) FROM public.company_settings WHERE key = ''hr.work_hours_per_day''), 8);',
    'i'
  );

  IF v_patched = v_original THEN
    RAISE EXCEPTION 'settle_attendance_day_against_leave work-hours lookup was not found';
  END IF;

  EXECUTE v_patched;
END;
$$;


-- Penalty occurrence/escalation rules remain untouched; only the daily hours
-- and early-leave endpoint use the immutable attendance snapshot.
DO $$
DECLARE
  v_original TEXT;
  v_patched TEXT;
  v_work_hours_matches INTEGER;
  v_end_matches INTEGER;
BEGIN
  SELECT pg_get_functiondef('public.process_attendance_penalties(uuid)'::regprocedure)
  INTO v_original;

  SELECT COUNT(*) INTO v_work_hours_matches
  FROM regexp_matches(
    v_original,
    'SELECT\s+COALESCE\(\(value\)::NUMERIC,\s*8\)\s+INTO\s+v_work_hours\s+FROM\s+company_settings\s+WHERE\s+key\s*=\s*''hr\.work_hours_per_day''\s*;',
    'gi'
  );
  IF v_work_hours_matches <> 1 THEN
    RAISE EXCEPTION 'process_attendance_penalties work-hours lookup count changed (%)',
      v_work_hours_matches;
  END IF;

  v_patched := regexp_replace(
    v_original,
    'SELECT\s+COALESCE\(\(value\)::NUMERIC,\s*8\)\s+INTO\s+v_work_hours\s+FROM\s+company_settings\s+WHERE\s+key\s*=\s*''hr\.work_hours_per_day''\s*;',
    'v_work_hours := COALESCE(NULLIF(v_day.scheduled_minutes, 0) / 60.0, (SELECT COALESCE(value::NUMERIC, 8) FROM public.company_settings WHERE key = ''hr.work_hours_per_day''), 8);',
    'i'
  );
  IF v_patched = v_original THEN
    RAISE EXCEPTION 'process_attendance_penalties work-hours lookup was not found';
  END IF;

  v_original := v_patched;

  SELECT COUNT(*) INTO v_end_matches
  FROM regexp_matches(
    v_original,
    'SELECT\s+COALESCE\(value,\s*''17:00''\)::TIME\s+INTO\s+v_work_end\s+FROM\s+company_settings\s+WHERE\s+key\s*=\s*''hr\.work_end_time''\s*;\s*v_early_start\s*:=\s*v_day\.punch_out_time\s*;\s*v_early_end\s*:=\s*\(v_day\.shift_date::TEXT\s*\|\|\s*''\s''\s*\|\|\s*v_work_end::TEXT\)::TIMESTAMP\s+AT\s+TIME\s+ZONE\s+''Africa/Cairo''\s*;',
    'gi'
  );
  IF v_end_matches <> 1 THEN
    RAISE EXCEPTION 'process_attendance_penalties scheduled end lookup count changed (%)',
      v_end_matches;
  END IF;

  v_patched := regexp_replace(
    v_original,
    'SELECT\s+COALESCE\(value,\s*''17:00''\)::TIME\s+INTO\s+v_work_end\s+FROM\s+company_settings\s+WHERE\s+key\s*=\s*''hr\.work_end_time''\s*;\s*v_early_start\s*:=\s*v_day\.punch_out_time\s*;\s*v_early_end\s*:=\s*\(v_day\.shift_date::TEXT\s*\|\|\s*''\s''\s*\|\|\s*v_work_end::TEXT\)::TIMESTAMP\s+AT\s+TIME\s+ZONE\s+''Africa/Cairo''\s*;',
    'v_early_start := v_day.punch_out_time; v_early_end := COALESCE(v_day.scheduled_end_at, (SELECT scheduled_end_at FROM public.get_employee_work_schedule(v_day.employee_id, v_day.shift_date)));',
    'i'
  );
  IF v_patched = v_original THEN
    RAISE EXCEPTION 'process_attendance_penalties scheduled end lookup was not found';
  END IF;

  EXECUTE v_patched;
END;
$$;


-- Payroll keeps deductions, approvals, journals, advances and deficit carryover
-- intact. Only workday counts and the overtime-hours divisor become scheduled.
DO $$
DECLARE
  v_original TEXT;
  v_patched TEXT;
  v_workday_matches INTEGER;
  v_hours_matches INTEGER;
  v_partial_matches INTEGER;
BEGIN
  SELECT pg_get_functiondef('public.calculate_employee_payroll(uuid,uuid)'::regprocedure)
  INTO v_original;

  SELECT COUNT(*) INTO v_workday_matches
  FROM regexp_matches(
    v_original,
    'v_off_day_name\s*:=.*?v_working_days\s*:=\s*v_calendar_days\s*;',
    'gis'
  );
  IF v_workday_matches <> 1 THEN
    RAISE EXCEPTION 'calculate_employee_payroll work-day block count changed (%)',
      v_workday_matches;
  END IF;

  v_patched := regexp_replace(
    v_original,
    'v_off_day_name\s*:=.*?v_working_days\s*:=\s*v_calendar_days\s*;',
    'SELECT COUNT(*)::INTEGER INTO v_calendar_days FROM generate_series(v_period.start_date, v_period.end_date, interval ''1 day'') AS gs(work_date) CROSS JOIN LATERAL public.get_employee_work_schedule(p_employee_id, gs.work_date::DATE) schedule WHERE schedule.is_working_day; IF v_calendar_days <= 0 THEN v_calendar_days := 26; END IF; v_working_days := v_calendar_days;',
    'is'
  );
  IF v_patched = v_original THEN
    RAISE EXCEPTION 'calculate_employee_payroll work-day block was not found';
  END IF;

  v_original := v_patched;

  SELECT COUNT(*) INTO v_hours_matches
  FROM regexp_matches(
    v_original,
    'SELECT\s+COALESCE\(value::NUMERIC,\s*8\)\s+INTO\s+v_work_hours_per_day\s+FROM\s+company_settings\s+WHERE\s+key\s*=\s*''hr\.work_hours_per_day''\s*;',
    'gis'
  );
  IF v_hours_matches <> 1 THEN
    RAISE EXCEPTION 'calculate_employee_payroll scheduled-hours lookup count changed (%)',
      v_hours_matches;
  END IF;

  v_patched := regexp_replace(
    v_original,
    'SELECT\s+COALESCE\(value::NUMERIC,\s*8\)\s+INTO\s+v_work_hours_per_day\s+FROM\s+company_settings\s+WHERE\s+key\s*=\s*''hr\.work_hours_per_day''\s*;',
    'SELECT COALESCE(SUM(schedule.scheduled_minutes)::NUMERIC / NULLIF(v_working_days * 60.0, 0), (SELECT COALESCE(value::NUMERIC, 8) FROM public.company_settings WHERE key = ''hr.work_hours_per_day''), 8) INTO v_work_hours_per_day FROM generate_series(v_period.start_date, v_period.end_date, interval ''1 day'') AS gs(work_date) CROSS JOIN LATERAL public.get_employee_work_schedule(p_employee_id, gs.work_date::DATE) schedule WHERE schedule.is_working_day;',
    'is'
  );
  IF v_patched = v_original THEN
    RAISE EXCEPTION 'calculate_employee_payroll scheduled-hours lookup was not found';
  END IF;

  v_original := v_patched;

  SELECT COUNT(*) INTO v_partial_matches
  FROM regexp_matches(
    v_original,
    'IF\s+EXTRACT\(DOW\s+FROM\s+v_d\)::INTEGER\s*<>\s*v_off_dow\s+THEN\s+IF\s+NOT\s+EXISTS\s*\(SELECT\s+1\s+FROM\s+hr_public_holidays\s+WHERE\s+holiday_date\s*=\s*v_d\)\s+THEN\s+v_partial_working\s*:=\s*v_partial_working\s*\+\s*1\s*;\s+END\s+IF\s*;\s+END\s+IF\s*;',
    'gis'
  );
  IF v_partial_matches <> 3 THEN
    RAISE EXCEPTION 'calculate_employee_payroll partial-month loop count changed (%)',
      v_partial_matches;
  END IF;

  v_patched := regexp_replace(
    v_original,
    'IF\s+EXTRACT\(DOW\s+FROM\s+v_d\)::INTEGER\s*<>\s*v_off_dow\s+THEN\s+IF\s+NOT\s+EXISTS\s*\(SELECT\s+1\s+FROM\s+hr_public_holidays\s+WHERE\s+holiday_date\s*=\s*v_d\)\s+THEN\s+v_partial_working\s*:=\s*v_partial_working\s*\+\s*1\s*;\s+END\s+IF\s*;\s+END\s+IF\s*;',
    'IF public.is_employee_work_day(p_employee_id, v_d) = ''work_day'' THEN v_partial_working := v_partial_working + 1; END IF;',
    'gis'
  );
  IF v_patched = v_original THEN
    RAISE EXCEPTION 'calculate_employee_payroll partial-month loops were not found';
  END IF;

  EXECUTE v_patched;
END;
$$;


REVOKE ALL ON FUNCTION public.sync_attendance_day_schedule()
  FROM PUBLIC, anon, authenticated, service_role;

-- CREATE OR REPLACE preserves old ACLs, while newly created functions inherit
-- EXECUTE FROM PUBLIC. Keep the two existing UI operations available to signed-
-- in users, and restrict cron/internal helpers to the service role.
REVOKE ALL ON FUNCTION public.is_employee_work_day(UUID, DATE)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_employee_work_day(UUID, DATE)
  TO service_role;

REVOKE ALL ON FUNCTION public.mark_daily_absences(DATE)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_daily_absences(DATE)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.run_auto_checkout(DATE)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.run_auto_checkout(DATE)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.scan_attendance_daily_review_alerts()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.scan_attendance_daily_review_alerts()
  TO service_role;

REVOKE ALL ON FUNCTION public.notify_absent_employees()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.notify_absent_employees()
  TO service_role;

COMMENT ON TABLE public.hr_employee_work_schedules IS
  'Dated seven-day employee schedule versions; no version means company defaults.';
COMMENT ON COLUMN public.hr_attendance_days.scheduled_start_at IS
  'Immutable planned start snapshot for this attendance day.';
COMMENT ON COLUMN public.hr_attendance_days.scheduled_end_at IS
  'Immutable planned end snapshot for this attendance day.';
COMMENT ON COLUMN public.hr_attendance_days.scheduled_minutes IS
  'Immutable planned minutes snapshot; zero for rest days and public holidays.';

RESET lock_timeout;
RESET statement_timeout;
