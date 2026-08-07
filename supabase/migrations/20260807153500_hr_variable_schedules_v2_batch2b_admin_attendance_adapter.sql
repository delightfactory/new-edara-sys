-- HR Variable Schedules V2 — Batch 2B
-- Administrative attendance correction adapter only.
--
-- Safety model:
--   * preserve the public RPC name/signature;
--   * retain the exact captured production implementation as Legacy;
--   * route to Legacy immediately while the shared V2 runtime gate is false;
--   * when the gate is eventually opened, use the custom path only for an
--     employee/date with an effective custom schedule or an existing custom snapshot;
--   * do not change authorization, payroll locks, leave policy, penalty policy,
--     absence logic, auto-checkout, payroll, UI, or generic settings.

BEGIN;

DO $guard$
DECLARE
  v_hash text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid))
  INTO v_hash
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'upsert_attendance_and_reprocess'
    AND pg_get_function_identity_arguments(p.oid) =
      'p_employee_id uuid, p_shift_date date, p_punch_in_time timestamp with time zone, p_punch_out_time timestamp with time zone, p_status hr_attendance_status, p_notes text, p_user_id uuid';

  IF v_hash IS DISTINCT FROM 'a0123e9ec343603dee9adf4ec73739b4' THEN
    RAISE EXCEPTION 'Batch 2B baseline mismatch for upsert_attendance_and_reprocess; review production drift before applying';
  END IF;

  IF to_regprocedure('public.upsert_attendance_and_reprocess_legacy(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)') IS NOT NULL
     OR to_regprocedure('public.upsert_attendance_and_reprocess_custom_schedule(uuid,date,timestamp with time zone,timestamp with time zone,hr_attendance_status,text,uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'Batch 2B helper function name collision';
  END IF;

  IF to_regprocedure('public.hr_variable_schedules_v2_runtime_enabled()') IS NULL THEN
    RAISE EXCEPTION 'Batch 2B requires the fail-closed V2 runtime gate from Batch 2A';
  END IF;
END;
$guard$;

-- Preserve the exact production implementation under a private Legacy alias.
ALTER FUNCTION public.upsert_attendance_and_reprocess(
  uuid, date, timestamp with time zone, timestamp with time zone,
  hr_attendance_status, text, uuid
) RENAME TO upsert_attendance_and_reprocess_legacy;

REVOKE ALL ON FUNCTION public.upsert_attendance_and_reprocess_legacy(
  uuid, date, timestamp with time zone, timestamp with time zone,
  hr_attendance_status, text, uuid
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.upsert_attendance_and_reprocess_custom_schedule(
  p_employee_id uuid,
  p_shift_date date,
  p_punch_in_time timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_punch_out_time timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_status hr_attendance_status DEFAULT NULL::hr_attendance_status,
  p_notes text DEFAULT NULL::text,
  p_user_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_day_id            uuid;
  v_existing          hr_attendance_days%ROWTYPE;
  v_new_eff_hours     numeric;
  v_new_late_min      integer := 0;
  v_new_early_min     integer := 0;
  v_new_ot_min        integer := 0;
  v_new_status        hr_attendance_status;
  v_new_co_status     hr_checkout_status;
  v_work_start        time;
  v_work_end          time;
  v_grace_min         integer;
  v_sched_start       timestamptz;
  v_sched_end         timestamptz;
  v_penalties_count   integer;
  v_payroll_status    text;
  v_schedule          record;
  v_schedule_id       uuid;
  v_scheduled_minutes integer;
  v_custom_working_day boolean;
BEGIN
  -- Preserve the captured authorization contract exactly.
  IF NOT check_permission(COALESCE(p_user_id, auth.uid()), 'hr.attendance.create') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تعديل الحضور';
  END IF;

  -- Preserve the approved/paid payroll lock exactly.
  SELECT pr.status INTO v_payroll_status
  FROM hr_payroll_lines pl
  JOIN hr_payroll_runs pr ON pr.id = pl.payroll_run_id
  WHERE pl.employee_id = p_employee_id
    AND pr.period_id IN (
      SELECT id FROM hr_payroll_periods
      WHERE p_shift_date BETWEEN start_date AND end_date
    );

  IF v_payroll_status IN ('approved', 'paid') THEN
    RAISE EXCEPTION 'لا يمكن تعديل الحضور لليوم % لأنه مرتبط بمسير رواتب في حالة %', p_shift_date, v_payroll_status;
  END IF;

  SELECT * INTO v_existing
  FROM public.hr_attendance_days
  WHERE employee_id = p_employee_id
    AND shift_date = p_shift_date;

  -- Prefer a snapshot already attached to the attendance day. This prevents an
  -- administrative correction from reinterpreting a day that was processed under
  -- a specific custom schedule version.
  IF FOUND AND v_existing.custom_schedule_id IS NOT NULL THEN
    v_schedule_id := v_existing.custom_schedule_id;
    v_scheduled_minutes := v_existing.custom_scheduled_minutes;
    v_work_start := v_existing.custom_scheduled_start;
    v_work_end := v_existing.custom_scheduled_end;
    v_custom_working_day := COALESCE(v_scheduled_minutes, 0) > 0;
  ELSE
    SELECT * INTO v_schedule
    FROM public.resolve_employee_custom_schedule(p_employee_id, p_shift_date);

    IF NOT FOUND THEN
      RAISE EXCEPTION 'V2 custom administrative attendance path invoked without a complete effective custom schedule';
    END IF;

    v_schedule_id := v_schedule.schedule_id;
    v_scheduled_minutes := v_schedule.scheduled_minutes;
    v_work_start := v_schedule.start_time;
    v_work_end := v_schedule.end_time;
    v_custom_working_day := v_schedule.is_working_day;
  END IF;

  SELECT COALESCE(value::integer, 15) INTO v_grace_min
  FROM company_settings WHERE key = 'hr.late_grace_minutes';

  v_new_status := COALESCE(p_status, 'present');
  v_new_co_status := NULL;

  IF p_punch_in_time IS NOT NULL AND p_punch_out_time IS NOT NULL THEN
    v_new_eff_hours := LEAST(
      ROUND(EXTRACT(EPOCH FROM (p_punch_out_time - p_punch_in_time)) / 3600.0, 2),
      24.00
    );

    IF v_custom_working_day THEN
      v_sched_start := (p_shift_date + v_work_start) AT TIME ZONE 'Africa/Cairo';
      IF p_punch_in_time > v_sched_start + (v_grace_min || ' minutes')::interval THEN
        v_new_late_min := EXTRACT(EPOCH FROM (p_punch_in_time - v_sched_start))::integer / 60;
        IF v_new_late_min > 0 THEN
          v_new_status := 'late';
        END IF;
      END IF;

      v_sched_end := (p_shift_date + v_work_end) AT TIME ZONE 'Africa/Cairo';
      -- Keep the administrative correction thresholds exactly as production:
      -- overtime after 30 minutes, early leave before 5 minutes.
      IF p_punch_out_time > v_sched_end + interval '30 minutes' THEN
        v_new_ot_min := EXTRACT(EPOCH FROM (p_punch_out_time - v_sched_end))::integer / 60;
        v_new_co_status := 'overtime';
      ELSIF p_punch_out_time < v_sched_end - interval '5 minutes' THEN
        v_new_early_min := EXTRACT(EPOCH FROM (v_sched_end - p_punch_out_time))::integer / 60;
        IF EXISTS (
          SELECT 1 FROM hr_leave_requests
          WHERE employee_id = p_employee_id
            AND start_date <= p_shift_date AND end_date >= p_shift_date
            AND status = 'approved'
        ) OR EXISTS (
          SELECT 1 FROM hr_permission_requests
          WHERE employee_id = p_employee_id
            AND permission_date = p_shift_date
            AND status = 'approved'
        ) THEN
          v_new_co_status := 'early_authorized';
        ELSE
          v_new_co_status := 'early_unauthorized';
        END IF;
      ELSE
        v_new_co_status := 'on_time';
      END IF;
    ELSE
      -- Manual attendance on a configured custom non-working day remains possible
      -- under the existing admin policy, but company-time late/early/overtime must
      -- not be invented for that off-day.
      v_new_late_min := 0;
      v_new_early_min := 0;
      v_new_ot_min := 0;
      v_new_co_status := 'on_time';
    END IF;

  ELSIF p_punch_in_time IS NOT NULL THEN
    IF v_custom_working_day THEN
      v_sched_start := (p_shift_date + v_work_start) AT TIME ZONE 'Africa/Cairo';
      IF p_punch_in_time > v_sched_start + (v_grace_min || ' minutes')::interval THEN
        v_new_late_min := EXTRACT(EPOCH FROM (p_punch_in_time - v_sched_start))::integer / 60;
        v_new_status := 'late';
      END IF;
    ELSE
      v_new_late_min := 0;
    END IF;
  END IF;

  INSERT INTO hr_attendance_days (
    employee_id, shift_date, work_date,
    punch_in_time, punch_out_time,
    status, checkout_status,
    late_minutes, early_leave_minutes, overtime_minutes,
    effective_hours, day_value,
    notes, review_status, is_manually_locked,
    custom_schedule_id, custom_scheduled_start, custom_scheduled_end, custom_scheduled_minutes
  ) VALUES (
    p_employee_id, p_shift_date, p_shift_date,
    p_punch_in_time, p_punch_out_time,
    v_new_status, v_new_co_status,
    v_new_late_min, v_new_early_min, v_new_ot_min,
    v_new_eff_hours,
    CASE v_new_status
      WHEN 'half_day' THEN 0.5
      WHEN 'absent_unauthorized' THEN 0
      WHEN 'absent_authorized' THEN 0
      ELSE 1.0
    END,
    p_notes, 'reviewed', true,
    v_schedule_id,
    CASE WHEN v_custom_working_day THEN v_work_start ELSE NULL END,
    CASE WHEN v_custom_working_day THEN v_work_end ELSE NULL END,
    v_scheduled_minutes
  )
  ON CONFLICT (employee_id, shift_date)
  DO UPDATE SET
    punch_in_time       = EXCLUDED.punch_in_time,
    punch_out_time      = EXCLUDED.punch_out_time,
    status              = EXCLUDED.status,
    checkout_status     = EXCLUDED.checkout_status,
    late_minutes        = EXCLUDED.late_minutes,
    early_leave_minutes = EXCLUDED.early_leave_minutes,
    overtime_minutes    = EXCLUDED.overtime_minutes,
    effective_hours     = EXCLUDED.effective_hours,
    day_value           = EXCLUDED.day_value,
    notes               = EXCLUDED.notes,
    review_status       = 'reviewed',
    is_manually_locked  = true,
    reviewed_by         = COALESCE(p_user_id, auth.uid()),
    reviewed_at         = now(),
    custom_schedule_id       = EXCLUDED.custom_schedule_id,
    custom_scheduled_start   = EXCLUDED.custom_scheduled_start,
    custom_scheduled_end     = EXCLUDED.custom_scheduled_end,
    custom_scheduled_minutes = EXCLUDED.custom_scheduled_minutes,
    updated_at          = now()
  RETURNING id INTO v_day_id;

  -- These downstream helpers are intentionally still Legacy. The shared runtime
  -- gate remains hard-coded FALSE until Batch 3 reviews their schedule-dependent
  -- duration/penalty assumptions.
  PERFORM settle_attendance_day_against_leave(v_day_id, true);

  SELECT reprocess_attendance_day_penalties(v_day_id)
  INTO v_penalties_count;

  RETURN jsonb_build_object(
    'success', true,
    'attendance_day_id', v_day_id,
    'status', v_new_status,
    'checkout_status', v_new_co_status,
    'late_minutes', v_new_late_min,
    'early_leave_minutes', v_new_early_min,
    'overtime_minutes', v_new_ot_min,
    'effective_hours', v_new_eff_hours,
    'penalties_applied', v_penalties_count,
    'message', format('تم تحديث الحضور إدارياً وتم قفل اليوم — %s جزاء/ات أُعيد حسابه', v_penalties_count)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.upsert_attendance_and_reprocess_custom_schedule(
  uuid, date, timestamp with time zone, timestamp with time zone,
  hr_attendance_status, text, uuid
) FROM PUBLIC, anon, authenticated, service_role;

-- Compatibility wrapper under the unchanged public RPC name.
CREATE OR REPLACE FUNCTION public.upsert_attendance_and_reprocess(
  p_employee_id uuid,
  p_shift_date date,
  p_punch_in_time timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_punch_out_time timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_status hr_attendance_status DEFAULT NULL::hr_attendance_status,
  p_notes text DEFAULT NULL::text,
  p_user_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.hr_variable_schedules_v2_runtime_enabled() THEN
    RETURN public.upsert_attendance_and_reprocess_legacy(
      p_employee_id, p_shift_date, p_punch_in_time, p_punch_out_time,
      p_status, p_notes, p_user_id
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_attendance_days d
    WHERE d.employee_id = p_employee_id
      AND d.shift_date = p_shift_date
      AND d.custom_schedule_id IS NOT NULL
  ) OR EXISTS (
    SELECT 1
    FROM public.resolve_employee_custom_schedule(p_employee_id, p_shift_date)
  ) THEN
    RETURN public.upsert_attendance_and_reprocess_custom_schedule(
      p_employee_id, p_shift_date, p_punch_in_time, p_punch_out_time,
      p_status, p_notes, p_user_id
    );
  END IF;

  RETURN public.upsert_attendance_and_reprocess_legacy(
    p_employee_id, p_shift_date, p_punch_in_time, p_punch_out_time,
    p_status, p_notes, p_user_id
  );
END;
$function$;

COMMENT ON FUNCTION public.upsert_attendance_and_reprocess(
  uuid, date, timestamp with time zone, timestamp with time zone,
  hr_attendance_status, text, uuid
) IS 'Compatibility wrapper: exact Legacy admin-attendance path while V2 gate is false or no custom schedule/snapshot exists.';

-- Restore the captured public EXECUTE contract on the original RPC name only.
REVOKE ALL ON FUNCTION public.upsert_attendance_and_reprocess(
  uuid, date, timestamp with time zone, timestamp with time zone,
  hr_attendance_status, text, uuid
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.upsert_attendance_and_reprocess(
  uuid, date, timestamp with time zone, timestamp with time zone,
  hr_attendance_status, text, uuid
) TO PUBLIC, anon, authenticated, service_role;

COMMIT;
