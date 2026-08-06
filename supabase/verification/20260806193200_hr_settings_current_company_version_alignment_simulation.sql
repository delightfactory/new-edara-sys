-- =============================================================================
-- Legacy settings/current company version alignment — disposable simulation
--
-- DISPOSABLE DATABASE ONLY. Requires:
--   SET SESSION edara.allow_schedule_simulation = 'disposable-only';
-- All writes roll back.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '90s';

DO $simulation$
DECLARE
  v_actor UUID;
  v_current public.hr_company_work_schedules%ROWTYPE;
  v_expected_start TEXT;
  v_result JSONB;
BEGIN
  IF current_setting('edara.allow_schedule_simulation', true) IS DISTINCT FROM 'disposable-only' THEN
    RAISE EXCEPTION 'Simulation safety stop: disposable-only session flag is required';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready()
     OR NOT public.hr_company_work_schedule_activation_consistent() THEN
    RAISE EXCEPTION 'Alignment simulation requires the clean consistent installed state';
  END IF;

  SELECT candidate.user_id
  INTO v_actor
  FROM (
    SELECT ur.user_id
    FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id = ur.role_id
    WHERE rp.permission IN ('*', 'settings.update')
    GROUP BY ur.user_id
    HAVING bool_or(rp.permission IN ('*', 'settings.update'))
  ) candidate
  JOIN public.profiles p ON p.id = candidate.user_id
  ORDER BY candidate.user_id
  LIMIT 1;

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Alignment simulation could not find an authorized actor';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_actor::TEXT, true);

  SELECT * INTO v_current
  FROM public.hr_company_work_schedules s
  WHERE s.status IN ('active', 'retired')
    AND s.effective_range @> (now() AT TIME ZONE 'Africa/Cairo')::DATE;

  v_expected_start := to_char(v_current.start_time, 'HH24:MI');

  -- Emulate a delayed-activation mismatch inside the same transaction. The
  -- deferred constraint has not run yet, so the alignment RPC can repair it.
  UPDATE public.company_settings
  SET value = CASE WHEN v_expected_start = '09:00' THEN '10:00' ELSE '09:00' END
  WHERE key = 'hr.work_start_time';

  IF public.hr_company_work_schedule_activation_consistent() THEN
    RAISE EXCEPTION 'Alignment simulation failed: deliberate mismatch was not detected';
  END IF;

  SELECT public.align_legacy_company_settings_to_current_version()
  INTO v_result;

  SET CONSTRAINTS trg_company_settings_schedule_consistency_deferred IMMEDIATE;
  SET CONSTRAINTS trg_company_settings_schedule_consistency_deferred DEFERRED;

  IF COALESCE((v_result->>'success')::BOOLEAN, false) = false
     OR (SELECT value FROM public.company_settings WHERE key = 'hr.work_start_time') <> v_expected_start
     OR NOT public.hr_company_work_schedule_activation_consistent() THEN
    RAISE EXCEPTION 'Alignment simulation failed: current version was not restored atomically';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.audit_logs a
    WHERE a.action = 'legacy_company_settings_aligned_to_version'
      AND a.entity_id = v_current.id
      AND a.user_id = v_actor
  ) THEN
    RAISE EXCEPTION 'Alignment simulation failed: audit record is missing';
  END IF;

  RAISE NOTICE 'Current-version alignment simulation passed; all data will roll back';
END;
$simulation$;

ROLLBACK;
