-- =============================================================================
-- EDARA — Current-version alignment lock-order correction
--
-- All paths that may touch both company_settings and company schedule history
-- must acquire the HR-settings lock first, then the company-history lock.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  IF to_regprocedure('public.align_legacy_company_settings_to_current_version()') IS NULL
     OR to_regprocedure('public.serialize_hr_setting_value_update()') IS NULL THEN
    RAISE EXCEPTION 'Alignment lock-order preflight failed: required paths are missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Alignment lock-order preflight failed: feature/readiness must remain false';
  END IF;
END;
$preflight$;

DO $patch_alignment$
DECLARE
  v_definition TEXT;
  v_old TEXT;
  v_new TEXT;
  v_occurrences INTEGER;
BEGIN
  SELECT pg_get_functiondef(
    'public.align_legacy_company_settings_to_current_version()'::regprocedure
  ) INTO v_definition;

  v_definition := replace(v_definition, E'\r\n', E'\n');
  v_definition := replace(v_definition, E'\r', E'\n');

  v_old := $old$
  PERFORM pg_advisory_xact_lock(hashtextextended('hr_company_work_schedules', 0));
$old$;

  v_new := $new$
  PERFORM pg_advisory_xact_lock(hashtextextended('hr_settings_atomic', 0));
  PERFORM pg_advisory_xact_lock(hashtextextended('hr_company_work_schedules', 0));
$new$;

  v_occurrences := (
    length(v_definition) - length(replace(v_definition, v_old, ''))
  ) / length(v_old);

  IF v_occurrences <> 1 THEN
    RAISE EXCEPTION
      'Alignment lock-order patch failed: company-lock marker count=%',
      v_occurrences;
  END IF;

  v_definition := replace(v_definition, v_old, v_new);
  EXECUTE v_definition;
END;
$patch_alignment$;

REVOKE ALL ON FUNCTION public.align_legacy_company_settings_to_current_version()
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.align_legacy_company_settings_to_current_version()
  TO authenticated;

DO $assertions$
DECLARE
  v_definition TEXT;
  v_hr_lock_pos INTEGER;
  v_company_lock_pos INTEGER;
  v_update_pos INTEGER;
BEGIN
  SELECT pg_get_functiondef(
    'public.align_legacy_company_settings_to_current_version()'::regprocedure
  ) INTO v_definition;

  v_hr_lock_pos := position(
    'pg_advisory_xact_lock(hashtextextended(''hr_settings_atomic'', 0))'
    IN v_definition
  );
  v_company_lock_pos := position(
    'pg_advisory_xact_lock(hashtextextended(''hr_company_work_schedules'', 0))'
    IN v_definition
  );
  v_update_pos := position('UPDATE public.company_settings' IN v_definition);

  IF v_hr_lock_pos <= 0
     OR v_company_lock_pos <= 0
     OR v_update_pos <= 0
     OR v_hr_lock_pos >= v_company_lock_pos
     OR v_company_lock_pos >= v_update_pos THEN
    RAISE EXCEPTION
      'Alignment lock-order assertion failed: expected HR -> company -> update order';
  END IF;
END;
$assertions$;

COMMIT;
