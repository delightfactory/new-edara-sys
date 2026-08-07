-- HR Variable Schedules V2 — Batch 1
-- Additive schema only. This migration intentionally does not modify any existing
-- attendance, leave, payroll, settings, cron, trigger, or application runtime path.

BEGIN;

CREATE TABLE public.hr_employee_work_schedules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE RESTRICT,
  effective_from date NOT NULL,
  effective_to date NULL,
  notes text NULL,
  created_by uuid NULL DEFAULT auth.uid(),
  updated_by uuid NULL DEFAULT auth.uid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT hr_employee_work_schedules_date_range_chk
    CHECK (effective_to IS NULL OR effective_to >= effective_from),
  CONSTRAINT hr_employee_work_schedules_employee_start_uk
    UNIQUE (employee_id, effective_from)
);

COMMENT ON TABLE public.hr_employee_work_schedules IS
  'V2 employee-specific weekly schedule versions. Additive only; no company fallback is stored here.';
COMMENT ON COLUMN public.hr_employee_work_schedules.effective_from IS
  'First date governed by this custom schedule version. New versions must start in the future.';
COMMENT ON COLUMN public.hr_employee_work_schedules.effective_to IS
  'Inclusive final date. NULL means open-ended until a later future version is planned.';

CREATE INDEX hr_employee_work_schedules_employee_range_idx
  ON public.hr_employee_work_schedules (employee_id, effective_from DESC, effective_to);

CREATE TABLE public.hr_employee_work_schedule_days (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  schedule_id uuid NOT NULL REFERENCES public.hr_employee_work_schedules(id) ON DELETE CASCADE,
  day_of_week smallint NOT NULL,
  is_working_day boolean NOT NULL,
  start_time time without time zone NULL,
  end_time time without time zone NULL,
  created_by uuid NULL DEFAULT auth.uid(),
  updated_by uuid NULL DEFAULT auth.uid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT hr_employee_work_schedule_days_dow_chk
    CHECK (day_of_week BETWEEN 0 AND 6),
  CONSTRAINT hr_employee_work_schedule_days_shape_chk
    CHECK (
      (
        is_working_day = true
        AND start_time IS NOT NULL
        AND end_time IS NOT NULL
        AND end_time > start_time
      )
      OR
      (
        is_working_day = false
        AND start_time IS NULL
        AND end_time IS NULL
      )
    ),
  CONSTRAINT hr_employee_work_schedule_days_schedule_dow_uk
    UNIQUE (schedule_id, day_of_week)
);

COMMENT ON TABLE public.hr_employee_work_schedule_days IS
  'Exactly one row per weekday (0=Sunday .. 6=Saturday) for a complete custom schedule version.';
COMMENT ON COLUMN public.hr_employee_work_schedule_days.start_time IS
  'Local Cairo wall-clock start time. Overnight shifts are intentionally unsupported in V1.';
COMMENT ON COLUMN public.hr_employee_work_schedule_days.end_time IS
  'Local Cairo wall-clock end time. Official minutes are derived from start/end; they are not duplicated.';

CREATE INDEX hr_employee_work_schedule_days_schedule_idx
  ON public.hr_employee_work_schedule_days (schedule_id, day_of_week);

