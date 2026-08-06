-- =============================================================================
-- EDARA — Company history guard correction
--
-- Tightens the active-to-retired actor contract and replaces a permissive
-- structural assertion from the immediately preceding hardening migration.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  IF to_regprocedure('public.guard_hr_company_work_schedule_mutation()') IS NULL
     OR to_regprocedure('public.assert_company_work_schedule_change_safe(date,date,integer,uuid)') IS NULL
     OR to_regprocedure('public.hr_company_work_schedule_activation_consistent()') IS NULL THEN
    RAISE EXCEPTION 'Company-history guard-correction preflight failed: hardening is incomplete';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Company-history guard-correction preflight failed: feature/readiness must remain false';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.guard_hr_company_work_schedule_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $function$
DECLARE
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'active' OR NEW.effective_to IS NOT NULL THEN
      RAISE EXCEPTION 'A company schedule version must be inserted active and open-ended';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status = 'retired' THEN
    IF NEW.effective_from IS DISTINCT FROM OLD.effective_from
       OR NEW.effective_to IS DISTINCT FROM OLD.effective_to
       OR NEW.status IS DISTINCT FROM OLD.status
       OR NEW.start_time IS DISTINCT FROM OLD.start_time
       OR NEW.end_time IS DISTINCT FROM OLD.end_time
       OR NEW.weekly_off_day IS DISTINCT FROM OLD.weekly_off_day
       OR NEW.notes IS DISTINCT FROM OLD.notes
       OR NEW.is_system_baseline IS DISTINCT FROM OLD.is_system_baseline
       OR NEW.activated_by IS DISTINCT FROM OLD.activated_by
       OR NEW.activated_at IS DISTINCT FROM OLD.activated_at
       OR NEW.retired_by IS DISTINCT FROM OLD.retired_by
       OR NEW.retired_at IS DISTINCT FROM OLD.retired_at
       OR NEW.created_by IS DISTINCT FROM OLD.created_by
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'A retired company schedule version is immutable';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.status = 'retired' THEN
    IF NEW.effective_from IS DISTINCT FROM OLD.effective_from
       OR NEW.effective_to IS NULL
       OR NEW.effective_to < NEW.effective_from
       OR NEW.start_time IS DISTINCT FROM OLD.start_time
       OR NEW.end_time IS DISTINCT FROM OLD.end_time
       OR NEW.weekly_off_day IS DISTINCT FROM OLD.weekly_off_day
       OR NEW.notes IS DISTINCT FROM OLD.notes
       OR NEW.is_system_baseline IS DISTINCT FROM OLD.is_system_baseline
       OR NEW.activated_by IS DISTINCT FROM OLD.activated_by
       OR NEW.activated_at IS DISTINCT FROM OLD.activated_at
       OR NEW.retired_by IS NULL
       OR NEW.retired_at IS NULL THEN
      RAISE EXCEPTION 'Invalid active-to-retired company schedule transition';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.status <> 'active'
     OR NEW.effective_from IS DISTINCT FROM OLD.effective_from
     OR NEW.effective_to IS NOT NULL
     OR NEW.is_system_baseline IS DISTINCT FROM OLD.is_system_baseline
     OR NEW.activated_by IS DISTINCT FROM OLD.activated_by
     OR NEW.activated_at IS DISTINCT FROM OLD.activated_at
     OR NEW.retired_by IS NOT NULL
     OR NEW.retired_at IS NOT NULL
     OR NEW.created_by IS DISTINCT FROM OLD.created_by
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Unsupported company schedule mutation';
  END IF;

  IF OLD.is_system_baseline OR OLD.effective_from <= v_today THEN
    IF NEW.start_time IS DISTINCT FROM OLD.start_time
       OR NEW.end_time IS DISTINCT FROM OLD.end_time
       OR NEW.weekly_off_day IS DISTINCT FROM OLD.weekly_off_day
       OR NEW.notes IS DISTINCT FROM OLD.notes THEN
      RAISE EXCEPTION 'Only the latest future company schedule version may be corrected in place';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_hr_company_work_schedule_mutation()
  FROM PUBLIC, anon, authenticated, service_role;

DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  SELECT pg_get_functiondef(
    'public.guard_hr_company_work_schedule_mutation()'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%NEW.retired_by IS NULL%'
     OR v_definition NOT ILIKE '%OLD.status = ''retired''%'
     OR v_definition NOT ILIKE '%OLD.is_system_baseline OR OLD.effective_from <= v_today%' THEN
    RAISE EXCEPTION 'Company-history guard-correction assertion failed: lifecycle guard is incomplete';
  END IF;

  SELECT pg_get_functiondef(
    'public.save_company_work_schedule_version(date,text,text,text,text)'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%assert_company_work_schedule_change_safe%'
     OR v_definition NOT ILIKE '%settings.update%'
     OR v_definition NOT ILIKE '%أول يوم في الشهر%'
     OR v_definition NOT ILIKE '%RETURNING * INTO v_new%' THEN
    RAISE EXCEPTION 'Company-history guard-correction assertion failed: save RPC is incomplete';
  END IF;

  SELECT pg_get_functiondef(
    'public.update_future_company_work_schedule_version(uuid,text,text,text,text)'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT ILIKE '%assert_company_work_schedule_change_safe%'
     OR v_definition NOT ILIKE '%v_target.effective_from <= v_today%'
     OR v_definition NOT ILIKE '%RETURNING * INTO v_updated%'
     OR v_definition NOT ILIKE '%أول يوم في الشهر%' THEN
    RAISE EXCEPTION 'Company-history guard-correction assertion failed: update RPC is incomplete';
  END IF;

  IF NOT public.hr_company_work_schedule_activation_consistent() THEN
    RAISE EXCEPTION 'Company-history guard-correction assertion failed: baseline consistency is false';
  END IF;
END;
$assertions$;

COMMIT;
