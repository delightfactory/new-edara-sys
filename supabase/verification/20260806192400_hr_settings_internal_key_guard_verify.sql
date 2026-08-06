-- =============================================================================
-- Internal HR activation key isolation — read-only verification
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '60s';

DO $verify$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Internal-key verify failed: feature/readiness must remain false';
  END IF;

  SELECT pg_get_functiondef('public.update_hr_settings_atomic(jsonb)'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%hr.employee_work_schedules_enabled%'
     OR v_definition NOT ILIKE '%مفتاح تفعيل جداول الموظفين داخلي%'
     OR v_definition NOT ILIKE '%settings.update%'
     OR v_definition NOT ILIKE '%hr_settings_updated_atomic%' THEN
    RAISE EXCEPTION 'Internal-key verify failed: generic RPC isolation is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.guard_employee_work_schedules_activation()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%hr.employee_work_schedules_enabled%'
     OR v_definition NOT ILIKE '%hr_employee_work_schedules_activation_ready%'
     OR v_definition NOT ILIKE '%cannot be enabled%' THEN
    RAISE EXCEPTION 'Internal-key verify failed: release activation guard changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    WHERE t.tgrelid = 'public.company_settings'::regclass
      AND t.tgname = 'trg_company_settings_employee_schedule_activation_guard'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'Internal-key verify failed: activation trigger is missing';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'verification', 'internal_hr_activation_key_isolation',
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'generic_settings_rpc_rejects_key', true,
  'release_activation_trigger_present', true,
  'dedicated_final_activation_required', true
) AS result;

ROLLBACK;
