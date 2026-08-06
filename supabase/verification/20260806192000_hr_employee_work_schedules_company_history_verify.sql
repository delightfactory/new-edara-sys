-- =============================================================================
-- Employee Work Schedules — company history and atomic settings verification
--
-- Read-only. Run after migrations 20260806190000 through 20260806191300.
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '120s';

DO $verify$
DECLARE
  v_definition TEXT;
  v_trigger_definition TEXT;
  v_baseline public.hr_company_work_schedules%ROWTYPE;
  v_valid JSONB;
  v_start_text TEXT;
  v_end_text TEXT;
  v_hours_text TEXT;
  v_off_text TEXT;
  v_table_acl TEXT;
  v_constraint_count INTEGER;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Company-history verify failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Company-history verify failed: employee schedule/snapshot runtime data changed';
  END IF;

  IF (SELECT count(*) FROM public.hr_company_work_schedules) <> 1
     OR (SELECT count(*) FROM public.hr_company_work_schedules WHERE is_system_baseline) <> 1 THEN
    RAISE EXCEPTION 'Company-history verify failed: expected exactly one technical baseline';
  END IF;

  SELECT * INTO v_baseline
  FROM public.hr_company_work_schedules
  WHERE is_system_baseline = true;

  SELECT
    max(value) FILTER (WHERE key = 'hr.work_start_time'),
    max(value) FILTER (WHERE key = 'hr.work_end_time'),
    max(value) FILTER (WHERE key = 'hr.work_hours_per_day'),
    max(value) FILTER (WHERE key = 'hr.weekly_off_day')
  INTO v_start_text, v_end_text, v_hours_text, v_off_text
  FROM public.company_settings
  WHERE key IN (
    'hr.work_start_time',
    'hr.work_end_time',
    'hr.work_hours_per_day',
    'hr.weekly_off_day'
  );

  v_valid := public.validate_hr_company_work_schedule_values(
    v_start_text,
    v_end_text,
    v_hours_text,
    v_off_text
  );

  IF to_char(v_baseline.start_time, 'HH24:MI') IS DISTINCT FROM (v_valid->>'start_time')
     OR to_char(v_baseline.end_time, 'HH24:MI') IS DISTINCT FROM (v_valid->>'end_time')
     OR v_baseline.scheduled_minutes IS DISTINCT FROM (v_valid->>'scheduled_minutes')::INTEGER
     OR v_baseline.weekly_off_day::TEXT IS DISTINCT FROM (v_valid->>'weekly_off_day') THEN
    RAISE EXCEPTION 'Company-history verify failed: baseline differs from validated company settings';
  END IF;

  IF (public.validate_hr_company_work_schedule_values('1100', '19:00', '8', 'FRIDAY')->>'start_time')
       IS DISTINCT FROM '11:00' THEN
    RAISE EXCEPTION 'Company-history verify failed: compact production time normalization is broken';
  END IF;

  IF public.get_company_scheduled_minutes_for_date(v_baseline.effective_from)
       IS DISTINCT FROM v_baseline.scheduled_minutes THEN
    RAISE EXCEPTION 'Company-history verify failed: company duration depends on weekday state';
  END IF;

  IF NOT public.hr_company_work_schedule_activation_consistent() THEN
    RAISE EXCEPTION 'Company-history verify failed: baseline/settings activation consistency is false';
  END IF;

  SELECT count(*)::INTEGER
  INTO v_constraint_count
  FROM pg_constraint c
  WHERE c.conrelid = 'public.hr_company_work_schedules'::regclass
    AND c.conname IN (
      'hr_company_work_schedules_status_check',
      'hr_company_work_schedules_dates_check',
      'hr_company_work_schedules_window_check',
      'hr_company_work_schedules_lifecycle_check',
      'hr_company_work_schedules_no_effective_overlap'
    );

  IF v_constraint_count <> 5 THEN
    RAISE EXCEPTION 'Company-history verify failed: table constraints are incomplete (%)', v_constraint_count;
  END IF;

  IF NOT (
    SELECT c.relrowsecurity
    FROM pg_class c
    WHERE c.oid = 'public.hr_company_work_schedules'::regclass
  ) THEN
    RAISE EXCEPTION 'Company-history verify failed: RLS is not enabled';
  END IF;

  SELECT c.relacl::TEXT INTO v_table_acl
  FROM pg_class c
  WHERE c.oid = 'public.hr_company_work_schedules'::regclass;

  IF has_table_privilege('authenticated', 'public.hr_company_work_schedules', 'INSERT')
     OR has_table_privilege('authenticated', 'public.hr_company_work_schedules', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.hr_company_work_schedules', 'DELETE')
     OR NOT has_table_privilege('authenticated', 'public.hr_company_work_schedules', 'SELECT') THEN
    RAISE EXCEPTION 'Company-history verify failed: table grants are incorrect (%)', v_table_acl;
  END IF;

  SELECT pg_get_functiondef(
    'public.resolve_employee_work_schedule_core(uuid,date,boolean)'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%resolve_employee_work_schedule_core_pre_company_history_20260806%'
     OR v_definition NOT ILIKE '%resolve_company_work_schedule_for_employee%'
     OR v_definition NOT ILIKE '%IF NOT COALESCE(p_use_custom, false)%' THEN
    RAISE EXCEPTION 'Company-history verify failed: central resolver dispatch is incomplete';
  END IF;

  SELECT pg_get_functiondef(
    'public.resolve_company_work_schedule_for_employee(uuid,date)'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%COALESCE(v_employee_off, v_schedule.weekly_off_day)%'
     OR v_definition NOT ILIKE '%v_schedule.scheduled_minutes%' THEN
    RAISE EXCEPTION 'Company-history verify failed: employee off-day fallback is incomplete';
  END IF;

  SELECT pg_get_functiondef(
    'public.guard_employee_work_schedule_activation_duration()'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%get_company_scheduled_minutes_for_date(NEW.effective_from)%' THEN
    RAISE EXCEPTION 'Company-history verify failed: first employee transition is not date-aware';
  END IF;

  SELECT pg_get_functiondef(
    'public.validate_employee_work_schedule_duration()'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%get_company_scheduled_minutes_for_date(v_effective_from)%' THEN
    RAISE EXCEPTION 'Company-history verify failed: deferred employee transition is not date-aware';
  END IF;

  SELECT pg_get_functiondef(
    'public.assert_company_work_schedule_change_safe(date,date,integer,uuid)'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%schedule_source = ''company''%'
     OR v_definition NOT ILIKE '%previous.effective_to = s.effective_from - 1%'
     OR v_definition NOT ILIKE '%EXTRACT(DAY FROM s.effective_from)%' THEN
    RAISE EXCEPTION 'Company-history verify failed: prepared-fact safety guard is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.guard_hr_company_work_schedule_mutation()'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%v_safe_baseline_correction%'
     OR v_definition NOT ILIKE '%NEW.retired_by IS NULL%'
     OR v_definition NOT ILIKE '%count(*) FROM public.hr_company_work_schedules%'
     OR v_definition NOT ILIKE '%NOT EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)%' THEN
    RAISE EXCEPTION 'Company-history verify failed: lifecycle/baseline mutation guard is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.update_hr_settings_atomic(jsonb)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%settings.update%'
     OR v_definition NOT ILIKE '%FOR UPDATE%'
     OR v_definition NOT ILIKE '%validate_hr_company_work_schedule_values%'
     OR v_definition NOT ILIKE '%hr_settings_updated_atomic%'
     OR v_definition NOT ILIKE '%company_baseline_synchronized%'
     OR v_definition NOT ILIKE '%UPDATE public.hr_company_work_schedules%' THEN
    RAISE EXCEPTION 'Company-history verify failed: atomic HR settings/baseline sync is incomplete';
  END IF;

  SELECT pg_get_triggerdef(t.oid, true)
  INTO v_trigger_definition
  FROM pg_trigger t
  WHERE t.tgrelid = 'public.company_settings'::regclass
    AND t.tgname = 'trg_company_settings_schedule_consistency_deferred'
    AND NOT t.tgisinternal;

  IF v_trigger_definition IS NULL
     OR v_trigger_definition NOT ILIKE '%DEFERRABLE INITIALLY DEFERRED%'
     OR v_trigger_definition NOT ILIKE '%enforce_company_schedule_settings_consistency%' THEN
    RAISE EXCEPTION 'Company-history verify failed: deferred direct-write protection is incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid = 'public.hr_company_work_schedules'::regclass
      AND t.tgname = 'trg_hr_company_work_schedules_mutation_guard'
      AND NOT t.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid = 'public.hr_company_work_schedules'::regclass
      AND t.tgname = 'trg_hr_company_work_schedules_delete_guard'
      AND NOT t.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid = 'public.company_settings'::regclass
      AND t.tgname = 'trg_company_settings_schedule_history_guard'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'Company-history verify failed: lifecycle/legacy-setting triggers are incomplete';
  END IF;

  IF NOT has_function_privilege(
       'authenticated',
       'public.save_company_work_schedule_version(date,text,text,text,text)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'authenticated',
       'public.update_future_company_work_schedule_version(uuid,text,text,text,text)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'authenticated',
       'public.update_hr_settings_atomic(jsonb)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'anon',
       'public.save_company_work_schedule_version(date,text,text,text,text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'service_role',
       'public.update_future_company_work_schedule_version(uuid,text,text,text,text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated',
       'public.assert_company_work_schedule_change_safe(date,date,integer,uuid)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated',
       'public.enforce_company_schedule_settings_consistency()',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Company-history verify failed: function grants are incorrect';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'verification', 'effective_dated_company_work_schedule',
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'company_history_rows', (SELECT count(*) FROM public.hr_company_work_schedules),
  'system_baseline_rows', (SELECT count(*) FROM public.hr_company_work_schedules WHERE is_system_baseline),
  'company_history_consistent', public.hr_company_work_schedule_activation_consistent(),
  'compact_time_normalized', true,
  'hardcoded_480_removed', true,
  'atomic_hr_settings', true,
  'baseline_sync_guarded', true,
  'direct_write_constraint_deferred', true,
  'runtime_employee_data_changed', false
) AS result;

ROLLBACK;
