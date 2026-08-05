-- =============================================================================
-- EDARA — Employee Work Schedules M3B
-- Compatibility bridge for the legacy record_attendance_gps RPC.
--
-- Disabled mode: exact current production implementation.
-- Enabled mode: delegates to the reviewed schedule-aware v2 implementation.
-- The legacy public signature is preserved; nothing is deleted.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
DECLARE
  v_hash TEXT;
BEGIN
  IF to_regprocedure('public.record_attendance_gps_v2_scheduled(numeric,numeric,numeric,text,timestamp with time zone)') IS NULL
     OR to_regprocedure('public.hr_employee_work_schedules_activation_ready()') IS NULL THEN
    RAISE EXCEPTION 'M3B preflight failed: M3A runtime/activation guard is missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'M3B preflight failed: feature switch must remain false';
  END IF;

  IF public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'M3B preflight failed: release readiness must remain false';
  END IF;

  IF to_regprocedure('public.record_attendance_gps_legacy_20260805(numeric,numeric,numeric,text,timestamp with time zone)') IS NOT NULL THEN
    RAISE EXCEPTION 'M3B preflight failed: legacy GPS helper already exists';
  END IF;

  SELECT md5(pg_get_functiondef(
    'public.record_attendance_gps(numeric,numeric,numeric,text,timestamp with time zone)'::regprocedure
  )) INTO v_hash;

  IF v_hash <> '41f47aaff1eced8e368bce61cbd7a1a4' THEN
    RAISE EXCEPTION 'M3B preflight failed: record_attendance_gps drifted (%)', v_hash;
  END IF;
END;
$preflight$;

-- Clone exact current implementation under a private internal name.
DO $clone_legacy$
DECLARE
  v_definition TEXT;
BEGIN
  SELECT pg_get_functiondef(
    'public.record_attendance_gps(numeric,numeric,numeric,text,timestamp with time zone)'::regprocedure
  ) INTO v_definition;

  v_definition := replace(
    v_definition,
    'FUNCTION public.record_attendance_gps(',
    'FUNCTION public.record_attendance_gps_legacy_20260805('
  );

  EXECUTE v_definition;
END;
$clone_legacy$;

REVOKE ALL ON FUNCTION public.record_attendance_gps_legacy_20260805(NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.record_attendance_gps_legacy_20260805(NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ) IS
  'Internal exact pre-M3B legacy GPS implementation. Used only while employee work schedules are disabled.';

CREATE OR REPLACE FUNCTION public.record_attendance_gps(
  p_latitude NUMERIC,
  p_longitude NUMERIC,
  p_gps_accuracy NUMERIC,
  p_log_type TEXT,
  p_event_time TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF NOT public.hr_employee_work_schedules_enabled() THEN
    RETURN public.record_attendance_gps_legacy_20260805(
      p_latitude,
      p_longitude,
      p_gps_accuracy,
      p_log_type,
      p_event_time
    );
  END IF;

  -- All enabled-mode attendance uses one reviewed schedule-aware path. This
  -- prevents an old client from bypassing immutable schedule snapshots.
  RETURN public.record_attendance_gps_v2_scheduled(
    p_latitude,
    p_longitude,
    p_gps_accuracy,
    p_log_type,
    p_event_time
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.record_attendance_gps(NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ)
  TO anon, authenticated, service_role;

DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'M3B assertion failed: feature switch became enabled';
  END IF;

  IF public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'M3B assertion failed: activation readiness became true';
  END IF;

  SELECT pg_get_functiondef(
    'public.record_attendance_gps(numeric,numeric,numeric,text,timestamp with time zone)'::regprocedure
  ) INTO v_definition;

  IF v_definition NOT ILIKE '%record_attendance_gps_legacy_20260805%'
     OR v_definition NOT ILIKE '%record_attendance_gps_v2_scheduled%'
     OR v_definition NOT ILIKE '%hr_employee_work_schedules_enabled%' THEN
    RAISE EXCEPTION 'M3B assertion failed: compatibility wrapper is incomplete';
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
    RAISE EXCEPTION 'M3B assertion failed: internal legacy GPS helper is exposed';
  END IF;
END;
$assertions$;

COMMIT;
