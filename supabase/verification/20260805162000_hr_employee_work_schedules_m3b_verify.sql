-- =============================================================================
-- Employee Work Schedules M3B — read-only verification
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '60s';

DO $verify$
DECLARE
  v_hash TEXT;
  v_definition TEXT;
  v_public_result JSONB;
  v_legacy_result JSONB;
BEGIN
  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'M3B verify failed: feature switch is enabled';
  END IF;

  IF public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'M3B verify failed: activation readiness must remain false';
  END IF;

  SELECT md5(replace(
    pg_get_functiondef(
      'public.record_attendance_gps_legacy_20260805(numeric,numeric,numeric,text,timestamp with time zone)'::regprocedure
    ),
    'FUNCTION public.record_attendance_gps_legacy_20260805(',
    'FUNCTION public.record_attendance_gps('
  )) INTO v_hash;

  IF v_hash <> '41f47aaff1eced8e368bce61cbd7a1a4' THEN
    RAISE EXCEPTION 'M3B verify failed: legacy GPS clone mismatch (%)', v_hash;
  END IF;

  SELECT pg_get_functiondef(
    'public.record_attendance_gps(numeric,numeric,numeric,text,timestamp with time zone)'::regprocedure
  ) INTO v_definition;

  IF v_definition NOT ILIKE '%hr_employee_work_schedules_enabled%'
     OR v_definition NOT ILIKE '%record_attendance_gps_legacy_20260805%'
     OR v_definition NOT ILIKE '%record_attendance_gps_v2_scheduled%' THEN
    RAISE EXCEPTION 'M3B verify failed: public compatibility wrapper is incomplete';
  END IF;

  -- INVALID_LOG_TYPE returns before identity/location/data access and is safe
  -- for proving disabled-mode response parity.
  SELECT public.record_attendance_gps(0, 0, 0, '__m3b_invalid__', now())
  INTO v_public_result;
  SELECT public.record_attendance_gps_legacy_20260805(0, 0, 0, '__m3b_invalid__', now())
  INTO v_legacy_result;

  IF v_public_result IS DISTINCT FROM v_legacy_result THEN
    RAISE EXCEPTION
      'M3B verify failed: disabled legacy GPS wrapper differs; public=% legacy=%',
      v_public_result,
      v_legacy_result;
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.record_attendance_gps_legacy_20260805(numeric,numeric,numeric,text,timestamp with time zone)',
    'EXECUTE'
  ) OR has_function_privilege(
    'service_role',
    'public.record_attendance_gps_legacy_20260805(numeric,numeric,numeric,text,timestamp with time zone)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'M3B verify failed: internal legacy helper is exposed';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'disabled_legacy_response_parity', true,
  'enabled_route_targets_schedule_aware_v2', true,
  'legacy_signature_preserved', true,
  'internal_helper_exposed', false
) AS m3b_verification;

ROLLBACK;
