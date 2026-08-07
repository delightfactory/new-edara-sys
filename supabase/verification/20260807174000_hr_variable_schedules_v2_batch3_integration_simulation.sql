-- HR Variable Schedules V2 — Batch 3 integration simulation
--
-- Disposable behavioral proof only. Everything runs inside one transaction and
-- is rolled back, including temporary fixture rows, trigger-disable state, and the
-- temporary opening of the V2 runtime gate.
--
-- Covers:
--   1) custom working-day auto-checkout uses the snapshotted custom end;
--   2) custom non-working day is not auto-closed with a company fallback end;
--   3) unauthorized early-leave deduction uses custom scheduled minutes;
--   4) anomalous early-leave penalty on a custom off-day fails closed;
--   5) full custom-day leave settlement restores one leave day at custom duration;
--   6) partial custom-day leave settlement uses the custom-duration denominator;
--   7) rollback restores the hard-disabled runtime gate and trigger state.

BEGIN;

-- Keep this simulation focused on the V2 functions under test. Notification and
-- legacy leave-submission triggers are unrelated to these assertions and could
-- create fixture-only side effects. The DISABLE statements themselves are rolled
-- back at the end of this transaction.
ALTER TABLE public.hr_attendance_days DISABLE TRIGGER USER;
ALTER TABLE public.hr_leave_requests DISABLE TRIGGER USER;

-- Open V2 only inside this disposable transaction. ROLLBACK below must restore
-- the hard-false development gate from Batch 2A.
CREATE OR REPLACE FUNCTION public.hr_variable_schedules_v2_runtime_enabled()
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT true;
$function$;

DO $simulation$
DECLARE
  v_today date := (now() AT TIME ZONE 'Africa/Cairo')::date;
  v_employee_id uuid;
  v_schedule_id uuid;
  v_leave_type_id uuid;
  v_leave_balance_id uuid;
  v_work_auto_day_id uuid;
  v_off_auto_day_id uuid;
  v_penalty_day_id uuid;
  v_off_penalty_day_id uuid;
  v_leave_full_req_id uuid;
  v_leave_partial_req_id uuid;
  v_leave_full_day_id uuid;
  v_leave_partial_day_id uuid;
  v_expected_checkout timestamptz;
  v_actual_checkout timestamptz;
  v_is_auto boolean;
  v_early integer;
  v_overtime integer;
  v_penalty_count integer;
  v_penalty_rows integer;
  v_deduction_minutes integer;
  v_deduction_days numeric;
  v_used_days numeric;
  v_restored boolean;
  v_day_value numeric;
  v_status public.hr_attendance_status;
  v_expected_exception boolean := false;
