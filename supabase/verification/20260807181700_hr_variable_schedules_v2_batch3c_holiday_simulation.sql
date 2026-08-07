-- HR Variable Schedules V2 — Batch 3C behavioral simulation
-- Transactional and rollback-only. Proves the same complete custom weekly schedule
-- remains a 360-minute workday on a normal date but becomes a 0-minute non-working
-- official day when that date is present in hr_public_holidays.

BEGIN;

DO $simulation$
DECLARE
  v_today date := (now() AT TIME ZONE 'Africa/Cairo')::date;
  v_employee_id uuid;
  v_schedule_id uuid;
  v_effective_from date := v_today + 30;
  v_normal_date date := v_today + 35;
  v_holiday_date date := v_today + 36;
  v_ctx record;
  v_normal_seen boolean := false;
  v_holiday_seen boolean := false;
BEGIN
  INSERT INTO public.hr_employees (
    employee_number,
    full_name,
    personal_phone,
    hire_date,
    status
  ) VALUES (
    'V2-SIM-B3C-001',
    'V2 Batch 3C Holiday Fixture',
    '01000000002',
    v_today - 60,
    'active'
  )
  RETURNING id INTO v_employee_id;

  INSERT INTO public.hr_employee_work_schedules (
    employee_id,
    effective_from,
    notes
  ) VALUES (
    v_employee_id,
    v_effective_from,
    'Batch 3C public-holiday precedence fixture'
  )
  RETURNING id INTO v_schedule_id;

  -- Complete seven-day schedule: every weekday is intentionally 10:00–16:00 so
  -- the only reason v_holiday_date becomes non-working is the official holiday.
  INSERT INTO public.hr_employee_work_schedule_days (
    schedule_id,
    day_of_week,
    is_working_day,
    start_time,
    end_time
  )
  SELECT
    v_schedule_id,
    dow::smallint,
    true,
    '10:00'::time,
    '16:00'::time
  FROM generate_series(0, 6) AS dow;

  -- year is a generated column derived from holiday_date and must not be supplied.
  INSERT INTO public.hr_public_holidays (
    name,
    holiday_date,
    is_recurring,
    notes
  ) VALUES (
    'V2 Batch 3C simulated official holiday',
    v_holiday_date,
    false,
    'Rollback-only rehearsal fixture'
  );

  SELECT *
  INTO v_ctx
  FROM public.resolve_employee_custom_schedule(v_employee_id, v_normal_date);

  v_normal_seen := FOUND;

  IF NOT v_normal_seen
     OR v_ctx.schedule_id IS DISTINCT FROM v_schedule_id
     OR v_ctx.is_working_day IS DISTINCT FROM true
     OR v_ctx.start_time IS DISTINCT FROM '10:00'::time
     OR v_ctx.end_time IS DISTINCT FROM '16:00'::time
     OR v_ctx.scheduled_minutes IS DISTINCT FROM 360 THEN
    RAISE EXCEPTION
      'Batch 3C simulation failed: normal custom workday did not remain 10:00-16:00 / 360 minutes';
  END IF;

  SELECT *
  INTO v_ctx
  FROM public.resolve_employee_custom_schedule(v_employee_id, v_holiday_date);

  v_holiday_seen := FOUND;

  IF NOT v_holiday_seen
     OR v_ctx.schedule_id IS DISTINCT FROM v_schedule_id
     OR v_ctx.is_working_day IS DISTINCT FROM false
     OR v_ctx.start_time IS NOT NULL
     OR v_ctx.end_time IS NOT NULL
     OR v_ctx.scheduled_minutes IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION
      'Batch 3C simulation failed: official holiday did not override custom weekday to non-working / 0 minutes';
  END IF;
END;
$simulation$;

ROLLBACK;

-- Fixture must not survive the simulation.
DO $post_rollback$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.hr_employees WHERE employee_number = 'V2-SIM-B3C-001'
  ) OR EXISTS (
    SELECT 1 FROM public.hr_public_holidays
    WHERE name = 'V2 Batch 3C simulated official holiday'
  ) THEN
    RAISE EXCEPTION 'Batch 3C simulation failed: rollback left fixture data behind';
  END IF;

  IF public.hr_variable_schedules_v2_runtime_enabled() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Batch 3C simulation failed: runtime gate changed';
  END IF;
END;
$post_rollback$;

SELECT 'batch3c_holiday_simulation_pass' AS result;
