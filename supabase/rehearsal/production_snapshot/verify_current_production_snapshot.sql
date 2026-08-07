-- Verify that the isolated database was rebuilt from the current production
-- application schema before any HR Variable Schedules V2 migration is applied.
-- Production source was inspected read-only on 2026-08-07.

DO $snapshot$
DECLARE
  v_count bigint;
  v_hash text;
BEGIN
  -- Structural inventory: application-owned schemas only.
  SELECT count(*) INTO v_count
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r';
  IF v_count <> 125 THEN
    RAISE EXCEPTION 'Production snapshot public table count mismatch: expected 125, got %', v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'analytics' AND c.relkind = 'r';
  IF v_count <> 17 THEN
    RAISE EXCEPTION 'Production snapshot analytics table count mismatch: expected 17, got %', v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'private' AND c.relkind = 'r';
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'Production snapshot private table count mismatch: expected 2, got %', v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_policies WHERE schemaname = 'public';
  IF v_count <> 265 THEN
    RAISE EXCEPTION 'Production snapshot public RLS policy count mismatch: expected 265, got %', v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM pg_policies WHERE schemaname = 'analytics';
  IF v_count <> 18 THEN
    RAISE EXCEPTION 'Production snapshot analytics RLS policy count mismatch: expected 18, got %', v_count;
  END IF;

  -- Current payroll schema sentinels. These are precisely the columns that the
  -- old migration-reconstruction rehearsal was missing.
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='hr_payroll_runs'
      AND column_name='calculation_mode'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='hr_payroll_runs'
      AND column_name='calculated_through_date'
  ) THEN
    RAISE EXCEPTION 'Current payroll-run calculation columns are missing from snapshot';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='hr_payroll_lines'
      AND column_name='deficit_carryover'
  ) THEN
    RAISE EXCEPTION 'Current payroll deficit_carryover column is missing from snapshot';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='hr_advance_installments'
      AND column_name='deferred_reason'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='hr_advance_installments'
      AND column_name='deferred_to_month'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='hr_advance_installments'
      AND column_name='deferred_to_year'
  ) THEN
    RAISE EXCEPTION 'Current advance-installment defer columns are missing from snapshot';
  END IF;

  -- A production snapshot must predate V2. Refuse a contaminated baseline.
  IF to_regclass('public.hr_employee_work_schedules') IS NOT NULL
     OR to_regprocedure('public.hr_variable_schedules_v2_runtime_enabled()') IS NOT NULL THEN
    RAISE EXCEPTION 'Production snapshot unexpectedly contains HR Variable Schedules V2 objects';
  END IF;

  -- Exact current production function baselines. Normalized prosrc hashes avoid
  -- file newline representation differences while still guarding implementation drift.
  SELECT md5(replace(p.prosrc, E'\r\n', E'\n')) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='calculate_employee_payroll'
    AND pg_get_function_identity_arguments(p.oid)='p_employee_id uuid, p_run_id uuid';
  IF v_hash IS DISTINCT FROM 'c24e182e9088e1a219d40aafb9e8c43a' THEN
    RAISE EXCEPTION 'Snapshot calculate_employee_payroll mismatch: %', v_hash;
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n')) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='calculate_payroll_run'
    AND pg_get_function_identity_arguments(p.oid)='p_run_id uuid';
  IF v_hash IS DISTINCT FROM '2b79ef75f35f8deb2f2daa768e64d50f' THEN
    RAISE EXCEPTION 'Snapshot calculate_payroll_run mismatch: %', v_hash;
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n')) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='approve_payroll_run'
    AND pg_get_function_identity_arguments(p.oid)='p_run_id uuid, p_user_id uuid';
  IF v_hash IS DISTINCT FROM '4a3e9678f6a4c7b74f422d47c8239465' THEN
    RAISE EXCEPTION 'Snapshot approve_payroll_run mismatch: %', v_hash;
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n')) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='record_attendance_gps_v2'
    AND pg_get_function_identity_arguments(p.oid)=
      'p_latitude numeric, p_longitude numeric, p_gps_accuracy numeric, p_log_type text, p_event_time timestamp with time zone';
  IF v_hash IS DISTINCT FROM '12e9b106ce2992fd3268cadfde21558b' THEN
    RAISE EXCEPTION 'Snapshot record_attendance_gps_v2 mismatch: %', v_hash;
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n')) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='upsert_attendance_and_reprocess'
    AND pg_get_function_identity_arguments(p.oid)=
      'p_employee_id uuid, p_shift_date date, p_punch_in_time timestamp with time zone, p_punch_out_time timestamp with time zone, p_status hr_attendance_status, p_notes text, p_user_id uuid';
  IF v_hash IS DISTINCT FROM 'e00a7617452d6b2796366b9e9be12e90' THEN
    RAISE EXCEPTION 'Snapshot upsert_attendance_and_reprocess mismatch: %', v_hash;
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n')) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='is_employee_work_day'
    AND pg_get_function_identity_arguments(p.oid)='p_employee_id uuid, p_date date';
  IF v_hash IS DISTINCT FROM '561f564a44537961e799f5826cbf865b' THEN
    RAISE EXCEPTION 'Snapshot is_employee_work_day mismatch: %', v_hash;
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n')) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='mark_daily_absences'
    AND pg_get_function_identity_arguments(p.oid)='p_target_date date';
  IF v_hash IS DISTINCT FROM '45983089033bddad79c682d5b58f122e' THEN
    RAISE EXCEPTION 'Snapshot mark_daily_absences mismatch: %', v_hash;
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n')) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='run_auto_checkout'
    AND pg_get_function_identity_arguments(p.oid)='p_target_date date';
  IF v_hash IS DISTINCT FROM 'd13869f50592c2dc31c63e9212183c81' THEN
    RAISE EXCEPTION 'Snapshot run_auto_checkout mismatch: %', v_hash;
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n')) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='process_attendance_penalties'
    AND pg_get_function_identity_arguments(p.oid)='p_attendance_day_id uuid';
  IF v_hash IS DISTINCT FROM 'c05f834d11387ab8312965c16a065a0a' THEN
    RAISE EXCEPTION 'Snapshot process_attendance_penalties mismatch: %', v_hash;
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n')) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='settle_attendance_day_against_leave'
    AND pg_get_function_identity_arguments(p.oid)='p_attendance_day_id uuid, p_force boolean';
  IF v_hash IS DISTINCT FROM 'f0cd9bc5b6787e76aa970de6a9ce9370' THEN
    RAISE EXCEPTION 'Snapshot settle_attendance_day_against_leave mismatch: %', v_hash;
  END IF;
END;
$snapshot$;
