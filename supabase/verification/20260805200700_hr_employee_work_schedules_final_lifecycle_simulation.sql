-- =============================================================================
-- Employee Work Schedules — authoritative final lifecycle simulation
--
-- DISPOSABLE DATABASE ONLY.
-- Required session guard:
--   SET SESSION edara.allow_schedule_simulation = 'disposable-only';
--
-- Chooses a future month boundary for the first six-hour custom schedule, then
-- tests same-duration correction/replacement and immutable legacy snapshots.
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
  v_second_start DATE;
  v_legacy_date DATE;
  v_first_schedule_id UUID;
  v_second_schedule_id UUID;
  v_attendance_id UUID;
  v_result JSONB;
  v_days JSONB;
  v_corrected_days JSONB;
  v_replacement_days JSONB;
  v_resolved RECORD;
  v_snapshot_at TIMESTAMPTZ;
  v_snapshot_start TIMESTAMPTZ;
  v_expected_failure BOOLEAN;
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

  SELECT month_start
  INTO v_first_start
  FROM (
    SELECT (date_trunc('month', v_today) + make_interval(months => offset_month))::DATE AS month_start
    FROM generate_series(2, 24) offset_month
  ) candidate
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.hr_public_holidays h
    WHERE h.holiday_date IN (
      candidate.month_start - 2,
      candidate.month_start,
      candidate.month_start + 6,
      candidate.month_start + 14,
      candidate.month_start + 20
    )
  )
  ORDER BY month_start
  LIMIT 1;

  IF v_first_start IS NULL THEN
    RAISE EXCEPTION 'Simulation could not find a suitable future month boundary';
  END IF;

  v_second_start := v_first_start + 14;
  v_legacy_date := v_first_start - 2;

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
    'SIMF-' || v_suffix,
    'محاكاة دورة جدول العمل النهائية',
    '+999520' || v_suffix,
    'active',
    v_today,
    6000,
    v_actor,
    'Disposable final schedule lifecycle simulation'
  );

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
    'Final lifecycle simulation — first six-hour version'
  ) INTO v_result;

  v_first_schedule_id := (v_result #>> '{schedule,id}')::UUID;
  IF v_first_schedule_id IS NULL THEN
    RAISE EXCEPTION 'Simulation failed: first schedule ID is missing';
  END IF;

  SELECT * INTO v_resolved
  FROM public.resolve_employee_work_schedule(v_employee_id, v_first_start);

  IF v_resolved.schedule_source <> 'company' THEN
    RAISE EXCEPTION 'Simulation failed: disabled public resolver did not preserve company fallback';
  END IF;

  SELECT * INTO v_resolved
  FROM public.resolve_employee_work_schedule_core(v_employee_id, v_first_start, true);

  IF v_resolved.schedule_source <> 'employee'
     OR v_resolved.work_schedule_id <> v_first_schedule_id
     OR v_resolved.scheduled_minutes <> 360 THEN
    RAISE EXCEPTION 'Simulation failed: initial six-hour schedule is incorrect';
  END IF;

  v_corrected_days := jsonb_set(v_days, '{0,start_time}', '"14:00"'::JSONB);
  v_corrected_days := jsonb_set(v_corrected_days, '{0,end_time}', '"20:00"'::JSONB);

  SELECT public.update_future_employee_work_schedule(
    v_first_schedule_id,
    v_corrected_days,
    'Final lifecycle simulation — corrected before start'
  ) INTO v_result;

  SELECT * INTO v_resolved
  FROM public.resolve_employee_work_schedule_core(v_employee_id, v_first_start, true);

  IF (v_resolved.scheduled_start_at AT TIME ZONE 'Africa/Cairo')::TIME <> TIME '14:00'
     OR (v_resolved.scheduled_end_at AT TIME ZONE 'Africa/Cairo')::TIME <> TIME '20:00'
     OR v_resolved.scheduled_minutes <> 360 THEN
    RAISE EXCEPTION 'Simulation failed: same-duration future correction did not persist';
  END IF;

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
          ) ORDER BY item->>'day_of_week'
        )
        FROM jsonb_array_elements(v_days) item
      ),
      'Expected all-off rejection'
    );
  EXCEPTION WHEN OTHERS THEN
    v_expected_failure := true;
  END;

  IF NOT v_expected_failure THEN
    RAISE EXCEPTION 'Simulation failed: all-off correction was accepted';
  END IF;

  v_replacement_days := jsonb_build_array(
    jsonb_build_object('day_of_week','saturday',  'is_working_day',true,  'start_time','13:00','end_time','19:00'),
    jsonb_build_object('day_of_week','sunday',    'is_working_day',true,  'start_time','09:00','end_time','15:00'),
    jsonb_build_object('day_of_week','monday',    'is_working_day',true,  'start_time','13:00','end_time','19:00'),
    jsonb_build_object('day_of_week','tuesday',   'is_working_day',true,  'start_time','13:00','end_time','19:00'),
    jsonb_build_object('day_of_week','wednesday', 'is_working_day',true,  'start_time','09:00','end_time','15:00'),
    jsonb_build_object('day_of_week','thursday',  'is_working_day',true,  'start_time','09:00','end_time','15:00'),
    jsonb_build_object('day_of_week','friday',    'is_working_day',false, 'start_time',NULL,   'end_time',NULL)
  );

  SELECT public.save_employee_work_schedule(
    v_employee_id,
    v_second_start,
    v_replacement_days,
    'Final lifecycle simulation — same-duration replacement'
  ) INTO v_result;

  v_second_schedule_id := (v_result #>> '{schedule,id}')::UUID;

  IF v_second_schedule_id IS NULL THEN
    RAISE EXCEPTION 'Simulation failed: replacement schedule ID is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.hr_employee_work_schedules
    WHERE id = v_first_schedule_id
      AND status = 'retired'
      AND effective_to = v_second_start - 1
  ) THEN
    RAISE EXCEPTION 'Simulation failed: previous schedule was not closed correctly';
  END IF;

  SELECT * INTO v_resolved
  FROM public.resolve_employee_work_schedule_core(v_employee_id, v_second_start, true);

  IF v_resolved.work_schedule_id <> v_second_schedule_id
     OR v_resolved.scheduled_minutes <> 360 THEN
    RAISE EXCEPTION 'Simulation failed: replacement schedule is incorrect';
  END IF;

  INSERT INTO public.hr_attendance_days (
    employee_id,
    shift_date,
    work_date,
    status,
    notes
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
  SET value = '12:00',
      updated_at = now()
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

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Simulation failed: feature/readiness changed unexpectedly';
  END IF;
END;
$simulation$;

SELECT jsonb_build_object(
  'simulation_status', 'pass_before_rollback',
  'initial_custom_schedule_started_on_month_boundary', true,
  'same_duration_future_edit', true,
  'same_duration_version_replacement', true,
  'all_off_rejected', true,
  'legacy_snapshot_immutable', true,
  'feature_enabled_inside_transaction', public.hr_employee_work_schedules_enabled(),
  'activation_ready_inside_transaction', public.hr_employee_work_schedules_activation_ready(),
  'next_action', 'ROLLBACK'
) AS final_lifecycle_simulation;

ROLLBACK;
