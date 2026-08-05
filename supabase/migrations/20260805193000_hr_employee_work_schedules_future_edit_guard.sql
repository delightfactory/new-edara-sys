-- =============================================================================
-- EDARA — Employee Work Schedules future-edit guard
--
-- Allows an authorized HR user to correct weekday details of an active schedule
-- only while its effective date is still in the future and no attendance row
-- references it. Historical/current schedules remain immutable.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '90s';

DO $preflight$
BEGIN
  IF to_regprocedure('public.save_employee_work_schedule(uuid,date,jsonb,text)') IS NULL
     OR to_regprocedure('public.guard_employee_work_schedule_header()') IS NULL
     OR to_regprocedure('public.guard_employee_work_schedule_day_mutation()') IS NULL THEN
    RAISE EXCEPTION 'Future-edit preflight failed: M2 schedule functions are missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Future-edit preflight failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'Future-edit preflight failed: no schedule data is expected before rehearsal';
  END IF;

  IF to_regprocedure('public.update_future_employee_work_schedule(uuid,jsonb,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'Future-edit preflight failed: update RPC already exists';
  END IF;
END;
$preflight$;

-- Require seven rows and at least one actual working day at activation.
CREATE OR REPLACE FUNCTION public.guard_employee_work_schedule_header()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $function$
DECLARE
  v_day_count INTEGER;
  v_working_day_count INTEGER;
  v_cairo_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'draft' THEN
      RAISE EXCEPTION 'A schedule header must be inserted as draft';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status = 'retired' THEN
    IF NEW.employee_id IS DISTINCT FROM OLD.employee_id
       OR NEW.effective_from IS DISTINCT FROM OLD.effective_from
       OR NEW.effective_to IS DISTINCT FROM OLD.effective_to
       OR NEW.status IS DISTINCT FROM OLD.status THEN
      RAISE EXCEPTION 'A retired schedule version is immutable';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status = 'active' THEN
    IF NEW.status = 'retired' THEN
      IF NEW.employee_id IS DISTINCT FROM OLD.employee_id
         OR NEW.effective_from IS DISTINCT FROM OLD.effective_from
         OR NEW.effective_to IS NULL
         OR NEW.effective_to < NEW.effective_from THEN
        RAISE EXCEPTION 'Invalid active-to-retired schedule transition';
      END IF;
      RETURN NEW;
    END IF;

    IF NEW.employee_id IS DISTINCT FROM OLD.employee_id
       OR NEW.effective_from IS DISTINCT FROM OLD.effective_from
       OR NEW.effective_to IS DISTINCT FROM OLD.effective_to
       OR NEW.status IS DISTINCT FROM OLD.status THEN
      RAISE EXCEPTION 'An active schedule cannot be edited in place';
    END IF;

    RETURN NEW;
  END IF;

  IF OLD.status = 'draft' AND NEW.status = 'active' THEN
    IF NEW.effective_from <= v_cairo_today THEN
      RAISE EXCEPTION
        'Schedule activation must start after the current Cairo date (%)',
        v_cairo_today;
    END IF;

    SELECT
      count(*)::INTEGER,
      count(*) FILTER (WHERE d.is_working_day)::INTEGER
    INTO v_day_count, v_working_day_count
    FROM public.hr_employee_work_schedule_days d
    WHERE d.schedule_id = NEW.id;

    IF v_day_count <> 7 THEN
      RAISE EXCEPTION 'An active schedule requires exactly 7 weekday rows; found %', v_day_count;
    END IF;

    IF v_working_day_count <= 0 THEN
      RAISE EXCEPTION 'An active schedule requires at least one working day';
    END IF;

    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'Unsupported schedule status transition: % -> %', OLD.status, NEW.status;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_employee_work_schedule_header()
  FROM PUBLIC, anon, authenticated, service_role;

-- Allow weekday mutation only inside the controlled future-update RPC.
CREATE OR REPLACE FUNCTION public.guard_employee_work_schedule_day_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $function$
DECLARE
  v_schedule_id UUID;
  v_status TEXT;
  v_effective_from DATE;
  v_edit_token TEXT;
  v_cairo_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.schedule_id IS DISTINCT FROM OLD.schedule_id THEN
    RAISE EXCEPTION 'A schedule day cannot be moved between schedule versions';
  END IF;

  v_schedule_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.schedule_id ELSE NEW.schedule_id END;

  SELECT s.status, s.effective_from
  INTO v_status, v_effective_from
  FROM public.hr_employee_work_schedules s
  WHERE s.id = v_schedule_id;

  IF NOT FOUND THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'Schedule % does not exist', v_schedule_id;
  END IF;

  IF v_status = 'draft' THEN
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  v_edit_token := current_setting('edara.employee_work_schedule_edit_id', true);

  IF v_status = 'active'
     AND v_effective_from > v_cairo_today
     AND v_edit_token = v_schedule_id::TEXT
     AND public.check_permission(auth.uid(), 'hr.employees.edit')
     AND NOT EXISTS (
       SELECT 1
       FROM public.hr_attendance_days ad
       WHERE ad.work_schedule_id = v_schedule_id
     ) THEN
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  RAISE EXCEPTION 'Weekday rows are immutable after schedule activation';
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_employee_work_schedule_day_mutation()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.update_future_employee_work_schedule(
  p_schedule_id UUID,
  p_days JSONB,
  p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
  v_actor UUID := auth.uid();
  v_cairo_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_schedule public.hr_employee_work_schedules%ROWTYPE;
  v_old JSONB;
  v_result JSONB;
  v_day_count INTEGER;
  v_distinct_day_count INTEGER;
  v_working_day_count INTEGER;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT public.check_permission(v_actor, 'hr.employees.edit') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تعديل جدول عمل الموظف';
  END IF;

  IF p_schedule_id IS NULL THEN
    RAISE EXCEPTION 'schedule_id is required';
  END IF;

  SELECT * INTO v_schedule
  FROM public.hr_employee_work_schedules
  WHERE id = p_schedule_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'جدول العمل غير موجود';
  END IF;

  IF v_schedule.status <> 'active' OR v_schedule.effective_from <= v_cairo_today THEN
    RAISE EXCEPTION 'يمكن تعديل جدول نشط لم يبدأ بعد فقط';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_attendance_days ad
    WHERE ad.work_schedule_id = p_schedule_id
  ) THEN
    RAISE EXCEPTION 'لا يمكن تعديل جدول مرتبط بسجلات حضور';
  END IF;

  IF p_days IS NULL OR jsonb_typeof(p_days) <> 'array'
     OR jsonb_array_length(p_days) <> 7 THEN
    RAISE EXCEPTION 'يجب إدخال الأيام السبعة كاملة';
  END IF;

  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_days) item
    WHERE jsonb_typeof(item) <> 'object'
  ) THEN
    RAISE EXCEPTION 'كل عنصر في days يجب أن يكون كائناً';
  END IF;

  SELECT
    count(*)::INTEGER,
    count(DISTINCT lower(btrim(item->>'day_of_week')))::INTEGER,
    count(*) FILTER (
      WHERE jsonb_typeof(item->'is_working_day') = 'boolean'
        AND (item->>'is_working_day')::BOOLEAN
    )::INTEGER
  INTO v_day_count, v_distinct_day_count, v_working_day_count
  FROM jsonb_array_elements(p_days) item;

  IF v_day_count <> 7 OR v_distinct_day_count <> 7 THEN
    RAISE EXCEPTION 'الأيام السبعة يجب أن تكون فريدة وكاملة';
  END IF;

  IF v_working_day_count <= 0 THEN
    RAISE EXCEPTION 'يجب أن يحتوي الجدول على يوم عمل واحد على الأقل';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_days) item
    WHERE item->>'day_of_week' IS NULL
       OR lower(btrim(item->>'day_of_week')) NOT IN (
         'saturday', 'sunday', 'monday', 'tuesday',
         'wednesday', 'thursday', 'friday'
       )
       OR jsonb_typeof(item->'is_working_day') IS DISTINCT FROM 'boolean'
  ) THEN
    RAISE EXCEPTION 'بيانات اليوم أو حالة يوم العمل غير صحيحة';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_days) item
    WHERE (item->>'is_working_day')::BOOLEAN
      AND (
        COALESCE(item->>'start_time', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
        OR COALESCE(item->>'end_time', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
        OR (item->>'end_time')::TIME <= (item->>'start_time')::TIME
      )
  ) THEN
    RAISE EXCEPTION 'أيام العمل تتطلب وقت بداية ونهاية صحيحين بصيغة HH:MM';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_days) item
    WHERE NOT (item->>'is_working_day')::BOOLEAN
      AND (
        NULLIF(btrim(COALESCE(item->>'start_time', '')), '') IS NOT NULL
        OR NULLIF(btrim(COALESCE(item->>'end_time', '')), '') IS NOT NULL
      )
  ) THEN
    RAISE EXCEPTION 'يوم الإجازة لا يقبل وقت بداية أو نهاية';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_schedule.employee_id::TEXT, 0));

  SELECT jsonb_build_object(
    'schedule', to_jsonb(v_schedule),
    'days', (
      SELECT jsonb_agg(to_jsonb(d) ORDER BY d.day_of_week)
      FROM public.hr_employee_work_schedule_days d
      WHERE d.schedule_id = p_schedule_id
    )
  ) INTO v_old;

  PERFORM set_config('edara.employee_work_schedule_edit_id', p_schedule_id::TEXT, true);

  DELETE FROM public.hr_employee_work_schedule_days
  WHERE schedule_id = p_schedule_id;

  INSERT INTO public.hr_employee_work_schedule_days (
    schedule_id,
    day_of_week,
    is_working_day,
    start_time,
    end_time
  )
  SELECT
    p_schedule_id,
    lower(btrim(item->>'day_of_week'))::public.hr_day_of_week,
    (item->>'is_working_day')::BOOLEAN,
    CASE WHEN (item->>'is_working_day')::BOOLEAN THEN (item->>'start_time')::TIME ELSE NULL END,
    CASE WHEN (item->>'is_working_day')::BOOLEAN THEN (item->>'end_time')::TIME ELSE NULL END
  FROM jsonb_array_elements(p_days) item;

  UPDATE public.hr_employee_work_schedules
  SET notes = NULLIF(btrim(p_notes), ''),
      updated_by = v_actor,
      updated_at = now()
  WHERE id = p_schedule_id;

  SELECT jsonb_build_object(
    'id', s.id,
    'employee_id', s.employee_id,
    'effective_from', s.effective_from,
    'effective_to', s.effective_to,
    'status', s.status,
    'notes', s.notes,
    'days', (
      SELECT jsonb_agg(
        jsonb_build_object(
          'day_of_week', d.day_of_week,
          'is_working_day', d.is_working_day,
          'start_time', d.start_time,
          'end_time', d.end_time,
          'scheduled_minutes', d.scheduled_minutes
        ) ORDER BY d.day_of_week
      )
      FROM public.hr_employee_work_schedule_days d
      WHERE d.schedule_id = s.id
    )
  ) INTO v_result
  FROM public.hr_employee_work_schedules s
  WHERE s.id = p_schedule_id;

  INSERT INTO public.audit_logs (
    user_id,
    action,
    entity_type,
    entity_id,
    old_data,
    new_data,
    user_agent
  ) VALUES (
    v_actor,
    'employee_work_schedule_future_updated',
    'hr_employee_work_schedule',
    p_schedule_id,
    v_old,
    v_result,
    'EDARA future employee work schedule update RPC'
  );

  RETURN jsonb_build_object(
    'success', true,
    'schedule', v_result,
    'feature_enabled', public.hr_employee_work_schedules_enabled()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.update_future_employee_work_schedule(UUID, JSONB, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.update_future_employee_work_schedule(UUID, JSONB, TEXT)
  TO authenticated;

DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Future-edit assertion failed: feature/readiness changed';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'Future-edit assertion failed: migration seeded schedule data';
  END IF;

  SELECT pg_get_functiondef('public.guard_employee_work_schedule_header()'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%v_working_day_count%'
     OR v_definition NOT ILIKE '%at least one working day%' THEN
    RAISE EXCEPTION 'Future-edit assertion failed: zero-workday guard is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.update_future_employee_work_schedule(uuid,jsonb,text)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%effective_from <= v_cairo_today%'
     OR v_definition NOT ILIKE '%hr_attendance_days%'
     OR v_definition NOT ILIKE '%pg_advisory_xact_lock%'
     OR v_definition NOT ILIKE '%employee_work_schedule_future_updated%' THEN
    RAISE EXCEPTION 'Future-edit assertion failed: controlled update RPC is incomplete';
  END IF;
END;
$assertions$;

COMMIT;
