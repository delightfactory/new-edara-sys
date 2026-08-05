-- =============================================================================
-- Employee Work Schedules — consistent daily duration verification
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '60s';

DO $verify$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Duration verify failed: feature/readiness must remain false';
  END IF;

  SELECT pg_get_functiondef('public.guard_employee_work_schedule_activation_duration()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%OLD.status = ''draft'' AND NEW.status = ''active''%'
     OR v_definition NOT ILIKE '%min(d.scheduled_minutes)%'
     OR v_definition NOT ILIKE '%max(d.scheduled_minutes)%'
     OR v_definition NOT ILIKE '%same duration%' THEN
    RAISE EXCEPTION 'Duration verify failed: activation guard is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.validate_employee_work_schedule_duration()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%v_day_count <> 7%'
     OR v_definition NOT ILIKE '%v_working_days <= 0%'
     OR v_definition NOT ILIKE '%v_min_minutes IS DISTINCT FROM v_max_minutes%' THEN
    RAISE EXCEPTION 'Duration verify failed: deferred final-state validator is incomplete';
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
    RAISE EXCEPTION 'Duration verify failed: activation duration trigger is missing';
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
    RAISE EXCEPTION 'Duration verify failed: deferred duration trigger is missing';
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
    'public.validate_employee_work_schedule_duration()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Duration verify failed: internal trigger helper is exposed';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'same_duration_per_schedule_required', true,
  'future_edit_final_state_protected', true,
  'runtime_data_changed', false
) AS consistent_duration_verification;

ROLLBACK;
