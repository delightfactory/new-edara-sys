-- =============================================================================
-- EDARA — Employee Work Schedules M2: resolver, integrity guards, and RPCs
--
-- IMPORTANT:
--   * Requires M1.
--   * Does not replace any existing attendance/payroll function.
--   * Does not enable the runtime feature switch.
--   * Does not seed any employee schedule.
--   * Apply manually only after M1 verification in a disposable environment.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

-- ----------------------------------------------------------------------------
-- 0. M2 preflight
-- ----------------------------------------------------------------------------
DO $preflight$
BEGIN
  IF to_regclass('public.hr_employee_work_schedules') IS NULL
     OR to_regclass('public.hr_employee_work_schedule_days') IS NULL THEN
    RAISE EXCEPTION 'M2 preflight failed: M1 schedule tables are missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'hr_attendance_days'
      AND column_name = 'schedule_day_kind'
  ) THEN
    RAISE EXCEPTION 'M2 preflight failed: M1 attendance snapshot columns are missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.company_settings
    WHERE key = 'hr.employee_work_schedules_enabled'
      AND value = 'false'
      AND type = 'boolean'
      AND is_public = false
  ) THEN
    RAISE EXCEPTION 'M2 preflight failed: feature switch must exist and remain false';
  END IF;

  IF to_regprocedure('public.hr_employee_work_schedules_enabled()') IS NOT NULL
     OR to_regprocedure('public.hr_day_of_week_for_date(date)') IS NOT NULL
     OR to_regprocedure('public.resolve_employee_work_schedule_core(uuid,date,boolean)') IS NOT NULL
     OR to_regprocedure('public.resolve_employee_work_schedule(uuid,date)') IS NOT NULL
     OR to_regprocedure('public.save_employee_work_schedule(uuid,date,jsonb,text)') IS NOT NULL
     OR to_regprocedure('public.ensure_attendance_schedule_snapshot(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'M2 preflight failed: one or more M2 functions already exist';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'M2 preflight failed: no schedule data is expected before guarded RPCs exist';
  END IF;
END;
$preflight$;

-- Minute precision is explicit in v1; seconds would make generated minutes
-- ambiguous and are not supported by the UI contract.
ALTER TABLE public.hr_employee_work_schedule_days
  ADD CONSTRAINT hr_employee_work_schedule_days_minute_precision_check
  CHECK (
    (NOT is_working_day)
    OR
    (
      EXTRACT(SECOND FROM start_time) = 0
      AND EXTRACT(SECOND FROM end_time) = 0
    )
  );

-- ----------------------------------------------------------------------------
-- 1. Internal feature switch helper
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.hr_employee_work_schedules_enabled()
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
  SELECT COALESCE(
    (
      SELECT lower(btrim(value)) IN ('true', '1', 'on', 'yes')
      FROM public.company_settings
      WHERE key = 'hr.employee_work_schedules_enabled'
    ),
    false
  );
$function$;

REVOKE ALL ON FUNCTION public.hr_employee_work_schedules_enabled()
  FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.hr_employee_work_schedules_enabled() IS
  'Internal runtime switch helper. No custom schedule may affect attendance/payroll while false.';

-- ----------------------------------------------------------------------------
-- 2. Locale-independent weekday mapping
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.hr_day_of_week_for_date(p_date DATE)
RETURNS public.hr_day_of_week
LANGUAGE SQL
IMMUTABLE
STRICT
SET search_path = public
AS $function$
  SELECT CASE EXTRACT(DOW FROM p_date)::INTEGER
    WHEN 0 THEN 'sunday'::public.hr_day_of_week
    WHEN 1 THEN 'monday'::public.hr_day_of_week
    WHEN 2 THEN 'tuesday'::public.hr_day_of_week
    WHEN 3 THEN 'wednesday'::public.hr_day_of_week
    WHEN 4 THEN 'thursday'::public.hr_day_of_week
    WHEN 5 THEN 'friday'::public.hr_day_of_week
    WHEN 6 THEN 'saturday'::public.hr_day_of_week
  END;
$function$;

REVOKE ALL ON FUNCTION public.hr_day_of_week_for_date(DATE)
  FROM PUBLIC, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 3. Core resolver
--    p_use_custom = false is reserved for legacy attendance rows with no snapshot.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.resolve_employee_work_schedule_core(
  p_employee_id UUID,
  p_target_date DATE,
  p_use_custom  BOOLEAN
)
RETURNS TABLE (
  day_kind            TEXT,
  is_working_day      BOOLEAN,
  scheduled_start_at  TIMESTAMPTZ,
  scheduled_end_at    TIMESTAMPTZ,
  scheduled_minutes   INTEGER,
  schedule_source     TEXT,
  work_schedule_id    UUID
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_employee_off          public.hr_day_of_week;
  v_target_day            public.hr_day_of_week;
  v_schedule_count        INTEGER;
  v_schedule_id           UUID;
  v_schedule_day_count    INTEGER;
  v_custom_working        BOOLEAN;
  v_custom_start          TIME;
  v_custom_end            TIME;
  v_custom_minutes        INTEGER;

  v_company_off_text      TEXT;
  v_company_off           public.hr_day_of_week;
  v_work_start_text       TEXT;
  v_work_end_text         TEXT;
  v_work_hours_text       TEXT;
  v_work_start            TIME;
  v_work_end              TIME;
  v_window_minutes        INTEGER;
  v_configured_minutes    NUMERIC;
BEGIN
  IF p_employee_id IS NULL OR p_target_date IS NULL THEN
    RAISE EXCEPTION 'employee_id and target_date are required';
  END IF;

  -- Preserve historical compatibility: current employee status does not
  -- reinterpret old dates. Live attendance and payroll keep their own
  -- hire/status/termination guards.
  SELECT e.weekly_off_day
  INTO v_employee_off
  FROM public.hr_employees e
  WHERE e.id = p_employee_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Employee % does not exist', p_employee_id;
  END IF;

  -- Public holiday always wins and is snapshotted as a non-working day.
  IF EXISTS (
    SELECT 1
    FROM public.hr_public_holidays h
    WHERE h.holiday_date = p_target_date
  ) THEN
    RETURN QUERY
    SELECT
      'public_holiday'::TEXT,
      false,
      NULL::TIMESTAMPTZ,
      NULL::TIMESTAMPTZ,
      0,
      'public_holiday'::TEXT,
      NULL::UUID;
    RETURN;
  END IF;

  v_target_day := public.hr_day_of_week_for_date(p_target_date);

  IF COALESCE(p_use_custom, false) THEN
    SELECT
      count(*)::INTEGER,
      (array_agg(s.id ORDER BY s.effective_from DESC))[1]
    INTO v_schedule_count, v_schedule_id
    FROM public.hr_employee_work_schedules s
    WHERE s.employee_id = p_employee_id
      AND s.status IN ('active', 'retired')
      AND s.effective_range @> p_target_date;

    IF v_schedule_count > 1 THEN
      RAISE EXCEPTION
        'Schedule integrity error: % effective schedules cover employee % on %',
        v_schedule_count, p_employee_id, p_target_date;
    END IF;

    IF v_schedule_count = 1 THEN
      SELECT count(*)::INTEGER
      INTO v_schedule_day_count
      FROM public.hr_employee_work_schedule_days d
      WHERE d.schedule_id = v_schedule_id;

      IF v_schedule_day_count <> 7 THEN
        RAISE EXCEPTION
          'Schedule integrity error: schedule % has % day rows instead of 7',
          v_schedule_id, v_schedule_day_count;
      END IF;

      SELECT
        d.is_working_day,
        d.start_time,
        d.end_time,
        d.scheduled_minutes
      INTO
        v_custom_working,
        v_custom_start,
        v_custom_end,
        v_custom_minutes
      FROM public.hr_employee_work_schedule_days d
      WHERE d.schedule_id = v_schedule_id
        AND d.day_of_week = v_target_day;

      IF NOT FOUND THEN
        RAISE EXCEPTION
          'Schedule integrity error: schedule % has no row for %',
          v_schedule_id, v_target_day;
      END IF;

      IF NOT v_custom_working THEN
        RETURN QUERY
        SELECT
          'weekly_off'::TEXT,
          false,
          NULL::TIMESTAMPTZ,
          NULL::TIMESTAMPTZ,
          0,
          'employee'::TEXT,
          v_schedule_id;
        RETURN;
      END IF;

      RETURN QUERY
      SELECT
        'work_day'::TEXT,
        true,
        (p_target_date + v_custom_start) AT TIME ZONE 'Africa/Cairo',
        (p_target_date + v_custom_end) AT TIME ZONE 'Africa/Cairo',
        v_custom_minutes,
        'employee'::TEXT,
        v_schedule_id;
      RETURN;
    END IF;
  END IF;

  -- Legacy fallback weekly off: employee override first, then company setting.
  IF v_employee_off IS NULL THEN
    SELECT value
    INTO v_company_off_text
    FROM public.company_settings
    WHERE key = 'hr.weekly_off_day';

    v_company_off_text := COALESCE(NULLIF(lower(btrim(v_company_off_text)), ''), 'friday');

    BEGIN
      v_company_off := v_company_off_text::public.hr_day_of_week;
    EXCEPTION
      WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'Invalid hr.weekly_off_day setting: %', v_company_off_text;
    END;
  ELSE
    v_company_off := v_employee_off;
  END IF;

  IF v_target_day = v_company_off THEN
    RETURN QUERY
    SELECT
      'weekly_off'::TEXT,
      false,
      NULL::TIMESTAMPTZ,
      NULL::TIMESTAMPTZ,
      0,
      'company'::TEXT,
      NULL::UUID;
    RETURN;
  END IF;

  -- One strict company-time contract prevents attendance and payroll from
  -- silently using different daily-hour assumptions.
  SELECT
    max(value) FILTER (WHERE key = 'hr.work_start_time'),
    max(value) FILTER (WHERE key = 'hr.work_end_time'),
    max(value) FILTER (WHERE key = 'hr.work_hours_per_day')
  INTO v_work_start_text, v_work_end_text, v_work_hours_text
  FROM public.company_settings
  WHERE key IN (
    'hr.work_start_time',
    'hr.work_end_time',
    'hr.work_hours_per_day'
  );

  IF v_work_start_text IS NULL
     OR v_work_end_text IS NULL
     OR v_work_hours_text IS NULL THEN
    RAISE EXCEPTION
      'Company work-time settings are incomplete; start, end, and hours/day are all required';
  END IF;

  BEGIN
    v_work_start := btrim(v_work_start_text)::TIME;
    v_work_end := btrim(v_work_end_text)::TIME;
    v_configured_minutes := btrim(v_work_hours_text)::NUMERIC * 60;
  EXCEPTION
    WHEN invalid_text_representation OR datetime_field_overflow THEN
      RAISE EXCEPTION
        'Invalid company work-time settings: start=%, end=%, hours=%',
        v_work_start_text, v_work_end_text, v_work_hours_text;
  END;

  IF v_work_end <= v_work_start THEN
    RAISE EXCEPTION
      'Overnight or non-positive company work window is not supported in v1: % - %',
      v_work_start, v_work_end;
  END IF;

  IF EXTRACT(SECOND FROM v_work_start) <> 0
     OR EXTRACT(SECOND FROM v_work_end) <> 0 THEN
    RAISE EXCEPTION 'Company work start/end must use minute precision';
  END IF;

  v_window_minutes := (EXTRACT(EPOCH FROM (v_work_end - v_work_start)) / 60)::INTEGER;

  IF v_configured_minutes <= 0
     OR v_configured_minutes <> v_window_minutes THEN
    RAISE EXCEPTION
      'Company work-time mismatch: time window=% minutes, configured hours/day=% minutes',
      v_window_minutes, v_configured_minutes;
  END IF;

  RETURN QUERY
  SELECT
    'work_day'::TEXT,
    true,
    (p_target_date + v_work_start) AT TIME ZONE 'Africa/Cairo',
    (p_target_date + v_work_end) AT TIME ZONE 'Africa/Cairo',
    v_window_minutes,
    'company'::TEXT,
    NULL::UUID;
END;
$function$;

REVOKE ALL ON FUNCTION public.resolve_employee_work_schedule_core(UUID, DATE, BOOLEAN)
  FROM PUBLIC, anon, authenticated;

-- Public-name internal wrapper. It follows the feature switch and is consumed
-- by reviewed security-definer callers in later migrations.
CREATE FUNCTION public.resolve_employee_work_schedule(
  p_employee_id UUID,
  p_target_date DATE
)
RETURNS TABLE (
  day_kind            TEXT,
  is_working_day      BOOLEAN,
  scheduled_start_at  TIMESTAMPTZ,
  scheduled_end_at    TIMESTAMPTZ,
  scheduled_minutes   INTEGER,
  schedule_source     TEXT,
  work_schedule_id    UUID
)
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
  SELECT *
  FROM public.resolve_employee_work_schedule_core(
    p_employee_id,
    p_target_date,
    public.hr_employee_work_schedules_enabled()
  );
$function$;

REVOKE ALL ON FUNCTION public.resolve_employee_work_schedule(UUID, DATE)
  FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.resolve_employee_work_schedule(UUID, DATE) IS
  'Central schedule resolver. Custom schedules are ignored while the feature switch is false.';

-- ----------------------------------------------------------------------------
-- 4. Lifecycle and immutability guards
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.guard_employee_work_schedule_header()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $function$
DECLARE
  v_day_count INTEGER;
  v_cairo_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'draft' THEN
      RAISE EXCEPTION 'A schedule header must be inserted as draft';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status = 'retired' THEN
    IF NEW.employee_id IS DISTINCT FROM OLD.employee_id
       OR NEW.effective_from IS DISTINCT FROM OLD.effective_from
       OR NEW.effective_to IS DISTINCT FROM OLD.effective_to
       OR NEW.status IS DISTINCT FROM OLD.status THEN
      RAISE EXCEPTION 'A retired schedule version is immutable';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status = 'active' THEN
    IF NEW.status = 'retired' THEN
      IF NEW.employee_id IS DISTINCT FROM OLD.employee_id
         OR NEW.effective_from IS DISTINCT FROM OLD.effective_from
         OR NEW.effective_to IS NULL
         OR NEW.effective_to < NEW.effective_from THEN
        RAISE EXCEPTION 'Invalid active-to-retired schedule transition';
      END IF;
      RETURN NEW;
    END IF;

    IF NEW.employee_id IS DISTINCT FROM OLD.employee_id
       OR NEW.effective_from IS DISTINCT FROM OLD.effective_from
       OR NEW.effective_to IS DISTINCT FROM OLD.effective_to
       OR NEW.status IS DISTINCT FROM OLD.status THEN
      RAISE EXCEPTION 'An active schedule cannot be edited in place';
    END IF;

    RETURN NEW;
  END IF;

  -- Only draft -> active is accepted as an activation transition.
  IF OLD.status = 'draft' AND NEW.status = 'active' THEN
    IF NEW.effective_from <= v_cairo_today THEN
      RAISE EXCEPTION
        'Schedule activation must start after the current Cairo date (%)',
        v_cairo_today;
    END IF;

    SELECT count(*)::INTEGER
    INTO v_day_count
    FROM public.hr_employee_work_schedule_days d
    WHERE d.schedule_id = NEW.id;

    IF v_day_count <> 7 THEN
      RAISE EXCEPTION 'An active schedule requires exactly 7 weekday rows; found %', v_day_count;
    END IF;

    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'Unsupported schedule status transition: % -> %', OLD.status, NEW.status;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_employee_work_schedule_header()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_hr_employee_work_schedules_header_guard
  ON public.hr_employee_work_schedules;
CREATE TRIGGER trg_hr_employee_work_schedules_header_guard
  BEFORE INSERT OR UPDATE ON public.hr_employee_work_schedules
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_employee_work_schedule_header();

CREATE FUNCTION public.guard_employee_work_schedule_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  IF OLD.status <> 'draft' THEN
    RAISE EXCEPTION 'Only an unreferenced draft schedule may be deleted';
  END IF;
  RETURN OLD;
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_employee_work_schedule_delete()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_hr_employee_work_schedules_delete_guard
  ON public.hr_employee_work_schedules;
CREATE TRIGGER trg_hr_employee_work_schedules_delete_guard
  BEFORE DELETE ON public.hr_employee_work_schedules
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_employee_work_schedule_delete();

CREATE FUNCTION public.guard_employee_work_schedule_day_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $function$
DECLARE
  v_schedule_id UUID;
  v_status TEXT;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.schedule_id IS DISTINCT FROM OLD.schedule_id THEN
    RAISE EXCEPTION 'A schedule day cannot be moved between schedule versions';
  END IF;

  v_schedule_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.schedule_id ELSE NEW.schedule_id END;

  SELECT s.status
  INTO v_status
  FROM public.hr_employee_work_schedules s
  WHERE s.id = v_schedule_id;

  -- During ON DELETE CASCADE of a draft header, the parent may no longer be
  -- visible to this child trigger. The header delete guard already proved it
  -- was a draft, so a missing parent is allowed only for DELETE.
  IF NOT FOUND THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'Schedule % does not exist', v_schedule_id;
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'Weekday rows are immutable after schedule activation';
  END IF;

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_employee_work_schedule_day_mutation()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_hr_employee_work_schedule_days_guard
  ON public.hr_employee_work_schedule_days;
CREATE TRIGGER trg_hr_employee_work_schedule_days_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.hr_employee_work_schedule_days
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_employee_work_schedule_day_mutation();

-- ----------------------------------------------------------------------------
-- 5. Atomic future schedule save/activation RPC
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.save_employee_work_schedule(
  p_employee_id    UUID,
  p_effective_from DATE,
  p_days           JSONB,
  p_notes          TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
  v_actor UUID := auth.uid();
  v_cairo_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_employee public.hr_employees%ROWTYPE;
  v_schedule_id UUID;
  v_previous public.hr_employee_work_schedules%ROWTYPE;
  v_previous_found BOOLEAN := false;
  v_day_count INTEGER;
  v_distinct_day_count INTEGER;
  v_result JSONB;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT public.check_permission(v_actor, 'hr.employees.edit') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تعديل جدول عمل الموظف';
  END IF;

  IF p_employee_id IS NULL OR p_effective_from IS NULL THEN
    RAISE EXCEPTION 'employee_id and effective_from are required';
  END IF;

  IF p_effective_from <= v_cairo_today THEN
    RAISE EXCEPTION
      'تاريخ بدء الجدول يجب أن يكون بعد تاريخ اليوم بتوقيت القاهرة (%)',
      v_cairo_today;
  END IF;

  SELECT *
  INTO v_employee
  FROM public.hr_employees
  WHERE id = p_employee_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الموظف غير موجود';
  END IF;

  IF v_employee.status = 'terminated' THEN
    RAISE EXCEPTION 'لا يمكن إنشاء جدول مستقبلي لموظف منتهي الخدمة';
  END IF;

  IF p_effective_from < v_employee.hire_date THEN
    RAISE EXCEPTION 'تاريخ الجدول لا يمكن أن يسبق تاريخ تعيين الموظف';
  END IF;

  IF v_employee.termination_date IS NOT NULL
     AND p_effective_from > v_employee.termination_date THEN
    RAISE EXCEPTION 'تاريخ الجدول يقع بعد تاريخ انتهاء خدمة الموظف';
  END IF;

  IF p_days IS NULL OR jsonb_typeof(p_days) <> 'array' THEN
    RAISE EXCEPTION 'days must be a JSON array';
  END IF;

  IF jsonb_array_length(p_days) <> 7 THEN
    RAISE EXCEPTION 'يجب إدخال الأيام السبعة كاملة';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_days) item
    WHERE jsonb_typeof(item) <> 'object'
  ) THEN
    RAISE EXCEPTION 'كل عنصر في days يجب أن يكون كائناً';
  END IF;

  SELECT
    count(*)::INTEGER,
    count(DISTINCT lower(btrim(item->>'day_of_week')))::INTEGER
  INTO v_day_count, v_distinct_day_count
  FROM jsonb_array_elements(p_days) item;

  IF v_day_count <> 7 OR v_distinct_day_count <> 7 THEN
    RAISE EXCEPTION 'الأيام السبعة يجب أن تكون فريدة وكاملة';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_days) item
    WHERE item->>'day_of_week' IS NULL
       OR lower(btrim(item->>'day_of_week')) NOT IN (
         'saturday', 'sunday', 'monday', 'tuesday',
         'wednesday', 'thursday', 'friday'
       )
       OR jsonb_typeof(item->'is_working_day') IS DISTINCT FROM 'boolean'
  ) THEN
    RAISE EXCEPTION 'بيانات اليوم أو حالة يوم العمل غير صحيحة';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_days) item
    WHERE (item->>'is_working_day')::BOOLEAN
      AND (
        COALESCE(item->>'start_time', '') !~ '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$'
        OR COALESCE(item->>'end_time', '') !~ '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$'
      )
  ) THEN
    RAISE EXCEPTION 'أيام العمل تتطلب وقت بداية ونهاية بصيغة HH:MM';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_days) item
    WHERE (item->>'is_working_day')::BOOLEAN
      AND (item->>'end_time')::TIME <= (item->>'start_time')::TIME
  ) THEN
    RAISE EXCEPTION 'وقت نهاية العمل يجب أن يكون بعد وقت البداية في نفس اليوم';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_days) item
    WHERE NOT (item->>'is_working_day')::BOOLEAN
      AND (
        NULLIF(btrim(COALESCE(item->>'start_time', '')), '') IS NOT NULL
        OR NULLIF(btrim(COALESCE(item->>'end_time', '')), '') IS NOT NULL
      )
  ) THEN
    RAISE EXCEPTION 'يوم الإجازة لا يقبل وقت بداية أو نهاية';
  END IF;

  -- Serialize all schedule changes for one employee.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_employee_id::TEXT, 0));

  -- Do not insert before or over an already-planned effective version.
  IF EXISTS (
    SELECT 1
    FROM public.hr_employee_work_schedules s
    WHERE s.employee_id = p_employee_id
      AND s.status IN ('active', 'retired')
      AND s.effective_from >= p_effective_from
  ) THEN
    RAISE EXCEPTION 'يوجد جدول فعّال أو مخطط يبدأ في نفس التاريخ أو بعده؛ راجع التسلسل أولاً';
  END IF;

  SELECT s.*
  INTO v_previous
  FROM public.hr_employee_work_schedules s
  WHERE s.employee_id = p_employee_id
    AND s.status = 'active'
    AND s.effective_from < p_effective_from
    AND (s.effective_to IS NULL OR s.effective_to >= p_effective_from)
  ORDER BY s.effective_from DESC
  LIMIT 1
  FOR UPDATE;

  v_previous_found := FOUND;

  IF v_previous_found AND EXISTS (
    SELECT 1
    FROM public.hr_attendance_days ad
    WHERE ad.work_schedule_id = v_previous.id
      AND ad.shift_date >= p_effective_from
  ) THEN
    RAISE EXCEPTION 'لا يمكن إغلاق الجدول السابق بسبب وجود حضور مرتبط بعد تاريخ الجدول الجديد';
  END IF;

  IF v_previous_found THEN
    UPDATE public.hr_employee_work_schedules
    SET status = 'retired',
        effective_to = p_effective_from - 1,
        retired_by = v_actor,
        retired_at = now(),
        updated_by = v_actor
    WHERE id = v_previous.id;
  END IF;

  INSERT INTO public.hr_employee_work_schedules (
    employee_id,
    effective_from,
    effective_to,
    status,
    notes,
    created_by,
    updated_by
  ) VALUES (
    p_employee_id,
    p_effective_from,
    NULL,
    'draft',
    NULLIF(btrim(p_notes), ''),
    v_actor,
    v_actor
  )
  RETURNING id INTO v_schedule_id;

  INSERT INTO public.hr_employee_work_schedule_days (
    schedule_id,
    day_of_week,
    is_working_day,
    start_time,
    end_time
  )
  SELECT
    v_schedule_id,
    lower(btrim(item->>'day_of_week'))::public.hr_day_of_week,
    (item->>'is_working_day')::BOOLEAN,
    CASE
      WHEN (item->>'is_working_day')::BOOLEAN
        THEN (item->>'start_time')::TIME
      ELSE NULL
    END,
    CASE
      WHEN (item->>'is_working_day')::BOOLEAN
        THEN (item->>'end_time')::TIME
      ELSE NULL
    END
  FROM jsonb_array_elements(p_days) item;

  UPDATE public.hr_employee_work_schedules
  SET status = 'active',
      activated_by = v_actor,
      activated_at = now(),
      updated_by = v_actor
  WHERE id = v_schedule_id;

  SELECT jsonb_build_object(
    'id', s.id,
    'employee_id', s.employee_id,
    'effective_from', s.effective_from,
    'effective_to', s.effective_to,
    'status', s.status,
    'notes', s.notes,
    'days', (
      SELECT jsonb_agg(
        jsonb_build_object(
          'day_of_week', d.day_of_week,
          'is_working_day', d.is_working_day,
          'start_time', d.start_time,
          'end_time', d.end_time,
          'scheduled_minutes', d.scheduled_minutes
        )
        ORDER BY d.day_of_week
      )
      FROM public.hr_employee_work_schedule_days d
      WHERE d.schedule_id = s.id
    )
  )
  INTO v_result
  FROM public.hr_employee_work_schedules s
  WHERE s.id = v_schedule_id;

  INSERT INTO public.audit_logs (
    user_id,
    action,
    entity_type,
    entity_id,
    old_data,
    new_data,
    user_agent
  ) VALUES (
    v_actor,
    'employee_work_schedule_saved',
    'hr_employee_work_schedule',
    v_schedule_id,
    CASE
      WHEN v_previous_found THEN to_jsonb(v_previous)
      ELSE NULL
    END,
    v_result,
    'EDARA employee work schedule RPC'
  );

  RETURN jsonb_build_object(
    'success', true,
    'schedule', v_result,
    'previous_schedule_retired', v_previous_found,
    'feature_enabled', public.hr_employee_work_schedules_enabled()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.save_employee_work_schedule(UUID, DATE, JSONB, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_employee_work_schedule(UUID, DATE, JSONB, TEXT)
  TO authenticated;

COMMENT ON FUNCTION public.save_employee_work_schedule(UUID, DATE, JSONB, TEXT) IS
  'Atomically creates and activates one complete future employee weekly schedule. Requires hr.employees.edit.';

-- ----------------------------------------------------------------------------
-- 6. Legacy-safe snapshot helper for existing attendance rows
--    It never refreshes a complete snapshot and never applies custom schedules
--    retroactively to a legacy row.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.ensure_attendance_schedule_snapshot(
  p_attendance_day_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_day public.hr_attendance_days%ROWTYPE;
  v_payroll_status TEXT;
  v_resolved RECORD;
  v_actor UUID := auth.uid();
BEGIN
  IF p_attendance_day_id IS NULL THEN
    RAISE EXCEPTION 'attendance_day_id is required';
  END IF;

  SELECT *
  INTO v_day
  FROM public.hr_attendance_days
  WHERE id = p_attendance_day_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Attendance day % does not exist', p_attendance_day_id;
  END IF;

  IF v_day.schedule_snapshot_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'attendance_day_id', v_day.id,
      'created', false,
      'day_kind', v_day.schedule_day_kind,
      'scheduled_start_at', v_day.scheduled_start_at,
      'scheduled_end_at', v_day.scheduled_end_at,
      'scheduled_minutes', v_day.scheduled_minutes,
      'schedule_source', v_day.schedule_source,
      'work_schedule_id', v_day.work_schedule_id,
      'schedule_snapshot_at', v_day.schedule_snapshot_at
    );
  END IF;

  -- M1 check constraint allows only all-null or complete snapshots. This guard
  -- provides a clearer error if the constraint was bypassed by an owner.
  IF v_day.schedule_day_kind IS NOT NULL
     OR v_day.scheduled_start_at IS NOT NULL
     OR v_day.scheduled_end_at IS NOT NULL
     OR v_day.scheduled_minutes IS NOT NULL
     OR v_day.schedule_source IS NOT NULL
     OR v_day.work_schedule_id IS NOT NULL THEN
    RAISE EXCEPTION 'Attendance day % contains an incomplete schedule snapshot', v_day.id;
  END IF;

  SELECT pr.status::TEXT
  INTO v_payroll_status
  FROM public.hr_payroll_lines pl
  JOIN public.hr_payroll_runs pr ON pr.id = pl.payroll_run_id
  JOIN public.hr_payroll_periods pp ON pp.id = pr.period_id
  WHERE pl.employee_id = v_day.employee_id
    AND v_day.shift_date BETWEEN pp.start_date AND pp.end_date
    AND pr.status IN ('approved', 'paid')
  ORDER BY CASE pr.status WHEN 'paid' THEN 1 ELSE 2 END
  LIMIT 1;

  IF v_payroll_status IS NOT NULL THEN
    RAISE EXCEPTION
      'Cannot create schedule snapshot for attendance day % covered by % payroll',
      v_day.id, v_payroll_status;
  END IF;

  -- Force legacy fallback. A custom schedule created later must never be
  -- applied retroactively to an old attendance row with no snapshot.
  SELECT *
  INTO v_resolved
  FROM public.resolve_employee_work_schedule_core(
    v_day.employee_id,
    v_day.shift_date,
    false
  );

  UPDATE public.hr_attendance_days
  SET schedule_day_kind = v_resolved.day_kind,
      scheduled_start_at = v_resolved.scheduled_start_at,
      scheduled_end_at = v_resolved.scheduled_end_at,
      scheduled_minutes = v_resolved.scheduled_minutes,
      schedule_source = v_resolved.schedule_source,
      work_schedule_id = v_resolved.work_schedule_id,
      schedule_snapshot_at = now(),
      updated_at = now()
  WHERE id = v_day.id;

  INSERT INTO public.audit_logs (
    user_id,
    action,
    entity_type,
    entity_id,
    old_data,
    new_data,
    user_agent
  ) VALUES (
    v_actor,
    'attendance_schedule_snapshot_created',
    'hr_attendance_day',
    v_day.id,
    jsonb_build_object(
      'schedule_snapshot_at', NULL,
      'legacy_row', true
    ),
    jsonb_build_object(
      'day_kind', v_resolved.day_kind,
      'scheduled_start_at', v_resolved.scheduled_start_at,
      'scheduled_end_at', v_resolved.scheduled_end_at,
      'scheduled_minutes', v_resolved.scheduled_minutes,
      'schedule_source', v_resolved.schedule_source,
      'work_schedule_id', v_resolved.work_schedule_id
    ),
    'EDARA attendance schedule snapshot helper'
  );

  RETURN jsonb_build_object(
    'attendance_day_id', v_day.id,
    'created', true,
    'day_kind', v_resolved.day_kind,
    'scheduled_start_at', v_resolved.scheduled_start_at,
    'scheduled_end_at', v_resolved.scheduled_end_at,
    'scheduled_minutes', v_resolved.scheduled_minutes,
    'schedule_source', v_resolved.schedule_source,
    'work_schedule_id', v_resolved.work_schedule_id,
    'schedule_snapshot_at', now()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.ensure_attendance_schedule_snapshot(UUID)
  FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.ensure_attendance_schedule_snapshot(UUID) IS
  'Internal helper: creates one immutable legacy fallback snapshot for an existing open-period attendance row.';

-- ----------------------------------------------------------------------------
-- 7. M2 assertions — runtime remains disabled and existing rows untouched
-- ----------------------------------------------------------------------------
DO $assertions$
BEGIN
  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'M2 assertion failed: feature switch became enabled';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'M2 assertion failed: migration must not seed schedule data';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_attendance_days
    WHERE schedule_snapshot_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'M2 assertion failed: migration must not snapshot historical attendance';
  END IF;
END;
$assertions$;

COMMIT;
