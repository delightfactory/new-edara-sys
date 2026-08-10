-- One-time, fail-closed correction for Ahmed Neamatallah's August 2026 schedule.
--
-- Business facts confirmed by management:
--   * the weekly schedule already stored from 2026-08-12 was actually in force
--     from 2026-08-01;
--   * 2026-08-02 was a full attended day, but no punch times were recorded;
--   * no punch times may be invented for that day.
--
-- Existing punches are preserved and recalculated through the production
-- attendance service function. Historical notifications are suppressed while
-- the old rows are corrected, and all safety checks run in the same transaction.

SET lock_timeout = '5s';
SET statement_timeout = '60s';

DO $migration$
DECLARE
  v_employee_id UUID;
  v_reviewer_id UUID;
  v_count INTEGER;
  v_changed INTEGER;
  v_target_fingerprint TEXT;
  v_row RECORD;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('correct_ahmed_schedule_from_august_first'));

  SELECT count(*)
  INTO v_count
  FROM public.hr_employees
  WHERE trim(full_name) = 'احمد نعمة الله';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one active employee named Ahmed Neamatallah; found %', v_count;
  END IF;

  SELECT id, user_id
  INTO v_employee_id, v_reviewer_id
  FROM public.hr_employees
  WHERE trim(full_name) = 'احمد نعمة الله';

  PERFORM 1
  FROM public.hr_employees
  WHERE id = v_employee_id
    AND status = 'active'
    AND hire_date <= DATE '2026-08-01'
    AND termination_date IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ahmed is not active for the correction period';
  END IF;

  IF v_reviewer_id IS NULL
     OR NOT public.check_permission(v_reviewer_id, 'hr.attendance.create') THEN
    RAISE EXCEPTION 'Ahmed has no linked profile with attendance-edit permission';
  END IF;

  -- Accept only the exact seven-row schedule version reviewed before deployment.
  SELECT count(*)
  INTO v_count
  FROM public.hr_employee_work_schedules s
  WHERE s.employee_id = v_employee_id;

  IF v_count <> 7 THEN
    RAISE EXCEPTION 'Expected exactly seven schedule rows for Ahmed; found %', v_count;
  END IF;

  SELECT count(*)
  INTO v_count
  FROM public.hr_employee_work_schedules s
  WHERE s.employee_id = v_employee_id
    AND s.effective_from = DATE '2026-08-12'
    AND s.uses_company_defaults = false
    AND (
      (s.day_of_week IN ('saturday', 'monday', 'tuesday')
        AND s.is_working_day = true
        AND s.start_time = TIME '15:00'
        AND s.end_time = TIME '21:00')
      OR
      (s.day_of_week IN ('sunday', 'wednesday', 'thursday')
        AND s.is_working_day = true
        AND s.start_time = TIME '10:00'
        AND s.end_time = TIME '16:00')
      OR
      (s.day_of_week = 'friday'
        AND s.is_working_day = false
        AND s.start_time IS NULL
        AND s.end_time IS NULL)
    );

  IF v_count <> 7 THEN
    RAISE EXCEPTION 'Ahmed schedule no longer matches the reviewed 2026-08-12 version';
  END IF;

  -- A closed period or any already-calculated payroll line requires a separate
  -- accounting workflow, so this migration refuses to continue in that case.
  IF EXISTS (
    SELECT 1
    FROM public.hr_payroll_periods p
    WHERE DATE '2026-08-02' BETWEEN p.start_date AND p.end_date
      AND p.is_closed = true
  ) THEN
    RAISE EXCEPTION 'The August 2026 payroll period is already closed';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_payroll_lines pl
    JOIN public.hr_payroll_runs pr ON pr.id = pl.payroll_run_id
    JOIN public.hr_payroll_periods pp ON pp.id = pr.period_id
    WHERE pl.employee_id = v_employee_id
      AND DATE '2026-08-02' BETWEEN pp.start_date AND pp.end_date
  ) THEN
    RAISE EXCEPTION 'Ahmed already has an August 2026 payroll line';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_leave_requests lr
    WHERE lr.employee_id = v_employee_id
      AND lr.status = 'approved'
      AND daterange(lr.start_date, lr.end_date, '[]')
          && daterange(DATE '2026-08-01', DATE '2026-08-10', '[]')
  ) OR EXISTS (
    SELECT 1
    FROM public.hr_permission_requests pr
    WHERE pr.employee_id = v_employee_id
      AND pr.status = 'approved'
      AND pr.permission_date BETWEEN DATE '2026-08-01' AND DATE '2026-08-10'
  ) THEN
    RAISE EXCEPTION 'Approved leave or permission now overlaps the correction period';
  END IF;

  -- Lock and fingerprint the exact eight punched days that were reviewed.
  PERFORM 1
  FROM public.hr_attendance_days d
  WHERE d.employee_id = v_employee_id
    AND d.shift_date BETWEEN DATE '2026-08-01' AND DATE '2026-08-10'
  FOR UPDATE;

  SELECT count(*),
         md5(coalesce(string_agg(concat_ws('|',
           shift_date::text,
           coalesce(to_char(punch_in_time AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US'), ''),
           coalesce(to_char(punch_out_time AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US'), ''),
           status::text, coalesce(checkout_status::text, ''), late_minutes::text,
           early_leave_minutes::text, overtime_minutes::text,
           coalesce(effective_hours::text, ''), day_value::text, review_status::text,
           coalesce(reviewed_by::text, ''),
           coalesce(to_char(reviewed_at AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US'), ''),
           coalesce(notes, ''), is_manually_locked::text,
           coalesce(source_leave_request_id::text, ''),
           coalesce(to_char(scheduled_start_at AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US'), ''),
           coalesce(to_char(scheduled_end_at AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US'), ''),
           coalesce(scheduled_minutes::text, '')
         ), E'\n' ORDER BY shift_date), ''))
  INTO v_count, v_target_fingerprint
  FROM public.hr_attendance_days d
  WHERE d.employee_id = v_employee_id
    AND d.shift_date BETWEEN DATE '2026-08-01' AND DATE '2026-08-10';

  IF v_count <> 8 OR v_target_fingerprint <> 'c54627610db9674a09cc9c4596fb02a0' THEN
    RAISE EXCEPTION 'Ahmed attendance changed after review (count %, fingerprint %)',
      v_count, v_target_fingerprint;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_penalty_instances pi
    JOIN public.hr_attendance_days d ON d.id = pi.attendance_day_id
    WHERE d.employee_id = v_employee_id
      AND d.shift_date BETWEEN DATE '2026-08-01' AND DATE '2026-08-10'
      AND (pi.is_manual OR pi.is_overridden OR pi.payroll_run_id IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'A protected manual, overridden, or payroll-linked penalty exists';
  END IF;

  CREATE TEMP TABLE _ahmed_attendance_before ON COMMIT DROP AS
  SELECT d.id, d.shift_date, d.punch_in_time, d.punch_out_time, d.notes,
         d.review_status, d.reviewed_by, d.reviewed_at, d.is_manually_locked
  FROM public.hr_attendance_days d
  WHERE d.employee_id = v_employee_id
    AND d.shift_date BETWEEN DATE '2026-08-01' AND DATE '2026-08-10';

  UPDATE public.hr_employee_work_schedules
  SET effective_from = DATE '2026-08-01'
  WHERE employee_id = v_employee_id
    AND effective_from = DATE '2026-08-12';

  GET DIAGNOSTICS v_changed = ROW_COUNT;
  IF v_changed <> 7 THEN
    RAISE EXCEPTION 'Expected to move seven schedule rows; moved %', v_changed;
  END IF;

  -- Historical snapshot immutability and early-leave notifications are correct
  -- for normal operations. Disable only these two triggers during this approved,
  -- one-time backfill; transaction rollback restores them on any error.
  ALTER TABLE public.hr_attendance_days
    DISABLE TRIGGER trg_sync_attendance_day_schedule;
  ALTER TABLE public.hr_attendance_days
    DISABLE TRIGGER trg_notify_attendance_early_leave;

  FOR v_row IN
    SELECT * FROM _ahmed_attendance_before ORDER BY shift_date
  LOOP
    PERFORM public.upsert_attendance_and_reprocess(
      v_employee_id,
      v_row.shift_date,
      v_row.punch_in_time,
      v_row.punch_out_time,
      NULL,
      v_row.notes,
      v_reviewer_id
    );
  END LOOP;

  -- Restore review/lock metadata changed by the administrative upsert and write
  -- the corrected immutable schedule snapshot for those historical days.
  UPDATE public.hr_attendance_days d
  SET review_status = b.review_status,
      reviewed_by = b.reviewed_by,
      reviewed_at = b.reviewed_at,
      is_manually_locked = b.is_manually_locked,
      scheduled_start_at = s.scheduled_start_at,
      scheduled_end_at = s.scheduled_end_at,
      scheduled_minutes = s.scheduled_minutes
  FROM _ahmed_attendance_before b
  CROSS JOIN LATERAL public.get_employee_work_schedule(v_employee_id, b.shift_date) s
  WHERE d.id = b.id;

  ALTER TABLE public.hr_attendance_days
    ENABLE TRIGGER trg_notify_attendance_early_leave;
  ALTER TABLE public.hr_attendance_days
    ENABLE TRIGGER trg_sync_attendance_day_schedule;

  -- Sunday 2 August: credit a full attended day, but keep punch times and actual
  -- hours NULL because they are not documented facts.
  PERFORM public.upsert_attendance_and_reprocess(
    v_employee_id,
    DATE '2026-08-02',
    NULL,
    NULL,
    'present',
    'تصحيح إداري: الموظف حضر يوم 2026-08-02 ولم يسجل حضورًا أو انصرافًا. لا توجد أوقات فعلية موثقة.',
    v_reviewer_id
  );

  UPDATE public.hr_attendance_days
  SET reviewed_by = v_reviewer_id,
      reviewed_at = now()
  WHERE employee_id = v_employee_id
    AND shift_date = DATE '2026-08-02';

  -- Exact postconditions for the eight recalculated punched days.
  WITH expected(shift_date, status, checkout_status, late_minutes,
                early_leave_minutes, overtime_minutes) AS (
    VALUES
      (DATE '2026-08-01', 'late'::public.hr_attendance_status,
       'early_unauthorized'::public.hr_checkout_status, 34, 82, 0),
      (DATE '2026-08-03', 'present'::public.hr_attendance_status,
       'on_time'::public.hr_checkout_status, 0, 0, 0),
      (DATE '2026-08-04', 'late'::public.hr_attendance_status,
       'on_time'::public.hr_checkout_status, 20, 0, 0),
      (DATE '2026-08-05', 'present'::public.hr_attendance_status,
       'early_unauthorized'::public.hr_checkout_status, 0, 20, 0),
      (DATE '2026-08-06', 'present'::public.hr_attendance_status,
       'on_time'::public.hr_checkout_status, 0, 0, 0),
      (DATE '2026-08-08', 'late'::public.hr_attendance_status,
       'overtime'::public.hr_checkout_status, 63, 0, 49),
      (DATE '2026-08-09', 'late'::public.hr_attendance_status,
       'on_time'::public.hr_checkout_status, 33, 0, 0),
      (DATE '2026-08-10', 'present'::public.hr_attendance_status,
       'early_unauthorized'::public.hr_checkout_status, 0, 32, 0)
  )
  SELECT count(*)
  INTO v_count
  FROM expected e
  JOIN public.hr_attendance_days d
    ON d.employee_id = v_employee_id AND d.shift_date = e.shift_date
  CROSS JOIN LATERAL public.get_employee_work_schedule(v_employee_id, e.shift_date) s
  WHERE d.status = e.status
    AND d.checkout_status = e.checkout_status
    AND d.late_minutes = e.late_minutes
    AND d.early_leave_minutes = e.early_leave_minutes
    AND d.overtime_minutes = e.overtime_minutes
    AND d.day_value = 1
    AND d.scheduled_start_at IS NOT DISTINCT FROM s.scheduled_start_at
    AND d.scheduled_end_at IS NOT DISTINCT FROM s.scheduled_end_at
    AND d.scheduled_minutes IS NOT DISTINCT FROM s.scheduled_minutes;

  IF v_count <> 8 THEN
    RAISE EXCEPTION 'Only % of eight recalculated attendance days passed validation', v_count;
  END IF;

  SELECT count(*)
  INTO v_count
  FROM public.hr_attendance_days d
  CROSS JOIN LATERAL public.get_employee_work_schedule(v_employee_id, d.shift_date) s
  WHERE d.employee_id = v_employee_id
    AND d.shift_date = DATE '2026-08-02'
    AND d.status = 'present'
    AND d.day_value = 1
    AND d.punch_in_time IS NULL
    AND d.punch_out_time IS NULL
    AND d.effective_hours IS NULL
    AND d.late_minutes = 0
    AND d.early_leave_minutes = 0
    AND d.overtime_minutes = 0
    AND d.review_status = 'reviewed'
    AND d.reviewed_by = v_reviewer_id
    AND d.reviewed_at IS NOT NULL
    AND d.is_manually_locked = true
    AND d.scheduled_start_at IS NOT DISTINCT FROM s.scheduled_start_at
    AND d.scheduled_end_at IS NOT DISTINCT FROM s.scheduled_end_at
    AND d.scheduled_minutes = 360;

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'The manual attendance record for 2026-08-02 failed validation';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_penalty_instances pi
    JOIN public.hr_attendance_days d ON d.id = pi.attendance_day_id
    WHERE d.employee_id = v_employee_id
      AND d.shift_date = DATE '2026-08-02'
  ) THEN
    RAISE EXCEPTION 'The manual attendance record for 2026-08-02 received a penalty';
  END IF;

  SELECT count(*)
  INTO v_count
  FROM public.hr_employee_work_schedules
  WHERE employee_id = v_employee_id
    AND effective_from = DATE '2026-08-01';

  IF v_count <> 7 THEN
    RAISE EXCEPTION 'The final schedule version does not contain seven rows from 2026-08-01';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid = 'public.hr_attendance_days'::regclass
      AND tgname IN (
        'trg_sync_attendance_day_schedule',
        'trg_notify_attendance_early_leave'
      )
      AND tgenabled <> 'O'
  ) THEN
    RAISE EXCEPTION 'An attendance trigger was not re-enabled';
  END IF;
END;
$migration$;
