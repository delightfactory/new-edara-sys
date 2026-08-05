-- =============================================================================
-- EDARA — Employee Work Schedules admin context
--
-- Exposes only the non-sensitive schedule settings needed by the employee
-- schedule UI. It does not broaden company_settings RLS or table grants.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  IF to_regprocedure('public.hr_employee_work_schedules_enabled()') IS NULL THEN
    RAISE EXCEPTION 'Admin-context preflight failed: feature helper is missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Admin-context preflight failed: feature/readiness must remain false';
  END IF;

  IF to_regprocedure('public.get_employee_work_schedule_admin_context()') IS NOT NULL THEN
    RAISE EXCEPTION 'Admin-context preflight failed: RPC already exists';
  END IF;
END;
$preflight$;

CREATE FUNCTION public.get_employee_work_schedule_admin_context()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_actor UUID := auth.uid();
  v_start_text TEXT;
  v_end_text TEXT;
  v_hours_text TEXT;
  v_off_text TEXT;
  v_start TIME;
  v_end TIME;
  v_hours NUMERIC;
  v_window_minutes INTEGER;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.check_permission(v_actor, 'hr.employees.read')
    OR public.check_permission(v_actor, 'hr.attendance.read')
    OR public.check_permission(v_actor, 'hr.employees.edit')
  ) THEN
    RAISE EXCEPTION 'لا تملك صلاحية الاطلاع على جداول عمل الموظفين';
  END IF;

  SELECT
    max(value) FILTER (WHERE key = 'hr.work_start_time'),
    max(value) FILTER (WHERE key = 'hr.work_end_time'),
    max(value) FILTER (WHERE key = 'hr.work_hours_per_day'),
    max(value) FILTER (WHERE key = 'hr.weekly_off_day')
  INTO v_start_text, v_end_text, v_hours_text, v_off_text
  FROM public.company_settings
  WHERE key IN (
    'hr.work_start_time',
    'hr.work_end_time',
    'hr.work_hours_per_day',
    'hr.weekly_off_day'
  );

  IF v_start_text IS NULL
     OR v_end_text IS NULL
     OR v_hours_text IS NULL
     OR v_off_text IS NULL THEN
    RAISE EXCEPTION 'إعدادات مواعيد الشركة غير مكتملة';
  END IF;

  BEGIN
    v_start := btrim(v_start_text)::TIME;
    v_end := btrim(v_end_text)::TIME;
    v_hours := btrim(v_hours_text)::NUMERIC;
  EXCEPTION
    WHEN invalid_text_representation OR datetime_field_overflow THEN
      RAISE EXCEPTION 'إعدادات مواعيد الشركة غير صالحة';
  END;

  IF lower(btrim(v_off_text)) NOT IN (
    'saturday', 'sunday', 'monday', 'tuesday',
    'wednesday', 'thursday', 'friday'
  ) THEN
    RAISE EXCEPTION 'إعداد يوم الإجازة الأسبوعية للشركة غير صالح';
  END IF;

  IF v_end <= v_start THEN
    RAISE EXCEPTION 'مواعيد الشركة الليلية أو غير الموجبة غير مدعومة في الإصدار الحالي';
  END IF;

  v_window_minutes := (EXTRACT(EPOCH FROM (v_end - v_start)) / 60)::INTEGER;

  IF v_hours <= 0 OR v_hours * 60 <> v_window_minutes THEN
    RAISE EXCEPTION 'عدد ساعات الشركة لا يطابق وقت البداية والنهاية';
  END IF;

  RETURN jsonb_build_object(
    'installed', true,
    'enabled', public.hr_employee_work_schedules_enabled(),
    'company_defaults', jsonb_build_object(
      'start_time', to_char(v_start, 'HH24:MI'),
      'end_time', to_char(v_end, 'HH24:MI'),
      'work_hours_per_day', v_hours,
      'weekly_off_day', lower(btrim(v_off_text))
    )
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_employee_work_schedule_admin_context()
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_employee_work_schedule_admin_context()
  TO authenticated;

COMMENT ON FUNCTION public.get_employee_work_schedule_admin_context() IS
  'Least-privilege HR read context for employee schedule UI. Does not expose arbitrary company settings.';

DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  SELECT pg_get_functiondef('public.get_employee_work_schedule_admin_context()'::regprocedure)
  INTO v_definition;

  IF v_definition NOT ILIKE '%hr.employees.read%'
     OR v_definition NOT ILIKE '%hr.attendance.read%'
     OR v_definition NOT ILIKE '%hr.employees.edit%'
     OR v_definition NOT ILIKE '%hr.work_start_time%'
     OR v_definition ILIKE '%SELECT * FROM public.company_settings%' THEN
    RAISE EXCEPTION 'Admin-context assertion failed: RPC permission/scope is incomplete';
  END IF;

  IF NOT has_function_privilege(
    'authenticated',
    'public.get_employee_work_schedule_admin_context()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Admin-context assertion failed: authenticated execution is missing';
  END IF;

  IF has_function_privilege(
    'anon',
    'public.get_employee_work_schedule_admin_context()',
    'EXECUTE'
  ) OR has_function_privilege(
    'service_role',
    'public.get_employee_work_schedule_admin_context()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Admin-context assertion failed: RPC is exposed too broadly';
  END IF;
END;
$assertions$;

COMMIT;
