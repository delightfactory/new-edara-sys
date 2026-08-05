-- =============================================================================
-- Employee Work Schedules M1 — read-only post-migration verification
--
-- Run only after M1 on a disposable database first.
-- This script performs no DDL/DML and must leave the database unchanged.
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '60s';

DO $verify$
DECLARE
  v_count INTEGER;
  v_bad TEXT;
BEGIN
  -- Core objects.
  IF to_regclass('public.hr_employee_work_schedules') IS NULL THEN
    RAISE EXCEPTION 'M1 verify failed: schedule header table is missing';
  END IF;

  IF to_regclass('public.hr_employee_work_schedule_days') IS NULL THEN
    RAISE EXCEPTION 'M1 verify failed: schedule day table is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_extension e
    JOIN pg_namespace n ON n.oid = e.extnamespace
    WHERE e.extname = 'btree_gist'
      AND n.nspname = 'extensions'
  ) THEN
    RAISE EXCEPTION 'M1 verify failed: btree_gist is not installed in extensions';
  END IF;

  -- M1 must not seed schedules.
  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'M1 verify failed: schedule data was unexpectedly seeded';
  END IF;

  -- Feature must remain disabled and private.
  IF NOT EXISTS (
    SELECT 1
    FROM public.company_settings
    WHERE key = 'hr.employee_work_schedules_enabled'
      AND value = 'false'
      AND type = 'boolean'
      AND is_public = false
  ) THEN
    RAISE EXCEPTION 'M1 verify failed: feature switch is missing, public, or not false';
  END IF;

  -- Exactly seven nullable/no-default snapshot columns.
  SELECT count(*)
  INTO v_count
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'hr_attendance_days'
    AND column_name IN (
      'schedule_day_kind',
      'scheduled_start_at',
      'scheduled_end_at',
      'scheduled_minutes',
      'schedule_source',
      'work_schedule_id',
      'schedule_snapshot_at'
    )
    AND is_nullable = 'YES'
    AND column_default IS NULL;

  IF v_count <> 7 THEN
    RAISE EXCEPTION 'M1 verify failed: expected 7 nullable/no-default snapshot columns, found %', v_count;
  END IF;

  -- No historical attendance backfill.
  IF EXISTS (
    SELECT 1
    FROM public.hr_attendance_days
    WHERE schedule_day_kind IS NOT NULL
       OR scheduled_start_at IS NOT NULL
       OR scheduled_end_at IS NOT NULL
       OR scheduled_minutes IS NOT NULL
       OR schedule_source IS NOT NULL
       OR work_schedule_id IS NOT NULL
       OR schedule_snapshot_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'M1 verify failed: historical attendance snapshot data was populated';
  END IF;

  -- Required constraints are present and validated.
  SELECT string_agg(c.conname, ', ' ORDER BY c.conname)
  INTO v_bad
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = t.relnamespace
  WHERE n.nspname = 'public'
    AND t.relname IN (
      'hr_employee_work_schedules',
      'hr_employee_work_schedule_days',
      'hr_attendance_days'
    )
    AND c.conname IN (
      'hr_employee_work_schedules_status_check',
      'hr_employee_work_schedules_dates_check',
      'hr_employee_work_schedules_lifecycle_check',
      'hr_employee_work_schedules_no_effective_overlap',
      'hr_employee_work_schedule_days_schedule_day_key',
      'hr_employee_work_schedule_days_window_check',
      'hr_employee_work_schedule_days_minutes_check',
      'hr_attendance_days_work_schedule_id_fkey',
      'hr_attendance_days_schedule_snapshot_check'
    )
    AND NOT c.convalidated;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'M1 verify failed: unvalidated constraints: %', v_bad;
  END IF;

  SELECT count(*)
  INTO v_count
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = t.relnamespace
  WHERE n.nspname = 'public'
    AND c.conname IN (
      'hr_employee_work_schedules_status_check',
      'hr_employee_work_schedules_dates_check',
      'hr_employee_work_schedules_lifecycle_check',
      'hr_employee_work_schedules_no_effective_overlap',
      'hr_employee_work_schedule_days_schedule_day_key',
      'hr_employee_work_schedule_days_window_check',
      'hr_employee_work_schedule_days_minutes_check',
      'hr_attendance_days_work_schedule_id_fkey',
      'hr_attendance_days_schedule_snapshot_check'
    );

  IF v_count <> 9 THEN
    RAISE EXCEPTION 'M1 verify failed: expected 9 named constraints, found %', v_count;
  END IF;

  -- RLS is enabled on both new tables.
  IF EXISTS (
    SELECT 1
    FROM pg_class t
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname IN ('hr_employee_work_schedules', 'hr_employee_work_schedule_days')
      AND NOT t.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'M1 verify failed: RLS is not enabled on one or more schedule tables';
  END IF;

  -- Authenticated users receive SELECT only; no direct schedule mutation.
  IF NOT has_table_privilege('authenticated', 'public.hr_employee_work_schedules', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.hr_employee_work_schedule_days', 'SELECT') THEN
    RAISE EXCEPTION 'M1 verify failed: authenticated SELECT grant is missing';
  END IF;

  IF has_table_privilege('authenticated', 'public.hr_employee_work_schedules', 'INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated', 'public.hr_employee_work_schedule_days', 'INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'M1 verify failed: authenticated has direct schedule write privileges';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('hr_employee_work_schedules', 'hr_employee_work_schedule_days')
      AND cmd <> 'SELECT'
  ) THEN
    RAISE EXCEPTION 'M1 verify failed: a write RLS policy exists on schedule tables';
  END IF;

  SELECT count(*)
  INTO v_count
  FROM pg_policies
  WHERE schemaname = 'public'
    AND (
      (tablename = 'hr_employee_work_schedules' AND policyname = 'hr_employee_work_schedules_read' AND cmd = 'SELECT')
      OR
      (tablename = 'hr_employee_work_schedule_days' AND policyname = 'hr_employee_work_schedule_days_read' AND cmd = 'SELECT')
    );

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'M1 verify failed: expected two read policies, found %', v_count;
  END IF;

  -- Existing runtime functions must be byte-for-byte definition-equivalent to baseline.
  WITH expected(signature, definition_md5) AS (
    VALUES
      ('calculate_employee_payroll(uuid,uuid)', 'c294bf592059b7e86429960c3e2b3075'),
      ('is_employee_work_day(uuid,date)', '3e047334df57ad284bea8e9504724dd0'),
      ('mark_daily_absences(date)', '21e4cb27c5d1008da928cbf14ad56f1b'),
      ('notify_absent_employees()', '0d117e202cbbcf08e9d1b35b4b4dab14'),
      ('process_attendance_penalties(uuid)', '7ea1046753bbcfbbb47bcb35c27f986e'),
      ('record_attendance_gps_v2(numeric,numeric,numeric,text,timestamp with time zone)', 'bd70c45984e188a38cceb45eea00fa00'),
      ('record_attendance_gps(numeric,numeric,numeric,text,timestamp with time zone)', '41f47aaff1eced8e368bce61cbd7a1a4'),
      ('run_attendance_operational_scan()', '40baaa14f7df81f78025d14ebb0fc288'),
      ('run_auto_checkout(date)', '7687df6dc398cd73ed53408c2c53d1a8'),
      ('scan_attendance_daily_review_alerts()', '9997ff7734f0289b85c5d9a3b8330c38'),
      ('scan_attendance_tracking_alerts()', '139e2ad118b89ff33d5052e67041e4e6'),
      ('settle_attendance_day_against_leave(uuid,boolean)', 'c5724ab559a12ca470bcd0bae8ad8206'),
      ('upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)', 'a0123e9ec343603dee9adf4ec73739b4')
  ), actual AS (
    SELECT p.oid::regprocedure::text AS signature,
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
    RAISE EXCEPTION 'M1 verify failed: existing function definitions changed:%', E'\n' || v_bad;
  END IF;

  -- Existing operational cron remains active and unchanged.
  IF NOT EXISTS (
    SELECT 1
    FROM cron.job
    WHERE jobname = 'scan-attendance-alerts'
      AND schedule = '*/15 * * * *'
      AND command = 'select public.run_attendance_operational_scan();'
      AND active = true
  ) THEN
    RAISE EXCEPTION 'M1 verify failed: attendance operational cron changed';
  END IF;
END;
$verify$;

-- Human-readable verification output.
SELECT jsonb_build_object(
  'status', 'pass',
  'feature_enabled', (
    SELECT value::BOOLEAN
    FROM public.company_settings
    WHERE key = 'hr.employee_work_schedules_enabled'
  ),
  'schedule_rows', (
    SELECT count(*) FROM public.hr_employee_work_schedules
  ),
  'schedule_day_rows', (
    SELECT count(*) FROM public.hr_employee_work_schedule_days
  ),
  'attendance_rows_with_snapshot', (
    SELECT count(*)
    FROM public.hr_attendance_days
    WHERE schedule_snapshot_at IS NOT NULL
  ),
  'runtime_functions_changed', false,
  'cron_unchanged', true,
  'direct_authenticated_writes', false
) AS m1_verification;

ROLLBACK;
