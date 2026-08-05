-- =============================================================================
-- Employee Work Schedules — activation guard simulation
--
-- Run only on a disposable database after M3A + activation guard.
-- This file performs one guarded UPDATE inside a transaction and always rolls
-- back. Its purpose is to prove the trigger, not read-only mode, blocks enablement.
-- =============================================================================

BEGIN;
SET LOCAL statement_timeout = '30s';

DO $simulation$
DECLARE
  v_before TEXT;
  v_after TEXT;
  v_blocked BOOLEAN := false;
  v_error TEXT;
BEGIN
  SELECT value
  INTO v_before
  FROM public.company_settings
  WHERE key = 'hr.employee_work_schedules_enabled'
  FOR UPDATE;

  IF v_before IS NULL THEN
    RAISE EXCEPTION 'Activation simulation failed: feature setting is missing';
  END IF;

  IF lower(btrim(v_before)) NOT IN ('false', '0', 'off', 'no') THEN
    RAISE EXCEPTION 'Activation simulation failed: feature is not disabled before test (%)', v_before;
  END IF;

  BEGIN
    UPDATE public.company_settings
    SET value = 'true'
    WHERE key = 'hr.employee_work_schedules_enabled';
  EXCEPTION
    WHEN OTHERS THEN
      v_error := SQLERRM;
      IF SQLERRM ILIKE '%release readiness gate%'
         OR SQLERRM ILIKE '%cannot be enabled%' THEN
        v_blocked := true;
      ELSE
        RAISE;
      END IF;
  END;

  IF NOT v_blocked THEN
    RAISE EXCEPTION 'Activation simulation failed: setting update was not blocked';
  END IF;

  SELECT value
  INTO v_after
  FROM public.company_settings
  WHERE key = 'hr.employee_work_schedules_enabled';

  IF v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION
      'Activation simulation failed: setting changed despite guard; before=% after=%',
      v_before,
      v_after;
  END IF;

  RAISE NOTICE 'Activation guard blocked enablement as expected: %', v_error;
END;
$simulation$;

SELECT jsonb_build_object(
  'status', 'pass',
  'activation_attempt_blocked', true,
  'setting_preserved', true,
  'transaction_will_rollback', true
) AS activation_guard_simulation;

ROLLBACK;
