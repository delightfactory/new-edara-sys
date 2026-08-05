-- =============================================================================
-- Employee Work Schedules — final duration and month-boundary preflight
--
-- Run after all schedule migrations and rollback-only simulations.
-- Read-only. Complements the general final disabled preflight.
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '90s';

DO $verify$
DECLARE
  v_definition TEXT;
  v_bad TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Final duration preflight failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'Final duration preflight failed: schedule simulation rows remain';
  END IF;

  WITH required(signature) AS (
    VALUES
      ('guard_employee_work_schedule_activation_duration()'),
      ('validate_employee_work_schedule_duration()')
  ), actual AS (
    SELECT p.oid::regprocedure::TEXT AS signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
  )
  SELECT string_agg(r.signature, ', ' ORDER BY r.signature)
  INTO v_bad
  FROM required r
  LEFT JOIN actual a USING (signature)
  WHERE a.signature IS NULL;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Final duration preflight failed: required helpers missing: %', v_bad;
  END IF;

  SELECT pg_get_functiondef('public.guard_employee_work_schedule_activation_duration()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%count(*) FILTER (WHERE d.is_working_day)%'
     OR v_definition NOT ILIKE '%min(d.scheduled_minutes)%'
     OR v_definition NOT ILIKE '%max(d.scheduled_minutes)%'
     OR v_definition NOT ILIKE '%s.effective_to = NEW.effective_from - 1%'
     OR v_definition NOT ILIKE '%EXTRACT(DAY FROM NEW.effective_from)%'
     OR v_definition NOT ILIKE '%first day of a month%' THEN
    RAISE EXCEPTION 'Final duration preflight failed: activation duration/month-boundary guard is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.validate_employee_work_schedule_duration()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%v_day_count <> 7%'
     OR v_definition NOT ILIKE '%v_working_days <= 0%'
     OR v_definition NOT ILIKE '%v_min_minutes IS DISTINCT FROM v_max_minutes%'
     OR v_definition NOT ILIKE '%s.effective_to = v_effective_from - 1%'
     OR v_definition NOT ILIKE '%EXTRACT(DAY FROM v_effective_from)%'
     OR v_definition NOT ILIKE '%outside a month boundary%' THEN
    RAISE EXCEPTION 'Final duration preflight failed: deferred duration/month-boundary validator is incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'hr_employee_work_schedules'
      AND t.tgname = 'trg_hr_employee_work_schedule_activation_duration'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'Final duration preflight failed: activation duration trigger is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'hr_employee_work_schedule_days'
      AND t.tgname = 'trg_hr_employee_work_schedule_duration_consistency'
      AND t.tgdeferrable
      AND t.tginitdeferred
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'Final duration preflight failed: deferred duration trigger is missing';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.guard_employee_work_schedule_activation_duration()',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.validate_employee_work_schedule_duration()',
    'EXECUTE'
  ) OR has_function_privilege(
    'service_role',
    'public.guard_employee_work_schedule_activation_duration()',
    'EXECUTE'
  ) OR has_function_privilege(
    'service_role',
    'public.validate_employee_work_schedule_duration()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Final duration preflight failed: internal duration helper is exposed';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'working_days_require_uniform_duration', true,
  'daily_duration_change_requires_month_boundary', true,
  'same_duration_time_change_allowed_on_future_date', true,
  'duration_guard_helpers_exposed', false,
  'simulation_rows_remaining', false,
  'production_activation_authorized', false
) AS final_duration_preflight;

ROLLBACK;
