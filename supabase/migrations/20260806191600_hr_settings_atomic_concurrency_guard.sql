-- =============================================================================
-- EDARA — HR settings concurrency guard
--
-- Serializes the atomic RPC before it reads the current bundle and makes direct
-- HR setting updates use the same transaction lock. This prevents a waiting
-- writer from applying a bundle calculated from stale pre-lock values.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  IF to_regprocedure('public.update_hr_settings_atomic(jsonb)') IS NULL
     OR to_regclass('public.company_settings') IS NULL THEN
    RAISE EXCEPTION 'HR-settings concurrency preflight failed: atomic settings path is missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'HR-settings concurrency preflight failed: feature/readiness must remain false';
  END IF;

  IF to_regprocedure('public.serialize_hr_setting_value_update()') IS NOT NULL THEN
    RAISE EXCEPTION 'HR-settings concurrency preflight failed: serialization helper already exists';
  END IF;
END;
$preflight$;

-- Acquire the shared transaction lock before the RPC validates or reads any
-- current setting. Text surgery is fail-closed and targets exactly one marker.
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
  IF p_updates IS NULL OR jsonb_typeof(p_updates) <> 'array' THEN
$old$;

  v_new := $new$
  PERFORM pg_advisory_xact_lock(hashtextextended('hr_settings_atomic', 0));

  IF p_updates IS NULL OR jsonb_typeof(p_updates) <> 'array' THEN
$new$;

  v_occurrences := (
    length(v_definition) - length(replace(v_definition, v_old, ''))
  ) / length(v_old);

  IF v_occurrences <> 1 THEN
    RAISE EXCEPTION
      'HR-settings concurrency patch failed: atomic marker count=%',
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

CREATE FUNCTION public.serialize_hr_setting_value_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  IF OLD.category = 'hr' OR NEW.category = 'hr' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('hr_settings_atomic', 0));
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.serialize_hr_setting_value_update()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_company_settings_hr_serialization
  ON public.company_settings;
CREATE TRIGGER trg_company_settings_hr_serialization
  BEFORE UPDATE OF value ON public.company_settings
  FOR EACH ROW
  WHEN (OLD.category = 'hr' OR NEW.category = 'hr')
  EXECUTE FUNCTION public.serialize_hr_setting_value_update();

DO $assertions$
DECLARE
  v_definition TEXT;
  v_lock_pos INTEGER;
  v_read_pos INTEGER;
BEGIN
  SELECT pg_get_functiondef('public.update_hr_settings_atomic(jsonb)'::regprocedure)
  INTO v_definition;

  v_lock_pos := position(
    'pg_advisory_xact_lock(hashtextextended(''hr_settings_atomic'', 0))'
    IN v_definition
  );
  v_read_pos := position(
    'max(value) FILTER (WHERE key = ''hr.work_start_time'')'
    IN v_definition
  );

  IF v_lock_pos <= 0 OR v_read_pos <= 0 OR v_lock_pos >= v_read_pos THEN
    RAISE EXCEPTION
      'HR-settings concurrency assertion failed: RPC lock does not precede current-state read';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    WHERE t.tgrelid = 'public.company_settings'::regclass
      AND t.tgname = 'trg_company_settings_hr_serialization'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'HR-settings concurrency assertion failed: direct-write trigger is missing';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.serialize_hr_setting_value_update()',
    'EXECUTE'
  ) OR has_function_privilege(
    'service_role',
    'public.serialize_hr_setting_value_update()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'HR-settings concurrency assertion failed: trigger helper is exposed';
  END IF;
END;
$assertions$;

COMMIT;
