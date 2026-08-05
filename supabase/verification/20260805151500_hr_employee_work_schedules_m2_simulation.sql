-- =============================================================================
-- Employee Work Schedules M2 — transactional simulation (DISPOSABLE DB ONLY)
--
-- Safety gate:
--   Run this in the same SQL session first:
--     SET SESSION edara.allow_schedule_simulation = 'disposable-only';
--
-- The script creates schedules and one attendance row inside a transaction,
-- exercises resolver/lifecycle/snapshot behavior, and always ends with ROLLBACK.
-- Do not run on production even though it rolls back.
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
  v_legacy_attendance_date DATE;
  v_first_schedule_id UUID;
  v_second_schedule_id UUID;
  v_attendance_id UUID;
  v_protected_attendance_id UUID;
  v_save_result JSONB;
  v_snapshot_result JSONB;
  v_first_days JSONB;
  v_second_days JSONB;
  v_resolved RECORD;
  v_original_snapshot_at TIMESTAMPTZ;
  v_original_scheduled_start TIMESTAMPTZ;
  v_expected_failure BOOLEAN;
  v_count INTEGER;
BEGIN
  IF current_setting('edara.allow_schedule_simulation', true) IS DISTINCT FROM 'disposable-only' THEN
    RAISE EXCEPTION
      'Simulation safety stop: set edara.allow_schedule_simulation=disposable-only in this disposable DB session first';
  END IF;

  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'Simulation requires the feature switch to start false';
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
    RAISE EXCEPTION 'Simulation could not find a user with hr.employees.edit or wildcard permission';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_actor::TEXT, true);

  SELECT e.id
  INTO v_employee_id
  FROM public.hr_employees e
  WHERE e.status = 'active'
    AND e.termination_date IS NULL
    AND (e.weekly_off_day IS NULL OR e.weekly_off_day = 'friday')
  ORDER BY e.hire_date, e.id
  LIMIT 1;

  IF v_employee_id IS NULL THEN
    RAISE EXCEPTION 'Simulation could not find a suitable active employee';
  END IF;

  -- Next future Saturday. Move by whole weeks until all test dates are clear.
  v_first_start := v_today + ((6 - EXTRACT(DOW FROM v_today)::INTEGER + 7) % 7);
  IF v_first_start <= v_today THEN
    v_first_start := v_first_start + 7;
  END IF;

  LOOP
    v_legacy_attendance_date := v_first_start - 2; -- Thursday before activation.

    EXIT WHEN NOT EXISTS (
      SELECT 1
      FROM public.hr_public_holidays h
      WHERE h.holiday_date IN (
        v_legacy_attendance_date,
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
        AND ad.shift_date = v_legacy_attendance_date
    );

    v_first_start := v_first_start + 7;
  END LOOP;

  v_second_start := v_first_start + 14;

  -- Ahmed Neamatallah-style six-hour alternating windows.
  v_first_days := jsonb_build_array(
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
    v_first_days,
    'M2 disposable simulation — first schedule'
  )
  INTO v_save_result;

  v_first_schedule_id := (v_save_result #>> '{schedule,id}')::UUID;

  IF v_first_schedule_id IS NULL THEN
    RAISE EXCEPTION 'Simulation failed: first save RPC did not return a schedule ID';
  END IF;

  SELECT count(*)
  INTO v_count
  FROM public.hr_employee_work_schedule_days
  WHERE schedule_id = v_first_schedule_id;

  IF v_count <> 7 THEN
    RAISE EXCEPTION 'Simulation failed: first schedule has % day rows', v_count;
  END IF;

  -- Feature false: wrapper must still return company fallback.
  SELECT *
  INTO v_resolved
  FROM public.resolve_employee_work_schedule(v_employee_id, v_first_start);

  IF v_resolved.schedule_source <> 'company'
     OR v_resolved.day_kind <> 'work_day'
     OR v_resolved.scheduled_minutes <> 480
     OR (v_resolved.scheduled_start_at AT TIME ZONE 'Africa/Cairo')::TIME <> TIME '11:00'
     OR (v_resolved.scheduled_end_at AT TIME ZONE 'Africa/Cairo')::TIME <> TIME '19:00' THEN
    RAISE EXCEPTION 'Simulation failed: feature-disabled wrapper did not preserve company fallback';
  END IF;

  -- Internal custom resolution proves the saved schedule itself is correct.
  SELECT *
  INTO v_resolved
  FROM public.resolve_employee_work_schedule_core(v_employee_id, v_first_start, true);

  IF v_resolved.schedule_source <> 'employee'
     OR v_resolved.work_schedule_id <> v_first_schedule_id
     OR v_resolved.scheduled_minutes <> 360
     OR (v_resolved.scheduled_start_at AT TIME ZONE 'Africa/Cairo')::TIME <> TIME '15:00'
     OR (v_resolved.scheduled_end_at AT TIME ZONE 'Africa/Cairo')::TIME <> TIME '21:00' THEN
    RAISE EXCEPTION 'Simulation failed: Saturday custom schedule resolution is incorrect';
  END IF;

  SELECT *
  INTO v_resolved
  FROM public.resolve_employee_work_schedule_core(v_employee_id, v_first_start + 1, true);

  IF v_resolved.scheduled_minutes <> 360
     OR (v_resolved.scheduled_start_at AT TIME ZONE 'Africa/Cairo')::TIME <> TIME '10:00'
     OR (v_resolved.scheduled_end_at AT TIME ZONE 'Africa/Cairo')::TIME <> TIME '16:00' THEN
    RAISE EXCEPTION 'Simulation failed: Sunday custom schedule resolution is incorrect';
  END IF;

  SELECT *
  INTO v_resolved
  FROM public.resolve_employee_work_schedule_core(v_employee_id, v_first_start + 6, true);

  IF v_resolved.day_kind <> 'weekly_off'
     OR v_resolved.is_working_day
     OR v_resolved.scheduled_minutes <> 0
     OR v_resolved.scheduled_start_at IS NOT NULL
     OR v_resolved.scheduled_end_at IS NOT NULL THEN
    RAISE EXCEPTION 'Simulation failed: Friday custom off-day resolution is incorrect';
  END IF;

  -- Enable only inside this rollback transaction and prove wrapper switching.
  UPDATE public.company_settings
  SET value = 'true', updated_at = now()
  WHERE key = 'hr.employee_work_schedules_enabled';

  IF NOT public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'Simulation failed: transactional feature switch did not become true';
  END IF;

  SELECT *
  INTO v_resolved
  FROM public.resolve_employee_work_schedule(v_employee_id, v_first_start);

  IF v_resolved.schedule_source <> 'employee'
     OR v_resolved.work_schedule_id <> v_first_schedule_id THEN
    RAISE EXCEPTION 'Simulation failed: enabled wrapper did not select employee schedule';
  END IF;

  -- Nine-hour official sales-style window for the replacement version.
  v_second_days := jsonb_build_array(
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
    v_second_days,
    'M2 disposable simulation — replacement schedule'
  )
  INTO v_save_result;

  v_second_schedule_id := (v_save_result #>> '{schedule,id}')::UUID;

  IF v_second_schedule_id IS NULL OR v_second_schedule_id = v_first_schedule_id THEN
    RAISE EXCEPTION 'Simulation failed: replacement schedule ID is invalid';
  END IF;

  SELECT count(*)
  INTO v_count
  FROM public.hr_employee_work_schedules
  WHERE employee_id = v_employee_id
    AND status = 'active';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Simulation failed: expected one active schedule, found %', v_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.hr_employee_work_schedules
    WHERE id = v_first_schedule_id
      AND status = 'retired'
      AND effective_to = v_second_start - 1
  ) THEN
    RAISE EXCEPTION 'Simulation failed: first schedule was not retired with the correct end date';
  END IF;

  SELECT *
  INTO v_resolved
  FROM public.resolve_employee_work_schedule(v_employee_id, v_first_start);

  IF v_resolved.work_schedule_id <> v_first_schedule_id
     OR v_resolved.scheduled_minutes <> 360 THEN
    RAISE EXCEPTION 'Simulation failed: retired historical schedule no longer resolves its date';
  END IF;

  SELECT *
  INTO v_resolved
  FROM public.resolve_employee_work_schedule(v_employee_id, v_second_start);

  IF v_resolved.work_schedule_id <> v_second_schedule_id
     OR v_resolved.scheduled_minutes <> 540
     OR (v_resolved.scheduled_start_at AT TIME ZONE 'Africa/Cairo')::TIME <> TIME '09:00'
     OR (v_resolved.scheduled_end_at AT TIME ZONE 'Africa/Cairo')::TIME <> TIME '18:00' THEN
    RAISE EXCEPTION 'Simulation failed: replacement nine-hour schedule is incorrect';
  END IF;

  -- A new normal RPC cannot activate today or in the past.
  v_expected_failure := false;
  BEGIN
    PERFORM public.save_employee_work_schedule(
      v_employee_id,
      v_today,
      v_first_days,
      'Expected rejection'
    );
  EXCEPTION WHEN OTHERS THEN
    v_expected_failure := true;
  END;

  IF NOT v_expected_failure THEN
    RAISE EXCEPTION 'Simulation failed: same-day activation was not rejected';
  END IF;

  -- Legacy attendance row created before first custom effective date.
  INSERT INTO public.hr_attendance_days (
    employee_id,
    shift_date,
    work_date,
    status,
    notes
  ) VALUES (
    v_employee_id,
    v_legacy_attendance_date,
    v_legacy_attendance_date,
    'present',
    'M2 disposable snapshot simulation'
  )
  RETURNING id INTO v_attendance_id;

  SELECT public.ensure_attendance_schedule_snapshot(v_attendance_id)
  INTO v_snapshot_result;

  IF (v_snapshot_result->>'created')::BOOLEAN IS DISTINCT FROM true
     OR v_snapshot_result->>'schedule_source' <> 'company'
     OR (v_snapshot_result->>'scheduled_minutes')::INTEGER <> 480
     OR (v_snapshot_result->>'work_schedule_id') IS NOT NULL THEN
    RAISE EXCEPTION 'Simulation failed: legacy attendance snapshot was not company fallback';
  END IF;

  SELECT schedule_snapshot_at, scheduled_start_at
  INTO v_original_snapshot_at, v_original_scheduled_start
  FROM public.hr_attendance_days
  WHERE id = v_attendance_id;

  -- Change company time inside the transaction. Re-calling the helper must
  -- return the existing snapshot without reinterpretation or resolver failure.
  UPDATE public.company_settings
  SET value = '12:00', updated_at = now()
  WHERE key = 'hr.work_start_time';

  SELECT public.ensure_attendance_schedule_snapshot(v_attendance_id)
  INTO v_snapshot_result;

  IF (v_snapshot_result->>'created')::BOOLEAN IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Simulation failed: complete snapshot was recreated';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_attendance_days
    WHERE id = v_attendance_id
      AND (
        schedule_snapshot_at IS DISTINCT FROM v_original_snapshot_at
        OR scheduled_start_at IS DISTINCT FROM v_original_scheduled_start
      )
  ) THEN
    RAISE EXCEPTION 'Simulation failed: immutable attendance snapshot changed';
  END IF;

  -- Existing approved/paid payroll attendance must reject first snapshot.
  SELECT ad.id
  INTO v_protected_attendance_id
  FROM public.hr_attendance_days ad
  JOIN public.hr_payroll_lines pl ON pl.employee_id = ad.employee_id
  JOIN public.hr_payroll_runs pr ON pr.id = pl.payroll_run_id
  JOIN public.hr_payroll_periods pp ON pp.id = pr.period_id
  WHERE ad.shift_date BETWEEN pp.start_date AND pp.end_date
    AND pr.status IN ('approved', 'paid')
    AND ad.schedule_snapshot_at IS NULL
  ORDER BY ad.shift_date DESC
  LIMIT 1;

  IF v_protected_attendance_id IS NOT NULL THEN
    v_expected_failure := false;
    BEGIN
      PERFORM public.ensure_attendance_schedule_snapshot(v_protected_attendance_id);
    EXCEPTION WHEN OTHERS THEN
      v_expected_failure := true;
    END;

    IF NOT v_expected_failure THEN
      RAISE EXCEPTION 'Simulation failed: protected payroll attendance accepted a snapshot';
    END IF;
  END IF;

  RAISE NOTICE
    'M2 simulation PASS: employee %, first schedule %, replacement %, legacy snapshot %',
    v_employee_id, v_first_schedule_id, v_second_schedule_id, v_attendance_id;
END;
$simulation$;

SELECT jsonb_build_object(
  'simulation_status', 'pass_before_rollback',
  'feature_value_inside_transaction', (
    SELECT value FROM public.company_settings
    WHERE key = 'hr.employee_work_schedules_enabled'
  ),
  'temporary_schedule_rows', (
    SELECT count(*) FROM public.hr_employee_work_schedules
  ),
  'temporary_snapshot_rows', (
    SELECT count(*) FROM public.hr_attendance_days
    WHERE schedule_snapshot_at IS NOT NULL
  ),
  'next_action', 'ROLLBACK'
) AS m2_simulation_result;

ROLLBACK;
