-- =============================================================================
-- EDARA — Company schedule history hardening
--
-- Adds lifecycle immutability, protects future company changes from invalidating
-- employee-schedule transitions or established company snapshots, and exposes a
-- read-only activation-consistency diagnostic. Readiness itself remains FALSE.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

DO $preflight$
BEGIN
  IF to_regclass('public.hr_company_work_schedules') IS NULL
     OR to_regprocedure('public.validate_hr_company_work_schedule_values(text,text,text,text)') IS NULL
     OR to_regprocedure('public.save_company_work_schedule_version(date,text,text,text,text)') IS NULL
     OR to_regprocedure('public.update_future_company_work_schedule_version(uuid,text,text,text,text)') IS NULL
     OR to_regprocedure('public.resolve_company_work_schedule_for_employee(uuid,date)') IS NULL THEN
    RAISE EXCEPTION 'Company-history hardening preflight failed: company history is incomplete';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Company-history hardening preflight failed: feature/readiness must remain false';
  END IF;

  IF to_regprocedure('public.guard_hr_company_work_schedule_mutation()') IS NOT NULL
     OR to_regprocedure('public.guard_hr_company_work_schedule_delete()') IS NOT NULL
     OR to_regprocedure('public.assert_company_work_schedule_change_safe(date,date,integer,uuid)') IS NOT NULL
     OR to_regprocedure('public.hr_company_work_schedule_activation_consistent()') IS NOT NULL THEN
    RAISE EXCEPTION 'Company-history hardening preflight failed: target helpers already exist';
  END IF;
END;
$preflight$;

-- -----------------------------------------------------------------------------
-- 1. Company schedule lifecycle protection
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.guard_hr_company_work_schedule_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $function$
DECLARE
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'active' OR NEW.effective_to IS NOT NULL THEN
      RAISE EXCEPTION 'A company schedule version must be inserted active and open-ended';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status = 'retired' THEN
    IF NEW.effective_from IS DISTINCT FROM OLD.effective_from
       OR NEW.effective_to IS DISTINCT FROM OLD.effective_to
       OR NEW.status IS DISTINCT FROM OLD.status
       OR NEW.start_time IS DISTINCT FROM OLD.start_time
       OR NEW.end_time IS DISTINCT FROM OLD.end_time
       OR NEW.weekly_off_day IS DISTINCT FROM OLD.weekly_off_day
       OR NEW.notes IS DISTINCT FROM OLD.notes
       OR NEW.is_system_baseline IS DISTINCT FROM OLD.is_system_baseline
       OR NEW.activated_by IS DISTINCT FROM OLD.activated_by
       OR NEW.activated_at IS DISTINCT FROM OLD.activated_at
       OR NEW.retired_by IS DISTINCT FROM OLD.retired_by
       OR NEW.retired_at IS DISTINCT FROM OLD.retired_at
       OR NEW.created_by IS DISTINCT FROM OLD.created_by
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'A retired company schedule version is immutable';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.status = 'retired' THEN
    IF NEW.effective_from IS DISTINCT FROM OLD.effective_from
       OR NEW.effective_to IS NULL
       OR NEW.effective_to < NEW.effective_from
       OR NEW.start_time IS DISTINCT FROM OLD.start_time
       OR NEW.end_time IS DISTINCT FROM OLD.end_time
       OR NEW.weekly_off_day IS DISTINCT FROM OLD.weekly_off_day
       OR NEW.notes IS DISTINCT FROM OLD.notes
       OR NEW.is_system_baseline IS DISTINCT FROM OLD.is_system_baseline
       OR NEW.activated_by IS DISTINCT FROM OLD.activated_by
       OR NEW.activated_at IS DISTINCT FROM OLD.activated_at
       OR NEW.retired_at IS NULL THEN
      RAISE EXCEPTION 'Invalid active-to-retired company schedule transition';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.status <> 'active'
     OR NEW.effective_from IS DISTINCT FROM OLD.effective_from
     OR NEW.effective_to IS NOT NULL
     OR NEW.is_system_baseline IS DISTINCT FROM OLD.is_system_baseline
     OR NEW.activated_by IS DISTINCT FROM OLD.activated_by
     OR NEW.activated_at IS DISTINCT FROM OLD.activated_at
     OR NEW.retired_by IS NOT NULL
     OR NEW.retired_at IS NOT NULL
     OR NEW.created_by IS DISTINCT FROM OLD.created_by
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Unsupported company schedule mutation';
  END IF;

  IF OLD.is_system_baseline OR OLD.effective_from <= v_today THEN
    IF NEW.start_time IS DISTINCT FROM OLD.start_time
       OR NEW.end_time IS DISTINCT FROM OLD.end_time
       OR NEW.weekly_off_day IS DISTINCT FROM OLD.weekly_off_day
       OR NEW.notes IS DISTINCT FROM OLD.notes THEN
      RAISE EXCEPTION 'Only the latest future company schedule version may be corrected in place';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_hr_company_work_schedule_mutation()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_hr_company_work_schedules_mutation_guard
  ON public.hr_company_work_schedules;
