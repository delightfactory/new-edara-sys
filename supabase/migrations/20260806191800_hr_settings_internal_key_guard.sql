-- =============================================================================
-- EDARA — Internal HR settings key guard
--
-- The employee-schedule feature switch is a release control, not a generic HR
-- setting. It may only be handled by the final dedicated activation workflow.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  IF to_regprocedure('public.update_hr_settings_atomic(jsonb)') IS NULL
     OR to_regprocedure('public.guard_employee_work_schedules_activation()') IS NULL THEN
    RAISE EXCEPTION 'Internal-key guard preflight failed: settings/activation guards are missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Internal-key guard preflight failed: feature/readiness must remain false';
  END IF;
END;
$preflight$;

DO $patch_atomic_rpc$
DECLARE
  v_definition TEXT;
  v_old TEXT;
  v_new TEXT;
  v_occurrences INTEGER;
BEGIN
  SELECT pg_get_functiondef('public.update_hr_settings_atomic(jsonb)'::regprocedure)
  INTO v_definition;

  v_definition := replace(v_definition, E'\r\n', E'\n');
  v_definition := replace(v_definition, E'\r', E'\n');

  v_old := $old$
  v_input_count := jsonb_array_length(p_updates);
$old$;

  v_new := $new$
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_updates) item
    WHERE btrim(item->>'key') = 'hr.employee_work_schedules_enabled'
  ) THEN
    RAISE EXCEPTION
      'مفتاح تفعيل جداول الموظفين داخلي ولا يُحفظ من شاشة إعدادات HR العامة';
  END IF;

  v_input_count := jsonb_array_length(p_updates);
$new$;

  v_occurrences := (
    length(v_definition) - length(replace(v_definition, v_old, ''))
  ) / length(v_old);

  IF v_occurrences <> 1 THEN
    RAISE EXCEPTION
      'Internal-key guard patch failed: input-count marker count=%',
      v_occurrences;
  END IF;

  v_definition := replace(v_definition, v_old, v_new);
  EXECUTE v_definition;
END;
$patch_atomic_rpc$;

REVOKE ALL ON FUNCTION public.update_hr_settings_atomic(JSONB)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.update_hr_settings_atomic(JSONB)
  TO authenticated;

DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  SELECT pg_get_functiondef('public.update_hr_settings_atomic(jsonb)'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%hr.employee_work_schedules_enabled%'
     OR v_definition NOT ILIKE '%مفتاح تفعيل جداول الموظفين داخلي%'
     OR v_definition NOT ILIKE '%pg_advisory_xact_lock(hashtextextended(''hr_settings_atomic'', 0))%' THEN
    RAISE EXCEPTION 'Internal-key guard assertion failed: RPC protection is incomplete';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Internal-key guard assertion failed: feature/readiness changed';
  END IF;
END;
$assertions$;

COMMIT;
