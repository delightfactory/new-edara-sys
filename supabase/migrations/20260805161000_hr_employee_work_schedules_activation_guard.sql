-- =============================================================================
-- EDARA — Employee Work Schedules activation guard
--
-- Prevents accidental/partial activation while attendance automations,
-- penalties, leave settlement, and payroll are not yet schedule-aware.
--
-- A later final-release migration must replace the readiness function with
-- strict structural/hash checks before the setting can become TRUE.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  IF to_regprocedure('public.record_attendance_gps_v2_scheduled(numeric,numeric,numeric,text,timestamp with time zone)') IS NULL
     OR to_regprocedure('public.upsert_attendance_and_reprocess_scheduled(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)') IS NULL THEN
    RAISE EXCEPTION 'Activation guard preflight failed: M3A callers are missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'Activation guard preflight failed: feature is already enabled';
  END IF;

  IF to_regprocedure('public.hr_employee_work_schedules_activation_ready()') IS NOT NULL
     OR to_regprocedure('public.guard_employee_work_schedules_activation()') IS NOT NULL THEN
    RAISE EXCEPTION 'Activation guard preflight failed: guard functions already exist';
  END IF;
END;
$preflight$;

-- Deliberately false at M3A. M4/M5/final verification must replace this
-- implementation; no application user can bypass the setting trigger.
CREATE FUNCTION public.hr_employee_work_schedules_activation_ready()
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
  SELECT false;
$function$;

REVOKE ALL ON FUNCTION public.hr_employee_work_schedules_activation_ready()
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.hr_employee_work_schedules_activation_ready() IS
  'Release gate. Intentionally false until all schedule-aware attendance, automation, penalty, leave, payroll, and verification migrations are installed.';

CREATE FUNCTION public.guard_employee_work_schedules_activation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_truthy BOOLEAN;
BEGIN
  IF NEW.key <> 'hr.employee_work_schedules_enabled' THEN
    RETURN NEW;
  END IF;

  v_truthy := lower(btrim(NEW.value)) IN ('true', '1', 'on', 'yes');

  IF v_truthy AND NOT public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION
      'Employee work schedules cannot be enabled: release readiness gate is not satisfied';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_employee_work_schedules_activation()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_company_settings_employee_schedule_activation_guard
  ON public.company_settings;
CREATE TRIGGER trg_company_settings_employee_schedule_activation_guard
  BEFORE INSERT OR UPDATE OF value ON public.company_settings
  FOR EACH ROW
  WHEN (NEW.key = 'hr.employee_work_schedules_enabled')
  EXECUTE FUNCTION public.guard_employee_work_schedules_activation();

DO $assertions$
BEGIN
  IF public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Activation guard assertion failed: readiness must be false at M3A';
  END IF;

  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'Activation guard assertion failed: feature switch became enabled';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'company_settings'
      AND t.tgname = 'trg_company_settings_employee_schedule_activation_guard'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'Activation guard assertion failed: company_settings trigger is missing';
  END IF;
END;
$assertions$;

COMMIT;
