-- =============================================================================
-- Employee Work Schedules — company baseline duration verification
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '60s';

DO $verify$
DECLARE
  v_definition TEXT;
  v_minutes INTEGER;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Company-duration verify failed: feature/readiness must remain false';
  END IF;

  SELECT public.get_company_default_scheduled_minutes()
  INTO v_minutes;

  IF v_minutes <> 480 THEN
    RAISE EXCEPTION 'Company-duration verify failed: expected 480 current company minutes, found %', v_minutes;
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
    RAISE EXCEPTION 'Company-duration verify failed: schedule rows were seeded';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'validated_company_minutes', public.get_company_default_scheduled_minutes(),
  'first_custom_schedule_compares_to_company', true,
  'duration_change_requires_month_boundary', true,
  'internal_helper_exposed', false,
  'runtime_data_changed', false
) AS company_duration_verification;

ROLLBACK;
