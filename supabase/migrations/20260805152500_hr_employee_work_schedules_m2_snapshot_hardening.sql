-- =============================================================================
-- EDARA — Employee Work Schedules M2 snapshot hardening
--
-- Prevents an unsnapshotted attendance row that falls inside an employee custom
-- schedule from being silently reinterpreted with company fallback hours.
--
-- No existing attendance/payroll caller is replaced in this migration.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  IF to_regprocedure('public.ensure_attendance_schedule_snapshot(uuid)') IS NULL
     OR to_regprocedure('public.resolve_employee_work_schedule_core(uuid,date,boolean)') IS NULL THEN
    RAISE EXCEPTION 'M2 snapshot hardening preflight failed: base M2 helpers are missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'M2 snapshot hardening preflight failed: feature switch must remain false during migration staging';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'M2 snapshot hardening preflight failed: no schedule data is expected before rehearsal';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.ensure_attendance_schedule_snapshot(
  p_attendance_day_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_day public.hr_attendance_days%ROWTYPE;
  v_payroll_status TEXT;
  v_custom_candidate RECORD;
  v_resolved RECORD;
  v_actor UUID := auth.uid();
  v_snapshot_at TIMESTAMPTZ;
BEGIN
  IF p_attendance_day_id IS NULL THEN
    RAISE EXCEPTION 'attendance_day_id is required';
  END IF;

  SELECT *
  INTO v_day
  FROM public.hr_attendance_days
  WHERE id = p_attendance_day_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Attendance day % does not exist', p_attendance_day_id;
  END IF;

  IF v_day.schedule_snapshot_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'attendance_day_id', v_day.id,
      'created', false,
      'day_kind', v_day.schedule_day_kind,
      'scheduled_start_at', v_day.scheduled_start_at,
      'scheduled_end_at', v_day.scheduled_end_at,
      'scheduled_minutes', v_day.scheduled_minutes,
      'schedule_source', v_day.schedule_source,
      'work_schedule_id', v_day.work_schedule_id,
      'schedule_snapshot_at', v_day.schedule_snapshot_at
    );
  END IF;

  -- M1 permits either a wholly-null legacy snapshot or a complete snapshot.
  -- Keep a direct defensive check in case a table owner bypasses constraints.
  IF v_day.schedule_day_kind IS NOT NULL
     OR v_day.scheduled_start_at IS NOT NULL
     OR v_day.scheduled_end_at IS NOT NULL
     OR v_day.scheduled_minutes IS NOT NULL
     OR v_day.schedule_source IS NOT NULL
     OR v_day.work_schedule_id IS NOT NULL THEN
    RAISE EXCEPTION 'Attendance day % contains an incomplete schedule snapshot', v_day.id;
  END IF;

  SELECT pr.status::TEXT
  INTO v_payroll_status
  FROM public.hr_payroll_lines pl
  JOIN public.hr_payroll_runs pr ON pr.id = pl.payroll_run_id
  JOIN public.hr_payroll_periods pp ON pp.id = pr.period_id
  WHERE pl.employee_id = v_day.employee_id
    AND v_day.shift_date BETWEEN pp.start_date AND pp.end_date
    AND pr.status IN ('approved', 'paid')
  ORDER BY CASE pr.status WHEN 'paid' THEN 1 ELSE 2 END
  LIMIT 1;

  IF v_payroll_status IS NOT NULL THEN
    RAISE EXCEPTION
      'Cannot create schedule snapshot for attendance day % covered by % payroll',
      v_day.id, v_payroll_status;
  END IF;

  -- Detect whether a versioned employee schedule covers the date, regardless
  -- of the current feature-switch state. If it does, guessing company fallback
  -- would be unsafe: the row may have been created by a partially failed future
  -- caller. Stop for controlled reconciliation instead.
  SELECT *
  INTO v_custom_candidate
  FROM public.resolve_employee_work_schedule_core(
    v_day.employee_id,
    v_day.shift_date,
    true
  );

  IF v_custom_candidate.schedule_source = 'employee' THEN
    RAISE EXCEPTION
      'Attendance day % is missing its immutable snapshot for employee schedule %; controlled reconciliation is required',
      v_day.id, v_custom_candidate.work_schedule_id;
  END IF;

  -- Safe legacy case: no employee schedule covers this date. Reproduce the
  -- company/employee-off-day behavior and persist it exactly once.
  SELECT *
  INTO v_resolved
  FROM public.resolve_employee_work_schedule_core(
    v_day.employee_id,
    v_day.shift_date,
    false
  );

  v_snapshot_at := now();

  UPDATE public.hr_attendance_days
  SET schedule_day_kind = v_resolved.day_kind,
      scheduled_start_at = v_resolved.scheduled_start_at,
      scheduled_end_at = v_resolved.scheduled_end_at,
      scheduled_minutes = v_resolved.scheduled_minutes,
      schedule_source = v_resolved.schedule_source,
      work_schedule_id = v_resolved.work_schedule_id,
      schedule_snapshot_at = v_snapshot_at,
      updated_at = now()
  WHERE id = v_day.id;

  INSERT INTO public.audit_logs (
    user_id,
    action,
    entity_type,
    entity_id,
    old_data,
    new_data,
    user_agent
  ) VALUES (
    v_actor,
    'attendance_schedule_snapshot_created',
    'hr_attendance_day',
    v_day.id,
    jsonb_build_object(
      'schedule_snapshot_at', NULL,
      'legacy_row', true
    ),
    jsonb_build_object(
      'day_kind', v_resolved.day_kind,
      'scheduled_start_at', v_resolved.scheduled_start_at,
      'scheduled_end_at', v_resolved.scheduled_end_at,
      'scheduled_minutes', v_resolved.scheduled_minutes,
      'schedule_source', v_resolved.schedule_source,
      'work_schedule_id', v_resolved.work_schedule_id,
      'schedule_snapshot_at', v_snapshot_at
    ),
    'EDARA attendance schedule snapshot helper'
  );

  RETURN jsonb_build_object(
    'attendance_day_id', v_day.id,
    'created', true,
    'day_kind', v_resolved.day_kind,
    'scheduled_start_at', v_resolved.scheduled_start_at,
    'scheduled_end_at', v_resolved.scheduled_end_at,
    'scheduled_minutes', v_resolved.scheduled_minutes,
    'schedule_source', v_resolved.schedule_source,
    'work_schedule_id', v_resolved.work_schedule_id,
    'schedule_snapshot_at', v_snapshot_at
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.ensure_attendance_schedule_snapshot(UUID)
  FROM PUBLIC, anon, authenticated;

DO $assertions$
BEGIN
  IF public.hr_employee_work_schedules_enabled() THEN
    RAISE EXCEPTION 'M2 snapshot hardening assertion failed: feature switch became enabled';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'M2 snapshot hardening assertion failed: no schedule data may be seeded';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_attendance_days
    WHERE schedule_snapshot_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'M2 snapshot hardening assertion failed: migration must not alter historical attendance';
  END IF;
END;
$assertions$;

COMMIT;
