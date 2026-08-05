-- =============================================================================
-- Employee Work Schedules — final company baseline duration preflight
--
-- Read-only companion to the general and duration final preflights.
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '90s';

DO $verify$
DECLARE
  v_definition TEXT;
  v_minutes INTEGER;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Final company-duration preflight failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'Final company-duration preflight failed: simulation schedule rows remain';
  END IF;

  IF to_regprocedure('public.get_company_default_scheduled_minutes()') IS NULL THEN
    RAISE EXCEPTION 'Final company-duration preflight failed: company minute helper is missing';
  END IF;

  SELECT public.get_company_default_scheduled_minutes()
  INTO v_minutes;

  IF v_minutes <> 480 THEN
    RAISE EXCEPTION
      'Final company-duration preflight failed: reviewed company baseline changed from 480 to % minutes',
      v_minutes;
  END IF;

  SELECT pg_get_functiondef('public.guard_employee_work_schedule_activation_duration()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%get_company_default_scheduled_minutes%'
     OR v_definition NOT ILIKE '%v_previous_source := ''company''%'
     OR v_definition NOT ILIKE '%v_previous_source := ''employee''%'
     OR v_definition NOT ILIKE '%EXTRACT(DAY FROM NEW.effective_from)%'
     OR v_definition NOT ILIKE '%first day of a month%' THEN
    RAISE EXCEPTION 'Final company-duration preflight failed: activation baseline logic is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.validate_employee_work_schedule_duration()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%get_company_default_scheduled_minutes%'
     OR v_definition NOT ILIKE '%v_previous_source := ''company''%'
     OR v_definition NOT ILIKE '%v_previous_source := ''employee''%'
     OR v_definition NOT ILIKE '%EXTRACT(DAY FROM v_effective_from)%'
     OR v_definition NOT ILIKE '%outside a month boundary%' THEN
    RAISE EXCEPTION 'Final company-duration preflight failed: deferred baseline logic is incomplete';
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
    RAISE EXCEPTION 'Final company-duration preflight failed: internal helper is exposed';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'company_baseline_minutes', public.get_company_default_scheduled_minutes(),
  'first_custom_schedule_compares_to_company', true,
  'later_schedule_compares_to_employee_predecessor', true,
  'duration_change_requires_month_boundary', true,
  'simulation_rows_remaining', false,
  'production_activation_authorized', false
) AS final_company_duration_preflight;

ROLLBACK;
