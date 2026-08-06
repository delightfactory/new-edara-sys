-- =============================================================================
-- EDARA — Company schedule read-policy alignment
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  IF to_regclass('public.hr_company_work_schedules') IS NULL THEN
    RAISE EXCEPTION 'Company read-policy preflight failed: history table is missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Company read-policy preflight failed: feature/readiness must remain false';
  END IF;
END;
$preflight$;

DROP POLICY IF EXISTS hr_company_work_schedules_read
  ON public.hr_company_work_schedules;

CREATE POLICY hr_company_work_schedules_read
  ON public.hr_company_work_schedules
  FOR SELECT
  TO authenticated
  USING (
    (SELECT public.check_permission((SELECT auth.uid()), 'settings.read'))
    OR (SELECT public.check_permission((SELECT auth.uid()), 'settings.update'))
    OR (SELECT public.check_permission((SELECT auth.uid()), 'hr.employees.read'))
    OR (SELECT public.check_permission((SELECT auth.uid()), 'hr.attendance.read'))
    OR (SELECT public.check_permission((SELECT auth.uid()), 'hr.employees.edit'))
  );

DO $assertions$
DECLARE
  v_policy TEXT;
BEGIN
  SELECT pg_get_expr(p.polqual, p.polrelid)
  INTO v_policy
  FROM pg_policy p
  WHERE p.polrelid = 'public.hr_company_work_schedules'::regclass
    AND p.polname = 'hr_company_work_schedules_read';

  IF v_policy IS NULL
     OR v_policy NOT ILIKE '%settings.read%'
     OR v_policy NOT ILIKE '%settings.update%'
     OR v_policy NOT ILIKE '%hr.employees.read%'
     OR v_policy NOT ILIKE '%hr.attendance.read%' THEN
    RAISE EXCEPTION 'Company read-policy assertion failed: visibility contract is incomplete';
  END IF;
END;
$assertions$;

COMMIT;
