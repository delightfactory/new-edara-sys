-- =============================================================================
-- Current company version alignment — read-only verification
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '60s';

DO $verify$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Current-version alignment verify failed: feature/readiness must remain false';
  END IF;

  SELECT pg_get_functiondef(
    'public.align_legacy_company_settings_to_current_version()'::regprocedure
  ) INTO v_definition;

  IF v_definition NOT ILIKE '%settings.update%'
     OR v_definition NOT ILIKE '%effective_range @> v_today%'
     OR v_definition NOT ILIKE '%FOR UPDATE%'
     OR v_definition NOT ILIKE '%legacy_company_settings_aligned_to_version%'
     OR v_definition NOT ILIKE '%hr_company_work_schedule_activation_consistent%' THEN
    RAISE EXCEPTION 'Current-version alignment verify failed: RPC contract is incomplete';
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
     )
     OR has_function_privilege(
       'service_role',
       'public.align_legacy_company_settings_to_current_version()',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Current-version alignment verify failed: RPC grants are incorrect';
  END IF;

  IF NOT public.hr_company_work_schedule_activation_consistent() THEN
    RAISE EXCEPTION 'Current-version alignment verify failed: installed state is inconsistent';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'verification', 'current_company_version_alignment',
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'company_history_consistent', public.hr_company_work_schedule_activation_consistent(),
  'authenticated_execute', true,
  'anonymous_execute', false,
  'service_role_execute', false
) AS result;

ROLLBACK;
