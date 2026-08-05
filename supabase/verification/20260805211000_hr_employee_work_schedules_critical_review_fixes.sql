-- =============================================================================
-- Employee Work Schedules — critical review fix verification
--
-- Safe structural verification. It performs no writes and does not enable the
-- feature. Run after all schedule migrations including 20260805210000.
-- =============================================================================

BEGIN;
SET LOCAL statement_timeout = '60s';

DO $verify$
DECLARE
  v_definition TEXT;
  v_predicate_count INTEGER;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Verification failed: feature/readiness must remain false';
  END IF;

  SELECT pg_get_functiondef(
    'public.upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)'::regprocedure
  ) INTO v_definition;

  IF v_definition NOT ILIKE '%v_actor UUID := auth.uid()%'
     OR v_definition ILIKE '%check_permission(COALESCE(p_user_id, auth.uid())%'
     OR v_definition NOT ILIKE '%upsert_attendance_and_reprocess_scheduled%v_actor%'
     OR v_definition NOT ILIKE '%upsert_attendance_and_reprocess_legacy_20260805%v_actor%' THEN
    RAISE EXCEPTION 'Verification failed: attendance actor is not bound to the authenticated caller';
  END IF;

  IF has_function_privilege(
       'anon',
       'public.upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)',
       'EXECUTE'
     )
     OR has_function_privilege('anon', 'public.mark_daily_absences(date)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.run_auto_checkout(date)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.scan_attendance_daily_review_alerts()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.run_attendance_operational_scan()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.notify_absent_employees()', 'EXECUTE') THEN
    RAISE EXCEPTION 'Verification failed: anonymous attendance mutation access remains';
  END IF;

  IF has_function_privilege(
       'authenticated',
       'public.process_attendance_penalties(uuid)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated',
       'public.settle_attendance_day_against_leave(uuid,boolean)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Verification failed: internal monetary mutation helper remains externally executable';
  END IF;

  SELECT pg_get_functiondef(
    'public.calculate_employee_payroll_scheduled(uuid,uuid)'::regprocedure
  ) INTO v_definition;

  v_predicate_count := (
    length(v_definition) - length(replace(
      v_definition,
      'schedule_day_kind = ''work_day'' OR schedule_snapshot_at IS NULL',
      ''
    ))
  ) / length('schedule_day_kind = ''work_day'' OR schedule_snapshot_at IS NULL');

  IF v_predicate_count < 4 THEN
    RAISE EXCEPTION
      'Verification failed: scheduled payroll has only % work-day eligibility predicates',
      v_predicate_count;
  END IF;

  IF v_definition NOT ILIKE '%SUM(day_value)%v_attended_days%'
     OR v_definition NOT ILIKE '%SUM(overtime_minutes)%v_total_overtime_minutes%' THEN
    RAISE EXCEPTION 'Verification failed: expected payroll attendance aggregates are missing';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'verification', 'critical_review_fixes',
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'anonymous_mutation_access_removed', true,
  'authenticated_actor_binding_verified', true,
  'scheduled_payroll_workday_filter_verified', true
) AS result;

ROLLBACK;
