-- =============================================================================
-- Employee Work Schedules — admin context read verification
--
-- Run after all schedule migrations on a disposable database.
-- No DDL or business-data mutation is performed.
-- =============================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '60s';

DO $verify$
DECLARE
  v_actor UUID;
  v_context JSONB;
  v_defaults JSONB;
  v_keys TEXT[];
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Admin-context verify failed: feature/readiness must remain false';
  END IF;

  SELECT candidate.user_id
  INTO v_actor
  FROM (
    SELECT DISTINCT ur.user_id
    FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id = ur.role_id
    WHERE rp.permission IN (
      '*',
      'hr.employees.read',
      'hr.employees.edit',
      'hr.attendance.read'
    )
  ) candidate
  JOIN public.profiles p ON p.id = candidate.user_id
  ORDER BY candidate.user_id
  LIMIT 1;

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Admin-context verify failed: no authorized HR reader exists';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_actor::TEXT, true);

  SELECT public.get_employee_work_schedule_admin_context()
  INTO v_context;

  IF v_context IS NULL
     OR (v_context->>'installed')::BOOLEAN IS DISTINCT FROM true
     OR (v_context->>'enabled')::BOOLEAN IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Admin-context verify failed: invalid feature state: %', v_context;
  END IF;

  SELECT array_agg(key ORDER BY key)
  INTO v_keys
  FROM jsonb_object_keys(v_context) key;

  IF v_keys IS DISTINCT FROM ARRAY['company_defaults', 'enabled', 'installed']::TEXT[] THEN
    RAISE EXCEPTION 'Admin-context verify failed: unexpected top-level keys: %', v_keys;
  END IF;

  v_defaults := v_context->'company_defaults';

  SELECT array_agg(key ORDER BY key)
  INTO v_keys
  FROM jsonb_object_keys(v_defaults) key;

  IF v_keys IS DISTINCT FROM ARRAY[
    'end_time',
    'start_time',
    'weekly_off_day',
    'work_hours_per_day'
  ]::TEXT[] THEN
    RAISE EXCEPTION 'Admin-context verify failed: unexpected default keys: %', v_keys;
  END IF;

  IF v_defaults->>'start_time' <> '11:00'
     OR v_defaults->>'end_time' <> '19:00'
     OR (v_defaults->>'work_hours_per_day')::NUMERIC <> 8
     OR v_defaults->>'weekly_off_day' <> 'friday' THEN
    RAISE EXCEPTION 'Admin-context verify failed: current company defaults mismatch: %', v_defaults;
  END IF;

  SELECT pg_get_functiondef('public.get_employee_work_schedule_admin_context()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%SECURITY DEFINER%'
     OR v_definition NOT ILIKE '%hr.employees.read%'
     OR v_definition NOT ILIKE '%hr.employees.edit%'
     OR v_definition NOT ILIKE '%hr.attendance.read%'
     OR v_definition NOT ILIKE '%WHERE key IN%'
     OR v_definition ILIKE '%SELECT * FROM public.company_settings%' THEN
    RAISE EXCEPTION 'Admin-context verify failed: function scope or permission guard is incomplete';
  END IF;

  IF NOT has_function_privilege(
    'authenticated',
    'public.get_employee_work_schedule_admin_context()',
    'EXECUTE'
  ) OR has_function_privilege(
    'anon',
    'public.get_employee_work_schedule_admin_context()',
    'EXECUTE'
  ) OR has_function_privilege(
    'service_role',
    'public.get_employee_work_schedule_admin_context()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Admin-context verify failed: execution grants are incorrect';
  END IF;
END;
$verify$;

SELECT jsonb_build_object(
  'status', 'pass',
  'feature_enabled', public.hr_employee_work_schedules_enabled(),
  'activation_ready', public.hr_employee_work_schedules_activation_ready(),
  'least_privilege_context', true,
  'arbitrary_settings_exposed', false,
  'runtime_data_changed', false
) AS admin_context_verification;

ROLLBACK;
