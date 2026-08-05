-- =============================================================================
-- EDARA — Employee Work Schedules: trusted service-role actor delegation
--
-- Authenticated callers are always bound to auth.uid(). A service-role caller
-- may supply p_user_id only as the audited human actor, preserving backend jobs
-- without allowing ordinary callers to impersonate another user.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  IF to_regprocedure(
       'public.upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)'
     ) IS NULL THEN
    RAISE EXCEPTION 'Service-role actor guard preflight failed: public attendance RPC is missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Service-role actor guard preflight failed: feature/readiness must remain false';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.upsert_attendance_and_reprocess(
  p_employee_id UUID,
  p_shift_date DATE,
  p_punch_in_time TIMESTAMPTZ DEFAULT NULL,
  p_punch_out_time TIMESTAMPTZ DEFAULT NULL,
  p_status public.hr_attendance_status DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_actor UUID := auth.uid();
  v_role TEXT := COALESCE(auth.role(), '');
BEGIN
  IF v_role = 'service_role' THEN
    v_actor := p_user_id;
  END IF;

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'A verified attendance actor is required';
  END IF;

  IF NOT public.check_permission(v_actor, 'hr.attendance.create')
     AND NOT public.check_permission(v_actor, 'hr.attendance.edit')
     AND NOT public.check_permission(v_actor, 'hr.attendance.update')
     AND NOT public.check_permission(v_actor, 'hr.attendance.approve') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تعديل الحضور';
  END IF;

  IF NOT public.hr_employee_work_schedules_enabled() THEN
    RETURN public.upsert_attendance_and_reprocess_legacy_20260805(
      p_employee_id,
      p_shift_date,
      p_punch_in_time,
      p_punch_out_time,
      p_status,
      p_notes,
      v_actor
    );
  END IF;

  RETURN public.upsert_attendance_and_reprocess_scheduled(
    p_employee_id,
    p_shift_date,
    p_punch_in_time,
    p_punch_out_time,
    p_status,
    p_notes,
    v_actor
  );
END;
$function$;

COMMENT ON FUNCTION public.upsert_attendance_and_reprocess(
  UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ, public.hr_attendance_status, TEXT, UUID
) IS
  'Administrative attendance correction. Authenticated callers are bound to auth.uid(); service_role may delegate only to a supplied actor who independently holds an attendance-management permission.';

REVOKE ALL ON FUNCTION public.upsert_attendance_and_reprocess(
  UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ, public.hr_attendance_status, TEXT, UUID
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_attendance_and_reprocess(
  UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ, public.hr_attendance_status, TEXT, UUID
) TO authenticated, service_role;

DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  SELECT pg_get_functiondef(
    'public.upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)'::regprocedure
  ) INTO v_definition;

  IF v_definition NOT ILIKE '%v_role TEXT := COALESCE(auth.role(), '''')%'
     OR v_definition NOT ILIKE '%IF v_role = ''service_role''%'
     OR v_definition NOT ILIKE '%v_actor := p_user_id%'
     OR v_definition ILIKE '%COALESCE(p_user_id, auth.uid())%' THEN
    RAISE EXCEPTION 'Service-role actor guard assertion failed: trusted delegation is incomplete';
  END IF;

  IF has_function_privilege(
       'anon',
       'public.upsert_attendance_and_reprocess(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Service-role actor guard assertion failed: anon execution remains';
  END IF;
END;
$assertions$;

COMMIT;
