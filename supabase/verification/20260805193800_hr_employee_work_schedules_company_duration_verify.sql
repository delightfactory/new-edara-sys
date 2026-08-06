-- =============================================================================
-- Employee Work Schedules — company baseline duration verification
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '60s';

DO $verify$
DECLARE
  v_definition TEXT;
  v_minutes INTEGER;
  v_expected_minutes INTEGER;
  v_start_text TEXT;
  v_end_text TEXT;
  v_hours_text TEXT;
  v_start TIME;
  v_end TIME;
  v_hours NUMERIC;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Company-duration verify failed: feature/readiness must remain false';
  END IF;

  SELECT public.get_company_default_scheduled_minutes()
  INTO v_minutes;

  SELECT
    max(value) FILTER (WHERE key = 'hr.work_start_time'),
    max(value) FILTER (WHERE key = 'hr.work_end_time'),
    max(value) FILTER (WHERE key = 'hr.work_hours_per_day')
  INTO v_start_text, v_end_text, v_hours_text
  FROM public.company_settings
  WHERE key IN (
    'hr.work_start_time',
    'hr.work_end_time',
    'hr.work_hours_per_day'
  );

  IF v_start_text IS NULL OR v_end_text IS NULL OR v_hours_text IS NULL THEN
    RAISE EXCEPTION 'Company-duration verify failed: current company settings are incomplete';
  END IF;

  BEGIN
    v_start := btrim(v_start_text)::TIME;
    v_end := btrim(v_end_text)::TIME;
    v_hours := btrim(v_hours_text)::NUMERIC;
  EXCEPTION
    WHEN invalid_text_representation OR datetime_field_overflow THEN
      RAISE EXCEPTION 'Company-duration verify failed: current company settings are invalid';
  END;

  IF v_end <= v_start THEN
    RAISE EXCEPTION 'Company-duration verify failed: company window is not positive';
  END IF;

  v_expected_minutes := (EXTRACT(EPOCH FROM (v_end - v_start)) / 60)::INTEGER;

  IF v_expected_minutes <= 0
     OR v_hours * 60 <> v_expected_minutes
     OR v_minutes IS DISTINCT FROM v_expected_minutes THEN
    RAISE EXCEPTION
      'Company-duration verify failed: helper=% window=% configured=%',
      v_minutes,
      v_expected_minutes,
      v_hours * 60;
  END IF;

  SELECT pg_get_functiondef('public.get_company_default_scheduled_minutes()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%hr.work_start_time%'
     OR v_definition NOT ILIKE '%hr.work_end_time%'
     OR v_definition NOT ILIKE '%hr.work_hours_per_day%'
     OR v_definition NOT ILIKE '%v_hours * 60 <> v_window_minutes%' THEN
    RAISE EXCEPTION 'Company-duration verify failed: company minute helper is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.guard_employee_work_schedule_activation_duration()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%get_company_default_scheduled_minutes%'
     OR v_definition NOT ILIKE '%v_previous_source := ''company''%'
     OR v_definition NOT ILIKE '%EXTRACT(DAY FROM NEW.effective_from)%'
     OR v_definition NOT ILIKE '%first day of a month%' THEN
    RAISE EXCEPTION 'Company-duration verify failed: activation fallback boundary is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.validate_employee_work_schedule_duration()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%get_company_default_scheduled_minutes%'
     OR v_definition NOT ILIKE '%v_previous_source := ''company''%'
     OR v_definition NOT ILIKE '%EXTRACT(DAY FROM v_effective_from)%'
     OR v_definition NOT ILIKE '%outside a month boundary%' THEN
    RAISE EXCEPTION 'Company-duration verify failed: deferred fallback boundary is incomplete';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.get_company_default_scheduled_minutes()',
    'EXECUTE'
  ) OR has_function_privilege(
    'service_role',
    'public.get_company_default_scheduled_minutes()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Company-duration verify failed: internal helper is exposed';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'Company-duration verify failed: employee schedule rows were seeded';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'validated_company_minutes', public.get_company_default_scheduled_minutes(),
  'hardcoded_company_minutes', false,
  'first_custom_schedule_compares_to_company', true,
  'duration_change_requires_month_boundary', true,
  'internal_helper_exposed', false,
  'runtime_data_changed', false
) AS company_duration_verification;

ROLLBACK;
