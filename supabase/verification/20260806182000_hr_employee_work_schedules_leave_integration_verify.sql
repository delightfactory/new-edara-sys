-- =============================================================================
-- Employee Work Schedules — schedule-aware leave integration verification
--
-- Read-only structural verification. Run after migrations 20260806180000,
-- 20260806181000, 20260806181500, and 20260806181700. It does not enable the
-- feature or modify business data.
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '90s';

DO $verify$
DECLARE
  v_definition TEXT;
  v_trigger_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Leave verification failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Leave verification failed: installed-state runtime tables must remain empty';
  END IF;

  IF md5(pg_get_functiondef(
       'public.sync_approved_leave_to_attendance_legacy_20260806(uuid)'::regprocedure
     )) <> '3c3d2222e3d24ac1246fdff05799f9be' THEN
    RAISE EXCEPTION 'Leave verification failed: disabled sync clone differs from production baseline';
  END IF;

  IF md5(pg_get_functiondef(
       'public.cleanup_approved_leave_sync_legacy_20260806(uuid)'::regprocedure
     )) <> '2b26c6150df6ef8ae045c7874d66d316' THEN
    RAISE EXCEPTION 'Leave verification failed: disabled cleanup clone differs from production baseline';
  END IF;

  SELECT pg_get_functiondef('public.calculate_employee_leave_workdays(uuid,date,date,boolean)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%resolve_employee_work_schedule_core%'
     OR v_definition NOT ILIKE '%day_kind = ''work_day''%'
     OR v_definition ILIKE '%cannot cross calendar years%'
     OR v_definition NOT ILIKE '%hire date%'
     OR v_definition NOT ILIKE '%termination date%' THEN
    RAISE EXCEPTION 'Leave verification failed: compatible server-side workday calculator is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.handle_leave_submission()'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%IF NOT public.hr_employee_work_schedules_enabled()%'
     OR v_definition NOT ILIKE '%NEW.days_count := v_days%'
     OR v_definition NOT ILIKE '%pending_days = COALESCE(pending_days, 0) + v_days%'
     OR v_definition NOT ILIKE '%remaining_days = GREATEST%' THEN
    RAISE EXCEPTION 'Leave verification failed: submission trigger is not schedule/balance aware';
  END IF;

  SELECT pg_get_functiondef('public.handle_leave_approval()'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%NEW.days_count := v_days%'
     OR v_definition NOT ILIKE '%OLD.days_count%'
     OR v_definition NOT ILIKE '%used_days = COALESCE(used_days, 0) + NEW.days_count%'
     OR v_definition NOT ILIKE '%cleanup_approved_leave_sync_scheduled%'
     OR v_definition NOT ILIKE '%لا يمكن تعديل الموظف أو نوع الإجازة أو مدتها%' THEN
    RAISE EXCEPTION 'Leave verification failed: approval/balance transition is incomplete';
  END IF;

  SELECT pg_get_triggerdef(t.oid, true)
  INTO v_trigger_definition
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = 'hr_leave_requests'
    AND t.tgname = 'trg_leave_schedule_sync_after_approval'
    AND NOT t.tgisinternal;

  IF v_trigger_definition IS NULL
     OR v_trigger_definition NOT ILIKE '%AFTER UPDATE OF status%'
     OR v_trigger_definition NOT ILIKE '%sync_approved_leave_after_status_change%' THEN
    RAISE EXCEPTION 'Leave verification failed: approval synchronization is not AFTER UPDATE';
  END IF;

  SELECT pg_get_functiondef('public.sync_approved_leave_to_attendance_scheduled(uuid)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%WHERE r.day_kind = ''work_day''%'
     OR v_definition NOT ILIKE '%schedule_day_kind%'
     OR v_definition NOT ILIKE '%scheduled_start_at%'
     OR v_definition NOT ILIKE '%scheduled_end_at%'
     OR v_definition NOT ILIKE '%scheduled_minutes%'
     OR v_definition NOT ILIKE '%schedule_snapshot_at%'
     OR v_definition NOT ILIKE '%v_linked_count <> v_leave.days_count%'
     OR v_definition NOT ILIKE '%normalize_attendance_day_schedule_metrics%' THEN
    RAISE EXCEPTION 'Leave verification failed: attendance synchronization contract is incomplete';
  END IF;

  SELECT pg_get_functiondef(
    'public.settle_attendance_day_against_leave_scheduled(uuid,boolean)'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%used_days = GREATEST(0, COALESCE(used_days, 0) - 1)%'
     OR v_definition NOT ILIKE '%remaining_days = GREATEST%'
     OR v_definition NOT ILIKE '%scheduled_minutes%' THEN
    RAISE EXCEPTION 'Leave verification failed: full-day settlement does not align used/remaining balances';
  END IF;

  SELECT pg_get_functiondef('public.normalize_attendance_day_schedule_metrics(uuid)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%COALESCE(lt.is_paid, true) = false%'
     OR v_definition NOT ILIKE '%COALESCE(lt.affects_salary, false) = true%'
     OR v_definition NOT ILIKE '%COALESCE(effective_hours, 0) / (scheduled_minutes / 60.0)%'
     OR v_definition NOT ILIKE '%status = ''on_leave''%'
     OR v_definition NOT ILIKE '%status = ''present''%' THEN
    RAISE EXCEPTION 'Leave verification failed: partial paid/unpaid attendance policy is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.calculate_employee_payroll_scheduled(uuid,uuid)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%LEFT JOIN hr_leave_types%'
     OR v_definition NOT ILIKE '%COALESCE(lt.is_paid, true) = true%'
     OR v_definition NOT ILIKE '%COALESCE(lt.affects_salary, false) = false%'
     OR v_definition NOT ILIKE '%schedule_day_kind = ''work_day'' OR ad.schedule_snapshot_at IS NULL%' THEN
    RAISE EXCEPTION 'Leave verification failed: paid/unpaid leave payroll separation is incomplete';
  END IF;

  IF has_function_privilege('anon', 'public.preview_employee_leave_workday_count(uuid,date,date)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.calculate_employee_leave_workdays(uuid,date,date,boolean)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.sync_approved_leave_to_attendance_scheduled(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.cleanup_approved_leave_sync_scheduled(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.normalize_attendance_day_schedule_metrics(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Leave verification failed: internal helpers are externally exposed';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'verification', 'schedule_aware_leave_integration',
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'server_side_day_count', true,
  'cross_year_request_compatibility', true,
  'after_approval_sync', true,
  'complete_schedule_snapshot', true,
  'balance_consistency', true,
  'unpaid_leave_payroll_separation', true,
  'partial_unpaid_work_proration', true
) AS result;

ROLLBACK;
