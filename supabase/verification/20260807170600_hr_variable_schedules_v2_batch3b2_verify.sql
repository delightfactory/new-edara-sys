-- HR Variable Schedules V2 — Batch 3B2 verification
-- Read-only assertions for the isolated PostgreSQL rehearsal.

DO $verify$
DECLARE
  v_legacy_hash text;
  v_wrapper_body text;
  v_custom_body text;
BEGIN
  IF public.hr_variable_schedules_v2_runtime_enabled() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Batch 3B2 verification failed: V2 runtime gate must remain false';
  END IF;

  SELECT md5(replace(p.prosrc, E'\r\n', E'\n'))
  INTO v_legacy_hash
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'process_attendance_penalties_legacy'
    AND pg_get_function_identity_arguments(p.oid) = 'p_attendance_day_id uuid';

  IF v_legacy_hash IS DISTINCT FROM 'c05f834d11387ab8312965c16a065a0a' THEN
    RAISE EXCEPTION 'Batch 3B2 verification failed: Legacy penalty body drifted';
  END IF;

  SELECT p.prosrc
  INTO v_wrapper_body
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'process_attendance_penalties'
    AND pg_get_function_identity_arguments(p.oid) = 'p_attendance_day_id uuid';

  IF v_wrapper_body IS NULL
     OR position('IF NOT public.hr_variable_schedules_v2_runtime_enabled()' in v_wrapper_body) = 0
     OR position('process_attendance_penalties_legacy' in v_wrapper_body) = 0
     OR position('checkout_status <> ''early_unauthorized''' in v_wrapper_body) = 0
     OR position('resolve_employee_custom_schedule' in v_wrapper_body) = 0
     OR position('v_has_custom_schedule' in v_wrapper_body) = 0
     OR position('RAISE EXCEPTION ''Batch 3B2 refuses unauthorized early-leave penalty processing on a custom non-working day''' in v_wrapper_body) = 0
     OR position('process_attendance_penalties_custom_early_leave' in v_wrapper_body) = 0 THEN
    RAISE EXCEPTION 'Batch 3B2 verification failed: compatibility wrapper contract incomplete';
  END IF;

  IF position('IF NOT public.hr_variable_schedules_v2_runtime_enabled()' in v_wrapper_body)
     > position('resolve_employee_custom_schedule' in v_wrapper_body) THEN
    RAISE EXCEPTION 'Batch 3B2 verification failed: runtime gate is not checked before custom lookup';
  END IF;

  SELECT p.prosrc
  INTO v_custom_body
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'process_attendance_penalties_custom_early_leave'
    AND pg_get_function_identity_arguments(p.oid) = 'p_attendance_day_id uuid';

  IF v_custom_body IS NULL
     OR position('process_attendance_penalties_legacy' in v_custom_body) = 0
     OR position('penalty_type = ''early_leave_unauthorized''' in v_custom_body) = 0
     OR position('custom_scheduled_end' in v_custom_body) = 0
     OR position('custom_scheduled_minutes' in v_custom_body) = 0
     OR position('resolve_employee_custom_schedule' in v_custom_body) = 0
     OR position('v_early_end :=' in v_custom_body) = 0
     OR position('v_scheduled_end' in v_custom_body) = 0
     OR position('v_uncovered_minutes::numeric / v_scheduled_minutes::numeric' in v_custom_body) = 0
     OR position('hr_permission_requests' in v_custom_body) = 0
     OR position('actual_return' in v_custom_body) = 0
     OR position('expected_return' in v_custom_body) = 0
     OR position('duration_minutes' in v_custom_body) = 0 THEN
    RAISE EXCEPTION 'Batch 3B2 verification failed: custom early-leave calculation contract incomplete';
  END IF;

  IF NOT has_function_privilege('anon', 'public.process_attendance_penalties(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.process_attendance_penalties(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.process_attendance_penalties(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Batch 3B2 verification failed: public penalty execute contract changed';
  END IF;

  IF has_function_privilege('anon', 'public.process_attendance_penalties_legacy(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.process_attendance_penalties_legacy(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.process_attendance_penalties_custom_early_leave(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.process_attendance_penalties_custom_early_leave(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Batch 3B2 verification failed: internal penalty helper became externally executable';
  END IF;
END;
$verify$;

SELECT 'batch3b2_verify_pass' AS result;
