-- =============================================================================
-- EDARA — Employee Work Schedules: effective-dated company fallback
--
-- Narrow scope:
--   * preserve exact legacy company_settings behavior while the feature is off;
--   * create one immutable effective-dated company schedule history for enabled mode;
--   * seed one technical baseline from the current validated company settings;
--   * make the first employee schedule compare with the company version effective
--     on the employee schedule date, not with a mutable current setting;
--   * expose atomic future company-schedule create/edit RPCs.
--
-- This migration does not enable the feature, create employee schedules, change
-- attendance, backfill snapshots, recalculate payroll, or modify payroll runs.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

DO $preflight$
BEGIN
  IF to_regclass('public.company_settings') IS NULL
     OR to_regclass('public.hr_employees') IS NULL
     OR to_regclass('public.hr_attendance_days') IS NULL
     OR to_regprocedure('public.resolve_employee_work_schedule_core(uuid,date,boolean)') IS NULL
     OR to_regprocedure('public.get_company_default_scheduled_minutes()') IS NULL
     OR to_regprocedure('public.guard_employee_work_schedule_activation_duration()') IS NULL
     OR to_regprocedure('public.validate_employee_work_schedule_duration()') IS NULL
     OR to_regprocedure('public.hr_day_of_week_for_date(date)') IS NULL
     OR to_regprocedure('public.check_permission(uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'Company-history preflight failed: required schedule objects are missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Company-history preflight failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Company-history preflight failed: no employee schedule/snapshot runtime data is expected';
  END IF;

  IF to_regclass('public.hr_company_work_schedules') IS NOT NULL
     OR to_regprocedure('public.validate_hr_company_work_schedule_values(text,text,text,text)') IS NOT NULL
     OR to_regprocedure('public.resolve_company_work_schedule_version(date)') IS NOT NULL
     OR to_regprocedure('public.get_company_scheduled_minutes_for_date(date)') IS NOT NULL
     OR to_regprocedure('public.get_company_work_schedule_for_date(date)') IS NOT NULL
     OR to_regprocedure('public.save_company_work_schedule_version(date,text,text,text,text)') IS NOT NULL
     OR to_regprocedure('public.update_future_company_work_schedule_version(uuid,text,text,text,text)') IS NOT NULL
     OR to_regprocedure('public.resolve_employee_work_schedule_core_pre_company_history_20260806(uuid,date,boolean)') IS NOT NULL THEN
    RAISE EXCEPTION 'Company-history preflight failed: one or more target objects already exist';
  END IF;
END;
$preflight$;

-- -----------------------------------------------------------------------------
-- 1. Strict company schedule value validator
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.validate_hr_company_work_schedule_values(
  p_start_text TEXT,
  p_end_text TEXT,
  p_hours_text TEXT,
  p_off_text TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $function$
DECLARE
  v_start_input TEXT := regexp_replace(COALESCE(btrim(p_start_text), ''), '\s+', '', 'g');
  v_end_input TEXT := regexp_replace(COALESCE(btrim(p_end_text), ''), '\s+', '', 'g');
  v_hours_input TEXT := COALESCE(btrim(p_hours_text), '');
  v_off_input TEXT := lower(COALESCE(btrim(p_off_text), ''));
  v_start TIME;
  v_end TIME;
  v_hours NUMERIC;
  v_minutes INTEGER;
BEGIN
  IF v_start_input ~ '^(?:[01][0-9]|2[0-3])[0-5][0-9]$' THEN
    v_start_input := substr(v_start_input, 1, 2) || ':' || substr(v_start_input, 3, 2);
  ELSIF v_start_input ~ '^(?:[01]?[0-9]|2[0-3]):[0-5][0-9]$' THEN
    v_start_input := lpad(split_part(v_start_input, ':', 1), 2, '0')
      || ':' || split_part(v_start_input, ':', 2);
  ELSE
    RAISE EXCEPTION 'وقت بداية دوام الشركة يجب أن يكون بصيغة HH:MM';
  END IF;

  IF v_end_input ~ '^(?:[01][0-9]|2[0-3])[0-5][0-9]$' THEN
    v_end_input := substr(v_end_input, 1, 2) || ':' || substr(v_end_input, 3, 2);
  ELSIF v_end_input ~ '^(?:[01]?[0-9]|2[0-3]):[0-5][0-9]$' THEN
    v_end_input := lpad(split_part(v_end_input, ':', 1), 2, '0')
      || ':' || split_part(v_end_input, ':', 2);
  ELSE
    RAISE EXCEPTION 'وقت نهاية دوام الشركة يجب أن يكون بصيغة HH:MM';
  END IF;

  BEGIN
    v_start := v_start_input::TIME;
    v_end := v_end_input::TIME;
    v_hours := v_hours_input::NUMERIC;
  EXCEPTION
    WHEN invalid_text_representation OR datetime_field_overflow THEN
      RAISE EXCEPTION 'إعدادات ساعات عمل الشركة غير صالحة';
  END;

  IF v_end <= v_start THEN
    RAISE EXCEPTION 'مواعيد الشركة الليلية أو غير الموجبة غير مدعومة في V1';
  END IF;

  IF EXTRACT(SECOND FROM v_start) <> 0 OR EXTRACT(SECOND FROM v_end) <> 0 THEN
    RAISE EXCEPTION 'مواعيد الشركة يجب أن تستخدم دقة الدقيقة فقط';
  END IF;

  v_minutes := (EXTRACT(EPOCH FROM (v_end - v_start)) / 60)::INTEGER;

  IF v_hours <= 0 OR v_hours * 60 <> v_minutes THEN
    RAISE EXCEPTION
      'عدد ساعات الشركة (%) لا يطابق نافذة البداية والنهاية (%) دقيقة',
      v_hours,
      v_minutes;
  END IF;

  IF v_off_input NOT IN (
    'saturday', 'sunday', 'monday', 'tuesday',
    'wednesday', 'thursday', 'friday'
  ) THEN
    RAISE EXCEPTION 'يوم الإجازة الأسبوعية للشركة غير صالح';
  END IF;

  RETURN jsonb_build_object(
    'start_time', to_char(v_start, 'HH24:MI'),
    'end_time', to_char(v_end, 'HH24:MI'),
    'work_hours_per_day', v_hours,
    'scheduled_minutes', v_minutes,
    'weekly_off_day', v_off_input
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.validate_hr_company_work_schedule_values(TEXT, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 2. Effective-dated company schedule versions
-- -----------------------------------------------------------------------------
CREATE TABLE public.hr_company_work_schedules (
  id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  effective_from DATE NOT NULL,
  effective_to DATE,
  effective_range DATERANGE GENERATED ALWAYS AS (
    daterange(effective_from, COALESCE(effective_to, 'infinity'::DATE), '[]')
  ) STORED,
  status TEXT NOT NULL DEFAULT 'active',
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  scheduled_minutes INTEGER GENERATED ALWAYS AS (
    (EXTRACT(EPOCH FROM (end_time - start_time)) / 60)::INTEGER
  ) STORED,
  weekly_off_day public.hr_day_of_week NOT NULL,
  notes TEXT,
  is_system_baseline BOOLEAN NOT NULL DEFAULT false,

  activated_by UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  activated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  retired_by UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  retired_at TIMESTAMPTZ,

  created_by UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT hr_company_work_schedules_status_check
    CHECK (status IN ('active', 'retired')),
  CONSTRAINT hr_company_work_schedules_dates_check
    CHECK (effective_to IS NULL OR effective_to >= effective_from),
  CONSTRAINT hr_company_work_schedules_window_check
    CHECK (
      end_time > start_time
      AND EXTRACT(SECOND FROM start_time) = 0
      AND EXTRACT(SECOND FROM end_time) = 0
      AND scheduled_minutes > 0
      AND scheduled_minutes < 1440
    ),
  CONSTRAINT hr_company_work_schedules_lifecycle_check
    CHECK (
      (
        status = 'active'
        AND effective_to IS NULL
        AND retired_by IS NULL
        AND retired_at IS NULL
      )
      OR
      (
        status = 'retired'
        AND effective_to IS NOT NULL
        AND retired_at IS NOT NULL
      )
    ),
  CONSTRAINT hr_company_work_schedules_no_effective_overlap
    EXCLUDE USING gist (effective_range WITH &&)
    WHERE (status IN ('active', 'retired'))
);

CREATE INDEX hr_company_work_schedules_effective_idx
  ON public.hr_company_work_schedules(effective_from DESC);

DROP TRIGGER IF EXISTS trg_hr_company_work_schedules_updated_at
  ON public.hr_company_work_schedules;
CREATE TRIGGER trg_hr_company_work_schedules_updated_at
  BEFORE UPDATE ON public.hr_company_work_schedules
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.hr_company_work_schedules ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.hr_company_work_schedules
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.hr_company_work_schedules TO authenticated;

CREATE POLICY hr_company_work_schedules_read
  ON public.hr_company_work_schedules
  FOR SELECT
  TO authenticated
  USING (
    (SELECT public.check_permission((SELECT auth.uid()), 'settings.read'))
    OR (SELECT public.check_permission((SELECT auth.uid()), 'hr.employees.read'))
    OR (SELECT public.check_permission((SELECT auth.uid()), 'hr.attendance.read'))
    OR (SELECT public.check_permission((SELECT auth.uid()), 'hr.employees.edit'))
  );

COMMENT ON TABLE public.hr_company_work_schedules IS
  'Effective-dated company fallback schedule used only by enabled employee-schedule runtime.';
COMMENT ON COLUMN public.hr_company_work_schedules.is_system_baseline IS
  'True only for the technical baseline imported from current company_settings during installation.';

-- -----------------------------------------------------------------------------
-- 3. Import one technical baseline without changing current settings
-- -----------------------------------------------------------------------------
DO $seed_baseline$
DECLARE
  v_start_text TEXT;
  v_end_text TEXT;
  v_hours_text TEXT;
  v_off_text TEXT;
  v_valid JSONB;
  v_cairo_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_baseline_start DATE;
BEGIN
  SELECT
    max(value) FILTER (WHERE key = 'hr.work_start_time'),
    max(value) FILTER (WHERE key = 'hr.work_end_time'),
    max(value) FILTER (WHERE key = 'hr.work_hours_per_day'),
    max(value) FILTER (WHERE key = 'hr.weekly_off_day')
  INTO v_start_text, v_end_text, v_hours_text, v_off_text
  FROM public.company_settings
  WHERE key IN (
    'hr.work_start_time',
    'hr.work_end_time',
    'hr.work_hours_per_day',
    'hr.weekly_off_day'
  );

  v_valid := public.validate_hr_company_work_schedule_values(
    v_start_text,
    v_end_text,
    v_hours_text,
    v_off_text
  );

  SELECT LEAST(
    COALESCE((SELECT min(e.hire_date) FROM public.hr_employees e), v_cairo_today),
    COALESCE((SELECT min(a.shift_date) FROM public.hr_attendance_days a), v_cairo_today),
    COALESCE((SELECT min(p.start_date) FROM public.hr_payroll_periods p), v_cairo_today),
    v_cairo_today
  )
  INTO v_baseline_start;

  INSERT INTO public.hr_company_work_schedules (
    effective_from,
    effective_to,
    status,
    start_time,
    end_time,
    weekly_off_day,
    notes,
    is_system_baseline,
    activated_at
  ) VALUES (
    v_baseline_start,
    NULL,
    'active',
    (v_valid->>'start_time')::TIME,
    (v_valid->>'end_time')::TIME,
    (v_valid->>'weekly_off_day')::public.hr_day_of_week,
    'Technical baseline imported from validated company_settings; no runtime activation performed',
    true,
    now()
  );
END;
$seed_baseline$;

-- -----------------------------------------------------------------------------
-- 4. Versioned company resolver
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.resolve_company_work_schedule_version(
  p_target_date DATE
)
RETURNS TABLE (
  day_kind TEXT,
  is_working_day BOOLEAN,
  scheduled_start_at TIMESTAMPTZ,
  scheduled_end_at TIMESTAMPTZ,
  scheduled_minutes INTEGER,
  schedule_source TEXT,
  work_schedule_id UUID
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_count INTEGER;
  v_schedule public.hr_company_work_schedules%ROWTYPE;
  v_day public.hr_day_of_week;
BEGIN
  IF p_target_date IS NULL THEN
    RAISE EXCEPTION 'target_date is required';
  END IF;

  SELECT count(*)::INTEGER
  INTO v_count
  FROM public.hr_company_work_schedules s
  WHERE s.status IN ('active', 'retired')
    AND s.effective_range @> p_target_date;

  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'Company schedule integrity error: % versions cover %',
      v_count,
      p_target_date;
  END IF;

  SELECT * INTO v_schedule
  FROM public.hr_company_work_schedules s
  WHERE s.status IN ('active', 'retired')
    AND s.effective_range @> p_target_date;

  v_day := public.hr_day_of_week_for_date(p_target_date);

  IF v_day = v_schedule.weekly_off_day THEN
    RETURN QUERY SELECT
      'weekly_off'::TEXT,
      false,
      NULL::TIMESTAMPTZ,
      NULL::TIMESTAMPTZ,
      0,
      'company'::TEXT,
      NULL::UUID;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    'work_day'::TEXT,
    true,
    (p_target_date + v_schedule.start_time) AT TIME ZONE 'Africa/Cairo',
    (p_target_date + v_schedule.end_time) AT TIME ZONE 'Africa/Cairo',
    v_schedule.scheduled_minutes,
    'company'::TEXT,
    NULL::UUID;
END;
$function$;

REVOKE ALL ON FUNCTION public.resolve_company_work_schedule_version(DATE)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.get_company_scheduled_minutes_for_date(p_target_date DATE)
RETURNS INTEGER
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
  SELECT r.scheduled_minutes
  FROM public.resolve_company_work_schedule_version(p_target_date) r
  LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION public.get_company_scheduled_minutes_for_date(DATE)
  FROM PUBLIC, anon, authenticated, service_role;

-- Preserve the exact pre-history core for disabled mode and for public-holiday /
-- employee-custom branches that were already reviewed.
DO $clone_resolver$
DECLARE
  v_definition TEXT;
BEGIN
  SELECT pg_get_functiondef(
    'public.resolve_employee_work_schedule_core(uuid,date,boolean)'::regprocedure
  ) INTO v_definition;

  v_definition := replace(
    v_definition,
    'FUNCTION public.resolve_employee_work_schedule_core(',
    'FUNCTION public.resolve_employee_work_schedule_core_pre_company_history_20260806('
  );

  EXECUTE v_definition;
END;
$clone_resolver$;

REVOKE ALL ON FUNCTION public.resolve_employee_work_schedule_core_pre_company_history_20260806(UUID, DATE, BOOLEAN)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.resolve_employee_work_schedule_core(
  p_employee_id UUID,
  p_target_date DATE,
  p_use_custom BOOLEAN
)
RETURNS TABLE (
  day_kind TEXT,
  is_working_day BOOLEAN,
  scheduled_start_at TIMESTAMPTZ,
  scheduled_end_at TIMESTAMPTZ,
  scheduled_minutes INTEGER,
  schedule_source TEXT,
  work_schedule_id UUID
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_custom_count INTEGER;
BEGIN
  IF p_employee_id IS NULL OR p_target_date IS NULL THEN
    RAISE EXCEPTION 'employee_id and target_date are required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.hr_employees e WHERE e.id = p_employee_id
  ) THEN
    RAISE EXCEPTION 'Employee % does not exist', p_employee_id;
  END IF;

  -- Disabled mode remains the exact cloned legacy/company-settings resolver.
  IF NOT COALESCE(p_use_custom, false) THEN
    RETURN QUERY
    SELECT *
    FROM public.resolve_employee_work_schedule_core_pre_company_history_20260806(
      p_employee_id,
      p_target_date,
      false
    );
    RETURN;
  END IF;

  -- Public holidays retain first precedence and use the already-reviewed path.
  IF EXISTS (
    SELECT 1
    FROM public.hr_public_holidays h
    WHERE h.holiday_date = p_target_date
  ) THEN
    RETURN QUERY
    SELECT *
    FROM public.resolve_employee_work_schedule_core_pre_company_history_20260806(
      p_employee_id,
      p_target_date,
      true
    );
    RETURN;
  END IF;

  SELECT count(*)::INTEGER
  INTO v_custom_count
  FROM public.hr_employee_work_schedules s
  WHERE s.employee_id = p_employee_id
    AND s.status IN ('active', 'retired')
    AND s.effective_range @> p_target_date;

  IF v_custom_count > 0 THEN
    RETURN QUERY
    SELECT *
    FROM public.resolve_employee_work_schedule_core_pre_company_history_20260806(
      p_employee_id,
      p_target_date,
      true
    );
    RETURN;
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.resolve_company_work_schedule_version(p_target_date);
END;
$function$;

REVOKE ALL ON FUNCTION public.resolve_employee_work_schedule_core(UUID, DATE, BOOLEAN)
  FROM PUBLIC, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 5. First employee schedule compares to the company version for that date
-- -----------------------------------------------------------------------------
DO $patch_duration_guards$
DECLARE
  v_definition TEXT;
  v_old TEXT;
  v_new TEXT;
  v_occurrences INTEGER;
BEGIN
  SELECT pg_get_functiondef(
    'public.guard_employee_work_schedule_activation_duration()'::regprocedure
  ) INTO v_definition;

  v_old := 'v_previous_minutes := public.get_company_default_scheduled_minutes();';
  v_new := 'v_previous_minutes := public.get_company_scheduled_minutes_for_date(NEW.effective_from);';
  v_occurrences := (
    length(v_definition) - length(replace(v_definition, v_old, ''))
  ) / length(v_old);
  IF v_occurrences <> 1 THEN
    RAISE EXCEPTION 'Company-history duration patch failed: activation marker count=%', v_occurrences;
  END IF;
  v_definition := replace(v_definition, v_old, v_new);
  EXECUTE v_definition;

  SELECT pg_get_functiondef(
    'public.validate_employee_work_schedule_duration()'::regprocedure
  ) INTO v_definition;

  v_old := 'v_previous_minutes := public.get_company_default_scheduled_minutes();';
  v_new := 'v_previous_minutes := public.get_company_scheduled_minutes_for_date(v_effective_from);';
  v_occurrences := (
    length(v_definition) - length(replace(v_definition, v_old, ''))
  ) / length(v_old);
  IF v_occurrences <> 1 THEN
    RAISE EXCEPTION 'Company-history duration patch failed: deferred marker count=%', v_occurrences;
  END IF;
  v_definition := replace(v_definition, v_old, v_new);
  EXECUTE v_definition;
END;
$patch_duration_guards$;

REVOKE ALL ON FUNCTION public.guard_employee_work_schedule_activation_duration()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.validate_employee_work_schedule_duration()
  FROM PUBLIC, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 6. Least-privilege read RPC for a target date
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.get_company_work_schedule_for_date(p_target_date DATE)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_actor UUID := auth.uid();
  v_schedule public.hr_company_work_schedules%ROWTYPE;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.check_permission(v_actor, 'settings.read')
    OR public.check_permission(v_actor, 'settings.update')
    OR public.check_permission(v_actor, 'hr.employees.read')
    OR public.check_permission(v_actor, 'hr.attendance.read')
    OR public.check_permission(v_actor, 'hr.employees.edit')
  ) THEN
    RAISE EXCEPTION 'لا تملك صلاحية الاطلاع على جدول الشركة';
  END IF;

  SELECT * INTO v_schedule
  FROM public.hr_company_work_schedules s
  WHERE s.status IN ('active', 'retired')
    AND s.effective_range @> p_target_date;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'لا يوجد جدول شركة يغطي التاريخ المحدد';
  END IF;

  RETURN jsonb_build_object(
    'id', v_schedule.id,
    'effective_from', v_schedule.effective_from,
    'effective_to', v_schedule.effective_to,
    'status', v_schedule.status,
    'start_time', to_char(v_schedule.start_time, 'HH24:MI'),
    'end_time', to_char(v_schedule.end_time, 'HH24:MI'),
    'work_hours_per_day', v_schedule.scheduled_minutes / 60.0,
    'scheduled_minutes', v_schedule.scheduled_minutes,
    'weekly_off_day', v_schedule.weekly_off_day,
    'notes', v_schedule.notes,
    'is_system_baseline', v_schedule.is_system_baseline
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_company_work_schedule_for_date(DATE)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_company_work_schedule_for_date(DATE)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- 7. Atomic future company-version creation
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.save_company_work_schedule_version(
  p_effective_from DATE,
  p_start_time TEXT,
  p_end_time TEXT,
  p_weekly_off_day TEXT,
  p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
  v_actor UUID := auth.uid();
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_current public.hr_company_work_schedules%ROWTYPE;
  v_valid JSONB;
  v_new_id UUID;
  v_new_minutes INTEGER;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT public.check_permission(v_actor, 'settings.update') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تعديل إعدادات الشركة';
  END IF;

  IF p_effective_from IS NULL OR p_effective_from <= v_today THEN
    RAISE EXCEPTION 'تاريخ بدء جدول الشركة يجب أن يكون بعد اليوم بتوقيت القاهرة';
  END IF;

  v_valid := public.validate_hr_company_work_schedule_values(
    p_start_time,
    p_end_time,
    ((EXTRACT(EPOCH FROM ((v_valid->>'end_time')::TIME - (v_valid->>'start_time')::TIME)) / 3600))::TEXT,
    p_weekly_off_day
  );
END;
$function$;

-- Replace the temporary body above with a body that derives hours only after
-- strict time parsing. Keeping the public signature free from a duplicated hours
-- argument prevents callers from supplying two conflicting duration sources.
CREATE OR REPLACE FUNCTION public.save_company_work_schedule_version(
  p_effective_from DATE,
  p_start_time TEXT,
  p_end_time TEXT,
  p_weekly_off_day TEXT,
  p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
  v_actor UUID := auth.uid();
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_start_input TEXT := regexp_replace(COALESCE(btrim(p_start_time), ''), '\s+', '', 'g');
  v_end_input TEXT := regexp_replace(COALESCE(btrim(p_end_time), ''), '\s+', '', 'g');
  v_start TIME;
  v_end TIME;
  v_hours_text TEXT;
  v_valid JSONB;
  v_current public.hr_company_work_schedules%ROWTYPE;
  v_new_id UUID;
  v_new_minutes INTEGER;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT public.check_permission(v_actor, 'settings.update') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تعديل إعدادات الشركة';
  END IF;

  IF p_effective_from IS NULL OR p_effective_from <= v_today THEN
    RAISE EXCEPTION 'تاريخ بدء جدول الشركة يجب أن يكون بعد اليوم بتوقيت القاهرة';
  END IF;

  IF v_start_input ~ '^(?:[01][0-9]|2[0-3])[0-5][0-9]$' THEN
    v_start_input := substr(v_start_input, 1, 2) || ':' || substr(v_start_input, 3, 2);
  END IF;
  IF v_end_input ~ '^(?:[01][0-9]|2[0-3])[0-5][0-9]$' THEN
    v_end_input := substr(v_end_input, 1, 2) || ':' || substr(v_end_input, 3, 2);
  END IF;

  BEGIN
    v_start := v_start_input::TIME;
    v_end := v_end_input::TIME;
  EXCEPTION
    WHEN invalid_text_representation OR datetime_field_overflow THEN
      RAISE EXCEPTION 'مواعيد جدول الشركة غير صالحة';
  END;

  v_hours_text := (EXTRACT(EPOCH FROM (v_end - v_start)) / 3600)::NUMERIC::TEXT;
  v_valid := public.validate_hr_company_work_schedule_values(
    p_start_time,
    p_end_time,
    v_hours_text,
    p_weekly_off_day
  );
  v_new_minutes := (v_valid->>'scheduled_minutes')::INTEGER;

  PERFORM pg_advisory_xact_lock(hashtextextended('hr_company_work_schedules', 0));

  IF EXISTS (
    SELECT 1
    FROM public.hr_company_work_schedules s
    WHERE s.effective_from >= p_effective_from
  ) THEN
    RAISE EXCEPTION 'يوجد جدول شركة يبدأ في نفس التاريخ أو بعده؛ راجع التسلسل أولاً';
  END IF;

  SELECT * INTO v_current
  FROM public.hr_company_work_schedules s
  WHERE s.status = 'active'
    AND s.effective_range @> p_effective_from
  ORDER BY s.effective_from DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'تعذر تحديد نسخة جدول الشركة السابقة';
  END IF;

  IF v_current.scheduled_minutes IS DISTINCT FROM v_new_minutes
     AND EXTRACT(DAY FROM p_effective_from)::INTEGER <> 1 THEN
    RAISE EXCEPTION 'تغيير عدد ساعات يوم الشركة يجب أن يبدأ من أول يوم في الشهر';
  END IF;

  UPDATE public.hr_company_work_schedules
  SET status = 'retired',
      effective_to = p_effective_from - 1,
      retired_by = v_actor,
      retired_at = now(),
      updated_by = v_actor
  WHERE id = v_current.id;

  INSERT INTO public.hr_company_work_schedules (
    effective_from,
    effective_to,
    status,
    start_time,
    end_time,
    weekly_off_day,
    notes,
    is_system_baseline,
    activated_by,
    activated_at,
    created_by,
    updated_by
  ) VALUES (
    p_effective_from,
    NULL,
    'active',
    (v_valid->>'start_time')::TIME,
    (v_valid->>'end_time')::TIME,
    (v_valid->>'weekly_off_day')::public.hr_day_of_week,
    NULLIF(btrim(p_notes), ''),
    false,
    v_actor,
    now(),
    v_actor,
    v_actor
  )
  RETURNING id INTO v_new_id;

  INSERT INTO public.audit_logs (
    user_id,
    action,
    entity_type,
    entity_id,
    old_data,
    new_data,
    user_agent
  )
  SELECT
    v_actor,
    'company_work_schedule_version_saved',
    'hr_company_work_schedule',
    v_new_id,
    to_jsonb(v_current),
    to_jsonb(s),
    'EDARA company work schedule RPC'
  FROM public.hr_company_work_schedules s
  WHERE s.id = v_new_id;

  RETURN jsonb_build_object(
    'success', true,
    'schedule', public.get_company_work_schedule_for_date(p_effective_from),
    'previous_schedule_id', v_current.id,
    'feature_enabled', public.hr_employee_work_schedules_enabled()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.save_company_work_schedule_version(DATE, TEXT, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.save_company_work_schedule_version(DATE, TEXT, TEXT, TEXT, TEXT)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- 8. Future-version correction without rewriting effective dates/history
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.update_future_company_work_schedule_version(
  p_schedule_id UUID,
  p_start_time TEXT,
  p_end_time TEXT,
  p_weekly_off_day TEXT,
  p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_actor UUID := auth.uid();
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_target public.hr_company_work_schedules%ROWTYPE;
  v_previous public.hr_company_work_schedules%ROWTYPE;
  v_start_input TEXT := regexp_replace(COALESCE(btrim(p_start_time), ''), '\s+', '', 'g');
  v_end_input TEXT := regexp_replace(COALESCE(btrim(p_end_time), ''), '\s+', '', 'g');
  v_start TIME;
  v_end TIME;
  v_valid JSONB;
  v_new_minutes INTEGER;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT public.check_permission(v_actor, 'settings.update') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تعديل إعدادات الشركة';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('hr_company_work_schedules', 0));

  SELECT * INTO v_target
  FROM public.hr_company_work_schedules s
  WHERE s.id = p_schedule_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'نسخة جدول الشركة غير موجودة';
  END IF;

  IF v_target.status <> 'active'
     OR v_target.effective_from <= v_today
     OR v_target.is_system_baseline THEN
    RAISE EXCEPTION 'لا يمكن تعديل إلا نسخة شركة مستقبلية غير مفعلة زمنيًا';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_company_work_schedules s
    WHERE s.effective_from > v_target.effective_from
  ) THEN
    RAISE EXCEPTION 'لا يمكن تعديل نسخة ليست آخر نسخة في التسلسل';
  END IF;

  IF v_start_input ~ '^(?:[01][0-9]|2[0-3])[0-5][0-9]$' THEN
    v_start_input := substr(v_start_input, 1, 2) || ':' || substr(v_start_input, 3, 2);
  END IF;
  IF v_end_input ~ '^(?:[01][0-9]|2[0-3])[0-5][0-9]$' THEN
    v_end_input := substr(v_end_input, 1, 2) || ':' || substr(v_end_input, 3, 2);
  END IF;

  BEGIN
    v_start := v_start_input::TIME;
    v_end := v_end_input::TIME;
  EXCEPTION
    WHEN invalid_text_representation OR datetime_field_overflow THEN
      RAISE EXCEPTION 'مواعيد جدول الشركة غير صالحة';
  END;

  v_valid := public.validate_hr_company_work_schedule_values(
    p_start_time,
    p_end_time,
    (EXTRACT(EPOCH FROM (v_end - v_start)) / 3600)::NUMERIC::TEXT,
    p_weekly_off_day
  );
  v_new_minutes := (v_valid->>'scheduled_minutes')::INTEGER;

  SELECT * INTO v_previous
  FROM public.hr_company_work_schedules s
  WHERE s.status = 'retired'
    AND s.effective_to = v_target.effective_from - 1
  ORDER BY s.effective_from DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'تعذر تحديد نسخة الشركة السابقة';
  END IF;

  IF v_previous.scheduled_minutes IS DISTINCT FROM v_new_minutes
     AND EXTRACT(DAY FROM v_target.effective_from)::INTEGER <> 1 THEN
    RAISE EXCEPTION 'تغيير عدد ساعات يوم الشركة يجب أن يبدأ من أول يوم في الشهر';
  END IF;

  UPDATE public.hr_company_work_schedules
  SET start_time = (v_valid->>'start_time')::TIME,
      end_time = (v_valid->>'end_time')::TIME,
      weekly_off_day = (v_valid->>'weekly_off_day')::public.hr_day_of_week,
      notes = NULLIF(btrim(p_notes), ''),
      updated_by = v_actor,
      updated_at = now()
  WHERE id = v_target.id;

  INSERT INTO public.audit_logs (
    user_id,
    action,
    entity_type,
    entity_id,
    old_data,
    new_data,
    user_agent
  )
  SELECT
    v_actor,
    'company_work_schedule_future_version_updated',
    'hr_company_work_schedule',
    v_target.id,
    to_jsonb(v_target),
    to_jsonb(s),
    'EDARA company work schedule RPC'
  FROM public.hr_company_work_schedules s
  WHERE s.id = v_target.id;

  RETURN jsonb_build_object(
    'success', true,
    'schedule', public.get_company_work_schedule_for_date(v_target.effective_from),
    'feature_enabled', public.hr_employee_work_schedules_enabled()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.update_future_company_work_schedule_version(UUID, TEXT, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.update_future_company_work_schedule_version(UUID, TEXT, TEXT, TEXT, TEXT)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- 9. Protect enabled runtime from mutable legacy settings
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.guard_enabled_company_schedule_legacy_setting_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  IF NEW.key IN (
    'hr.work_start_time',
    'hr.work_end_time',
    'hr.work_hours_per_day',
    'hr.weekly_off_day'
  )
  AND NEW.value IS DISTINCT FROM OLD.value
  AND public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION
      'مواعيد الشركة مؤرخة بعد تفعيل جداول الموظفين؛ استخدم نسخة جدول شركة مستقبلية';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_enabled_company_schedule_legacy_setting_update()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_company_settings_schedule_history_guard
  ON public.company_settings;
CREATE TRIGGER trg_company_settings_schedule_history_guard
  BEFORE UPDATE OF value ON public.company_settings
  FOR EACH ROW
  WHEN (NEW.key IN (
    'hr.work_start_time',
    'hr.work_end_time',
    'hr.work_hours_per_day',
    'hr.weekly_off_day'
  ))
  EXECUTE FUNCTION public.guard_enabled_company_schedule_legacy_setting_update();

-- -----------------------------------------------------------------------------
-- 10. Assertions
-- -----------------------------------------------------------------------------
DO $assertions$
DECLARE
  v_baseline_count INTEGER;
  v_definition TEXT;
  v_current_minutes INTEGER;
  v_legacy_minutes INTEGER;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Company-history assertion failed: feature/readiness changed';
  END IF;

  SELECT count(*)::INTEGER INTO v_baseline_count
  FROM public.hr_company_work_schedules
  WHERE is_system_baseline = true;

  IF v_baseline_count <> 1
     OR (SELECT count(*) FROM public.hr_company_work_schedules) <> 1 THEN
    RAISE EXCEPTION 'Company-history assertion failed: expected exactly one baseline row';
  END IF;

  SELECT scheduled_minutes INTO v_current_minutes
  FROM public.hr_company_work_schedules
  WHERE is_system_baseline = true;

  v_legacy_minutes := public.get_company_default_scheduled_minutes();
  IF v_current_minutes IS DISTINCT FROM v_legacy_minutes THEN
    RAISE EXCEPTION
      'Company-history assertion failed: baseline minutes % differ from legacy %',
      v_current_minutes,
      v_legacy_minutes;
  END IF;

  SELECT pg_get_functiondef(
    'public.resolve_employee_work_schedule_core(uuid,date,boolean)'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%resolve_employee_work_schedule_core_pre_company_history_20260806%'
     OR v_definition NOT ILIKE '%resolve_company_work_schedule_version%'
     OR v_definition NOT ILIKE '%IF NOT COALESCE(p_use_custom, false)%' THEN
    RAISE EXCEPTION 'Company-history assertion failed: resolver dispatch is incomplete';
  END IF;

  SELECT pg_get_functiondef(
    'public.guard_employee_work_schedule_activation_duration()'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%get_company_scheduled_minutes_for_date(NEW.effective_from)%' THEN
    RAISE EXCEPTION 'Company-history assertion failed: activation duration baseline is not effective-dated';
  END IF;

  SELECT pg_get_functiondef(
    'public.validate_employee_work_schedule_duration()'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%get_company_scheduled_minutes_for_date(v_effective_from)%' THEN
    RAISE EXCEPTION 'Company-history assertion failed: deferred duration baseline is not effective-dated';
  END IF;

  IF has_function_privilege(
       'anon',
       'public.get_company_work_schedule_for_date(date)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'service_role',
       'public.save_company_work_schedule_version(date,text,text,text,text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated',
       'public.resolve_company_work_schedule_version(date)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Company-history assertion failed: internal/public grants are incorrect';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    WHERE t.tgrelid = 'public.company_settings'::regclass
      AND t.tgname = 'trg_company_settings_schedule_history_guard'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'Company-history assertion failed: legacy setting guard is missing';
  END IF;
END;
$assertions$;

COMMIT;
