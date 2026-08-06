-- =============================================================================
-- EDARA — Deferred company-setting consistency constraint
--
-- Prevents direct/legacy table updates from leaving mutable company_settings and
-- the effective-dated company baseline inconsistent. Atomic RPC transactions pass
-- because both sides are synchronized before the deferred trigger is evaluated.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  IF to_regprocedure('public.hr_company_work_schedule_activation_consistent()') IS NULL
     OR to_regprocedure('public.update_hr_settings_atomic(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'Company-consistency constraint preflight failed: required helpers are missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Company-consistency constraint preflight failed: feature/readiness must remain false';
  END IF;

  IF to_regprocedure('public.enforce_company_schedule_settings_consistency()') IS NOT NULL THEN
    RAISE EXCEPTION 'Company-consistency constraint preflight failed: trigger helper already exists';
  END IF;
END;
$preflight$;

CREATE FUNCTION public.enforce_company_schedule_settings_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  IF NEW.value IS NOT DISTINCT FROM OLD.value THEN
    RETURN NEW;
  END IF;

  IF NOT public.hr_company_work_schedule_activation_consistent() THEN
    RAISE EXCEPTION
      'تحديث مواعيد الشركة غير مكتمل؛ استخدم الحفظ الذري أو نسخة جدول شركة مستقبلية';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.enforce_company_schedule_settings_consistency()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_company_settings_schedule_consistency_deferred
  ON public.company_settings;
CREATE CONSTRAINT TRIGGER trg_company_settings_schedule_consistency_deferred
  AFTER UPDATE OF value ON public.company_settings
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (
    NEW.key IN (
      'hr.work_start_time',
      'hr.work_end_time',
      'hr.work_hours_per_day',
      'hr.weekly_off_day'
    )
  )
  EXECUTE FUNCTION public.enforce_company_schedule_settings_consistency();

DO $assertions$
DECLARE
  v_trigger_definition TEXT;
BEGIN
  SELECT pg_get_triggerdef(t.oid, true)
  INTO v_trigger_definition
  FROM pg_trigger t
  WHERE t.tgrelid = 'public.company_settings'::regclass
    AND t.tgname = 'trg_company_settings_schedule_consistency_deferred'
    AND NOT t.tgisinternal;

  IF v_trigger_definition IS NULL
     OR v_trigger_definition NOT ILIKE '%DEFERRABLE INITIALLY DEFERRED%'
     OR v_trigger_definition NOT ILIKE '%enforce_company_schedule_settings_consistency%' THEN
    RAISE EXCEPTION 'Company-consistency constraint assertion failed: deferred trigger is incomplete';
  END IF;

  IF NOT public.hr_company_work_schedule_activation_consistent() THEN
    RAISE EXCEPTION 'Company-consistency constraint assertion failed: installed state is inconsistent';
  END IF;
END;
$assertions$;

COMMIT;
