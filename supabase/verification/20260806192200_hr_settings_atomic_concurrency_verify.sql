-- =============================================================================
-- Atomic HR settings concurrency guard — read-only verification
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '60s';

DO $verify$
DECLARE
  v_definition TEXT;
  v_trigger_definition TEXT;
  v_lock_pos INTEGER;
  v_read_pos INTEGER;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'HR-settings concurrency verify failed: feature/readiness must remain false';
  END IF;

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
      'HR-settings concurrency verify failed: atomic lock does not precede state read';
  END IF;

  SELECT pg_get_functiondef('public.serialize_hr_setting_value_update()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%hashtextextended(''hr_settings_atomic'', 0)%'
     OR v_definition NOT ILIKE '%OLD.category = ''hr'' OR NEW.category = ''hr''%' THEN
    RAISE EXCEPTION 'HR-settings concurrency verify failed: direct-write serializer is incomplete';
  END IF;

  SELECT pg_get_triggerdef(t.oid, true)
  INTO v_trigger_definition
  FROM pg_trigger t
  WHERE t.tgrelid = 'public.company_settings'::regclass
    AND t.tgname = 'trg_company_settings_hr_serialization'
    AND NOT t.tgisinternal;

  IF v_trigger_definition IS NULL
     OR v_trigger_definition NOT ILIKE '%BEFORE UPDATE OF value%'
     OR v_trigger_definition NOT ILIKE '%serialize_hr_setting_value_update%' THEN
    RAISE EXCEPTION 'HR-settings concurrency verify failed: serialization trigger is incomplete';
  END IF;

  IF has_function_privilege(
       'authenticated',
       'public.serialize_hr_setting_value_update()',
       'EXECUTE'
     )
     OR has_function_privilege(
       'service_role',
       'public.serialize_hr_setting_value_update()',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'HR-settings concurrency verify failed: trigger helper is externally exposed';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'verification', 'atomic_hr_settings_concurrency_guard',
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'atomic_lock_precedes_read', true,
  'direct_writes_share_lock', true,
  'multi_session_rehearsal_required', true
) AS result;

ROLLBACK;
