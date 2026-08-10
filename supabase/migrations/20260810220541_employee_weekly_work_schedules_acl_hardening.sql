-- Restrict attendance SECURITY DEFINER functions without changing their logic.
-- Existing UI calls to mark_daily_absences and run_auto_checkout remain allowed
-- for authenticated users; cron/internal functions are service-only.

REVOKE ALL ON FUNCTION public.is_employee_work_day(UUID, DATE)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_employee_work_day(UUID, DATE)
  TO service_role;

REVOKE ALL ON FUNCTION public.mark_daily_absences(DATE)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_daily_absences(DATE)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.run_auto_checkout(DATE)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.run_auto_checkout(DATE)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.scan_attendance_daily_review_alerts()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.scan_attendance_daily_review_alerts()
  TO service_role;

REVOKE ALL ON FUNCTION public.notify_absent_employees()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.notify_absent_employees()
  TO service_role;
