-- =============================================================================
-- Employee Work Schedules — permission-union and snapshot simulation
--
-- DISPOSABLE DATABASE ONLY.
-- Required session guard:
--   SET SESSION edara.allow_schedule_simulation = 'disposable-only';
--
-- Every inserted row is rolled back.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

DO $simulation$
DECLARE
  v_actor UUID;
  v_employee_id UUID := extensions.gen_random_uuid();
  v_attendance_id UUID := extensions.gen_random_uuid();
  v_suffix TEXT := substr(replace(extensions.gen_random_uuid()::TEXT, '-', ''), 1, 10);
  v_test_date DATE := DATE '2026-09-15';
  v_uncovered INTEGER;
  v_penalty_minutes INTEGER;
  v_penalty_days NUMERIC;
  v_penalty_count INTEGER;
  v_guard_blocked BOOLEAN := false;
BEGIN
  IF current_setting('edara.allow_schedule_simulation', true) IS DISTINCT FROM 'disposable-only' THEN
    RAISE EXCEPTION 'Simulation safety stop: disposable-only session flag is required';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Simulation requires feature/readiness to remain false';
  END IF;

  SELECT ur.user_id
  INTO v_actor
  FROM public.user_roles ur
  JOIN public.role_permissions rp ON rp.role_id = ur.role_id
  GROUP BY ur.user_id
  HAVING bool_or(rp.permission = '*')
     OR bool_or(rp.permission = 'hr.employees.edit')
  ORDER BY ur.user_id
  LIMIT 1;

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Simulation could not find an HR actor';
  END IF;

  INSERT INTO public.hr_employees (
    id,
    employee_number,
    full_name,
    personal_phone,
    status,
    hire_date,
    is_field_employee,
    base_salary,
    created_by,
    notes
  ) VALUES (
    v_employee_id,
    'SIM-PERM-' || v_suffix,
    'محاكاة تداخل التصاريح',
    '+999800' || v_suffix,
    'active',
    DATE '2026-09-01',
    false,
    6000,
    v_actor,
    'Disposable permission/snapshot simulation'
  );

  INSERT INTO public.hr_permission_requests (
    employee_id,
    permission_date,
    leave_time,
    expected_return,
    duration_minutes,
    reason,
    status,
    approved_by,
    action_at
  ) VALUES
    (
      v_employee_id,
      v_test_date,
      TIME '15:00',
      TIME '16:30',
      90,
      'Disposable overlapping permission A',
      'approved',
      v_actor,
      now()
    ),
    (
      v_employee_id,
      v_test_date,
      TIME '16:00',
      TIME '17:00',
      60,
      'Disposable overlapping permission B',
      'approved',
      v_actor,
      now()
    );

  v_uncovered := public.get_uncovered_attendance_permission_minutes(
    v_employee_id,
    v_test_date,
    (v_test_date + TIME '15:00') AT TIME ZONE 'Africa/Cairo',
    (v_test_date + TIME '18:00') AT TIME ZONE 'Africa/Cairo'
  );

  -- Union coverage is 15:00-17:00 = 120 minutes; only 17:00-18:00 is uncovered.
  IF v_uncovered <> 60 THEN
    RAISE EXCEPTION 'Simulation failed: expected 60 uncovered minutes, got %', v_uncovered;
  END IF;

  INSERT INTO public.hr_attendance_days (
    id,
    employee_id,
    shift_date,
    work_date,
    status,
    day_value,
    punch_in_time,
    punch_out_time,
    effective_hours,
    checkout_status,
    early_leave_minutes,
    overtime_minutes,
    review_status,
    is_manually_locked,
    schedule_day_kind,
    scheduled_start_at,
    scheduled_end_at,
    scheduled_minutes,
    schedule_source,
    work_schedule_id,
    schedule_snapshot_at
  ) VALUES (
    v_attendance_id,
    v_employee_id,
    v_test_date,
    v_test_date,
    'present',
    1.00,
    (v_test_date + TIME '12:00') AT TIME ZONE 'Africa/Cairo',
    (v_test_date + TIME '15:00') AT TIME ZONE 'Africa/Cairo',
    3.00,
    'early_unauthorized',
    180,
    0,
    'reviewed',
    true,
    'work_day',
    (v_test_date + TIME '12:00') AT TIME ZONE 'Africa/Cairo',
    (v_test_date + TIME '18:00') AT TIME ZONE 'Africa/Cairo',
    360,
    'company',
    NULL,
    now()
  );

  v_penalty_count := public.process_attendance_penalties_scheduled(v_attendance_id);

  SELECT deduction_minutes, deduction_days
  INTO v_penalty_minutes, v_penalty_days
  FROM public.hr_penalty_instances
  WHERE attendance_day_id = v_attendance_id
    AND penalty_type = 'early_leave_unauthorized'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_penalty_count <> 1
     OR v_penalty_minutes <> 60
     OR abs(v_penalty_days - (60 / 360.0)) > 0.0001 THEN
    RAISE EXCEPTION
      'Simulation failed: penalty did not use one permission union; count=% minutes=% days=%',
      v_penalty_count,
      v_penalty_minutes,
      v_penalty_days;
  END IF;

  BEGIN
    UPDATE public.hr_attendance_days
    SET scheduled_end_at = (v_test_date + TIME '19:00') AT TIME ZONE 'Africa/Cairo',
        scheduled_minutes = 420
    WHERE id = v_attendance_id;
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM ILIKE '%snapshot is immutable%' THEN
        v_guard_blocked := true;
      ELSE
        RAISE;
      END IF;
  END;

  IF NOT v_guard_blocked THEN
    RAISE EXCEPTION 'Simulation failed: established attendance snapshot was mutable';
  END IF;
END;
$simulation$;

SELECT jsonb_build_object(
  'simulation_status', 'pass_before_rollback',
  'overlapping_permission_union_minutes', 120,
  'uncovered_and_penalized_minutes', 60,
  'snapshot_update_blocked', true,
  'next_action', 'ROLLBACK'
) AS result;

ROLLBACK;
