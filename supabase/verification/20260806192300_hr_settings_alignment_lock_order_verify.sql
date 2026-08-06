-- =============================================================================
-- Current company settings alignment lock order — read-only verification
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '60s';

DO $verify$
DECLARE
  v_definition TEXT;
  v_hr_lock_pos INTEGER;
  v_company_lock_pos INTEGER;
  v_update_pos INTEGER;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Alignment lock-order verify failed: feature/readiness must remain false';
  END IF;

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
      'Alignment lock-order verify failed: expected HR -> company -> update order';
  END IF;

  IF NOT has_function_privilege(
       'authenticated',
       'public.align_legacy_company_settings_to_current_version()',
       'EXECUTE'
     )
     OR has_function_privilege(
       'anon',
       'public.align_legacy_company_settings_to_current_version()',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Alignment lock-order verify failed: RPC grants changed';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'verification', 'company_settings_alignment_lock_order',
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'lock_order', jsonb_build_array('hr_settings_atomic', 'hr_company_work_schedules', 'company_settings_update'),
  'multi_session_rehearsal_required', true
) AS result;

ROLLBACK;
