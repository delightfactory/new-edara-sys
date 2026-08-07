-- HR Variable Schedules V2 — Batch 4A behavioral simulation
-- Rollback-only. Proves mixed-source day resolution and exact custom schedule metrics
-- without invoking or modifying the official payroll calculator.

BEGIN;

DO $simulation$
DECLARE
  v_today date := (now() AT TIME ZONE 'Africa/Cairo')::date;
  v_week_start date;
  v_employee_id uuid;
  v_schedule_id uuid;
  v_day record;
  v_metrics record;
BEGIN
  -- Future Sunday, safely beyond the schedule minimum effective date.
  v_week_start := v_today
    + (((7 - EXTRACT(DOW FROM v_today)::integer) % 7) + 35);

  INSERT INTO public.hr_employees (
    employee_number,
    full_name,
    personal_phone,
    hire_date,
    status
  ) VALUES (
    'V2-SIM-B4A-001',
    'V2 Batch 4A Payroll Metrics Fixture',
    '01000000003',
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
    v_week_start,
    'Batch 4A rollback-only schedule metrics fixture'
  )
  RETURNING id INTO v_schedule_id;

  -- Monday/Tuesday/Wednesday are 6-hour workdays. Other weekdays are custom off.
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
    (dow IN (1, 2, 3)),
    CASE WHEN dow IN (1, 2, 3) THEN '10:00'::time ELSE NULL END,
    CASE WHEN dow IN (1, 2, 3) THEN '16:00'::time ELSE NULL END
  FROM generate_series(0, 6) AS dow;

  -- Tuesday is an official holiday, so only Monday and Wednesday remain payable
  -- scheduled workdays in this custom week.
  INSERT INTO public.hr_public_holidays (
    name,
    holiday_date,
    is_recurring,
    notes
  ) VALUES (
    'V2 Batch 4A simulated payroll holiday',
    v_week_start + 2,
    false,
    'Rollback-only rehearsal fixture'
  );

  SELECT *
  INTO v_day
  FROM public.hr_v2_resolve_payroll_schedule_day(v_employee_id, v_week_start + 1);

  IF v_day.schedule_source <> 'custom'
     OR v_day.custom_schedule_id IS DISTINCT FROM v_schedule_id
     OR v_day.day_kind <> 'work_day'
     OR v_day.is_working_day IS DISTINCT FROM true
     OR v_day.scheduled_minutes <> 360 THEN
    RAISE EXCEPTION 'Batch 4A simulation failed: Monday custom payroll day != 360 minutes';
  END IF;

  SELECT *
  INTO v_day
  FROM public.hr_v2_resolve_payroll_schedule_day(v_employee_id, v_week_start + 2);

  IF v_day.schedule_source <> 'custom'
     OR v_day.day_kind <> 'public_holiday'
     OR v_day.is_working_day IS DISTINCT FROM false
     OR v_day.scheduled_minutes <> 0 THEN
    RAISE EXCEPTION 'Batch 4A simulation failed: public holiday was not zero-scheduled';
  END IF;

  SELECT *
  INTO v_metrics
  FROM public.hr_v2_get_payroll_schedule_metrics(
    v_employee_id,
    v_week_start,
    v_week_start + 6
  );

  IF v_metrics.work_days <> 2
     OR v_metrics.scheduled_minutes <> 720
     OR v_metrics.custom_dates <> 7
     OR v_metrics.custom_work_days <> 2
     OR v_metrics.legacy_work_days <> 0 THEN
    RAISE EXCEPTION
      'Batch 4A simulation failed: expected full custom week metrics 2 days/720 minutes/7 custom dates, got %/%/%',
      v_metrics.work_days, v_metrics.scheduled_minutes, v_metrics.custom_dates;
  END IF;

  -- Thursday-Saturday are a legitimate zero-workday custom interval. The helper
  -- must preserve zero instead of synthesizing the Legacy payroll fallback of one.
  SELECT *
  INTO v_metrics
  FROM public.hr_v2_get_payroll_schedule_metrics(
    v_employee_id,
    v_week_start + 4,
    v_week_start + 6
  );

  IF v_metrics.work_days <> 0
     OR v_metrics.scheduled_minutes <> 0
     OR v_metrics.custom_dates <> 3 THEN
    RAISE EXCEPTION
      'Batch 4A simulation failed: custom off-only interval did not remain zero';
  END IF;

  -- Date immediately before effective_from must remain exact Legacy source.
  SELECT *
  INTO v_day
  FROM public.hr_v2_resolve_payroll_schedule_day(v_employee_id, v_week_start - 1);

  IF v_day.schedule_source <> 'legacy'
     OR v_day.custom_schedule_id IS NOT NULL
     OR v_day.day_kind NOT IN ('work_day', 'weekly_off', 'public_holiday')
     OR (v_day.is_working_day AND v_day.scheduled_minutes <= 0)
     OR (NOT v_day.is_working_day AND v_day.scheduled_minutes <> 0) THEN
    RAISE EXCEPTION 'Batch 4A simulation failed: pre-effective date did not preserve Legacy schedule source';
  END IF;

  -- Batch 4A must remain financially inert.
  IF EXISTS (
    SELECT 1
    FROM public.hr_payroll_lines pl
    WHERE pl.employee_id = v_employee_id
  ) THEN
    RAISE EXCEPTION 'Batch 4A simulation failed: schedule metrics created payroll rows';
  END IF;
END;
$simulation$;

ROLLBACK;

DO $post_rollback$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.hr_employees WHERE employee_number = 'V2-SIM-B4A-001'
  ) OR EXISTS (
    SELECT 1 FROM public.hr_public_holidays
    WHERE name = 'V2 Batch 4A simulated payroll holiday'
  ) THEN
    RAISE EXCEPTION 'Batch 4A simulation failed: fixture survived rollback';
  END IF;

  IF public.hr_variable_schedules_v2_runtime_enabled() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Batch 4A simulation failed: runtime gate changed';
  END IF;
END;
$post_rollback$;

SELECT 'batch4a_metrics_simulation_pass' AS result;
