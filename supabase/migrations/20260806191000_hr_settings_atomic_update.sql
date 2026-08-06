-- =============================================================================
-- EDARA — Atomic HR settings update
--
-- Replaces the client-side series of independent UPDATE statements with one
-- validated transaction. It does not change any setting during migration.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  IF to_regclass('public.company_settings') IS NULL
     OR to_regclass('public.audit_logs') IS NULL
     OR to_regprocedure('public.check_permission(uuid,text)') IS NULL
     OR to_regprocedure('public.validate_hr_company_work_schedule_values(text,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'Atomic HR settings preflight failed: required objects are missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Atomic HR settings preflight failed: feature/readiness must remain false';
  END IF;

  IF to_regprocedure('public.update_hr_settings_atomic(jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'Atomic HR settings preflight failed: RPC already exists';
  END IF;
END;
$preflight$;

CREATE FUNCTION public.update_hr_settings_atomic(p_updates JSONB)
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
  v_schedule_valid JSONB;
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

  -- Build and validate the prospective company-time bundle. The caller may
  -- send all HR settings or only a subset; unchanged values come from storage.
  SELECT
    COALESCE(
      max(item->>'value') FILTER (WHERE btrim(item->>'key') = 'hr.work_start_time'),
      max(s.value) FILTER (WHERE s.key = 'hr.work_start_time')
    ),
    COALESCE(
      max(item->>'value') FILTER (WHERE btrim(item->>'key') = 'hr.work_end_time'),
      max(s.value) FILTER (WHERE s.key = 'hr.work_end_time')
    ),
    COALESCE(
      max(item->>'value') FILTER (WHERE btrim(item->>'key') = 'hr.work_hours_per_day'),
      max(s.value) FILTER (WHERE s.key = 'hr.work_hours_per_day')
    ),
    COALESCE(
      max(item->>'value') FILTER (WHERE btrim(item->>'key') = 'hr.weekly_off_day'),
      max(s.value) FILTER (WHERE s.key = 'hr.weekly_off_day')
    )
  INTO v_start_text, v_end_text, v_hours_text, v_off_text
  FROM public.company_settings s
  LEFT JOIN LATERAL jsonb_array_elements(p_updates) item
    ON btrim(item->>'key') = s.key
  WHERE s.key IN (
    'hr.work_start_time',
    'hr.work_end_time',
    'hr.work_hours_per_day',
    'hr.weekly_off_day'
  );

  v_schedule_valid := public.validate_hr_company_work_schedule_values(
    v_start_text,
    v_end_text,
    v_hours_text,
    v_off_text
  );

  -- Lock every target row in deterministic order before capturing old values.
  PERFORM 1
  FROM public.company_settings s
  JOIN (
    SELECT btrim(item->>'key') AS key
    FROM jsonb_array_elements(p_updates) item
  ) input ON input.key = s.key
  ORDER BY s.key
  FOR UPDATE;

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

  IF v_definition NOT ILIKE '%settings.update%'
     OR v_definition NOT ILIKE '%FOR UPDATE%'
     OR v_definition NOT ILIKE '%validate_hr_company_work_schedule_values%'
     OR v_definition NOT ILIKE '%hr_settings_updated_atomic%'
     OR v_definition NOT ILIKE '%updated_by = v_actor%' THEN
    RAISE EXCEPTION 'Atomic HR settings assertion failed: RPC contract is incomplete';
  END IF;

  IF NOT has_function_privilege(
       'authenticated',
       'public.update_hr_settings_atomic(jsonb)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'anon',
       'public.update_hr_settings_atomic(jsonb)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'service_role',
       'public.update_hr_settings_atomic(jsonb)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Atomic HR settings assertion failed: RPC grants are incorrect';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Atomic HR settings assertion failed: feature/readiness changed';
  END IF;
END;
$assertions$;

COMMIT;
