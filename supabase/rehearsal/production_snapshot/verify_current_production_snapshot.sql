-- Verify the isolated HR V2 baseline before any V2 migration is applied.
-- The baseline is production-derived, dependency-scoped, schema-only, and contains
-- no production rows. Production was inspected read-only on 2026-08-07.

DO $snapshot$
DECLARE
  v_hash text;
  v_table text;
  v_required_tables text[] := ARRAY[
    'company_settings',
    'hr_attendance_alerts',
    'hr_attendance_days',
    'hr_attendance_logs',
    'hr_employees',
    'hr_leave_balances',
    'hr_leave_requests',
    'hr_leave_types',
    'hr_payroll_lines',
    'hr_payroll_periods',
    'hr_payroll_runs',
    'hr_penalty_instances',
    'hr_penalty_rules',
    'hr_permission_requests',
    'hr_public_holidays',
    'hr_work_locations',
    'role_permissions',
    'roles',
    'user_permission_overrides',
    'user_roles'
  ];
BEGIN
  FOREACH v_table IN ARRAY v_required_tables LOOP
    IF to_regclass('public.' || v_table) IS NULL THEN
      RAISE EXCEPTION 'HR V2 production-derived snapshot is missing required table: %', v_table;
    END IF;
  END LOOP;

  -- Current payroll sentinels that distinguish the real production baseline from
  -- the historical rehearsal state that caused Batch 4A drift.
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

  -- The snapshot must be pre-V2. Refuse a contaminated baseline.
  IF to_regclass('public.hr_employee_work_schedules') IS NOT NULL
     OR to_regprocedure('public.hr_variable_schedules_v2_runtime_enabled()') IS NOT NULL THEN
    RAISE EXCEPTION 'Snapshot unexpectedly contains HR Variable Schedules V2 objects';
  END IF;

  IF to_regprocedure('public.check_permission(uuid,text)') IS NULL
     OR to_regprocedure('public.resolve_employee_attendance_location_context(uuid,numeric,numeric,text)') IS NULL
     OR to_regprocedure('public.reprocess_attendance_day_penalties(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Required current HR support functions are missing from snapshot';
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n')) INTO v_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='calculate_employee_payroll'
    AND pg_get_function_identity_arguments(p.oid)='p_employee_id uuid, p_run_id uuid';
  IF v_hash IS DISTINCT FROM 'c24e182e9088e1a219d40aafb9e8c43a' THEN
    RAISE EXCEPTION 'Snapshot calculate_employee_payroll mismatch: %', v_hash;
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
