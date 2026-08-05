-- =============================================================================
-- Employee Work Schedules M2 — read-only structural and fallback verification
--
-- Run after M1 + M2 + M2 integrity on a disposable database first.
-- No DDL/DML is performed.
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '60s';

DO $verify$
DECLARE
  v_count INTEGER;
  v_bad TEXT;
BEGIN
  -- Feature stays disabled and no schedule data is seeded.
  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'M2 verify failed: feature switch is enabled';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'M2 verify failed: schedules were unexpectedly seeded';
  END IF;

  -- Required functions.
  SELECT count(*)
  INTO v_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.oid::regprocedure::TEXT IN (
      'hr_employee_work_schedules_enabled()',
      'hr_day_of_week_for_date(date)',
      'resolve_employee_work_schedule_core(uuid,date,boolean)',
      'resolve_employee_work_schedule(uuid,date)',
      'save_employee_work_schedule(uuid,date,jsonb,text)',
      'ensure_attendance_schedule_snapshot(uuid)',
      'guard_employee_work_schedule_header()',
      'guard_employee_work_schedule_delete()',
      'guard_employee_work_schedule_day_mutation()'
    );

  IF v_count <> 9 THEN
    RAISE EXCEPTION 'M2 verify failed: expected 9 M2 functions, found %', v_count;
  END IF;

  -- Only the guarded save RPC is executable by authenticated users.
  IF NOT has_function_privilege(
    'authenticated',
    'public.save_employee_work_schedule(uuid,date,jsonb,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'M2 verify failed: authenticated cannot execute guarded save RPC';
  END IF;

  IF has_function_privilege('authenticated', 'public.resolve_employee_work_schedule_core(uuid,date,boolean)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.resolve_employee_work_schedule(uuid,date)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ensure_attendance_schedule_snapshot(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.hr_employee_work_schedules_enabled()', 'EXECUTE') THEN
    RAISE EXCEPTION 'M2 verify failed: an internal resolver/helper is exposed to authenticated';
  END IF;

  -- One active lifecycle head per employee.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'hr_employee_work_schedules'
      AND indexname = 'hr_employee_work_schedules_one_active_idx'
      AND indexdef ILIKE '%UNIQUE INDEX%'
      AND indexdef ILIKE '%WHERE (status = ''active''::text)%'
  ) THEN
    RAISE EXCEPTION 'M2 verify failed: unique active schedule index is missing';
  END IF;

  -- Minute precision constraint.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname = 'hr_employee_work_schedule_days'
      AND c.conname = 'hr_employee_work_schedule_days_minute_precision_check'
      AND c.convalidated
  ) THEN
    RAISE EXCEPTION 'M2 verify failed: minute precision constraint is missing/unvalidated';
  END IF;

  -- Locale-independent weekday mapping.
  WITH expected(d, expected_day) AS (
    VALUES
      (DATE '2026-08-01', 'saturday'::public.hr_day_of_week),
      (DATE '2026-08-02', 'sunday'::public.hr_day_of_week),
      (DATE '2026-08-03', 'monday'::public.hr_day_of_week),
      (DATE '2026-08-04', 'tuesday'::public.hr_day_of_week),
      (DATE '2026-08-05', 'wednesday'::public.hr_day_of_week),
      (DATE '2026-08-06', 'thursday'::public.hr_day_of_week),
      (DATE '2026-08-07', 'friday'::public.hr_day_of_week)
  )
  SELECT string_agg(format('%s expected=%s actual=%s', d, expected_day, public.hr_day_of_week_for_date(d)), E'\n')
  INTO v_bad
  FROM expected
  WHERE public.hr_day_of_week_for_date(d) IS DISTINCT FROM expected_day;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'M2 verify failed: weekday mapping mismatch:%', E'\n' || v_bad;
  END IF;

  -- With no schedules and switch false, the new core fallback must match the
  -- current production work-day function for active employees across 45 days.
  WITH sample AS (
    SELECT e.id AS employee_id, d::DATE AS target_date
    FROM public.hr_employees e
    CROSS JOIN generate_series(
      (now() AT TIME ZONE 'Africa/Cairo')::DATE - 15,
      (now() AT TIME ZONE 'Africa/Cairo')::DATE + 29,
      INTERVAL '1 day'
    ) d
    WHERE e.status = 'active'
  ), comparison AS (
    SELECT
      s.employee_id,
      s.target_date,
      public.is_employee_work_day(s.employee_id, s.target_date) AS legacy_kind,
      r.day_kind AS new_kind
    FROM sample s
    CROSS JOIN LATERAL public.resolve_employee_work_schedule_core(
      s.employee_id,
      s.target_date,
      false
    ) r
  )
  SELECT string_agg(
           format('%s %s legacy=%s new=%s', employee_id, target_date, legacy_kind, new_kind),
           E'\n' ORDER BY employee_id, target_date
         )
  INTO v_bad
  FROM comparison
  WHERE legacy_kind IS DISTINCT FROM new_kind;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'M2 verify failed: legacy work-day parity mismatch:%', E'\n' || v_bad;
  END IF;

  -- Current production time contract: resolver fallback must be 11:00-19:00,
  -- 480 minutes on a representative non-holiday work day.
  WITH representative AS (
    SELECT e.id AS employee_id, d::DATE AS target_date
    FROM public.hr_employees e
    CROSS JOIN LATERAL generate_series(
      (now() AT TIME ZONE 'Africa/Cairo')::DATE,
      (now() AT TIME ZONE 'Africa/Cairo')::DATE + 30,
      INTERVAL '1 day'
    ) d
    WHERE e.status = 'active'
      AND public.is_employee_work_day(e.id, d::DATE) = 'work_day'
    ORDER BY e.id, d
    LIMIT 1
  )
  SELECT format(
           'source=%s minutes=%s start=%s end=%s',
           r.schedule_source,
           r.scheduled_minutes,
           r.scheduled_start_at AT TIME ZONE 'Africa/Cairo',
           r.scheduled_end_at AT TIME ZONE 'Africa/Cairo'
         )
  INTO v_bad
  FROM representative x
  CROSS JOIN LATERAL public.resolve_employee_work_schedule_core(
    x.employee_id,
    x.target_date,
    false
  ) r
  WHERE r.schedule_source <> 'company'
     OR r.scheduled_minutes <> 480
     OR (r.scheduled_start_at AT TIME ZONE 'Africa/Cairo')::TIME <> TIME '11:00'
     OR (r.scheduled_end_at AT TIME ZONE 'Africa/Cairo')::TIME <> TIME '19:00';

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'M2 verify failed: company fallback contract mismatch: %', v_bad;
  END IF;

  -- Base runtime functions remain unchanged through M2.
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
    RAISE EXCEPTION 'M2 verify failed: existing runtime definitions changed:%', E'\n' || v_bad;
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'seeded_schedules', (SELECT count(*) FROM public.hr_employee_work_schedules),
  'legacy_day_kind_parity', true,
  'company_fallback_minutes', 480,
  'existing_runtime_functions_changed', false,
  'authenticated_internal_function_access', false
) AS m2_verification;

ROLLBACK;
