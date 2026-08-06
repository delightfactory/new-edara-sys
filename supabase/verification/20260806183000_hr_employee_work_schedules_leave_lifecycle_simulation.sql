-- =============================================================================
-- Employee Work Schedules — schedule-aware leave lifecycle simulation
--
-- DISPOSABLE DATABASE ONLY.
-- Required session guard:
--   SET SESSION edara.allow_schedule_simulation = 'disposable-only';
--
-- The production feature setting remains false. Inside this transaction only,
-- the internal feature helper is temporarily replaced so the prepared enabled
-- branch of the leave triggers can be exercised. ROLLBACK restores the helper
-- and removes every employee, schedule, balance, request, and attendance row.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '180s';

DO $guard$
BEGIN
  IF current_setting('edara.allow_schedule_simulation', true) IS DISTINCT FROM 'disposable-only' THEN
    RAISE EXCEPTION 'Simulation safety stop: disposable-only session flag is required';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Simulation requires feature/readiness to start false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'Simulation requires empty schedule tables';
  END IF;
END;
$guard$;

-- Transaction-local runtime override. The company setting is never changed.
CREATE OR REPLACE FUNCTION public.hr_employee_work_schedules_enabled()
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
  SELECT true;
$function$;

REVOKE ALL ON FUNCTION public.hr_employee_work_schedules_enabled()
  FROM PUBLIC, anon, authenticated;

DO $simulation$
DECLARE
  v_actor UUID;
  v_employee_id UUID := extensions.gen_random_uuid();
  v_schedule_id UUID;
  v_annual_type_id UUID;
  v_period_start DATE;
  v_period_end DATE;
  v_leave_start DATE;
  v_leave_end DATE;
  v_full_work_date DATE;
  v_request_id UUID;
  v_work_request_id UUID;
  v_days JSONB;
  v_result JSONB;
  v_days_count NUMERIC;
  v_pending NUMERIC;
  v_used NUMERIC;
  v_remaining NUMERIC;
  v_attendance_count INTEGER;
  v_snapshot_count INTEGER;
  v_work_attendance_id UUID;
  v_resolved RECORD;
  v_suffix TEXT := substr(replace(extensions.gen_random_uuid()::TEXT, '-', ''), 1, 10);