CREATE OR REPLACE FUNCTION public.guard_hr_employee_work_schedule_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_today date := (now() AT TIME ZONE 'Africa/Cairo')::date;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.effective_from <= v_today THEN
      RAISE EXCEPTION 'لا يمكن حذف نسخة جدول عمل بدأت بالفعل؛ أنشئ نسخة مستقبلية بدلاً من ذلك';
    END IF;
    RETURN OLD;
  END IF;

  IF NEW.effective_to IS NOT NULL AND NEW.effective_to < NEW.effective_from THEN
    RAISE EXCEPTION 'تاريخ نهاية جدول العمل لا يمكن أن يسبق تاريخ البداية';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.effective_from <= v_today THEN
      RAISE EXCEPTION 'جدول العمل المخصص يجب أن يبدأ في تاريخ مستقبلي';
    END IF;
  ELSE
    IF NEW.employee_id IS DISTINCT FROM OLD.employee_id THEN
      RAISE EXCEPTION 'لا يمكن نقل نسخة جدول عمل من موظف إلى موظف آخر';
    END IF;

    NEW.created_by := OLD.created_by;
    NEW.created_at := OLD.created_at;

    IF OLD.effective_from <= v_today THEN
      -- Historical timing is immutable. The only permitted change on a currently
      -- effective version is planning/changing its future inclusive end date.
      IF OLD.effective_to IS NOT NULL AND OLD.effective_to < v_today THEN
        RAISE EXCEPTION 'لا يمكن تعديل نسخة جدول عمل منتهية تاريخياً';
      END IF;

      IF NEW.effective_from IS DISTINCT FROM OLD.effective_from
         OR NEW.notes IS DISTINCT FROM OLD.notes THEN
        RAISE EXCEPTION 'لا يمكن تعديل بيانات نسخة جدول عمل بدأت بالفعل؛ يسمح فقط بتحديد نهاية مستقبلية لها';
      END IF;

      IF NEW.effective_to IS DISTINCT FROM OLD.effective_to
         AND NEW.effective_to IS NOT NULL
         AND NEW.effective_to < v_today THEN
        RAISE EXCEPTION 'لا يمكن إغلاق جدول عمل فعال بتاريخ سابق';
      END IF;
    ELSE
      IF NEW.effective_from <= v_today THEN
        RAISE EXCEPTION 'لا يمكن تقديم بداية جدول عمل مستقبلي إلى اليوم أو الماضي';
      END IF;
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_employee_work_schedules s
    WHERE s.employee_id = NEW.employee_id
      AND s.id <> NEW.id
      AND (s.effective_to IS NULL OR s.effective_to >= NEW.effective_from)
      AND (NEW.effective_to IS NULL OR s.effective_from <= NEW.effective_to)
  ) THEN
    RAISE EXCEPTION 'يوجد تداخل زمني مع نسخة أخرى من جدول العمل لهذا الموظف';
  END IF;

  NEW.updated_by := COALESCE(auth.uid(), NEW.updated_by, CASE WHEN TG_OP = 'UPDATE' THEN OLD.updated_by ELSE NULL END);
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_hr_employee_work_schedules_lifecycle
BEFORE INSERT OR UPDATE OR DELETE ON public.hr_employee_work_schedules
FOR EACH ROW EXECUTE FUNCTION public.guard_hr_employee_work_schedule_lifecycle();

CREATE OR REPLACE FUNCTION public.guard_hr_employee_work_schedule_day_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_schedule_id uuid;
  v_effective_from date;
  v_today date := (now() AT TIME ZONE 'Africa/Cairo')::date;
BEGIN
  v_schedule_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.schedule_id ELSE NEW.schedule_id END;

  SELECT s.effective_from
  INTO v_effective_from
  FROM public.hr_employee_work_schedules s
  WHERE s.id = v_schedule_id;

  -- During ON DELETE CASCADE, the parent row may already be invisible to the
  -- child trigger. The parent lifecycle trigger has already authorized deletion.
  IF NOT FOUND THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'نسخة جدول العمل غير موجودة';
  END IF;

  IF v_effective_from <= v_today THEN
    RAISE EXCEPTION 'لا يمكن تعديل أيام نسخة جدول عمل بدأت بالفعل؛ أنشئ نسخة مستقبلية جديدة';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.schedule_id IS DISTINCT FROM OLD.schedule_id THEN
      RAISE EXCEPTION 'لا يمكن نقل يوم من نسخة جدول عمل إلى نسخة أخرى';
    END IF;
    NEW.created_by := OLD.created_by;
    NEW.created_at := OLD.created_at;
  END IF;

  NEW.updated_by := COALESCE(auth.uid(), NEW.updated_by, CASE WHEN TG_OP = 'UPDATE' THEN OLD.updated_by ELSE NULL END);
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_hr_employee_work_schedule_days_lifecycle
BEFORE INSERT OR UPDATE OR DELETE ON public.hr_employee_work_schedule_days
FOR EACH ROW EXECUTE FUNCTION public.guard_hr_employee_work_schedule_day_lifecycle();

