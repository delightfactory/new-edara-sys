-- =============================================================================
-- EDARA — Align legacy company settings to today's versioned company schedule
--
-- Recovery path for delayed activation: if a prepared future company version has
-- already become effective while the feature is still off, copy that version's
-- values into legacy company_settings atomically. History itself is not changed.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  IF to_regclass('public.hr_company_work_schedules') IS NULL
     OR to_regprocedure('public.hr_company_work_schedule_activation_consistent()') IS NULL
     OR to_regprocedure('public.check_permission(uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'Current-version alignment preflight failed: required objects are missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Current-version alignment preflight failed: feature/readiness must remain false';
  END IF;

  IF to_regprocedure('public.align_legacy_company_settings_to_current_version()') IS NOT NULL THEN
    RAISE EXCEPTION 'Current-version alignment preflight failed: RPC already exists';
  END IF;
END;
$preflight$;

CREATE FUNCTION public.align_legacy_company_settings_to_current_version()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_actor UUID := auth.uid();
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_count INTEGER;
  v_current public.hr_company_work_schedules%ROWTYPE;
  v_old_data JSONB;
  v_new_data JSONB;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT public.check_permission(v_actor, 'settings.update') THEN
    RAISE EXCEPTION 'لا تملك صلاحية مصالحة إعدادات الشركة';
  END IF;

  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'لا تستخدم المصالحة بعد تفعيل الجداول المؤرخة';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('hr_company_work_schedules', 0));

  SELECT count(*)::INTEGER
  INTO v_count
  FROM public.hr_company_work_schedules s
  WHERE s.status IN ('active', 'retired')
    AND s.effective_range @> v_today;

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'تعذر تحديد نسخة شركة واحدة تغطي تاريخ اليوم';
  END IF;

  SELECT * INTO v_current
  FROM public.hr_company_work_schedules s
  WHERE s.status IN ('active', 'retired')
    AND s.effective_range @> v_today
  FOR SHARE;

  PERFORM 1
  FROM public.company_settings s
  WHERE s.key IN (
    'hr.work_start_time',
    'hr.work_end_time',
    'hr.work_hours_per_day',
    'hr.weekly_off_day'
  )
  ORDER BY s.key
  FOR UPDATE;

  IF (
    SELECT count(*)
    FROM public.company_settings s
    WHERE s.key IN (
      'hr.work_start_time',
      'hr.work_end_time',
      'hr.work_hours_per_day',
      'hr.weekly_off_day'
    )
  ) <> 4 THEN
    RAISE EXCEPTION 'إعدادات مواعيد الشركة القديمة غير مكتملة';
  END IF;

  SELECT jsonb_object_agg(s.key, s.value ORDER BY s.key)
  INTO v_old_data
  FROM public.company_settings s
  WHERE s.key IN (
    'hr.work_start_time',
    'hr.work_end_time',
    'hr.work_hours_per_day',
    'hr.weekly_off_day'
  );

  UPDATE public.company_settings s
  SET value = CASE s.key
        WHEN 'hr.work_start_time' THEN to_char(v_current.start_time, 'HH24:MI')
        WHEN 'hr.work_end_time' THEN to_char(v_current.end_time, 'HH24:MI')
        WHEN 'hr.work_hours_per_day' THEN (v_current.scheduled_minutes / 60.0)::TEXT
        WHEN 'hr.weekly_off_day' THEN v_current.weekly_off_day::TEXT
      END,
      updated_by = v_actor,
      updated_at = now()
  WHERE s.key IN (
    'hr.work_start_time',
    'hr.work_end_time',
    'hr.work_hours_per_day',
    'hr.weekly_off_day'
  );

  SELECT jsonb_object_agg(s.key, s.value ORDER BY s.key)
  INTO v_new_data
  FROM public.company_settings s
  WHERE s.key IN (
    'hr.work_start_time',
    'hr.work_end_time',
    'hr.work_hours_per_day',
    'hr.weekly_off_day'
  );

  IF NOT public.hr_company_work_schedule_activation_consistent() THEN
    RAISE EXCEPTION 'فشلت مصالحة إعدادات الشركة مع النسخة الحالية';
  END IF;

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
    'legacy_company_settings_aligned_to_version',
    'hr_company_work_schedule',
    v_current.id,
    v_old_data,
    v_new_data,
    'EDARA delayed-activation alignment RPC'
  );

  RETURN jsonb_build_object(
    'success', true,
    'company_schedule_id', v_current.id,
    'effective_from', v_current.effective_from,
    'settings', v_new_data,
    'company_history_consistent', true,
    'feature_enabled', false
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.align_legacy_company_settings_to_current_version()
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.align_legacy_company_settings_to_current_version()
  TO authenticated;

DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  SELECT pg_get_functiondef(
    'public.align_legacy_company_settings_to_current_version()'::regprocedure
  ) INTO v_definition;

  IF v_definition NOT ILIKE '%settings.update%'
     OR v_definition NOT ILIKE '%effective_range @> v_today%'
     OR v_definition NOT ILIKE '%FOR UPDATE%'
     OR v_definition NOT ILIKE '%legacy_company_settings_aligned_to_version%'
     OR v_definition NOT ILIKE '%hr_company_work_schedule_activation_consistent%' THEN
    RAISE EXCEPTION 'Current-version alignment assertion failed: RPC contract is incomplete';
  END IF;

  IF NOT has_function_privilege(
       'authenticated',
       'public.align_legacy_company_settings_to_current_version()',
       'EXECUTE'
     )
     OR has_function_privilege(
       'anon',
       'public.align_legacy_company_settings_to_current_version()',
       'EXECUTE'
     )
     OR has_function_privilege(
       'service_role',
       'public.align_legacy_company_settings_to_current_version()',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Current-version alignment assertion failed: RPC grants are incorrect';
  END IF;

  IF NOT public.hr_company_work_schedule_activation_consistent() THEN
    RAISE EXCEPTION 'Current-version alignment assertion failed: installed state is inconsistent';
  END IF;
END;
$assertions$;

COMMIT;
