-- Attribute the one-time administrative correction to the unique super-admin,
-- not to the employee whose attendance was corrected.

SET lock_timeout = '5s';
SET statement_timeout = '30s';

DO $migration$
DECLARE
  v_employee_id UUID;
  v_employee_user_id UUID;
  v_admin_id UUID;
  v_count INTEGER;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('correct_ahmed_schedule_from_august_first'));

  SELECT count(*) INTO v_count
  FROM public.hr_employees
  WHERE trim(full_name) = 'احمد نعمة الله';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one Ahmed Neamatallah employee; found %', v_count;
  END IF;

  SELECT id, user_id INTO v_employee_id, v_employee_user_id
  FROM public.hr_employees
  WHERE trim(full_name) = 'احمد نعمة الله';

  SELECT count(*) INTO v_count
  FROM public.profiles p
  WHERE EXISTS (
    SELECT 1
    FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    WHERE ur.user_id = p.id
      AND r.name = 'super_admin'
  );

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one super-admin reviewer; found %', v_count;
  END IF;

  SELECT p.id INTO v_admin_id
  FROM public.profiles p
  WHERE EXISTS (
    SELECT 1
    FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    WHERE ur.user_id = p.id
      AND r.name = 'super_admin'
  );

  IF NOT public.check_permission(v_admin_id, 'hr.attendance.create') THEN
    RAISE EXCEPTION 'The super-admin lacks attendance-edit permission';
  END IF;

  PERFORM 1
  FROM public.hr_attendance_days d
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
    AND d.reviewed_by = v_employee_user_id
    AND d.reviewed_at IS NOT NULL
    AND d.is_manually_locked = true
    AND d.scheduled_minutes = 360
    AND d.notes = 'تصحيح إداري: الموظف حضر يوم 2026-08-02 ولم يسجل حضورًا أو انصرافًا. لا توجد أوقات فعلية موثقة.'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'The reviewed 2026-08-02 correction no longer matches its expected state';
  END IF;

  UPDATE public.hr_attendance_days
  SET reviewed_by = v_admin_id,
      updated_at = now()
  WHERE employee_id = v_employee_id
    AND shift_date = DATE '2026-08-02';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'The 2026-08-02 correction reviewer was not updated';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_penalty_instances pi
    JOIN public.hr_attendance_days d ON d.id = pi.attendance_day_id
    WHERE d.employee_id = v_employee_id
      AND d.shift_date = DATE '2026-08-02'
  ) THEN
    RAISE EXCEPTION 'The 2026-08-02 correction unexpectedly has a penalty';
  END IF;
END;
$migration$;