-- Resolver contract:
-- * returns exactly zero rows when no complete effective custom schedule exists;
-- * a complete schedule has all seven weekdays and at least one working day;
-- * never synthesizes company settings or employee weekly-off fallback;
-- * therefore callers can preserve the exact legacy path when NOT FOUND.
CREATE OR REPLACE FUNCTION public.resolve_employee_custom_schedule(
  p_employee_id uuid,
  p_date date
)
RETURNS TABLE (
  schedule_id uuid,
  employee_id uuid,
  effective_from date,
  effective_to date,
  day_of_week smallint,
  is_working_day boolean,
  start_time time without time zone,
  end_time time without time zone,
  scheduled_minutes integer
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $function$
  SELECT
    s.id AS schedule_id,
    s.employee_id,
    s.effective_from,
    s.effective_to,
    d.day_of_week,
    d.is_working_day,
    d.start_time,
    d.end_time,
    CASE
      WHEN d.is_working_day
        THEN (EXTRACT(EPOCH FROM (d.end_time - d.start_time)) / 60)::integer
      ELSE 0
    END AS scheduled_minutes
  FROM public.hr_employee_work_schedules s
  JOIN public.hr_employee_work_schedule_days d
    ON d.schedule_id = s.id
   AND d.day_of_week = EXTRACT(DOW FROM p_date)::smallint
  WHERE s.employee_id = p_employee_id
    AND p_date >= s.effective_from
    AND (s.effective_to IS NULL OR p_date <= s.effective_to)
    AND (
      SELECT COUNT(*)
      FROM public.hr_employee_work_schedule_days all_days
      WHERE all_days.schedule_id = s.id
    ) = 7
    AND EXISTS (
      SELECT 1
      FROM public.hr_employee_work_schedule_days work_days
      WHERE work_days.schedule_id = s.id
        AND work_days.is_working_day = true
    )
  ORDER BY s.effective_from DESC
  LIMIT 1;
$function$;

COMMENT ON FUNCTION public.resolve_employee_custom_schedule(uuid, date) IS
  'V2 custom-only resolver. Zero rows means caller must use the untouched legacy schedule path.';

ALTER TABLE public.hr_employee_work_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_employee_work_schedule_days ENABLE ROW LEVEL SECURITY;

CREATE POLICY hr_employee_work_schedules_read
ON public.hr_employee_work_schedules
FOR SELECT
USING (
  employee_id IN (
    SELECT e.id
    FROM public.hr_employees e
    WHERE e.user_id = (SELECT auth.uid())
  )
  OR (SELECT public.check_permission((SELECT auth.uid()), 'hr.employees.read'))
);

CREATE POLICY hr_employee_work_schedules_write
ON public.hr_employee_work_schedules
FOR ALL
USING ((SELECT public.check_permission((SELECT auth.uid()), 'hr.employees.create')))
WITH CHECK ((SELECT public.check_permission((SELECT auth.uid()), 'hr.employees.create')));

CREATE POLICY hr_employee_work_schedule_days_read
ON public.hr_employee_work_schedule_days
FOR SELECT
USING (
  EXISTS (
    SELECT 1
    FROM public.hr_employee_work_schedules s
    JOIN public.hr_employees e ON e.id = s.employee_id
    WHERE s.id = schedule_id
      AND (
        e.user_id = (SELECT auth.uid())
        OR (SELECT public.check_permission((SELECT auth.uid()), 'hr.employees.read'))
      )
  )
);

CREATE POLICY hr_employee_work_schedule_days_write
ON public.hr_employee_work_schedule_days
FOR ALL
USING ((SELECT public.check_permission((SELECT auth.uid()), 'hr.employees.create')))
WITH CHECK ((SELECT public.check_permission((SELECT auth.uid()), 'hr.employees.create')));

REVOKE ALL ON TABLE public.hr_employee_work_schedules FROM anon;
REVOKE ALL ON TABLE public.hr_employee_work_schedule_days FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.hr_employee_work_schedules TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.hr_employee_work_schedule_days TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.resolve_employee_custom_schedule(uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_employee_custom_schedule(uuid, date) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.guard_hr_employee_work_schedule_lifecycle() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.guard_hr_employee_work_schedule_day_lifecycle() FROM PUBLIC;

COMMIT;
