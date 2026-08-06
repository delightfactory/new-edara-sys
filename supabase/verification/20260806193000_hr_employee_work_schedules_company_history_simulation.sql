-- =============================================================================
-- Employee Work Schedules — company history disposable simulation
--
-- DISPOSABLE DATABASE ONLY.
-- Required session guard:
--   SET SESSION edara.allow_schedule_simulation = 'disposable-only';
--
-- Every write is inside this transaction and is rolled back.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '180s';

DO $simulation$
DECLARE
  v_actor UUID;
  v_today DATE := (now() AT TIME ZONE 'Africa/Cairo')::DATE;
  v_month_start DATE;
  v_same_duration_date DATE;
  v_duration_change_date DATE;
  v_employee_schedule_date DATE;
  v_override_off_date DATE;
  v_override_work_date DATE;
  v_snapshot_date DATE;

  v_emp_same UUID := extensions.gen_random_uuid();
  v_emp_conflict UUID := extensions.gen_random_uuid();
  v_hash TEXT := substr(replace(extensions.gen_random_uuid()::TEXT, '-', ''), 1, 10);

  v_result JSONB;
  v_company_six_id UUID;
  v_employee_schedule_id UUID;
  v_days_six JSONB;
  v_days_eight JSONB;
  v_resolved RECORD;
  v_before_value TEXT;
  v_after_value TEXT;
  v_rejected BOOLEAN;
