-- =============================================================================
-- Employee Work Schedules — daily-duration month-boundary simulation
--
-- DISPOSABLE DATABASE ONLY.
-- Required session guard:
--   SET SESSION edara.allow_schedule_simulation = 'disposable-only';
--
-- Every temporary record is rolled back.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

DO $simulation$
DECLARE
  v_actor UUID;
  v_employee_id UUID := extensions.gen_random_uuid();
  v_suffix TEXT := substr(replace(extensions.gen_random_uuid()::TEXT, '-', ''), 1, 10);
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_first_start DATE;
  v_midmonth_start DATE;
  v_month_start DATE;
  v_first_schedule UUID;
  v_second_schedule UUID;
  v_result JSONB;
  v_six JSONB;
  v_nine JSONB;
  v_rejected BOOLEAN := false;
BEGIN
  IF current_setting('edara.allow_schedule_simulation', true) IS DISTINCT FROM 'disposable-only' THEN
    RAISE EXCEPTION 'Simulation safety stop: disposable-only session flag is required';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Simulation requires feature/readiness to remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'Simulation requires empty schedule tables';
  END IF;

  SELECT candidate.user_id
  INTO v_actor
  FROM (
    SELECT DISTINCT ur.user_id
    FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id = ur.role_id
    WHERE rp.permission IN ('*', 'hr.employees.edit')
  ) candidate
  JOIN public.profiles p ON p.id = candidate.user_id
  ORDER BY candidate.user_id
  LIMIT 1;

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Simulation could not find an HR schedule editor';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_actor::TEXT, true);

  v_first_start := v_today + 10;
  IF EXTRACT(DAY FROM v_first_start)::INTEGER = 1 THEN
    v_first_start := v_first_start + 1;
  END IF;

  v_midmonth_start := v_first_start + 7;
  WHILE EXTRACT(DAY FROM v_midmonth_start)::INTEGER = 1 LOOP
    v_midmonth_start := v_midmonth_start + 1;
  END LOOP;

  v_month_start := (date_trunc('month', v_midmonth_start) + INTERVAL '1 month')::DATE;

  INSERT INTO public.hr_employees (
    id,
    employee_number,
    full_name,
    personal_phone,
    status,
    hire_date,
    base_salary,
    created_by,
    notes
  ) VALUES (
    v_employee_id,
    'SIMB-' || v_suffix,
    'محاكاة حد تغيير ساعات اليوم',
    '+999700' || v_suffix,
    'active',
    v_first_start,
    6000,
    v_actor,
    'Disposable duration-boundary simulation'
  );

  v_six := jsonb_build_array(
    jsonb_build_object('day_of_week','saturday',  'is_working_day',true,  'start_time','15:00','end_time','21:00'),
    jsonb_build_object('day_of_week','sunday',    'is_working_day',true,  'start_time','10:00','end_time','16:00'),
    jsonb_build_object('day_of_week','monday',    'is_working_day',true,  'start_time','15:00','end_time','21:00'),
    jsonb_build_object('day_of_week','tuesday',   'is_working_day',true,  'start_time','15:00','end_time','21:00'),
    jsonb_build_object('day_of_week','wednesday', 'is_working_day',true,  'start_time','10:00','end_time','16:00'),
    jsonb_build_object('day_of_week','thursday',  'is_working_day',true,  'start_time','10:00','end_time','16:00'),
    jsonb_build_object('day_of_week','friday',    'is_working_day',false, 'start_time',NULL,   'end_time',NULL)
  );

  v_nine := jsonb_build_array(
    jsonb_build_object('day_of_week','saturday',  'is_working_day',true,  'start_time','09:00','end_time','18:00'),
    jsonb_build_object('day_of_week','sunday',    'is_working_day',true,  'start_time','09:00','end_time','18:00'),
    jsonb_build_object('day_of_week','monday',    'is_working_day',true,  'start_time','09:00','end_time','18:00'),
    jsonb_build_object('day_of_week','tuesday',   'is_working_day',true,  'start_time','09:00','end_time','18:00'),
    jsonb_build_object('day_of_week','wednesday', 'is_working_day',true,  'start_time','09:00','end_time','18:00'),
    jsonb_build_object('day_of_week','thursday',  'is_working_day',true,  'start_time','09:00','end_time','18:00'),
    jsonb_build_object('day_of_week','friday',    'is_working_day',false, 'start_time',NULL,   'end_time',NULL)
  );

  SELECT public.save_employee_work_schedule(
    v_employee_id,
    v_first_start,
    v_six,
    'Initial six-hour schedule'
  ) INTO v_result;
  v_first_schedule := (v_result #>> '{schedule,id}')::UUID;

  BEGIN
    PERFORM public.save_employee_work_schedule(
      v_employee_id,
      v_midmonth_start,
      v_nine,
      'Expected midmonth rejection'
    );
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM ILIKE '%first day of a month%'
         OR SQLERRM ILIKE '%outside a month boundary%' THEN
        v_rejected := true;
      ELSE
        RAISE;
      END IF;
  END;

  IF NOT v_rejected THEN
    RAISE EXCEPTION 'Simulation failed: six-to-nine-hour midmonth change was accepted';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.hr_employee_work_schedules
    WHERE id = v_first_schedule
      AND status = 'active'
      AND effective_to IS NULL
  ) THEN
    RAISE EXCEPTION 'Simulation failed: rejected change altered the original active schedule';
  END IF;

  SELECT public.save_employee_work_schedule(
    v_employee_id,
    v_month_start,
    v_nine,
    'Allowed month-boundary nine-hour schedule'
  ) INTO v_result;
  v_second_schedule := (v_result #>> '{schedule,id}')::UUID;

  IF v_second_schedule IS NULL THEN
    RAISE EXCEPTION 'Simulation failed: month-boundary duration change was not created';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.hr_employee_work_schedules
    WHERE id = v_first_schedule
      AND status = 'retired'
      AND effective_to = v_month_start - 1
  ) THEN
    RAISE EXCEPTION 'Simulation failed: prior schedule was not closed at the month boundary';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.hr_employee_work_schedule_days
    WHERE schedule_id = v_second_schedule
      AND is_working_day
    GROUP BY schedule_id
    HAVING min(scheduled_minutes) = 540
       AND max(scheduled_minutes) = 540
  ) THEN
    RAISE EXCEPTION 'Simulation failed: month-boundary schedule is not a consistent nine-hour schedule';
  END IF;
END;
$simulation$;

SELECT jsonb_build_object(
  'simulation_status', 'pass_before_rollback',
  'midmonth_daily_hours_change_rejected', true,
  'month_boundary_daily_hours_change_accepted', true,
  'rejected_transaction_preserved_previous_schedule', true,
  'next_action', 'ROLLBACK'
) AS duration_boundary_simulation;

ROLLBACK;
