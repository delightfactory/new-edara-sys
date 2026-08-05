-- =============================================================================
-- Employee Work Schedules M3A — read-only verification
--
-- Run only after M1 + M2 + M3A + activation guard on a disposable database.
-- No attendance/payroll/schedule data is created or changed.
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '90s';

DO $verify$
DECLARE
  v_hash TEXT;
  v_definition TEXT;
  v_bad TEXT;
  v_public_result JSONB;
  v_legacy_result JSONB;
BEGIN
  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'M3A verify failed: feature switch is enabled';
  END IF;

  IF public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'M3A verify failed: activation readiness must still be false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'M3A verify failed: schedules were unexpectedly seeded';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.hr_attendance_days
    WHERE schedule_snapshot_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'M3A verify failed: attendance rows were unexpectedly snapshotted';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'company_settings'
      AND t.tgname = 'trg_company_settings_employee_schedule_activation_guard'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'M3A verify failed: activation guard trigger is missing';
  END IF;

  SELECT pg_get_functiondef('public.guard_employee_work_schedules_activation()'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%hr_employee_work_schedules_activation_ready%'
     OR v_definition NOT ILIKE '%cannot be enabled%' THEN
    RAISE EXCEPTION 'M3A verify failed: activation guard function is incomplete';
  END IF;

  -- The internal disabled-mode implementations must be byte-equivalent after
  -- normalizing only the function name back to its production name.
  SELECT md5(replace(
    pg_get_functiondef(
      'public.record_attendance_gps_v2_legacy_20260805(numeric,numeric,numeric,text,timestamp with time zone)'::regprocedure
    ),
    'FUNCTION public.record_attendance_gps_v2_legacy_20260805(',
    'FUNCTION public.record_attendance_gps_v2('
  )) INTO v_hash;
  IF v_hash <> 'bd70c45984e188a38cceb45eea00fa00' THEN
    RAISE EXCEPTION 'M3A verify failed: GPS v2 legacy clone mismatch (%)', v_hash;
  END IF;

  SELECT md5(replace(
    pg_get_functiondef(
      'public.upsert_attendance_and_reprocess_legacy_20260805(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)'::regprocedure
    ),
    'FUNCTION public.upsert_attendance_and_reprocess_legacy_20260805(',
    'FUNCTION public.upsert_attendance_and_reprocess('
  )) INTO v_hash;
  IF v_hash <> 'a0123e9ec343603dee9adf4ec73739b4' THEN
    RAISE EXCEPTION 'M3A verify failed: manual attendance legacy clone mismatch (%)', v_hash;
  END IF;

  SELECT md5(replace(
    pg_get_functiondef(
      'public.is_employee_work_day_legacy_20260805(uuid,date)'::regprocedure
    ),
    'FUNCTION public.is_employee_work_day_legacy_20260805(',
    'FUNCTION public.is_employee_work_day('
  )) INTO v_hash;
  IF v_hash <> '3e047334df57ad284bea8e9504724dd0' THEN
    RAISE EXCEPTION 'M3A verify failed: work-day legacy clone mismatch (%)', v_hash;
  END IF;

  -- The old RPC is intentionally untouched during M3A.
  SELECT md5(pg_get_functiondef(
    'public.record_attendance_gps(numeric,numeric,numeric,text,timestamp with time zone)'::regprocedure
  )) INTO v_hash;
  IF v_hash <> '41f47aaff1eced8e368bce61cbd7a1a4' THEN
    RAISE EXCEPTION 'M3A verify failed: legacy GPS RPC changed (%)', v_hash;
  END IF;

  -- Disabled-mode GPS wrapper must return the exact legacy response before any
  -- identity/location/data access. INVALID_LOG_TYPE is non-mutating.
  SELECT public.record_attendance_gps_v2(0, 0, 0, '__m3a_invalid__', now())
  INTO v_public_result;
  SELECT public.record_attendance_gps_v2_legacy_20260805(0, 0, 0, '__m3a_invalid__', now())
  INTO v_legacy_result;

  IF v_public_result IS DISTINCT FROM v_legacy_result THEN
    RAISE EXCEPTION
      'M3A verify failed: disabled GPS wrapper differs from legacy helper; public=% legacy=%',
      v_public_result,
      v_legacy_result;
  END IF;

  -- Disabled-mode work-day wrapper must equal the exact legacy helper for all
  -- current employees over a broad date sample.
  WITH sample AS (
    SELECT e.id AS employee_id, d::DATE AS target_date
    FROM public.hr_employees e
    CROSS JOIN generate_series(
      (now() AT TIME ZONE 'Africa/Cairo')::DATE - 31,
      (now() AT TIME ZONE 'Africa/Cairo')::DATE + 45,
      INTERVAL '1 day'
    ) d
  ), comparison AS (
    SELECT
      s.employee_id,
      s.target_date,
      public.is_employee_work_day(s.employee_id, s.target_date) AS wrapper_value,
      public.is_employee_work_day_legacy_20260805(s.employee_id, s.target_date) AS legacy_value
    FROM sample s
  )
  SELECT string_agg(
           format('%s %s wrapper=%s legacy=%s', employee_id, target_date, wrapper_value, legacy_value),
           E'\n' ORDER BY employee_id, target_date
         )
  INTO v_bad
  FROM comparison
  WHERE wrapper_value IS DISTINCT FROM legacy_value;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'M3A verify failed: disabled work-day parity mismatch:%', E'\n' || v_bad;
  END IF;

  -- Schedule-aware callers may not independently read company start/end times.
  SELECT pg_get_functiondef(
    'public.record_attendance_gps_v2_scheduled(numeric,numeric,numeric,text,timestamp with time zone)'::regprocedure
  ) INTO v_definition;
  IF v_definition ILIKE '%hr.work_start_time%'
     OR v_definition ILIKE '%hr.work_end_time%' THEN
    RAISE EXCEPTION 'M3A verify failed: scheduled GPS caller bypasses central resolver';
  END IF;

  IF v_definition NOT ILIKE '%schedule_snapshot_at%'
     OR v_definition NOT ILIKE '%ensure_attendance_schedule_snapshot%'
     OR v_definition NOT ILIKE '%resolve_employee_work_schedule%' THEN
    RAISE EXCEPTION 'M3A verify failed: scheduled GPS snapshot/resolver wiring is incomplete';
  END IF;

  SELECT pg_get_functiondef(
    'public.upsert_attendance_and_reprocess_scheduled(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)'::regprocedure
  ) INTO v_definition;
  IF v_definition ILIKE '%hr.work_start_time%'
     OR v_definition ILIKE '%hr.work_end_time%' THEN
    RAISE EXCEPTION 'M3A verify failed: scheduled manual caller bypasses central resolver';
  END IF;

  IF v_definition NOT ILIKE '%schedule_snapshot_at%'
     OR v_definition NOT ILIKE '%ensure_attendance_schedule_snapshot%'
     OR v_definition NOT ILIKE '%resolve_employee_work_schedule%' THEN
    RAISE EXCEPTION 'M3A verify failed: scheduled manual snapshot/resolver wiring is incomplete';
  END IF;

  -- Internal helpers must not be callable directly by application roles.
  IF has_function_privilege('authenticated', 'public.record_attendance_gps_v2_scheduled(numeric,numeric,numeric,text,timestamp with time zone)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.record_attendance_gps_v2_legacy_20260805(numeric,numeric,numeric,text,timestamp with time zone)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.upsert_attendance_and_reprocess_scheduled(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.upsert_attendance_and_reprocess_legacy_20260805(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.is_employee_work_day_legacy_20260805(uuid,date)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.record_attendance_gps_v2_scheduled(numeric,numeric,numeric,text,timestamp with time zone)', 'EXECUTE') THEN
    RAISE EXCEPTION 'M3A verify failed: an internal helper is exposed';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'activation_guard_structure', true,
  'legacy_gps_v2_parity', true,
  'legacy_work_day_parity', true,
  'attendance_rows_changed', false,
  'schedule_rows_seeded', false,
  'old_gps_rpc_changed', false,
  'internal_helpers_exposed', false
) AS m3a_verification;

ROLLBACK;