BEGIN
  INSERT INTO public.hr_employees (
    employee_number,
    full_name,
    personal_phone,
    hire_date,
    status
  ) VALUES (
    'V2-SIM-B3-001',
    'V2 Batch 3 Integration Fixture',
    '01000000001',
    v_today - 60,
    'active'
  )
  RETURNING id INTO v_employee_id;

  -- One future schedule header exists only to satisfy the immutable snapshot FK.
  -- The behavioral tests intentionally use attendance snapshots, which are the
  -- authoritative historical interpretation once an attendance row was processed.
  INSERT INTO public.hr_employee_work_schedules (
    employee_id,
    effective_from,
    notes
  ) VALUES (
    v_employee_id,
    v_today + 30,
    'Batch 3 isolated simulation snapshot parent'
  )
  RETURNING id INTO v_schedule_id;

  -- -------------------------------------------------------------------------
  -- 1) Working-day auto-checkout: custom 10:00–16:00, 360 minutes.
  -- -------------------------------------------------------------------------
  INSERT INTO public.hr_attendance_days (
    employee_id,
    shift_date,
    work_date,
    punch_in_time,
    status,
    custom_schedule_id,
    custom_scheduled_start,
    custom_scheduled_end,
    custom_scheduled_minutes
  ) VALUES (
    v_employee_id,
    v_today - 2,
    v_today - 2,
    ((v_today - 2)::text || ' 10:00:00')::timestamp AT TIME ZONE 'Africa/Cairo',
    'present',
    v_schedule_id,
    '10:00'::time,
    '16:00'::time,
    360
  )
  RETURNING id INTO v_work_auto_day_id;

  PERFORM public.run_auto_checkout(v_today - 2);

  v_expected_checkout :=
    (((v_today - 2)::text || ' 16:00:00')::timestamp AT TIME ZONE 'Africa/Cairo');

  SELECT punch_out_time, is_auto_checkout, early_leave_minutes, overtime_minutes
  INTO v_actual_checkout, v_is_auto, v_early, v_overtime
  FROM public.hr_attendance_days
  WHERE id = v_work_auto_day_id;

  IF v_actual_checkout IS DISTINCT FROM v_expected_checkout
     OR v_is_auto IS DISTINCT FROM true
     OR v_early <> 0
     OR v_overtime <> 0 THEN
    RAISE EXCEPTION
      'Batch 3 integration failed: working-day auto-checkout did not use custom 16:00 end';
  END IF;

  -- -------------------------------------------------------------------------
  -- 2) Custom non-working day: snapshot minutes=0, no official start/end.
  -- It must remain open instead of borrowing company work_end.
  -- -------------------------------------------------------------------------
  INSERT INTO public.hr_attendance_days (
    employee_id,
    shift_date,
    work_date,
    punch_in_time,
    status,
    custom_schedule_id,
    custom_scheduled_start,
    custom_scheduled_end,
    custom_scheduled_minutes
  ) VALUES (
    v_employee_id,
    v_today - 3,
    v_today - 3,
    ((v_today - 3)::text || ' 10:00:00')::timestamp AT TIME ZONE 'Africa/Cairo',
    'present',
    v_schedule_id,
    NULL,
    NULL,
    0
  )
  RETURNING id INTO v_off_auto_day_id;

  PERFORM public.run_auto_checkout(v_today - 3);

  SELECT punch_out_time, is_auto_checkout
  INTO v_actual_checkout, v_is_auto
  FROM public.hr_attendance_days
  WHERE id = v_off_auto_day_id;

  IF v_actual_checkout IS NOT NULL OR v_is_auto IS DISTINCT FROM false THEN
    RAISE EXCEPTION
      'Batch 3 integration failed: custom off-day was incorrectly auto-closed';
  END IF;

  -- -------------------------------------------------------------------------
  -- 3) Early-leave penalty: 60 uncovered minutes on a 360-minute custom day.
  -- Expected deduction_days = 60 / 360 = 0.1667 after rounding to 4 decimals.
  -- -------------------------------------------------------------------------
  INSERT INTO public.hr_attendance_days (
    employee_id,
    shift_date,
    work_date,
    punch_in_time,
    punch_out_time,
    status,
    checkout_status,
    early_leave_minutes,
    effective_hours,
    custom_schedule_id,
    custom_scheduled_start,
    custom_scheduled_end,
    custom_scheduled_minutes
  ) VALUES (
    v_employee_id,
    v_today - 4,
    v_today - 4,
    ((v_today - 4)::text || ' 10:00:00')::timestamp AT TIME ZONE 'Africa/Cairo',
    ((v_today - 4)::text || ' 15:00:00')::timestamp AT TIME ZONE 'Africa/Cairo',
    'present',
    'early_unauthorized',
    60,
    5.00,
    v_schedule_id,
    '10:00'::time,
    '16:00'::time,
    360
  )
  RETURNING id INTO v_penalty_day_id;

  SELECT public.process_attendance_penalties(v_penalty_day_id)
  INTO v_penalty_count;

  SELECT count(*), max(deduction_minutes), max(deduction_days)
  INTO v_penalty_rows, v_deduction_minutes, v_deduction_days
  FROM public.hr_penalty_instances
  WHERE attendance_day_id = v_penalty_day_id
    AND penalty_type = 'early_leave_unauthorized'
    AND payroll_run_id IS NULL
    AND is_overridden = false
    AND COALESCE(is_manual, false) = false;

  IF v_penalty_count < 1
     OR v_penalty_rows <> 1
     OR v_deduction_minutes <> 60
     OR v_deduction_days <> 0.1667::numeric THEN
    RAISE EXCEPTION
      'Batch 3 integration failed: custom early-leave penalty expected 60 minutes / 0.1667 day, got rows %, minutes %, days %',
      v_penalty_rows, v_deduction_minutes, v_deduction_days;
  END IF;

  -- -------------------------------------------------------------------------
  -- 4) An anomalous early_unauthorized state on a custom off-day must fail closed
  -- before the Legacy engine can manufacture a company-duration penalty.
  -- -------------------------------------------------------------------------
  INSERT INTO public.hr_attendance_days (
    employee_id,
    shift_date,
    work_date,
    punch_in_time,
    punch_out_time,
    status,
    checkout_status,
    early_leave_minutes,
    effective_hours,
    custom_schedule_id,
    custom_scheduled_start,
    custom_scheduled_end,
    custom_scheduled_minutes
  ) VALUES (
    v_employee_id,
    v_today - 1,
    v_today - 1,
    ((v_today - 1)::text || ' 10:00:00')::timestamp AT TIME ZONE 'Africa/Cairo',
    ((v_today - 1)::text || ' 15:30:00')::timestamp AT TIME ZONE 'Africa/Cairo',
    'present',
    'early_unauthorized',
    30,
    5.50,
    v_schedule_id,
    NULL,
    NULL,
    0
  )
  RETURNING id INTO v_off_penalty_day_id;

  BEGIN
    PERFORM public.process_attendance_penalties(v_off_penalty_day_id);
  EXCEPTION WHEN OTHERS THEN
    IF position('custom non-working day' in SQLERRM) > 0 THEN
      v_expected_exception := true;
    ELSE
      RAISE;
    END IF;
  END;

  IF NOT v_expected_exception THEN
    RAISE EXCEPTION
      'Batch 3 integration failed: custom off-day early-leave anomaly did not fail closed';
  END IF;

  SELECT count(*)
  INTO v_penalty_rows
  FROM public.hr_penalty_instances
  WHERE attendance_day_id = v_off_penalty_day_id;

  IF v_penalty_rows <> 0 THEN
    RAISE EXCEPTION
      'Batch 3 integration failed: custom off-day anomaly created a penalty row';
  END IF;

  -- -------------------------------------------------------------------------
  -- Prepare two approved leave requests without invoking the unrelated legacy
  -- submission/approval triggers (disabled transactionally above).
  -- -------------------------------------------------------------------------
  SELECT lb.id, lb.leave_type_id
  INTO v_leave_balance_id, v_leave_type_id
  FROM public.hr_leave_balances lb
  JOIN public.hr_leave_types lt ON lt.id = lb.leave_type_id
  WHERE lb.employee_id = v_employee_id
    AND lt.is_active = true
    AND lt.has_balance = true
    AND lt.deducts_from_balance = true
  ORDER BY lt.code
  LIMIT 1;

  IF v_leave_balance_id IS NULL THEN
    SELECT lt.id
    INTO v_leave_type_id
    FROM public.hr_leave_types lt
    WHERE lt.is_active = true
      AND lt.has_balance = true
      AND lt.deducts_from_balance = true
    ORDER BY lt.code
    LIMIT 1;

    IF v_leave_type_id IS NULL THEN
      RAISE EXCEPTION 'Batch 3 integration failed: no seeded balance-based leave type is available';
    END IF;

    INSERT INTO public.hr_leave_balances (
      employee_id,
      leave_type_id,
      year,
      total_days,
      used_days,
      pending_days,
      carried_forward
    ) VALUES (
      v_employee_id,
      v_leave_type_id,
      EXTRACT(YEAR FROM v_today)::integer,
      10,
      2,
      0,
      0
    )
    RETURNING id INTO v_leave_balance_id;
  ELSE
    UPDATE public.hr_leave_balances
    SET total_days = GREATEST(total_days, 10),
        used_days = 2,
        pending_days = 0,
        updated_at = now()
    WHERE id = v_leave_balance_id;
  END IF;

  INSERT INTO public.hr_leave_requests (
    employee_id,
    leave_type_id,
    start_date,
    end_date,
    days_count,
    status,
    reason
  ) VALUES (
    v_employee_id,
    v_leave_type_id,
    v_today - 5,
    v_today - 5,
    1,
    'approved',
    'Batch 3 full-day settlement fixture'
  )
  RETURNING id INTO v_leave_full_req_id;

  INSERT INTO public.hr_leave_requests (
    employee_id,
    leave_type_id,
    start_date,
    end_date,
    days_count,
    status,
    reason
  ) VALUES (
    v_employee_id,
    v_leave_type_id,
    v_today - 6,
    v_today - 6,
    1,
    'approved',
    'Batch 3 partial-day settlement fixture'
  )
  RETURNING id INTO v_leave_partial_req_id;

  -- -------------------------------------------------------------------------
  -- 5) Full custom day: 6 effective hours on a 360-minute schedule restores one
  -- leave day even if company work_hours_per_day differs.
  -- -------------------------------------------------------------------------
  INSERT INTO public.hr_attendance_days (
    employee_id,
    shift_date,
    work_date,
    punch_in_time,
    punch_out_time,
    status,
    checkout_status,
    effective_hours,
    source_leave_request_id,
    custom_schedule_id,
    custom_scheduled_start,
    custom_scheduled_end,
    custom_scheduled_minutes
  ) VALUES (
    v_employee_id,
    v_today - 5,
    v_today - 5,
    ((v_today - 5)::text || ' 10:00:00')::timestamp AT TIME ZONE 'Africa/Cairo',
    ((v_today - 5)::text || ' 16:00:00')::timestamp AT TIME ZONE 'Africa/Cairo',
    'on_leave',
    'on_time',
    6.00,
    v_leave_full_req_id,
    v_schedule_id,
    '10:00'::time,
    '16:00'::time,
    360
  )
  RETURNING id INTO v_leave_full_day_id;

  PERFORM public.settle_attendance_day_against_leave(v_leave_full_day_id, false);

  SELECT used_days
  INTO v_used_days
  FROM public.hr_leave_balances
  WHERE id = v_leave_balance_id;

  SELECT leave_balance_restored, status
  INTO v_restored, v_status
  FROM public.hr_attendance_days
  WHERE id = v_leave_full_day_id;

  IF v_used_days <> 1
     OR v_restored IS DISTINCT FROM true
     OR v_status <> 'present' THEN
    RAISE EXCEPTION
      'Batch 3 integration failed: full custom-day leave settlement did not restore exactly one day';
  END IF;

  -- -------------------------------------------------------------------------
  -- 6) Partial custom day: 3 hours on a 6-hour schedule => day_value 0.50 and
  -- leave balance remains unchanged.
  -- -------------------------------------------------------------------------
  INSERT INTO public.hr_attendance_days (
    employee_id,
    shift_date,
    work_date,
    punch_in_time,
    punch_out_time,
    status,
    checkout_status,
    effective_hours,
    source_leave_request_id,
    custom_schedule_id,
    custom_scheduled_start,
    custom_scheduled_end,
    custom_scheduled_minutes
  ) VALUES (
    v_employee_id,
    v_today - 6,
    v_today - 6,
    ((v_today - 6)::text || ' 10:00:00')::timestamp AT TIME ZONE 'Africa/Cairo',
    ((v_today - 6)::text || ' 13:00:00')::timestamp AT TIME ZONE 'Africa/Cairo',
    'on_leave',
    'early_authorized',
    3.00,
    v_leave_partial_req_id,
    v_schedule_id,
    '10:00'::time,
    '16:00'::time,
    360
  )
  RETURNING id INTO v_leave_partial_day_id;

  PERFORM public.settle_attendance_day_against_leave(v_leave_partial_day_id, false);

  SELECT used_days
  INTO v_used_days
  FROM public.hr_leave_balances
  WHERE id = v_leave_balance_id;

  SELECT leave_balance_restored, day_value, status
  INTO v_restored, v_day_value, v_status
  FROM public.hr_attendance_days
  WHERE id = v_leave_partial_day_id;

  IF v_used_days <> 1
     OR v_restored IS DISTINCT FROM false
     OR v_day_value <> 0.50::numeric
     OR v_status <> 'present' THEN
    RAISE EXCEPTION
      'Batch 3 integration failed: partial custom-day settlement expected balance=1/day_value=0.50';
  END IF;
END;
$simulation$;

ROLLBACK;

-- Prove that the behavioral rehearsal did not leave V2 enabled or triggers
-- disabled after rollback.
DO $post_rollback$
DECLARE
  v_disabled integer;
BEGIN
  IF public.hr_variable_schedules_v2_runtime_enabled() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Batch 3 integration failed: runtime gate remained enabled after rollback';
  END IF;

  SELECT count(*)
  INTO v_disabled
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname IN ('hr_attendance_days', 'hr_leave_requests')
    AND NOT t.tgisinternal
    AND t.tgenabled = 'D';

  IF v_disabled <> 0 THEN
    RAISE EXCEPTION 'Batch 3 integration failed: user trigger state was not restored after rollback';
  END IF;
END;
$post_rollback$;

SELECT 'batch3_integration_simulation_pass' AS result;
