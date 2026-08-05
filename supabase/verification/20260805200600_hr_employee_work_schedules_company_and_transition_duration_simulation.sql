-- =============================================================================
-- Employee Work Schedules — company and transition duration simulation
--
-- DISPOSABLE DATABASE ONLY.
-- Required session guard:
--   SET SESSION edara.allow_schedule_simulation = 'disposable-only';
--
-- Tests both boundaries:
--   1. company 8h fallback -> first custom 6h schedule;
--   2. custom 6h -> custom 9h schedule.
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
  v_first_month_start DATE;
  v_initial_midmonth DATE;
  v_transition_midmonth DATE;
  v_second_month_start DATE;
  v_first_schedule UUID;
  v_second_schedule UUID;
  v_result JSONB;
  v_six JSONB;
  v_nine JSONB;
  v_initial_rejected BOOLEAN := false;
  v_transition_rejected BOOLEAN := false;
BEGIN
  IF current_setting('edara.allow_schedule_simulation', true) IS DISTINCT FROM 'disposable-only' THEN
    RAISE EXCEPTION 'Simulation safety stop: disposable-only session flag is required';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Simulation requires feature/readiness to remain false';
  END IF;

  IF public.get_company_default_scheduled_minutes() <> 480 THEN
    RAISE EXCEPTION 'Simulation requires the reviewed 480-minute company baseline';
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

  v_first_month_start := (date_trunc('month', v_today) + INTERVAL '2 months')::DATE;
  v_initial_midmonth := v_first_month_start + 10;
  v_transition_midmonth := v_first_month_start + 20;
  v_second_month_start := (v_first_month_start + INTERVAL '1 month')::DATE;

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
    'SIMC-' || v_suffix,
    'محاكاة مرجع ساعات الشركة',
    '+999710' || v_suffix,
    'active',
    v_today,
    6000,
    v_actor,
    'Disposable company/transition duration simulation'
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

  -- Initial custom schedule differs from company 8h and must not start midmonth.
  BEGIN
    PERFORM public.save_employee_work_schedule(
      v_employee_id,
      v_initial_midmonth,
      v_six,
      'Expected initial midmonth rejection'
    );
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM ILIKE '%first day of a month%'
         OR SQLERRM ILIKE '%outside a month boundary%' THEN
        v_initial_rejected := true;
      ELSE
        RAISE;
      END IF;
  END;

  IF NOT v_initial_rejected THEN
    RAISE EXCEPTION 'Simulation failed: first 6h custom schedule was accepted midmonth against company 8h baseline';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.hr_employee_work_schedules WHERE employee_id = v_employee_id
  ) THEN
    RAISE EXCEPTION 'Simulation failed: rejected initial schedule left persisted rows';
  END IF;

  SELECT public.save_employee_work_schedule(
    v_employee_id,
    v_first_month_start,
    v_six,
    'Allowed first-of-month six-hour schedule'
  ) INTO v_result;
  v_first_schedule := (v_result #>> '{schedule,id}')::UUID;

  IF v_first_schedule IS NULL THEN
    RAISE EXCEPTION 'Simulation failed: first-of-month initial schedule was not created';
  END IF;

  -- Subsequent duration change must also wait for a month boundary.
  BEGIN
    PERFORM public.save_employee_work_schedule(
      v_employee_id,
      v_transition_midmonth,
      v_nine,
      'Expected custom transition midmonth rejection'
    );
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM ILIKE '%first day of a month%'
         OR SQLERRM ILIKE '%outside a month boundary%' THEN
        v_transition_rejected := true;
      ELSE
        RAISE;
      END IF;
  END;

  IF NOT v_transition_rejected THEN
    RAISE EXCEPTION 'Simulation failed: six-to-nine-hour custom transition was accepted midmonth';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.hr_employee_work_schedules
    WHERE id = v_first_schedule
      AND status = 'active'
      AND effective_to IS NULL
  ) THEN
    RAISE EXCEPTION 'Simulation failed: rejected transition altered the active six-hour schedule';
  END IF;

  SELECT public.save_employee_work_schedule(
    v_employee_id,
    v_second_month_start,
    v_nine,
    'Allowed first-of-month nine-hour transition'
  ) INTO v_result;
  v_second_schedule := (v_result #>> '{schedule,id}')::UUID;

  IF v_second_schedule IS NULL THEN
    RAISE EXCEPTION 'Simulation failed: first-of-month nine-hour transition was not created';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.hr_employee_work_schedules
    WHERE id = v_first_schedule
      AND status = 'retired'
      AND effective_to = v_second_month_start - 1
  ) THEN
    RAISE EXCEPTION 'Simulation failed: six-hour predecessor was not closed at the month boundary';
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
    RAISE EXCEPTION 'Simulation failed: accepted replacement is not a consistent nine-hour schedule';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Simulation failed: feature/readiness changed unexpectedly';
  END IF;
END;
$simulation$;

SELECT jsonb_build_object(
  'simulation_status', 'pass_before_rollback',
  'company_baseline_minutes', public.get_company_default_scheduled_minutes(),
  'initial_six_hour_midmonth_rejected', true,
  'initial_six_hour_month_start_accepted', true,
  'six_to_nine_midmonth_rejected', true,
  'six_to_nine_month_start_accepted', true,
  'rejected_writes_left_no_state_change', true,
  'next_action', 'ROLLBACK'
) AS company_and_transition_duration_simulation;

ROLLBACK;