BEGIN
  IF current_setting('edara.allow_schedule_simulation', true) IS DISTINCT FROM 'disposable-only' THEN
    RAISE EXCEPTION 'Simulation safety stop: disposable-only session flag is required';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Company-history simulation requires feature/readiness false';
  END IF;

  IF (SELECT count(*) FROM public.hr_company_work_schedules) <> 1
     OR (SELECT count(*) FROM public.hr_company_work_schedules WHERE is_system_baseline) <> 1
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'Company-history simulation requires the clean installed baseline';
  END IF;

  SELECT candidate.user_id
  INTO v_actor
  FROM (
    SELECT ur.user_id
    FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id = ur.role_id
    WHERE rp.permission IN ('*', 'settings.update', 'hr.employees.edit')
    GROUP BY ur.user_id
    HAVING bool_or(rp.permission = '*')
       OR (
         bool_or(rp.permission = 'settings.update')
         AND bool_or(rp.permission = 'hr.employees.edit')
       )
  ) candidate
  JOIN public.profiles p ON p.id = candidate.user_id
  ORDER BY candidate.user_id
  LIMIT 1;

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Company-history simulation could not find an authorized actor';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_actor::TEXT, true);

  v_month_start := date_trunc('month', v_today + INTERVAL '18 months')::DATE;
  v_same_duration_date := v_month_start + 9;
  v_duration_change_date := (v_month_start + INTERVAL '1 month')::DATE;
  v_employee_schedule_date := v_duration_change_date + 9;

  INSERT INTO public.hr_employees (
    id,
    employee_number,
    full_name,
    personal_phone,
    status,
    hire_date,
    weekly_off_day,
    is_field_employee,
    base_salary,
    created_by,
    notes
  ) VALUES
    (
      v_emp_same,
      'SIM-CH-A-' || v_hash,
      'محاكاة تاريخ جدول الشركة أ',
      '+9981' || v_hash,
      'active',
      v_today,
      'saturday',
      false,
      6000,
      v_actor,
      'Disposable company schedule history simulation'
    ),
    (
      v_emp_conflict,
      'SIM-CH-B-' || v_hash,
      'محاكاة تاريخ جدول الشركة ب',
      '+9982' || v_hash,
      'active',
      v_today,
      NULL,
      false,
      6000,
      v_actor,
      'Disposable company schedule history simulation'
    );

  -- Invalid atomic bundle must roll back completely inside its statement.
  SELECT value INTO v_before_value
  FROM public.company_settings
  WHERE key = 'hr.work_start_time';

  v_rejected := false;
  BEGIN
    PERFORM public.update_hr_settings_atomic(jsonb_build_array(
      jsonb_build_object('key', 'hr.work_start_time', 'value', '10:00')
    ));
  EXCEPTION
    WHEN OTHERS THEN
      v_rejected := SQLERRM ILIKE '%لا يطابق%';
  END;

  IF NOT v_rejected THEN
    RAISE EXCEPTION 'Company-history simulation failed: inconsistent atomic time bundle was accepted';
  END IF;

  SELECT value INTO v_after_value
  FROM public.company_settings
  WHERE key = 'hr.work_start_time';

  IF v_after_value IS DISTINCT FROM v_before_value THEN
    RAISE EXCEPTION 'Company-history simulation failed: rejected atomic update changed a setting';
  END IF;

  -- A valid atomic save normalizes the compact production representation.
  PERFORM public.update_hr_settings_atomic(jsonb_build_array(
    jsonb_build_object('key', 'hr.work_start_time', 'value', '1100'),
    jsonb_build_object('key', 'hr.work_end_time', 'value', '19:00'),
    jsonb_build_object('key', 'hr.work_hours_per_day', 'value', '8'),
    jsonb_build_object('key', 'hr.weekly_off_day', 'value', 'friday')
  ));

  IF (SELECT value FROM public.company_settings WHERE key = 'hr.work_start_time') <> '11:00'
     OR NOT public.hr_company_work_schedule_activation_consistent() THEN
    RAISE EXCEPTION 'Company-history simulation failed: valid atomic normalization is inconsistent';
  END IF;

  -- Daily-duration change outside day 1 must fail.
  v_rejected := false;
  BEGIN
    PERFORM public.save_company_work_schedule_version(
      v_same_duration_date,
      '10:00',
      '16:00',
      'friday',
      'Expected rejection: six hours mid-month'
    );
  EXCEPTION
    WHEN OTHERS THEN
      v_rejected := SQLERRM ILIKE '%أول يوم في الشهر%';
  END;

  IF NOT v_rejected OR (SELECT count(*) FROM public.hr_company_work_schedules) <> 1 THEN
    RAISE EXCEPTION 'Company-history simulation failed: mid-month duration change was not rejected atomically';
  END IF;

  -- Same-duration time shift may start mid-month.
  SELECT public.save_company_work_schedule_version(
    v_same_duration_date,
    '10:00',
    '18:00',
    'friday',
    'Disposable same-duration shift'
  ) INTO v_result;

  IF (v_result #>> '{schedule,scheduled_minutes}')::INTEGER <> 480
     OR (v_result #>> '{schedule,start_time}') <> '10:00'
     OR (SELECT count(*) FROM public.hr_company_work_schedules) <> 2 THEN
    RAISE EXCEPTION 'Company-history simulation failed: same-duration company version is incorrect';
  END IF;

  -- Six-hour company day is allowed from the first of the following month.
  SELECT public.save_company_work_schedule_version(
    v_duration_change_date,
    '10:00',
    '16:00',
    'friday',
    'Disposable six-hour company version'
  ) INTO v_result;
  v_company_six_id := (v_result #>> '{schedule,id}')::UUID;

  IF v_company_six_id IS NULL
     OR (v_result #>> '{schedule,scheduled_minutes}')::INTEGER <> 360
     OR (SELECT count(*) FROM public.hr_company_work_schedules) <> 3 THEN
    RAISE EXCEPTION 'Company-history simulation failed: month-boundary duration version is incorrect';
  END IF;

  -- Future correction before prepared facts is allowed.
  SELECT public.update_future_company_work_schedule_version(
    v_company_six_id,
    '11:00',
    '17:00',
    'friday',
    'Disposable corrected future six-hour version'
  ) INTO v_result;

  IF (v_result #>> '{schedule,start_time}') <> '11:00'
     OR (v_result #>> '{schedule,scheduled_minutes}')::INTEGER <> 360 THEN
    RAISE EXCEPTION 'Company-history simulation failed: future company correction is incorrect';
  END IF;

  SELECT min(d::DATE) INTO v_override_off_date
  FROM generate_series(v_employee_schedule_date, v_employee_schedule_date + 30, INTERVAL '1 day') d
  WHERE public.hr_day_of_week_for_date(d::DATE) = 'saturday'
    AND NOT EXISTS (
      SELECT 1 FROM public.hr_public_holidays h WHERE h.holiday_date = d::DATE
    );

  SELECT min(d::DATE) INTO v_override_work_date
  FROM generate_series(v_employee_schedule_date, v_employee_schedule_date + 30, INTERVAL '1 day') d
  WHERE public.hr_day_of_week_for_date(d::DATE) = 'friday'
    AND NOT EXISTS (
      SELECT 1 FROM public.hr_public_holidays h WHERE h.holiday_date = d::DATE
    );

  IF v_override_off_date IS NULL OR v_override_work_date IS NULL THEN
    RAISE EXCEPTION 'Company-history simulation failed: override test dates were not found';
  END IF;

  SELECT * INTO v_resolved
  FROM public.resolve_employee_work_schedule_core(v_emp_same, v_override_off_date, true);

  IF v_resolved.day_kind <> 'weekly_off' OR v_resolved.scheduled_minutes <> 0 THEN
    RAISE EXCEPTION 'Company-history simulation failed: employee weekly-off override was lost';
  END IF;

  SELECT * INTO v_resolved
  FROM public.resolve_employee_work_schedule_core(v_emp_same, v_override_work_date, true);

  IF v_resolved.day_kind <> 'work_day'
     OR v_resolved.scheduled_minutes <> 360
     OR to_char(v_resolved.scheduled_start_at AT TIME ZONE 'Africa/Cairo', 'HH24:MI') <> '11:00'
     OR public.get_company_scheduled_minutes_for_date(v_override_work_date) <> 360 THEN
    RAISE EXCEPTION 'Company-history simulation failed: employee override/company duration resolution is incorrect';
  END IF;

  v_days_six := jsonb_build_array(
    jsonb_build_object('day_of_week','saturday',  'is_working_day',true,  'start_time','12:00','end_time','18:00'),
    jsonb_build_object('day_of_week','sunday',    'is_working_day',true,  'start_time','12:00','end_time','18:00'),
    jsonb_build_object('day_of_week','monday',    'is_working_day',true,  'start_time','12:00','end_time','18:00'),
    jsonb_build_object('day_of_week','tuesday',   'is_working_day',true,  'start_time','12:00','end_time','18:00'),
    jsonb_build_object('day_of_week','wednesday', 'is_working_day',true,  'start_time','12:00','end_time','18:00'),
    jsonb_build_object('day_of_week','thursday',  'is_working_day',true,  'start_time','12:00','end_time','18:00'),
    jsonb_build_object('day_of_week','friday',    'is_working_day',false, 'start_time',NULL,   'end_time',NULL)
  );

  v_days_eight := jsonb_build_array(
    jsonb_build_object('day_of_week','saturday',  'is_working_day',true,  'start_time','10:00','end_time','18:00'),
    jsonb_build_object('day_of_week','sunday',    'is_working_day',true,  'start_time','10:00','end_time','18:00'),
    jsonb_build_object('day_of_week','monday',    'is_working_day',true,  'start_time','10:00','end_time','18:00'),
    jsonb_build_object('day_of_week','tuesday',   'is_working_day',true,  'start_time','10:00','end_time','18:00'),
    jsonb_build_object('day_of_week','wednesday', 'is_working_day',true,  'start_time','10:00','end_time','18:00'),
    jsonb_build_object('day_of_week','thursday',  'is_working_day',true,  'start_time','10:00','end_time','18:00'),
    jsonb_build_object('day_of_week','friday',    'is_working_day',false, 'start_time',NULL,   'end_time',NULL)
  );

  -- First custom employee schedule matches the date-effective company duration.
  SELECT public.save_employee_work_schedule(
    v_emp_same,
    v_employee_schedule_date,
    v_days_six,
    'Disposable six-hour employee transition'
  ) INTO v_result;
  v_employee_schedule_id := (v_result #>> '{schedule,id}')::UUID;

  IF v_employee_schedule_id IS NULL THEN
    RAISE EXCEPTION 'Company-history simulation failed: matching employee schedule was not saved';
  END IF;

  -- A mismatching first employee schedule may not begin mid-month.
  v_rejected := false;
  BEGIN
    PERFORM public.save_employee_work_schedule(
      v_emp_conflict,
      v_employee_schedule_date,
      v_days_eight,
      'Expected rejection: eight hours against six-hour company baseline'
    );
  EXCEPTION
    WHEN OTHERS THEN
      v_rejected := SQLERRM ILIKE '%first day of a month%'
        OR SQLERRM ILIKE '%أول%الشهر%';
  END;

  IF NOT v_rejected THEN
    RAISE EXCEPTION 'Company-history simulation failed: mismatching employee transition was accepted';
  END IF;

  -- Changing the company duration now would invalidate the prepared employee
  -- transition and therefore must be rejected.
  v_rejected := false;
  BEGIN
    PERFORM public.update_future_company_work_schedule_version(
      v_company_six_id,
      '10:00',
      '18:00',
      'friday',
      'Expected rejection: invalidates prepared employee transition'
    );
  EXCEPTION
    WHEN OTHERS THEN
      v_rejected := SQLERRM ILIKE '%invalidate employee schedule%';
  END;

  IF NOT v_rejected THEN
    RAISE EXCEPTION 'Company-history simulation failed: employee-transition conflict was not blocked';
  END IF;

  -- Establish a company-source snapshot and prove that even a same-duration
  -- time correction can no longer reinterpret it.
  SELECT min(d::DATE) INTO v_snapshot_date
  FROM generate_series(v_duration_change_date, v_employee_schedule_date - 1, INTERVAL '1 day') d
  CROSS JOIN LATERAL public.resolve_employee_work_schedule_core(v_emp_conflict, d::DATE, true) r
  WHERE r.day_kind = 'work_day';

  IF v_snapshot_date IS NULL THEN
    RAISE EXCEPTION 'Company-history simulation failed: snapshot date was not found';
  END IF;

  SELECT * INTO v_resolved
  FROM public.resolve_employee_work_schedule_core(v_emp_conflict, v_snapshot_date, true);

  INSERT INTO public.hr_attendance_days (
    employee_id,
    shift_date,
    work_date,
    status,
    day_value,
    review_status,
    schedule_day_kind,
    scheduled_start_at,
    scheduled_end_at,
    scheduled_minutes,
    schedule_source,
    work_schedule_id,
    schedule_snapshot_at
  ) VALUES (
    v_emp_conflict,
    v_snapshot_date,
    v_snapshot_date,
    'present',
    1,
    'reviewed',
    v_resolved.day_kind,
    v_resolved.scheduled_start_at,
    v_resolved.scheduled_end_at,
    v_resolved.scheduled_minutes,
    v_resolved.schedule_source,
    v_resolved.work_schedule_id,
    now()
  );

  v_rejected := false;
  BEGIN
    PERFORM public.update_future_company_work_schedule_version(
      v_company_six_id,
      '09:00',
      '15:00',
      'friday',
      'Expected rejection: established company snapshot'
    );
  EXCEPTION
    WHEN OTHERS THEN
      v_rejected := SQLERRM ILIKE '%established attendance snapshot%';
  END;

  IF NOT v_rejected THEN
    RAISE EXCEPTION 'Company-history simulation failed: company snapshot conflict was not blocked';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.hr_payroll_lines pl
    WHERE pl.employee_id IN (v_emp_same, v_emp_conflict)
  ) THEN
    RAISE EXCEPTION 'Company-history simulation failed: payroll data was created';
  END IF;

  RAISE NOTICE 'Company-history simulation passed; all data will roll back';
END;
$simulation$;

ROLLBACK;
