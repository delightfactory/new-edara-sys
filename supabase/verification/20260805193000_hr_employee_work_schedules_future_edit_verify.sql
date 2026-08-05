-- =============================================================================
-- Employee Work Schedules — future-edit structural verification
--
-- Behavioral edit scenarios are covered by the rollback-only M2 simulation.
-- This file performs only read-only structural and privilege checks.
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '60s';

DO $verify$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Future-edit verify failed: feature/readiness must remain false';
  END IF;

  SELECT pg_get_functiondef('public.update_future_employee_work_schedule(uuid,jsonb,text)'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%hr.employees.edit%'
     OR v_definition NOT ILIKE '%status <> ''active''%'
     OR v_definition NOT ILIKE '%effective_from <= v_cairo_today%'
     OR v_definition NOT ILIKE '%hr_attendance_days%'
     OR v_definition NOT ILIKE '%pg_advisory_xact_lock%'
     OR v_definition NOT ILIKE '%jsonb_array_length(p_days) <> 7%'
     OR v_definition NOT ILIKE '%v_working_day_count <= 0%'
     OR v_definition NOT ILIKE '%employee_work_schedule_future_updated%' THEN
    RAISE EXCEPTION 'Future-edit verify failed: update RPC guard or audit contract is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.guard_employee_work_schedule_day_mutation()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%edara.employee_work_schedule_edit_id%'
     OR v_definition NOT ILIKE '%effective_from > v_cairo_today%'
     OR v_definition NOT ILIKE '%hr.employees.edit%'
     OR v_definition NOT ILIKE '%hr_attendance_days%' THEN
    RAISE EXCEPTION 'Future-edit verify failed: day mutation trigger guard is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.guard_employee_work_schedule_header()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%exactly 7 weekday rows%'
     OR v_definition NOT ILIKE '%at least one working day%'
     OR v_definition NOT ILIKE '%active schedule cannot be edited in place%' THEN
    RAISE EXCEPTION 'Future-edit verify failed: activation/header guard is incomplete';
  END IF;

  IF NOT has_function_privilege(
    'authenticated',
    'public.update_future_employee_work_schedule(uuid,jsonb,text)',
    'EXECUTE'
  ) OR has_function_privilege(
    'anon',
    'public.update_future_employee_work_schedule(uuid,jsonb,text)',
    'EXECUTE'
  ) OR has_function_privilege(
    'service_role',
    'public.update_future_employee_work_schedule(uuid,jsonb,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Future-edit verify failed: RPC grants are incorrect';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'Future-edit verify failed: verification expects no seeded schedules';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'future_only_edit', true,
  'attendance_referenced_edit_blocked', true,
  'zero_workday_schedule_blocked', true,
  'audit_required', true,
  'runtime_data_changed', false
) AS future_edit_verification;

ROLLBACK;