BEGIN
  SELECT candidate.user_id
  INTO v_actor
  FROM (
    SELECT ur.user_id
    FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id = ur.role_id
    GROUP BY ur.user_id
    HAVING bool_or(rp.permission = '*')
       OR (
         bool_or(rp.permission = 'hr.employees.edit')
         AND bool_or(rp.permission = 'hr.leaves.approve')
       )
  ) candidate
  JOIN public.profiles p ON p.id = candidate.user_id
  ORDER BY candidate.user_id
  LIMIT 1;

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Simulation could not find an HR actor';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_actor::TEXT, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  SELECT make_date(y, m, 1)
  INTO v_period_start
  FROM generate_series(2035, 2045) y
  CROSS JOIN generate_series(1, 12) m
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.hr_payroll_periods pp
    WHERE pp.year = y AND pp.month = m
  )
  ORDER BY y, m
  LIMIT 1;

  IF v_period_start IS NULL THEN
    RAISE EXCEPTION 'Simulation could not find an unused future month';
  END IF;

  v_period_end := (v_period_start + INTERVAL '1 month - 1 day')::DATE;

  SELECT id INTO v_annual_type_id
  FROM public.hr_leave_types
  WHERE code = 'ANNUAL' AND is_active = true
  LIMIT 1;

  IF v_annual_type_id IS NULL THEN
    RAISE EXCEPTION 'Simulation requires the active ANNUAL leave type';
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
    'SIM-LEAVE-' || v_suffix,
    'محاكاة تكامل الإجازات',
    '+999820' || v_suffix,
    'active',
    v_period_start,
    false,
    6000,
    v_actor,
    'Disposable schedule-aware leave simulation'
  );

  INSERT INTO public.hr_leave_balances (
    employee_id,
    leave_type_id,
    year,
    total_days,
    used_days,
    pending_days,
    carried_forward,
    remaining_days
  ) VALUES (
    v_employee_id,
    v_annual_type_id,
    EXTRACT(YEAR FROM v_period_start)::INTEGER,
    10,
    0,
    0,
    0,
    10
  );

  v_days := jsonb_build_array(
    jsonb_build_object('day_of_week','saturday',  'is_working_day',false, 'start_time',NULL,    'end_time',NULL),
    jsonb_build_object('day_of_week','sunday',    'is_working_day',true,  'start_time','10:00','end_time','16:00'),
    jsonb_build_object('day_of_week','monday',    'is_working_day',true,  'start_time','10:00','end_time','16:00'),
    jsonb_build_object('day_of_week','tuesday',   'is_working_day',true,  'start_time','10:00','end_time','16:00'),
    jsonb_build_object('day_of_week','wednesday', 'is_working_day',true,  'start_time','10:00','end_time','16:00'),
    jsonb_build_object('day_of_week','thursday',  'is_working_day',true,  'start_time','10:00','end_time','16:00'),
    jsonb_build_object('day_of_week','friday',    'is_working_day',false, 'start_time',NULL,    'end_time',NULL)
  );

  SELECT public.save_employee_work_schedule(
    v_employee_id,
    v_period_start,
    v_days,
    'Disposable leave integration schedule'
  ) INTO v_result;

  v_schedule_id := (v_result #>> '{schedule,id}')::UUID;
  IF v_schedule_id IS NULL THEN
    RAISE EXCEPTION 'Simulation failed: employee schedule was not created';
  END IF;

  SELECT min(d::DATE)
  INTO v_leave_start
  FROM generate_series(v_period_start, v_period_end - 4, INTERVAL '1 day') d
  WHERE public.hr_day_of_week_for_date(d::DATE) = 'thursday';

  v_leave_end := v_leave_start + 4;

  IF v_leave_start IS NULL OR v_leave_end > v_period_end THEN
    RAISE EXCEPTION 'Simulation failed: suitable Thursday-to-Monday range was not found';
  END IF;

  INSERT INTO public.hr_leave_requests (
    employee_id,
    leave_type_id,
    start_date,
    end_date,
    days_count,
    reason
  ) VALUES (
    v_employee_id,
    v_annual_type_id,
    v_leave_start,
    v_leave_end,
    99,
    'Disposable leave spanning two weekly-off days'
  )
  RETURNING id, days_count INTO v_request_id, v_days_count;

  -- Thursday, Sunday, and Monday are work days; Friday/Saturday are off.
  IF v_days_count <> 3 THEN
    RAISE EXCEPTION 'Simulation failed: server-side leave count expected 3, got %', v_days_count;
  END IF;

  SELECT pending_days, used_days, remaining_days
  INTO v_pending, v_used, v_remaining
  FROM public.hr_leave_balances
  WHERE employee_id = v_employee_id
    AND leave_type_id = v_annual_type_id
    AND year = EXTRACT(YEAR FROM v_period_start)::INTEGER;

  IF v_pending <> 3 OR v_used <> 0 OR v_remaining <> 7 THEN
    RAISE EXCEPTION
      'Simulation failed: submission balance pending=% used=% remaining=%',
      v_pending, v_used, v_remaining;
  END IF;

  UPDATE public.hr_leave_requests
  SET status = 'approved_supervisor'
  WHERE id = v_request_id;

  IF NOT EXISTS (
    SELECT 1 FROM public.hr_leave_requests
    WHERE id = v_request_id AND status = 'pending_hr' AND days_count = 3
  ) OR EXISTS (
    SELECT 1 FROM public.hr_attendance_days
    WHERE source_leave_request_id = v_request_id
  ) THEN
    RAISE EXCEPTION 'Simulation failed: supervisor approval state/sync is incorrect';
  END IF;

  UPDATE public.hr_leave_requests
  SET status = 'approved'
  WHERE id = v_request_id;

  SELECT pending_days, used_days, remaining_days
  INTO v_pending, v_used, v_remaining
  FROM public.hr_leave_balances
  WHERE employee_id = v_employee_id
    AND leave_type_id = v_annual_type_id
    AND year = EXTRACT(YEAR FROM v_period_start)::INTEGER;

  SELECT count(*)::INTEGER,
         count(*) FILTER (
           WHERE schedule_snapshot_at IS NOT NULL
             AND schedule_day_kind = 'work_day'
             AND scheduled_minutes = 360
             AND work_schedule_id = v_schedule_id
         )::INTEGER
  INTO v_attendance_count, v_snapshot_count
  FROM public.hr_attendance_days
  WHERE source_leave_request_id = v_request_id;

  IF v_pending <> 0 OR v_used <> 3 OR v_remaining <> 7
     OR v_attendance_count <> 3 OR v_snapshot_count <> 3
     OR EXISTS (
       SELECT 1
       FROM public.hr_attendance_days d
       WHERE d.source_leave_request_id = v_request_id
         AND public.hr_day_of_week_for_date(d.shift_date) IN ('friday', 'saturday')
     ) THEN
    RAISE EXCEPTION
      'Simulation failed: final approval balance/snapshot mismatch pending=% used=% remaining=% rows=% snapshots=%',
      v_pending, v_used, v_remaining, v_attendance_count, v_snapshot_count;
  END IF;

  UPDATE public.hr_leave_requests
  SET status = 'cancelled'
  WHERE id = v_request_id;

  SELECT pending_days, used_days, remaining_days
  INTO v_pending, v_used, v_remaining
  FROM public.hr_leave_balances
  WHERE employee_id = v_employee_id
    AND leave_type_id = v_annual_type_id
    AND year = EXTRACT(YEAR FROM v_period_start)::INTEGER;

  IF v_pending <> 0 OR v_used <> 0 OR v_remaining <> 10
     OR EXISTS (
       SELECT 1 FROM public.hr_attendance_days
       WHERE source_leave_request_id = v_request_id
     ) THEN
    RAISE EXCEPTION
      'Simulation failed: cancellation cleanup/balance mismatch pending=% used=% remaining=%',
      v_pending, v_used, v_remaining;
  END IF;

  SELECT min(d::DATE)
  INTO v_full_work_date
  FROM generate_series(v_leave_end + 1, v_period_end, INTERVAL '1 day') d
  CROSS JOIN LATERAL public.resolve_employee_work_schedule_core(
    v_employee_id, d::DATE, true
  ) r
  WHERE r.day_kind = 'work_day';

  IF v_full_work_date IS NULL THEN
    RAISE EXCEPTION 'Simulation failed: no later work day for settlement test';
  END IF;

  SELECT * INTO v_resolved
  FROM public.resolve_employee_work_schedule_core(v_employee_id, v_full_work_date, true);

  INSERT INTO public.hr_attendance_days (
    employee_id,
    shift_date,
    work_date,
    punch_in_time,
    punch_out_time,
    status,
    checkout_status,
    late_minutes,
    early_leave_minutes,
    overtime_minutes,
    effective_hours,
    day_value,
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
    v_employee_id,
    v_full_work_date,
    v_full_work_date,
    v_resolved.scheduled_start_at,
    v_resolved.scheduled_end_at,
    'present',
    'on_time',
    0,
    0,
    0,
    6,
    1,
    'reviewed',
    false,
    v_resolved.day_kind,
    v_resolved.scheduled_start_at,
    v_resolved.scheduled_end_at,
    v_resolved.scheduled_minutes,
    v_resolved.schedule_source,
    v_resolved.work_schedule_id,
    now()
  )
  RETURNING id INTO v_work_attendance_id;

  INSERT INTO public.hr_leave_requests (
    employee_id,
    leave_type_id,
    start_date,
    end_date,
    days_count,
    reason
  ) VALUES (
    v_employee_id,
    v_annual_type_id,
    v_full_work_date,
    v_full_work_date,
    50,
    'Disposable full attendance settlement test'
  )
  RETURNING id INTO v_work_request_id;

  UPDATE public.hr_leave_requests
  SET status = 'approved_supervisor'
  WHERE id = v_work_request_id;

  UPDATE public.hr_leave_requests
  SET status = 'approved'
  WHERE id = v_work_request_id;

  SELECT pending_days, used_days, remaining_days
  INTO v_pending, v_used, v_remaining
  FROM public.hr_leave_balances
  WHERE employee_id = v_employee_id
    AND leave_type_id = v_annual_type_id
    AND year = EXTRACT(YEAR FROM v_period_start)::INTEGER;

  IF v_pending <> 0 OR v_used <> 0 OR v_remaining <> 10
     OR NOT EXISTS (
       SELECT 1
       FROM public.hr_attendance_days
       WHERE id = v_work_attendance_id
         AND source_leave_request_id = v_work_request_id
         AND leave_balance_restored = true
         AND status = 'present'
         AND day_value = 1
     ) THEN
    RAISE EXCEPTION
      'Simulation failed: fully worked leave day did not restore balance pending=% used=% remaining=%',
      v_pending, v_used, v_remaining;
  END IF;
END;
$simulation$;

SELECT jsonb_build_object(
  'simulation_status', 'pass_before_rollback',
  'calendar_span_days', 5,
  'charged_workdays', 3,
  'weekly_off_days_excluded', 2,
  'approval_sync_after_persist', true,
  'snapshots_complete', true,
  'cancellation_restores_balance', true,
  'full_attendance_restores_leave_day', true,
  'production_feature_setting_changed', false,
  'next_action', 'ROLLBACK'
) AS result;

ROLLBACK;
