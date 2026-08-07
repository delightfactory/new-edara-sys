-- HR Variable Schedules V2 — Batch 1 structural verification
-- READ ONLY. Run only after applying the Batch 1 migration to an isolated database copy.

DO $verify$
DECLARE
  v_resolver record;
BEGIN
  IF to_regclass('public.hr_employee_work_schedules') IS NULL THEN
    RAISE EXCEPTION 'Batch 1 failed: schedule header table missing';
  END IF;

  IF to_regclass('public.hr_employee_work_schedule_days') IS NULL THEN
    RAISE EXCEPTION 'Batch 1 failed: schedule day table missing';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'Batch 1 failed: migration must not seed schedule data';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname='public' AND c.relname='hr_employee_work_schedules' AND c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'Batch 1 failed: header RLS disabled';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname='public' AND c.relname='hr_employee_work_schedule_days' AND c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'Batch 1 failed: day RLS disabled';
  END IF;

  SELECT p.provolatile, p.prosecdef
  INTO v_resolver
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND p.proname='resolve_employee_custom_schedule'
    AND pg_get_function_identity_arguments(p.oid)='p_employee_id uuid, p_date date';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Batch 1 failed: custom-only resolver missing';
  END IF;

  IF v_resolver.provolatile <> 's' OR v_resolver.prosecdef THEN
    RAISE EXCEPTION 'Batch 1 failed: resolver must be STABLE SECURITY INVOKER';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname='trg_hr_employee_work_schedules_lifecycle' AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'Batch 1 failed: header lifecycle trigger missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname='trg_hr_employee_work_schedule_days_lifecycle' AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'Batch 1 failed: day lifecycle trigger missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name IN ('hr_attendance_days','hr_payroll_lines','hr_leave_requests')
      AND column_name IN (
        'schedule_id','work_schedule_id','schedule_snapshot_at',
        'scheduled_start_at','scheduled_end_at','scheduled_minutes'
      )
  ) THEN
    RAISE EXCEPTION 'Batch 1 failed: legacy runtime tables were expanded unexpectedly';
  END IF;
END;
$verify$;

SELECT
  'batch1_structural_ok' AS result,
  (SELECT COUNT(*) FROM public.hr_employee_work_schedules) AS seeded_headers,
  (SELECT COUNT(*) FROM public.hr_employee_work_schedule_days) AS seeded_days,
  to_regprocedure('public.resolve_employee_custom_schedule(uuid,date)') IS NOT NULL AS resolver_present;
