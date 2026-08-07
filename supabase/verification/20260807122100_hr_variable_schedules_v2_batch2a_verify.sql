-- HR Variable Schedules V2 — Batch 2A verification
-- Read-only assertions after applying Batch 1 + Batch 2A to an isolated database.

DO $verify$
DECLARE
  v_body_hash text;
  v_gate boolean;
  v_count integer;
BEGIN
  -- Fail-closed runtime gate must remain disabled throughout development batches.
  SELECT public.hr_variable_schedules_v2_runtime_enabled() INTO v_gate;
  IF v_gate IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Batch 2A runtime gate must be false';
  END IF;

  -- Renaming must preserve the exact production Legacy body independent of function name.
  SELECT md5(p.prosrc)
  INTO v_body_hash
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'record_attendance_gps_v2_legacy'
    AND pg_get_function_identity_arguments(p.oid) =
      'p_latitude numeric, p_longitude numeric, p_gps_accuracy numeric, p_log_type text, p_event_time timestamp with time zone';

  IF v_body_hash IS DISTINCT FROM '8d8e6f188962e81933949e6472ba4541' THEN
    RAISE EXCEPTION 'Legacy GPS attendance body drifted during Batch 2A';
  END IF;

  IF to_regprocedure('public.record_attendance_gps_v2(numeric,numeric,numeric,text,timestamp with time zone)') IS NULL
     OR to_regprocedure('public.record_attendance_gps_v2_custom_schedule(numeric,numeric,numeric,text,timestamp with time zone)') IS NULL THEN
    RAISE EXCEPTION 'Batch 2A wrapper/custom function missing';
  END IF;

  -- The public RPC keeps its historical execution contract.
  IF NOT has_function_privilege('anon', 'public.record_attendance_gps_v2(numeric,numeric,numeric,text,timestamp with time zone)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.record_attendance_gps_v2(numeric,numeric,numeric,text,timestamp with time zone)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.record_attendance_gps_v2(numeric,numeric,numeric,text,timestamp with time zone)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Public GPS attendance RPC grant contract changed';
  END IF;

  -- Internal aliases must not become bypass RPCs.
  IF has_function_privilege('anon', 'public.record_attendance_gps_v2_legacy(numeric,numeric,numeric,text,timestamp with time zone)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.record_attendance_gps_v2_legacy(numeric,numeric,numeric,text,timestamp with time zone)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.record_attendance_gps_v2_custom_schedule(numeric,numeric,numeric,text,timestamp with time zone)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.record_attendance_gps_v2_custom_schedule(numeric,numeric,numeric,text,timestamp with time zone)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Internal GPS attendance implementation is externally executable';
  END IF;

  -- Snapshot columns must exist and remain nullable for all historical rows.
  SELECT count(*) INTO v_count
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'hr_attendance_days'
    AND column_name IN (
      'custom_schedule_id',
      'custom_scheduled_start',
      'custom_scheduled_end',
      'custom_scheduled_minutes'
    )
    AND is_nullable = 'YES';

  IF v_count <> 4 THEN
    RAISE EXCEPTION 'Batch 2A custom schedule snapshot columns are missing or non-nullable';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.hr_attendance_days
    WHERE custom_schedule_id IS NOT NULL
       OR custom_scheduled_start IS NOT NULL
       OR custom_scheduled_end IS NOT NULL
       OR custom_scheduled_minutes IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Batch 2A unexpectedly backfilled existing attendance rows';
  END IF;
END;
$verify$;

SELECT 'batch2a_verify_pass' AS result;
