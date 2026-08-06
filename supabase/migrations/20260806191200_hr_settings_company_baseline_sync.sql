-- =============================================================================
-- EDARA — Pre-activation company baseline synchronization
--
-- While no schedule facts have been prepared, an immediate legacy company-time
-- change may safely update the single technical baseline in the same transaction.
-- Once any company future version, employee schedule, or schedule snapshot exists,
-- legacy company-time edits are rejected and the future-version workflow is used.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '90s';

DO $preflight$
BEGIN
  IF to_regclass('public.hr_company_work_schedules') IS NULL
     OR to_regprocedure('public.update_hr_settings_atomic(jsonb)') IS NULL
     OR to_regprocedure('public.guard_hr_company_work_schedule_mutation()') IS NULL
     OR to_regprocedure('public.validate_hr_company_work_schedule_values(text,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'Baseline-sync preflight failed: company history/atomic settings are incomplete';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Baseline-sync preflight failed: feature/readiness must remain false';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.guard_hr_company_work_schedule_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $function$
DECLARE
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_business_fields_changed BOOLEAN;
  v_safe_baseline_correction BOOLEAN;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'active' OR NEW.effective_to IS NOT NULL THEN
      RAISE EXCEPTION 'A company schedule version must be inserted active and open-ended';
    END IF;
    RETURN NEW;
  END IF;

  v_business_fields_changed :=
    NEW.start_time IS DISTINCT FROM OLD.start_time
    OR NEW.end_time IS DISTINCT FROM OLD.end_time
    OR NEW.weekly_off_day IS DISTINCT FROM OLD.weekly_off_day
    OR NEW.notes IS DISTINCT FROM OLD.notes;

  IF OLD.status = 'retired' THEN
    IF NEW.effective_from IS DISTINCT FROM OLD.effective_from
       OR NEW.effective_to IS DISTINCT FROM OLD.effective_to
       OR NEW.status IS DISTINCT FROM OLD.status
       OR v_business_fields_changed
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
       OR v_business_fields_changed
       OR NEW.is_system_baseline IS DISTINCT FROM OLD.is_system_baseline
       OR NEW.activated_by IS DISTINCT FROM OLD.activated_by
       OR NEW.activated_at IS DISTINCT FROM OLD.activated_at
       OR NEW.retired_by IS NULL
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

  IF NOT v_business_fields_changed THEN
    RETURN NEW;
  END IF;

  v_safe_baseline_correction :=
    OLD.is_system_baseline
    AND NOT public.hr_employee_work_schedules_enabled()
    AND (SELECT count(*) FROM public.hr_company_work_schedules) = 1
    AND NOT EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
    AND NOT EXISTS (
      SELECT 1
      FROM public.hr_attendance_days
      WHERE schedule_snapshot_at IS NOT NULL
    );

  IF v_safe_baseline_correction THEN
    -- Notes are not part of automatic settings synchronization.
    IF NEW.notes IS DISTINCT FROM OLD.notes THEN
      RAISE EXCEPTION 'Technical baseline notes cannot be changed through settings synchronization';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.effective_from <= v_today OR OLD.is_system_baseline THEN
    RAISE EXCEPTION 'Only the latest future company schedule version may be corrected in place';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_hr_company_work_schedule_mutation()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.update_hr_settings_atomic(p_updates JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_actor UUID := auth.uid();
  v_input_count INTEGER;
  v_distinct_count INTEGER;
  v_missing_keys TEXT;
  v_bad_types TEXT;
  v_start_text TEXT;
  v_end_text TEXT;
  v_hours_text TEXT;
  v_off_text TEXT;
  v_current_valid JSONB;
  v_schedule_valid JSONB;
  v_schedule_changed BOOLEAN;
  v_baseline public.hr_company_work_schedules%ROWTYPE;
  v_old_data JSONB;
  v_new_data JSONB;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT public.check_permission(v_actor, 'settings.update') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تعديل إعدادات الشركة';
  END IF;

  IF p_updates IS NULL OR jsonb_typeof(p_updates) <> 'array' THEN
    RAISE EXCEPTION 'updates must be a JSON array';
  END IF;

  v_input_count := jsonb_array_length(p_updates);
  IF v_input_count <= 0 THEN
    RAISE EXCEPTION 'يجب إرسال إعداد واحد على الأقل';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_updates) item
    WHERE jsonb_typeof(item) <> 'object'
       OR NULLIF(btrim(item->>'key'), '') IS NULL
       OR NOT (item ? 'value')
       OR jsonb_typeof(item->'value') NOT IN ('string', 'number', 'boolean')
  ) THEN
    RAISE EXCEPTION 'كل تحديث يجب أن يحتوي على key وvalue نصية أو رقمية أو منطقية';
  END IF;

  SELECT count(DISTINCT btrim(item->>'key'))::INTEGER
  INTO v_distinct_count
  FROM jsonb_array_elements(p_updates) item;

  IF v_distinct_count <> v_input_count THEN
    RAISE EXCEPTION 'لا يجوز تكرار مفتاح إعداد داخل نفس العملية';
  END IF;

  SELECT string_agg(input.key, ', ' ORDER BY input.key)
  INTO v_missing_keys
  FROM (
    SELECT btrim(item->>'key') AS key
    FROM jsonb_array_elements(p_updates) item
  ) input
  LEFT JOIN public.company_settings s ON s.key = input.key
  WHERE s.key IS NULL OR s.category <> 'hr';

  IF v_missing_keys IS NOT NULL THEN
    RAISE EXCEPTION 'مفاتيح HR غير موجودة أو خارج النطاق: %', v_missing_keys;
  END IF;

  SELECT string_agg(s.key, ', ' ORDER BY s.key)
  INTO v_bad_types
  FROM public.company_settings s
  JOIN LATERAL (
    SELECT item->>'value' AS value
    FROM jsonb_array_elements(p_updates) item
    WHERE btrim(item->>'key') = s.key
  ) input ON true
  WHERE s.type = 'boolean'
    AND lower(btrim(input.value)) NOT IN ('true', 'false', '1', '0', 'on', 'off', 'yes', 'no');

  IF v_bad_types IS NOT NULL THEN
    RAISE EXCEPTION 'قيم منطقية غير صالحة: %', v_bad_types;
  END IF;

  BEGIN
    PERFORM btrim(input.value)::NUMERIC
    FROM public.company_settings s
    JOIN LATERAL (
      SELECT item->>'value' AS value
      FROM jsonb_array_elements(p_updates) item
      WHERE btrim(item->>'key') = s.key
    ) input ON true
    WHERE s.type = 'number';
  EXCEPTION
    WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RAISE EXCEPTION 'يوجد إعداد رقمي بقيمة غير صالحة';
  END;

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

  v_current_valid := public.validate_hr_company_work_schedule_values(
    v_start_text,
    v_end_text,
    v_hours_text,
    v_off_text
  );

  SELECT
    COALESCE(
      max(item->>'value') FILTER (WHERE btrim(item->>'key') = 'hr.work_start_time'),
      v_start_text
    ),
    COALESCE(
      max(item->>'value') FILTER (WHERE btrim(item->>'key') = 'hr.work_end_time'),
      v_end_text
    ),
    COALESCE(
      max(item->>'value') FILTER (WHERE btrim(item->>'key') = 'hr.work_hours_per_day'),
      v_hours_text
    ),
    COALESCE(
      max(item->>'value') FILTER (WHERE btrim(item->>'key') = 'hr.weekly_off_day'),
      v_off_text
    )
  INTO v_start_text, v_end_text, v_hours_text, v_off_text
  FROM jsonb_array_elements(p_updates) item;

  v_schedule_valid := public.validate_hr_company_work_schedule_values(
    v_start_text,
    v_end_text,
    v_hours_text,
    v_off_text
  );

  v_schedule_changed :=
    (v_current_valid->>'start_time') IS DISTINCT FROM (v_schedule_valid->>'start_time')
    OR (v_current_valid->>'end_time') IS DISTINCT FROM (v_schedule_valid->>'end_time')
    OR (v_current_valid->>'scheduled_minutes') IS DISTINCT FROM (v_schedule_valid->>'scheduled_minutes')
    OR (v_current_valid->>'weekly_off_day') IS DISTINCT FROM (v_schedule_valid->>'weekly_off_day');

  PERFORM 1
  FROM public.company_settings s
  JOIN (
    SELECT btrim(item->>'key') AS key
    FROM jsonb_array_elements(p_updates) item
  ) input ON input.key = s.key
  ORDER BY s.key
  FOR UPDATE;

  IF v_schedule_changed THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('hr_company_work_schedules', 0));

    IF public.hr_employee_work_schedules_enabled() THEN
      RAISE EXCEPTION 'بعد التفعيل، عدّل مواعيد الشركة من خلال نسخة مستقبلية';
    END IF;

    SELECT * INTO v_baseline
    FROM public.hr_company_work_schedules s
    WHERE s.is_system_baseline = true
      AND s.status = 'active'
      AND s.effective_to IS NULL
    FOR UPDATE;

    IF NOT FOUND
       OR (SELECT count(*) FROM public.hr_company_work_schedules) <> 1
       OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
       OR EXISTS (
         SELECT 1 FROM public.hr_attendance_days
         WHERE schedule_snapshot_at IS NOT NULL
       ) THEN
      RAISE EXCEPTION
        'بدأ تجهيز الجداول المؤرخة؛ استخدم نسخة جدول شركة مستقبلية بدل تعديل الحقول القديمة';
    END IF;
  END IF;

  SELECT jsonb_object_agg(s.key, s.value ORDER BY s.key)
  INTO v_old_data
  FROM public.company_settings s
  JOIN (
    SELECT btrim(item->>'key') AS key
    FROM jsonb_array_elements(p_updates) item
  ) input ON input.key = s.key;

  WITH normalized AS (
    SELECT
      s.key,
      CASE
        WHEN s.key = 'hr.work_start_time' THEN v_schedule_valid->>'start_time'
        WHEN s.key = 'hr.work_end_time' THEN v_schedule_valid->>'end_time'
        WHEN s.key = 'hr.work_hours_per_day' THEN v_schedule_valid->>'work_hours_per_day'
        WHEN s.key = 'hr.weekly_off_day' THEN v_schedule_valid->>'weekly_off_day'
        WHEN s.type = 'boolean' THEN
          CASE
            WHEN lower(btrim(item->>'value')) IN ('true', '1', 'on', 'yes') THEN 'true'
            ELSE 'false'
          END
        ELSE btrim(item->>'value')
      END AS value
    FROM public.company_settings s
    JOIN LATERAL jsonb_array_elements(p_updates) item
      ON btrim(item->>'key') = s.key
  )
  UPDATE public.company_settings s
  SET value = normalized.value,
      updated_by = v_actor,
      updated_at = now()
  FROM normalized
  WHERE s.key = normalized.key;

  IF v_schedule_changed THEN
    UPDATE public.hr_company_work_schedules
    SET start_time = (v_schedule_valid->>'start_time')::TIME,
        end_time = (v_schedule_valid->>'end_time')::TIME,
        weekly_off_day = (v_schedule_valid->>'weekly_off_day')::public.hr_day_of_week,
        updated_by = v_actor
    WHERE id = v_baseline.id;
  END IF;

  SELECT jsonb_object_agg(s.key, s.value ORDER BY s.key)
  INTO v_new_data
  FROM public.company_settings s
  JOIN (
    SELECT btrim(item->>'key') AS key
    FROM jsonb_array_elements(p_updates) item
  ) input ON input.key = s.key;

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
    'hr_settings_updated_atomic',
    'company_settings',
    NULL,
    v_old_data,
    v_new_data,
    'EDARA atomic HR settings RPC'
  );

  RETURN jsonb_build_object(
    'success', true,
    'updated_count', v_input_count,
    'settings', v_new_data,
    'company_schedule_changed', v_schedule_changed,
    'company_baseline_synchronized', v_schedule_changed,
    'feature_enabled', public.hr_employee_work_schedules_enabled(),
    'company_history_consistent', public.hr_company_work_schedule_activation_consistent()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.update_hr_settings_atomic(JSONB)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.update_hr_settings_atomic(JSONB)
  TO authenticated;

DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  SELECT pg_get_functiondef('public.update_hr_settings_atomic(jsonb)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%v_schedule_changed%'
     OR v_definition NOT ILIKE '%pg_advisory_xact_lock%'
     OR v_definition NOT ILIKE '%company_baseline_synchronized%'
     OR v_definition NOT ILIKE '%بدأ تجهيز الجداول المؤرخة%'
     OR v_definition NOT ILIKE '%UPDATE public.hr_company_work_schedules%' THEN
    RAISE EXCEPTION 'Baseline-sync assertion failed: atomic synchronization is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.guard_hr_company_work_schedule_mutation()'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%v_safe_baseline_correction%'
     OR v_definition NOT ILIKE '%count(*) FROM public.hr_company_work_schedules%'
     OR v_definition NOT ILIKE '%NOT EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)%' THEN
    RAISE EXCEPTION 'Baseline-sync assertion failed: lifecycle exception is not narrowly guarded';
  END IF;

  IF NOT public.hr_company_work_schedule_activation_consistent() THEN
    RAISE EXCEPTION 'Baseline-sync assertion failed: installed state is inconsistent';
  END IF;
END;
$assertions$;

COMMIT;
