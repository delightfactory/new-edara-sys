-- HR Variable Schedules V2 — Batch 2B verification
-- Read-only assertions. Intended for the later disposable PostgreSQL rehearsal.

DO $verify$
DECLARE
  v_body_hash text;
  v_wrapper_body text;
  v_custom_body text;
BEGIN
  IF public.hr_variable_schedules_v2_runtime_enabled() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Batch 2B verification failed: V2 runtime gate must remain false';
  END IF;

  SELECT md5(p.prosrc)
  INTO v_body_hash
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'upsert_attendance_and_reprocess_legacy'
    AND pg_get_function_identity_arguments(p.oid) =
      'p_employee_id uuid, p_shift_date date, p_punch_in_time timestamp with time zone, p_punch_out_time timestamp with time zone, p_status hr_attendance_status, p_notes text, p_user_id uuid';

  IF v_body_hash IS DISTINCT FROM 'a371dedb6b7b1aad184ea976f7aa2b59' THEN
    RAISE EXCEPTION 'Batch 2B verification failed: Legacy admin-attendance body drifted';
  END IF;

  SELECT p.prosrc
  INTO v_wrapper_body
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'upsert_attendance_and_reprocess'
    AND pg_get_function_identity_arguments(p.oid) =
      'p_employee_id uuid, p_shift_date date, p_punch_in_time timestamp with time zone, p_punch_out_time timestamp with time zone, p_status hr_attendance_status, p_notes text, p_user_id uuid';

  IF v_wrapper_body IS NULL THEN
    RAISE EXCEPTION 'Batch 2B verification failed: public wrapper missing';
  END IF;

  IF position('IF NOT public.hr_variable_schedules_v2_runtime_enabled()' in v_wrapper_body) = 0
     OR position('resolve_employee_custom_schedule' in v_wrapper_body) = 0
     OR position('IF NOT public.hr_variable_schedules_v2_runtime_enabled()' in v_wrapper_body)
        > position('resolve_employee_custom_schedule' in v_wrapper_body) THEN
    RAISE EXCEPTION 'Batch 2B verification failed: fail-closed dispatch is not before custom schedule lookup';
  END IF;

  IF NOT has_function_privilege('anon',
      'public.upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)',
      'EXECUTE')
     OR NOT has_function_privilege('authenticated',
      'public.upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)',
      'EXECUTE') THEN
    RAISE EXCEPTION 'Batch 2B verification failed: public RPC execute contract changed';
  END IF;

  IF has_function_privilege('anon',
      'public.upsert_attendance_and_reprocess_legacy(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)',
      'EXECUTE')
     OR has_function_privilege('authenticated',
      'public.upsert_attendance_and_reprocess_legacy(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)',
      'EXECUTE')
     OR has_function_privilege('anon',
      'public.upsert_attendance_and_reprocess_custom_schedule(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)',
      'EXECUTE')
     OR has_function_privilege('authenticated',
      'public.upsert_attendance_and_reprocess_custom_schedule(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)',
      'EXECUTE') THEN
    RAISE EXCEPTION 'Batch 2B verification failed: internal implementation became externally executable';
  END IF;

  SELECT p.prosrc
  INTO v_custom_body
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'upsert_attendance_and_reprocess_custom_schedule';

  IF v_custom_body IS NULL
     OR position('custom_schedule_id' in v_custom_body) = 0
     OR position('custom_scheduled_minutes' in v_custom_body) = 0
     OR position('interval ''30 minutes''' in v_custom_body) = 0
     OR position('interval ''5 minutes''' in v_custom_body) = 0
     OR position('settle_attendance_day_against_leave' in v_custom_body) = 0
     OR position('reprocess_attendance_day_penalties' in v_custom_body) = 0 THEN
    RAISE EXCEPTION 'Batch 2B verification failed: custom admin timing/legacy-downstream contract incomplete';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_attendance_days
    WHERE custom_schedule_id IS NULL
      AND (
        custom_scheduled_start IS NOT NULL
        OR custom_scheduled_end IS NOT NULL
        OR custom_scheduled_minutes IS NOT NULL
      )
  ) THEN
    RAISE EXCEPTION 'Batch 2B verification failed: invalid partial custom snapshot exists';
  END IF;
END;
$verify$;
