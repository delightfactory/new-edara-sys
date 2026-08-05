-- =============================================================================
-- EDARA — Employee Work Schedules M2 integrity hardening
--
-- This file tightens the draft M2 contract before any environment application:
--   * exactly one active schedule header per employee;
--   * all prior active versions are retired before a new one activates;
--   * clearer JSON time validation;
--   * explicit trigger-row returns.
--
-- No existing attendance/payroll function is replaced or called by this file.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  IF to_regprocedure('public.save_employee_work_schedule(uuid,date,jsonb,text)') IS NULL
     OR to_regprocedure('public.guard_employee_work_schedule_day_mutation()') IS NULL THEN
    RAISE EXCEPTION 'M2 integrity preflight failed: base M2 functions are missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'M2 integrity preflight failed: feature switch must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'M2 integrity preflight failed: no schedule data is expected yet';
  END IF;
END;
$preflight$;

-- One lifecycle head only. Historical versions are always retired.
CREATE UNIQUE INDEX hr_employee_work_schedules_one_active_idx
  ON public.hr_employee_work_schedules(employee_id)
  WHERE status = 'active';

CREATE OR REPLACE FUNCTION public.guard_employee_work_schedule_day_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $function$
DECLARE
  v_schedule_id UUID;
  v_status TEXT;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.schedule_id IS DISTINCT FROM OLD.schedule_id THEN
    RAISE EXCEPTION 'A schedule day cannot be moved between schedule versions';
  END IF;

  v_schedule_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.schedule_id ELSE NEW.schedule_id END;

  SELECT s.status
  INTO v_status
  FROM public.hr_employee_work_schedules s
  WHERE s.id = v_schedule_id;

  -- During ON DELETE CASCADE of a draft header, the parent may no longer be
  -- visible to this child trigger. The header delete guard already proved it
  -- was a draft, so a missing parent is allowed only for DELETE.
  IF NOT FOUND THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'Schedule % does not exist', v_schedule_id;
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'Weekday rows are immutable after schedule activation';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_employee_work_schedule_day_mutation()
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.save_employee_work_schedule(
  p_employee_id    UUID,
  p_effective_from DATE,
  p_days           JSONB,
  p_notes          TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
  v_actor UUID := auth.uid();
  v_cairo_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_employee public.hr_employees%ROWTYPE;
  v_schedule_id UUID;
  v_previous public.hr_employee_work_schedules%ROWTYPE;
  v_previous_found BOOLEAN := false;
  v_previous_new_end DATE;
  v_day_count INTEGER;
  v_distinct_day_count INTEGER;
  v_result JSONB;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT public.check_permission(v_actor, 'hr.employees.edit') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تعديل جدول عمل الموظف';
  END IF;

  IF p_employee_id IS NULL OR p_effective_from IS NULL THEN
    RAISE EXCEPTION 'employee_id and effective_from are required';
  END IF;

  IF p_effective_from <= v_cairo_today THEN
    RAISE EXCEPTION
      'تاريخ بدء الجدول يجب أن يكون بعد تاريخ اليوم بتوقيت القاهرة (%)',
      v_cairo_today;
  END IF;

  SELECT *
  INTO v_employee
  FROM public.hr_employees
  WHERE id = p_employee_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الموظف غير موجود';
  END IF;

  IF v_employee.status = 'terminated' THEN
    RAISE EXCEPTION 'لا يمكن إنشاء جدول مستقبلي لموظف منتهي الخدمة';
  END IF;

  IF p_effective_from < v_employee.hire_date THEN
    RAISE EXCEPTION 'تاريخ الجدول لا يمكن أن يسبق تاريخ تعيين الموظف';
  END IF;

  IF v_employee.termination_date IS NOT NULL
     AND p_effective_from > v_employee.termination_date THEN
    RAISE EXCEPTION 'تاريخ الجدول يقع بعد تاريخ انتهاء خدمة الموظف';
  END IF;

  IF p_days IS NULL OR jsonb_typeof(p_days) <> 'array' THEN
    RAISE EXCEPTION 'days must be a JSON array';
  END IF;

  IF jsonb_array_length(p_days) <> 7 THEN
    RAISE EXCEPTION 'يجب إدخال الأيام السبعة كاملة';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_days) item
    WHERE jsonb_typeof(item) <> 'object'
  ) THEN
    RAISE EXCEPTION 'كل عنصر في days يجب أن يكون كائناً';
  END IF;

  SELECT
    count(*)::INTEGER,
    count(DISTINCT lower(btrim(item->>'day_of_week')))::INTEGER
  INTO v_day_count, v_distinct_day_count
  FROM jsonb_array_elements(p_days) item;

  IF v_day_count <> 7 OR v_distinct_day_count <> 7 THEN
    RAISE EXCEPTION 'الأيام السبعة يجب أن تكون فريدة وكاملة';
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
      )
  ) THEN
    RAISE EXCEPTION 'أيام العمل تتطلب وقت بداية ونهاية بصيغة HH:MM';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_days) item
    WHERE (item->>'is_working_day')::BOOLEAN
      AND (item->>'end_time')::TIME <= (item->>'start_time')::TIME
  ) THEN
    RAISE EXCEPTION 'وقت نهاية العمل يجب أن يكون بعد وقت البداية في نفس اليوم';
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

  -- Serialize all schedule changes for one employee.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_employee_id::TEXT, 0));

  -- No pre-existing effective version may start at or after the new date.
  -- This keeps v1 to one future change at a time and prevents hidden chains.
  IF EXISTS (
    SELECT 1
    FROM public.hr_employee_work_schedules s
    WHERE s.employee_id = p_employee_id
      AND s.status IN ('active', 'retired')
      AND s.effective_from >= p_effective_from
  ) THEN
    RAISE EXCEPTION 'يوجد جدول فعّال أو مخطط يبدأ في نفس التاريخ أو بعده؛ راجع التسلسل أولاً';
  END IF;

  -- The unique partial index guarantees at most one row here.
  SELECT s.*
  INTO v_previous
  FROM public.hr_employee_work_schedules s
  WHERE s.employee_id = p_employee_id
    AND s.status = 'active'
  FOR UPDATE;

  v_previous_found := FOUND;

  IF v_previous_found THEN
    IF v_previous.effective_from >= p_effective_from THEN
      RAISE EXCEPTION 'تاريخ الجدول الجديد يجب أن يلي بداية الجدول النشط الحالي';
    END IF;

    v_previous_new_end := CASE
      WHEN v_previous.effective_to IS NULL
        OR v_previous.effective_to >= p_effective_from
        THEN p_effective_from - 1
      ELSE v_previous.effective_to
    END;

    IF EXISTS (
      SELECT 1
      FROM public.hr_attendance_days ad
      WHERE ad.work_schedule_id = v_previous.id
        AND ad.shift_date > v_previous_new_end
    ) THEN
      RAISE EXCEPTION 'لا يمكن إغلاق الجدول السابق بسبب وجود حضور مرتبط بعد نهايته المقترحة';
    END IF;

    UPDATE public.hr_employee_work_schedules
    SET status = 'retired',
        effective_to = v_previous_new_end,
        retired_by = v_actor,
        retired_at = now(),
        updated_by = v_actor
    WHERE id = v_previous.id;
  END IF;

  INSERT INTO public.hr_employee_work_schedules (
    employee_id,
    effective_from,
    effective_to,
    status,
    notes,
    created_by,
    updated_by
  ) VALUES (
    p_employee_id,
    p_effective_from,
    NULL,
    'draft',
    NULLIF(btrim(p_notes), ''),
    v_actor,
    v_actor
  )
  RETURNING id INTO v_schedule_id;

  INSERT INTO public.hr_employee_work_schedule_days (
    schedule_id,
    day_of_week,
    is_working_day,
    start_time,
    end_time
  )
  SELECT
    v_schedule_id,
    lower(btrim(item->>'day_of_week'))::public.hr_day_of_week,
    (item->>'is_working_day')::BOOLEAN,
    CASE
      WHEN (item->>'is_working_day')::BOOLEAN
        THEN (item->>'start_time')::TIME
      ELSE NULL
    END,
    CASE
      WHEN (item->>'is_working_day')::BOOLEAN
        THEN (item->>'end_time')::TIME
      ELSE NULL
    END
  FROM jsonb_array_elements(p_days) item;

  UPDATE public.hr_employee_work_schedules
  SET status = 'active',
      activated_by = v_actor,
      activated_at = now(),
      updated_by = v_actor
  WHERE id = v_schedule_id;

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
        )
        ORDER BY d.day_of_week
      )
      FROM public.hr_employee_work_schedule_days d
      WHERE d.schedule_id = s.id
    )
  )
  INTO v_result
  FROM public.hr_employee_work_schedules s
  WHERE s.id = v_schedule_id;

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
    'employee_work_schedule_saved',
    'hr_employee_work_schedule',
    v_schedule_id,
    CASE
      WHEN v_previous_found THEN to_jsonb(v_previous)
      ELSE NULL
    END,
    v_result,
    'EDARA employee work schedule RPC'
  );

  RETURN jsonb_build_object(
    'success', true,
    'schedule', v_result,
    'previous_schedule_retired', v_previous_found,
    'feature_enabled', public.hr_employee_work_schedules_enabled()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.save_employee_work_schedule(UUID, DATE, JSONB, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_employee_work_schedule(UUID, DATE, JSONB, TEXT)
  TO authenticated;

DO $assertions$
BEGIN
  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'M2 integrity assertion failed: feature switch became enabled';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'M2 integrity assertion failed: no schedule data may be seeded';
  END IF;
END;
$assertions$;

COMMIT;
