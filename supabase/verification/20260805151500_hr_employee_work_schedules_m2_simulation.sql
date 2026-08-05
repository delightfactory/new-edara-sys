-- =============================================================================
-- Employee Work Schedules M2 — transactional simulation (DISPOSABLE DB ONLY)
--
-- Safety gate:
--   SET SESSION edara.allow_schedule_simulation = 'disposable-only';
--
-- The feature switch remains FALSE throughout this simulation. Custom schedule
-- behavior is inspected through the internal core resolver. Every write is
-- rolled back at the end.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

DO $simulation$
DECLARE
  v_actor UUID;
  v_employee_id UUID;
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_first_start DATE;
  v_second_start DATE;
  v_legacy_date DATE;
  v_first_schedule_id UUID;
  v_second_schedule_id UUID;
  v_attendance_id UUID;
  v_result JSONB;
  v_days JSONB;
  v_updated_days JSONB;
  v_replacement_days JSONB;
  v_resolved RECORD;
  v_snapshot_at TIMESTAMPTZ;
  v_snapshot_start TIMESTAMPTZ;
  v_expected_failure BOOLEAN;
BEGIN
  IF current_setting('edara.allow_schedule_simulation', true) IS DISTINCT FROM 'disposable-only' THEN
    RAISE EXCEPTION 'Simulation safety stop: disposable-only session flag is required';
  END IF;

  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'Simulation requires the feature switch to remain false';
  END IF;

  IF to_regprocedure('public.hr_employee_work_schedules_activation_ready()') IS NOT NULL
     AND public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Simulation requires activation readiness to remain false';
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

  SELECT e.id
  INTO v_employee_id
  FROM public.hr_employees e
  WHERE e.status = 'active'
    AND e.termination_date IS NULL
  ORDER BY e.hire_date, e.id
  LIMIT 1;

  IF v_employee_id IS NULL THEN
    RAISE EXCEPTION 'Simulation could not find an active employee';
  END IF;

  v_first_start := v_today + ((6 - EXTRACT(DOW FROM v_today)::INTEGER + 7) % 7);
  IF v_first_start <= v_today THEN
    v_first_start := v_first_start + 7;
  END IF;

  LOOP
    v_legacy_date := v_first_start - 2;
    EXIT WHEN NOT EXISTS (
      SELECT 1
      FROM public.hr_public_holidays h
      WHERE h.holiday_date IN (
        v_legacy_date,
        v_first_start,
        v_first_start + 1,
        v_first_start + 6,
        v_first_start + 14
      )
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.hr_attendance_days ad
      WHERE ad.employee_id = v_employee_id
        AND ad.shift_date = v_legacy_date
    );

    v_first_start := v_first_start + 7;
  END LOOP;

  v_second_start := v_first_start + 14;

  v_days := jsonb_build_array(
    jsonb_build_object('day_of_week','saturday',  'is_working_day',true,  'start_time','15:00','end_time','21:00'),
    jsonb_build_object('day_of_week','sunday',    'is_working_day',true,  'start_time','10:00','end_time','16:00'),
    jsonb_build_object('day_of_week','monday',    'is_working_day',true,  'start_time','15:00','end_time','21:00'),
    jsonb_build_object('day_of_week','tuesday',   'is_working_day',true,  'start_time','15:00','end_time','21:00'),
    jsonb_build_object('day_of_week','wednesday', 'is_working_day',true,  'start_time','10:00','end_time','16:00'),
    jsonb_build_object('day_of_week','thursday',  'is_working_day',true,  'start_time','10:00','end_time','16:00'),
    jsonb_build_object('day_of_week','friday',    'is_working_day',false, 'start_time',NULL,   'end_time',NULL)
  );

  SELECT public.save_employee_work_schedule(
    v_employee_id,
    v_first_start,
    v_days,
    'Disposable simulation — mixed six-hour schedule'
  ) INTO v_result;

  v_first_schedule_id := (v_result #>> '{schedule,id}')::UUID;
  IF v_first_schedule_id IS NULL THEN
    RAISE EXCEPTION 'Simulation failed: first schedule ID is missing';
  END IF;

  -- Public resolver remains company fallback while the rollout switch is off.
  SELECT * INTO v_resolved
  FROM public.resolve_employee_work_schedule(v_employee_id, v_first_start);

  IF v_resolved.schedule_source <> 'company' THEN
    RAISE EXCEPTION 'Simulation failed: disabled public resolver did not preserve company fallback';
  END IF;

  -- Core resolver validates the prepared future schedule without activation.
  SELECT * INTO v_resolved
  FROM public.resolve_employee_work_schedule_core(v_employee_id, v_first_start, true);

  IF v_resolved.schedule_source <> 'employee'
     OR v_resolved.work_schedule_id <> v_first_schedule_id
     OR v_resolved.scheduled_minutes <> 360
     OR (v_resolved.scheduled_start_at AT TIME ZONE 'Africa/Cairo')::TIME <> TIME '15:00'
     OR (v_resolved.scheduled_end_at AT TIME ZONE 'Africa/Cairo')::TIME <> TIME '21:00' THEN
    RAISE EXCEPTION 'Simulation failed: mixed Saturday schedule is incorrect';
  END IF;

  SELECT * INTO v_resolved
  FROM public.resolve_employee_work_schedule_core(v_employee_id, v_first_start + 6, true);

  IF v_resolved.day_kind <> 'weekly_off'
     OR v_resolved.scheduled_minutes <> 0
     OR v_resolved.scheduled_start_at IS NOT NULL
     OR v_resolved.scheduled_end_at IS NOT NULL THEN
    RAISE EXCEPTION 'Simulation failed: Friday off-day resolution is incorrect';
  END IF;

  -- Correct the unstarted schedule through the narrow future-update RPC.
  v_updated_days := jsonb_set(v_days, '{0,start_time}', '"14:00"'::JSONB);
  v_updated_days := jsonb_set(v_updated_days, '{0,end_time}', '"20:00"'::JSONB);

  SELECT public.update_future_employee_work_schedule(
    v_first_schedule_id,
    v_updated_days,
    'Disposable simulation — corrected before activation'
  ) INTO v_result;

  SELECT * INTO v_resolved
  FROM public.resolve_employee_work_schedule_core(v_employee_id, v_first_start, true);

  IF (v_resolved.scheduled_start_at AT TIME ZONE 'Africa/Cairo')::TIME <> TIME '14:00'
     OR (v_resolved.scheduled_end_at AT TIME ZONE 'Africa/Cairo')::TIME <> TIME '20:00'
     OR v_resolved.scheduled_minutes <> 360 THEN
    RAISE EXCEPTION 'Simulation failed: future schedule correction did not persist';
  END IF;

  -- Reject a zero-workday correction.
  v_expected_failure := false;
  BEGIN
    PERFORM public.update_future_employee_work_schedule(
      v_first_schedule_id,
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'day_of_week', item->>'day_of_week',
            'is_working_day', false,
            'start_time', NULL,
            'end_time', NULL
          )
        )
        FROM jsonb_array_elements(v_days) item
      ),
      'Expected rejection'
    );
  EXCEPTION WHEN OTHERS THEN
    v_expected_failure := true;
  END;

  IF NOT v_expected_failure THEN
    RAISE EXCEPTION 'Simulation failed: all-off schedule correction was accepted';
  END IF;

  -- Add a later nine-hour replacement and prove lifecycle closure.
  v_replacement_days := jsonb_build_array(
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
    v_second_start,
    v_replacement_days,
    'Disposable simulation — nine-hour replacement'
  ) INTO v_result;

  v_second_schedule_id := (v_result #>> '{schedule,id}')::UUID;

  IF NOT EXISTS (
    SELECT 1
    FROM public.hr_employee_work_schedules
    WHERE id = v_first_schedule_id
      AND status = 'retired'
      AND effective_to = v_second_start - 1
  ) THEN
    RAISE EXCEPTION 'Simulation failed: prior schedule lifecycle was not closed correctly';
  END IF;

  SELECT * INTO v_resolved
  FROM public.resolve_employee_work_schedule_core(v_employee_id, v_second_start, true);

  IF v_resolved.work_schedule_id <> v_second_schedule_id
     OR v_resolved.scheduled_minutes <> 540 THEN
    RAISE EXCEPTION 'Simulation failed: nine-hour replacement is incorrect';
  END IF;

  -- Legacy attendance before custom activation receives a company snapshot and
  -- remains immutable when company settings change inside this transaction.
  INSERT INTO public.hr_attendance_days (
    employee_id, shift_date, work_date, status, notes
  ) VALUES (
    v_employee_id,
    v_legacy_date,
    v_legacy_date,
    'present',
    'Disposable legacy snapshot simulation'
  ) RETURNING id INTO v_attendance_id;

  PERFORM public.ensure_attendance_schedule_snapshot(v_attendance_id);

  SELECT schedule_snapshot_at, scheduled_start_at
  INTO v_snapshot_at, v_snapshot_start
  FROM public.hr_attendance_days
  WHERE id = v_attendance_id;

  IF v_snapshot_at IS NULL OR v_snapshot_start IS NULL THEN
    RAISE EXCEPTION 'Simulation failed: legacy company snapshot was not created';
  END IF;

  UPDATE public.company_settings
  SET value = '12:00', updated_at = now()
  WHERE key = 'hr.work_start_time';

  PERFORM public.ensure_attendance_schedule_snapshot(v_attendance_id);

  IF EXISTS (
    SELECT 1
    FROM public.hr_attendance_days
    WHERE id = v_attendance_id
      AND (
        schedule_snapshot_at IS DISTINCT FROM v_snapshot_at
        OR scheduled_start_at IS DISTINCT FROM v_snapshot_start
      )
  ) THEN
    RAISE EXCEPTION 'Simulation failed: immutable snapshot changed';
  END IF;

  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'Simulation failed: feature switch changed unexpectedly';
  END IF;
END;
$simulation$;

SELECT jsonb_build_object(
  'simulation_status', 'pass_before_rollback',
  'feature_enabled_inside_transaction', public.hr_employee_work_schedules_enabled(),
  'temporary_schedule_rows', (SELECT count(*) FROM public.hr_employee_work_schedules),
  'temporary_snapshot_rows', (
    SELECT count(*) FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL
  ),
  'next_action', 'ROLLBACK'
) AS m2_simulation_result;

ROLLBACK;
