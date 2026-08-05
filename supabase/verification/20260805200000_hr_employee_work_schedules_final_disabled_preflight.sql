-- =============================================================================
-- Employee Work Schedules — final installed-but-disabled preflight
--
-- Run after every feature migration and after rollback-only simulation.
-- This is read-only and must pass before any application build/preview decision.
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '180s';

DO $verify$
DECLARE
  v_missing TEXT;
  v_bad TEXT;
  v_hash TEXT;
  v_definition TEXT;
  v_feature_value TEXT;
BEGIN
  SELECT value
  INTO v_feature_value
  FROM public.company_settings
  WHERE key = 'hr.employee_work_schedules_enabled';

  IF lower(btrim(COALESCE(v_feature_value, ''))) NOT IN ('false', '0', 'off', 'no') THEN
    RAISE EXCEPTION 'Final preflight failed: feature switch is not false (%)', v_feature_value;
  END IF;

  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'Final preflight failed: feature helper reports enabled';
  END IF;

  IF public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Final preflight failed: activation readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'Final preflight failed: disposable installed-state check expects empty schedule tables';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_attendance_days
    WHERE schedule_snapshot_at IS NOT NULL
       OR schedule_day_kind IS NOT NULL
       OR scheduled_start_at IS NOT NULL
       OR scheduled_end_at IS NOT NULL
       OR scheduled_minutes IS NOT NULL
       OR schedule_source IS NOT NULL
       OR work_schedule_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Final preflight failed: attendance snapshot data was seeded or left by simulation';
  END IF;

  -- Required public and internal functions in the final disabled state.
  WITH required(signature) AS (
    VALUES
      ('hr_employee_work_schedules_enabled()'),
      ('hr_employee_work_schedules_activation_ready()'),
      ('guard_employee_work_schedules_activation()'),
      ('resolve_employee_work_schedule_core(uuid,date,boolean)'),
      ('resolve_employee_work_schedule(uuid,date)'),
      ('ensure_attendance_schedule_snapshot(uuid)'),
      ('save_employee_work_schedule(uuid,date,jsonb,text)'),
      ('update_future_employee_work_schedule(uuid,jsonb,text)'),
      ('get_employee_work_schedule_admin_context()'),
      ('get_employee_scheduled_period(uuid,date,date,boolean)'),
      ('assert_employee_payroll_schedule_snapshots(uuid,date,date)'),
      ('record_attendance_gps_v2(numeric,numeric,numeric,text,timestamp with time zone)'),
      ('record_attendance_gps(numeric,numeric,numeric,text,timestamp with time zone)'),
      ('upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)'),
      ('is_employee_work_day(uuid,date)'),
      ('mark_daily_absences(date)'),
      ('run_auto_checkout(date)'),
      ('process_attendance_penalties(uuid)'),
      ('settle_attendance_day_against_leave(uuid,boolean)'),
      ('notify_absent_employees()'),
      ('scan_attendance_daily_review_alerts()'),
      ('run_attendance_operational_scan()'),
      ('calculate_employee_payroll(uuid,uuid)')
  ), actual AS (
    SELECT p.oid::regprocedure::TEXT AS signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
  )
  SELECT string_agg(r.signature, ', ' ORDER BY r.signature)
  INTO v_missing
  FROM required r
  LEFT JOIN actual a USING (signature)
  WHERE a.signature IS NULL;

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Final preflight failed: required functions missing: %', v_missing;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'company_settings'
      AND t.tgname = 'trg_company_settings_employee_schedule_activation_guard'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'Final preflight failed: activation trigger is missing';
  END IF;

  -- Exact disabled-mode clones of every replaced production function.
  WITH expected(helper_signature, public_name, definition_md5) AS (
    VALUES
      ('record_attendance_gps_v2_legacy_20260805(numeric,numeric,numeric,text,timestamp with time zone)', 'record_attendance_gps_v2', 'bd70c45984e188a38cceb45eea00fa00'),
      ('record_attendance_gps_legacy_20260805(numeric,numeric,numeric,text,timestamp with time zone)', 'record_attendance_gps', '41f47aaff1eced8e368bce61cbd7a1a4'),
      ('upsert_attendance_and_reprocess_legacy_20260805(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)', 'upsert_attendance_and_reprocess', 'a0123e9ec343603dee9adf4ec73739b4'),
      ('is_employee_work_day_legacy_20260805(uuid,date)', 'is_employee_work_day', '3e047334df57ad284bea8e9504724dd0'),
      ('mark_daily_absences_legacy_20260805(date)', 'mark_daily_absences', '21e4cb27c5d1008da928cbf14ad56f1b'),
      ('run_auto_checkout_legacy_20260805(date)', 'run_auto_checkout', '7687df6dc398cd73ed53408c2c53d1a8'),
      ('process_attendance_penalties_legacy_20260805(uuid)', 'process_attendance_penalties', '7ea1046753bbcfbbb47bcb35c27f986e'),
      ('settle_attendance_day_against_leave_legacy_20260805(uuid,boolean)', 'settle_attendance_day_against_leave', 'c5724ab559a12ca470bcd0bae8ad8206'),
      ('notify_absent_employees_legacy_20260805()', 'notify_absent_employees', '0d117e202cbbcf08e9d1b35b4b4dab14'),
      ('scan_attendance_daily_review_alerts_legacy_20260805()', 'scan_attendance_daily_review_alerts', '9997ff7734f0289b85c5d9a3b8330c38'),
      ('run_attendance_operational_scan_legacy_20260805()', 'run_attendance_operational_scan', '40baaa14f7df81f78025d14ebb0fc288'),
      ('calculate_employee_payroll_legacy_20260805(uuid,uuid)', 'calculate_employee_payroll', 'c294bf592059b7e86429960c3e2b3075')
  ), actual AS (
    SELECT
      e.helper_signature,
      e.definition_md5 AS expected_md5,
      md5(replace(
        pg_get_functiondef(to_regprocedure('public.' || e.helper_signature)),
        'FUNCTION public.' || split_part(e.helper_signature, '(', 1) || '(',
        'FUNCTION public.' || e.public_name || '('
      )) AS actual_md5
    FROM expected e
  )
  SELECT string_agg(
           format('%s expected=%s actual=%s', helper_signature, expected_md5, COALESCE(actual_md5, '<missing>')),
           E'\n' ORDER BY helper_signature
         )
  INTO v_bad
  FROM actual
  WHERE actual_md5 IS DISTINCT FROM expected_md5;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Final preflight failed: legacy clone mismatch:%', E'\n' || v_bad;
  END IF;

  -- Existing schedule-neutral/financial orchestration remains exact.
  WITH expected(signature, definition_md5) AS (
    VALUES
      ('scan_attendance_tracking_alerts()', '139e2ad118b89ff33d5052e67041e4e6'),
      ('reprocess_attendance_day_penalties(uuid)', '5d1d271f18585e9d2381b9d1c12fa684'),
      ('calculate_payroll_run(uuid)', 'f97661bab79bc9b4fe7c68a19c9e9238'),
      ('approve_payroll_run(uuid,uuid)', 'e32a1fcea2993bfbd1c0e3880b37cbd6'),
      ('check_payroll_attendance_clearance(date,date,uuid)', '3732e7614a8b0a06cdf170f237d426fd')
  ), actual AS (
    SELECT p.oid::regprocedure::TEXT AS signature,
           md5(pg_get_functiondef(p.oid)) AS definition_md5
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
  )
  SELECT string_agg(
           format('%s expected=%s actual=%s', e.signature, e.definition_md5, COALESCE(a.definition_md5, '<missing>')),
           E'\n' ORDER BY e.signature
         )
  INTO v_bad
  FROM expected e
  LEFT JOIN actual a USING (signature)
  WHERE a.definition_md5 IS DISTINCT FROM e.definition_md5;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Final preflight failed: unchanged runtime drift:%', E'\n' || v_bad;
  END IF;

  -- Public dispatchers must remain flag-gated.
  WITH dispatchers(signature, legacy_token, scheduled_token) AS (
    VALUES
      ('record_attendance_gps_v2(numeric,numeric,numeric,text,timestamp with time zone)', 'record_attendance_gps_v2_legacy_20260805', 'record_attendance_gps_v2_scheduled'),
      ('record_attendance_gps(numeric,numeric,numeric,text,timestamp with time zone)', 'record_attendance_gps_legacy_20260805', 'record_attendance_gps_v2_scheduled'),
      ('upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)', 'upsert_attendance_and_reprocess_legacy_20260805', 'upsert_attendance_and_reprocess_scheduled'),
      ('is_employee_work_day(uuid,date)', 'is_employee_work_day_legacy_20260805', 'resolve_employee_work_schedule'),
      ('mark_daily_absences(date)', 'mark_daily_absences_legacy_20260805', 'mark_daily_absences_scheduled'),
      ('run_auto_checkout(date)', 'run_auto_checkout_legacy_20260805', 'run_auto_checkout_scheduled'),
      ('process_attendance_penalties(uuid)', 'process_attendance_penalties_legacy_20260805', 'process_attendance_penalties_scheduled'),
      ('settle_attendance_day_against_leave(uuid,boolean)', 'settle_attendance_day_against_leave_legacy_20260805', 'settle_attendance_day_against_leave_scheduled'),
      ('notify_absent_employees()', 'notify_absent_employees_legacy_20260805', 'notify_absent_employees_scheduled'),
      ('scan_attendance_daily_review_alerts()', 'scan_attendance_daily_review_alerts_legacy_20260805', 'scan_attendance_daily_review_alerts_scheduled'),
      ('run_attendance_operational_scan()', 'run_attendance_operational_scan_legacy_20260805', 'run_attendance_operational_scan_scheduled'),
      ('calculate_employee_payroll(uuid,uuid)', 'calculate_employee_payroll_legacy_20260805', 'calculate_employee_payroll_scheduled')
  ), actual AS (
    SELECT
      d.signature,
      d.legacy_token,
      d.scheduled_token,
      pg_get_functiondef(to_regprocedure('public.' || d.signature)) AS definition
    FROM dispatchers d
  )
  SELECT string_agg(signature, ', ' ORDER BY signature)
  INTO v_bad
  FROM actual
  WHERE definition NOT ILIKE '%hr_employee_work_schedules_enabled%'
     OR definition NOT ILIKE '%' || legacy_token || '%'
     OR definition NOT ILIKE '%' || scheduled_token || '%';

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Final preflight failed: incomplete public dispatchers: %', v_bad;
  END IF;

  -- Internal helpers must not be directly executable by application roles.
  WITH internal(signature) AS (
    VALUES
      ('resolve_employee_work_schedule_core(uuid,date,boolean)'),
      ('resolve_employee_work_schedule(uuid,date)'),
      ('ensure_attendance_schedule_snapshot(uuid)'),
      ('get_employee_scheduled_period(uuid,date,date,boolean)'),
      ('assert_employee_payroll_schedule_snapshots(uuid,date,date)'),
      ('record_attendance_gps_v2_scheduled(numeric,numeric,numeric,text,timestamp with time zone)'),
      ('record_attendance_gps_v2_legacy_20260805(numeric,numeric,numeric,text,timestamp with time zone)'),
      ('record_attendance_gps_legacy_20260805(numeric,numeric,numeric,text,timestamp with time zone)'),
      ('upsert_attendance_and_reprocess_scheduled(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)'),
      ('upsert_attendance_and_reprocess_legacy_20260805(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)'),
      ('mark_daily_absences_scheduled(date)'),
      ('run_auto_checkout_scheduled(date)'),
      ('process_attendance_penalties_scheduled(uuid)'),
      ('settle_attendance_day_against_leave_scheduled(uuid,boolean)'),
      ('notify_absent_employees_scheduled()'),
      ('scan_attendance_daily_review_alerts_scheduled()'),
      ('run_attendance_operational_scan_scheduled()'),
      ('calculate_employee_payroll_scheduled(uuid,uuid)'),
      ('calculate_employee_payroll_legacy_20260805(uuid,uuid)')
  )
  SELECT string_agg(
           format('%s auth=%s service=%s', signature,
             has_function_privilege('authenticated', 'public.' || signature, 'EXECUTE'),
             has_function_privilege('service_role', 'public.' || signature, 'EXECUTE')),
           E'\n' ORDER BY signature
         )
  INTO v_bad
  FROM internal
  WHERE has_function_privilege('authenticated', 'public.' || signature, 'EXECUTE')
     OR has_function_privilege('service_role', 'public.' || signature, 'EXECUTE');

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Final preflight failed: internal helper exposed:%', E'\n' || v_bad;
  END IF;

  -- Atomic notification dedupe contract.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname = 'notification_alert_state'
      AND c.conname = 'uq_nas_alert_key'
      AND c.contype = 'u'
      AND c.convalidated
  ) THEN
    RAISE EXCEPTION 'Final preflight failed: notification alert-key uniqueness is missing';
  END IF;

  SELECT pg_get_functiondef('public.notify_absent_employees_scheduled()'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%ON CONFLICT (alert_key) DO NOTHING%'
     OR v_definition NOT ILIKE '%scheduled_start_at%'
     OR v_definition NOT ILIKE '%notification_alert_state%' THEN
    RAISE EXCEPTION 'Final preflight failed: late-shift absence dedupe is incomplete';
  END IF;

  -- Existing attendance cron contracts remain unchanged.
  WITH expected(jobname, schedule, normalized_command, active) AS (
    VALUES
      ('scan-attendance-alerts', '*/15 * * * *', 'selectpublic.run_attendance_operational_scan();', true),
      ('notify-absent-employees', '0 14 * * *', 'selectpublic.notify_absent_employees();', true)
  ), actual AS (
    SELECT
      jobname,
      schedule,
      regexp_replace(lower(command), '\s+', '', 'g') AS normalized_command,
      active
    FROM cron.job
    WHERE jobname IN ('scan-attendance-alerts', 'notify-absent-employees')
  )
  SELECT string_agg(
           format('%s expected=%s/%s/%s actual=%s/%s/%s',
             e.jobname, e.schedule, e.normalized_command, e.active,
             COALESCE(a.schedule, '<missing>'), COALESCE(a.normalized_command, '<missing>'), a.active),
           E'\n' ORDER BY e.jobname
         )
  INTO v_bad
  FROM expected e
  LEFT JOIN actual a USING (jobname)
  WHERE a.jobname IS NULL
     OR a.schedule IS DISTINCT FROM e.schedule
     OR a.normalized_command IS DISTINCT FROM e.normalized_command
     OR a.active IS DISTINCT FROM e.active;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Final preflight failed: attendance cron drift:%', E'\n' || v_bad;
  END IF;

  IF (
    SELECT count(*)
    FROM cron.job
    WHERE jobname IN ('scan-attendance-alerts', 'notify-absent-employees')
  ) <> 2 THEN
    RAISE EXCEPTION 'Final preflight failed: duplicate/missing attendance cron jobs';
  END IF;

  -- Least-privilege application contract.
  IF to_regprocedure('public.get_employee_work_schedule_admin_context()') IS NULL
     OR to_regprocedure('public.save_employee_work_schedule(uuid,date,jsonb,text)') IS NULL
     OR to_regprocedure('public.update_future_employee_work_schedule(uuid,jsonb,text)') IS NULL THEN
    RAISE EXCEPTION 'Final preflight failed: application RPC contract is incomplete';
  END IF;

  IF NOT has_function_privilege('authenticated', 'public.get_employee_work_schedule_admin_context()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.save_employee_work_schedule(uuid,date,jsonb,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.update_future_employee_work_schedule(uuid,jsonb,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_employee_work_schedule_admin_context()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.save_employee_work_schedule(uuid,date,jsonb,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.update_future_employee_work_schedule(uuid,jsonb,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Final preflight failed: application RPC grants are incorrect';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'status', 'pass',
  'installed', true,
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'schedule_rows', (SELECT count(*) FROM public.hr_employee_work_schedules),
  'snapshot_rows', (SELECT count(*) FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL),
  'legacy_clones_exact', true,
  'public_dispatchers_flag_gated', true,
  'internal_helpers_exposed', false,
  'attendance_cron_changed', false,
  'notification_dedupe_atomic', true,
  'application_rpc_contract_ready', true,
  'production_activation_authorized', false
) AS final_disabled_preflight;

ROLLBACK;