CREATE TRIGGER trg_hr_company_work_schedules_mutation_guard
  BEFORE INSERT OR UPDATE ON public.hr_company_work_schedules
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_hr_company_work_schedule_mutation();

CREATE FUNCTION public.guard_hr_company_work_schedule_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  RAISE EXCEPTION 'Company work schedule history cannot be deleted';
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_hr_company_work_schedule_delete()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_hr_company_work_schedules_delete_guard
  ON public.hr_company_work_schedules;
CREATE TRIGGER trg_hr_company_work_schedules_delete_guard
  BEFORE DELETE ON public.hr_company_work_schedules
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_hr_company_work_schedule_delete();

-- -----------------------------------------------------------------------------
-- 2. A company change may not contradict already-prepared facts
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.assert_company_work_schedule_change_safe(
  p_effective_from DATE,
  p_effective_to DATE,
  p_new_scheduled_minutes INTEGER,
  p_excluded_company_schedule_id UUID DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_conflict RECORD;
BEGIN
  IF p_effective_from IS NULL
     OR p_new_scheduled_minutes IS NULL
     OR p_new_scheduled_minutes <= 0 THEN
    RAISE EXCEPTION 'Company schedule safety check requires a valid date and duration';
  END IF;

  -- A complete company snapshot is an established fact and must not be put
  -- under a newly interpreted company version.
  SELECT ad.id, ad.employee_id, ad.shift_date
  INTO v_conflict
  FROM public.hr_attendance_days ad
  WHERE ad.schedule_snapshot_at IS NOT NULL
    AND ad.schedule_source = 'company'
    AND ad.shift_date >= p_effective_from
    AND (p_effective_to IS NULL OR ad.shift_date <= p_effective_to)
  ORDER BY ad.shift_date, ad.id
  LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION
      'Company schedule change conflicts with established attendance snapshot % for employee % on %',
      v_conflict.id,
      v_conflict.employee_id,
      v_conflict.shift_date;
  END IF;

  -- Only an employee schedule with no immediately preceding employee version
  -- uses the company duration as its transition baseline.
  SELECT
    s.id AS schedule_id,
    s.employee_id,
    s.effective_from,
    min(d.scheduled_minutes) FILTER (WHERE d.is_working_day) AS employee_minutes
  INTO v_conflict
  FROM public.hr_employee_work_schedules s
  JOIN public.hr_employee_work_schedule_days d ON d.schedule_id = s.id
  WHERE s.status IN ('active', 'retired')
    AND s.effective_from >= p_effective_from
    AND (p_effective_to IS NULL OR s.effective_from <= p_effective_to)
    AND NOT EXISTS (
      SELECT 1
      FROM public.hr_employee_work_schedules previous
      WHERE previous.employee_id = s.employee_id
        AND previous.status = 'retired'
        AND previous.effective_to = s.effective_from - 1
    )
  GROUP BY s.id, s.employee_id, s.effective_from
  HAVING min(d.scheduled_minutes) FILTER (WHERE d.is_working_day)
           IS DISTINCT FROM p_new_scheduled_minutes
     AND EXTRACT(DAY FROM s.effective_from)::INTEGER <> 1
  ORDER BY s.effective_from, s.id
  LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION
      'Company schedule change would invalidate employee schedule % transition on % (% vs % minutes)',
      v_conflict.schedule_id,
      v_conflict.effective_from,
      v_conflict.employee_minutes,
      p_new_scheduled_minutes;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.assert_company_work_schedule_change_safe(DATE, DATE, INTEGER, UUID)
  FROM PUBLIC, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3. Replace company mutation RPCs with guarded final bodies
-- -----------------------------------------------------------------------------
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
  v_valid JSONB;
  v_current public.hr_company_work_schedules%ROWTYPE;
  v_new public.hr_company_work_schedules%ROWTYPE;
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

  IF (p_notes IS NOT NULL AND length(btrim(p_notes)) > 500) THEN
    RAISE EXCEPTION 'ملاحظات جدول الشركة لا يمكن أن تتجاوز 500 حرف';
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

  IF v_current.scheduled_minutes IS DISTINCT FROM (v_valid->>'scheduled_minutes')::INTEGER
     AND EXTRACT(DAY FROM p_effective_from)::INTEGER <> 1 THEN
    RAISE EXCEPTION 'تغيير عدد ساعات يوم الشركة يجب أن يبدأ من أول يوم في الشهر';
  END IF;

  PERFORM public.assert_company_work_schedule_change_safe(
    p_effective_from,
    NULL,
    (v_valid->>'scheduled_minutes')::INTEGER,
    NULL
  );

  UPDATE public.hr_company_work_schedules
  SET status = 'retired',
      effective_to = p_effective_from - 1,
      retired_by = v_actor,
      retired_at = now(),
      updated_by = v_actor
  WHERE id = v_current.id;

  INSERT INTO public.hr_company_work_schedules (
    effective_from,
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
  RETURNING * INTO v_new;

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
    'company_work_schedule_version_saved',
    'hr_company_work_schedule',
    v_new.id,
    to_jsonb(v_current),
    to_jsonb(v_new),
    'EDARA company work schedule RPC'
  );

  RETURN jsonb_build_object(
    'success', true,
    'schedule', jsonb_build_object(
      'id', v_new.id,
      'effective_from', v_new.effective_from,
      'effective_to', v_new.effective_to,
      'status', v_new.status,
      'start_time', to_char(v_new.start_time, 'HH24:MI'),
      'end_time', to_char(v_new.end_time, 'HH24:MI'),
      'work_hours_per_day', v_new.scheduled_minutes / 60.0,
      'scheduled_minutes', v_new.scheduled_minutes,
      'weekly_off_day', v_new.weekly_off_day,
      'notes', v_new.notes,
      'is_system_baseline', v_new.is_system_baseline
    ),
    'previous_schedule_id', v_current.id,
    'feature_enabled', public.hr_employee_work_schedules_enabled()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.save_company_work_schedule_version(DATE, TEXT, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.save_company_work_schedule_version(DATE, TEXT, TEXT, TEXT, TEXT)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.update_future_company_work_schedule_version(
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
  v_updated public.hr_company_work_schedules%ROWTYPE;
  v_start_input TEXT := regexp_replace(COALESCE(btrim(p_start_time), ''), '\s+', '', 'g');
  v_end_input TEXT := regexp_replace(COALESCE(btrim(p_end_time), ''), '\s+', '', 'g');
  v_start TIME;
  v_end TIME;
  v_valid JSONB;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT public.check_permission(v_actor, 'settings.update') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تعديل إعدادات الشركة';
  END IF;

  IF p_notes IS NOT NULL AND length(btrim(p_notes)) > 500 THEN
    RAISE EXCEPTION 'ملاحظات جدول الشركة لا يمكن أن تتجاوز 500 حرف';
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

  SELECT * INTO v_previous
  FROM public.hr_company_work_schedules s
  WHERE s.status = 'retired'
    AND s.effective_to = v_target.effective_from - 1
  ORDER BY s.effective_from DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'تعذر تحديد نسخة الشركة السابقة';
  END IF;

  IF v_previous.scheduled_minutes IS DISTINCT FROM (v_valid->>'scheduled_minutes')::INTEGER
     AND EXTRACT(DAY FROM v_target.effective_from)::INTEGER <> 1 THEN
    RAISE EXCEPTION 'تغيير عدد ساعات يوم الشركة يجب أن يبدأ من أول يوم في الشهر';
  END IF;

  PERFORM public.assert_company_work_schedule_change_safe(
    v_target.effective_from,
    v_target.effective_to,
    (v_valid->>'scheduled_minutes')::INTEGER,
    v_target.id
  );

  UPDATE public.hr_company_work_schedules
  SET start_time = (v_valid->>'start_time')::TIME,
      end_time = (v_valid->>'end_time')::TIME,
      weekly_off_day = (v_valid->>'weekly_off_day')::public.hr_day_of_week,
      notes = NULLIF(btrim(p_notes), ''),
      updated_by = v_actor
  WHERE id = v_target.id
  RETURNING * INTO v_updated;

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
    'company_work_schedule_future_version_updated',
    'hr_company_work_schedule',
    v_target.id,
    to_jsonb(v_target),
    to_jsonb(v_updated),
    'EDARA company work schedule RPC'
  );

  RETURN jsonb_build_object(
    'success', true,
    'schedule', jsonb_build_object(
      'id', v_updated.id,
      'effective_from', v_updated.effective_from,
      'effective_to', v_updated.effective_to,
      'status', v_updated.status,
      'start_time', to_char(v_updated.start_time, 'HH24:MI'),
      'end_time', to_char(v_updated.end_time, 'HH24:MI'),
      'work_hours_per_day', v_updated.scheduled_minutes / 60.0,
      'scheduled_minutes', v_updated.scheduled_minutes,
      'weekly_off_day', v_updated.weekly_off_day,
      'notes', v_updated.notes,
      'is_system_baseline', v_updated.is_system_baseline
    ),
    'feature_enabled', public.hr_employee_work_schedules_enabled()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.update_future_company_work_schedule_version(UUID, TEXT, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.update_future_company_work_schedule_version(UUID, TEXT, TEXT, TEXT, TEXT)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- 4. Activation consistency diagnostic; it never changes readiness or settings
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.hr_company_work_schedule_activation_consistent()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_start_text TEXT;
  v_end_text TEXT;
  v_hours_text TEXT;
  v_off_text TEXT;
  v_valid JSONB;
  v_current public.hr_company_work_schedules%ROWTYPE;
  v_version_count INTEGER;
  v_active_count INTEGER;
  v_gap_count INTEGER;
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

  SELECT count(*)::INTEGER
  INTO v_version_count
  FROM public.hr_company_work_schedules s
  WHERE s.status IN ('active', 'retired')
    AND s.effective_range @> v_today;

  IF v_version_count <> 1 THEN
    RETURN false;
  END IF;

  SELECT * INTO v_current
  FROM public.hr_company_work_schedules s
  WHERE s.status IN ('active', 'retired')
    AND s.effective_range @> v_today;

  IF to_char(v_current.start_time, 'HH24:MI') IS DISTINCT FROM (v_valid->>'start_time')
     OR to_char(v_current.end_time, 'HH24:MI') IS DISTINCT FROM (v_valid->>'end_time')
     OR v_current.scheduled_minutes IS DISTINCT FROM (v_valid->>'scheduled_minutes')::INTEGER
     OR v_current.weekly_off_day::TEXT IS DISTINCT FROM (v_valid->>'weekly_off_day') THEN
    RETURN false;
  END IF;

  SELECT count(*)::INTEGER
  INTO v_active_count
  FROM public.hr_company_work_schedules s
  WHERE s.status = 'active' AND s.effective_to IS NULL;

  IF v_active_count <> 1 THEN
    RETURN false;
  END IF;

  WITH ordered AS (
    SELECT
      s.effective_from,
      s.effective_to,
      lag(s.effective_to) OVER (ORDER BY s.effective_from) AS previous_to
    FROM public.hr_company_work_schedules s
    WHERE s.status IN ('active', 'retired')
  )
  SELECT count(*)::INTEGER
  INTO v_gap_count
  FROM ordered
  WHERE previous_to IS NOT NULL
    AND effective_from <> previous_to + 1;

  RETURN v_gap_count = 0;
EXCEPTION
  WHEN OTHERS THEN
    RETURN false;
END;
$function$;

REVOKE ALL ON FUNCTION public.hr_company_work_schedule_activation_consistent()
  FROM PUBLIC, anon, authenticated, service_role;

DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Company-history hardening assertion failed: feature/readiness changed';
  END IF;

  IF NOT public.hr_company_work_schedule_activation_consistent() THEN
    RAISE EXCEPTION 'Company-history hardening assertion failed: installed baseline is not activation-consistent';
  END IF;

  SELECT pg_get_functiondef(
    'public.save_company_work_schedule_version(date,text,text,text,text)'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%assert_company_work_schedule_change_safe%'
     OR v_definition NOT ILIKE '%settings.update%'
     OR v_definition NOT ILIKE '%first day of the month%' THEN
    -- English marker above is intentionally broad only for structural review;
    -- the actual Arabic exception remains the user-facing contract.
    IF v_definition NOT ILIKE '%أول يوم في الشهر%' THEN
      RAISE EXCEPTION 'Company-history hardening assertion failed: save RPC guard is incomplete';
    END IF;
  END IF;

  SELECT pg_get_functiondef(
    'public.update_future_company_work_schedule_version(uuid,text,text,text,text)'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%assert_company_work_schedule_change_safe%'
     OR v_definition NOT ILIKE '%v_target.effective_from <= v_today%'
     OR v_definition NOT ILIKE '%RETURNING * INTO v_updated%' THEN
    RAISE EXCEPTION 'Company-history hardening assertion failed: update RPC guard is incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid = 'public.hr_company_work_schedules'::regclass
      AND t.tgname = 'trg_hr_company_work_schedules_mutation_guard'
      AND NOT t.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid = 'public.hr_company_work_schedules'::regclass
      AND t.tgname = 'trg_hr_company_work_schedules_delete_guard'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'Company-history hardening assertion failed: lifecycle triggers are incomplete';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.assert_company_work_schedule_change_safe(date,date,integer,uuid)',
    'EXECUTE'
  ) OR has_function_privilege(
    'service_role',
    'public.hr_company_work_schedule_activation_consistent()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Company-history hardening assertion failed: internal helpers are exposed';
  END IF;
END;
$assertions$;

COMMIT;
