-- HR Variable Schedules V2 — Batch 3B2
-- Early-leave penalty schedule inputs only.
--
-- Scope:
--   * preserve the public process_attendance_penalties(uuid) signature;
--   * preserve the exact Legacy function for all non-custom and all non-early-leave cases;
--   * for a custom-schedule working day with unauthorized early leave, replace only
--     the Legacy early-leave penalty with one using the custom scheduled end and
--     custom scheduled minutes as its denominator;
--   * preserve the inherited permission-overlap algorithm and all other penalty policy;
--   * do not activate V2.

BEGIN;

DO $guard$
DECLARE
  v_hash text;
BEGIN
  SELECT md5(replace(p.prosrc, E'\r\n', E'\n'))
  INTO v_hash
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'process_attendance_penalties'
    AND pg_get_function_identity_arguments(p.oid) = 'p_attendance_day_id uuid';

  IF v_hash IS DISTINCT FROM 'c05f834d11387ab8312965c16a065a0a' THEN
    RAISE EXCEPTION 'Batch 3B2 baseline mismatch for process_attendance_penalties; review production drift before applying';
  END IF;

  IF to_regprocedure('public.process_attendance_penalties_legacy(uuid)') IS NOT NULL
     OR to_regprocedure('public.process_attendance_penalties_custom_early_leave(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'Batch 3B2 helper function name collision';
  END IF;

  IF to_regprocedure('public.hr_variable_schedules_v2_runtime_enabled()') IS NULL
     OR to_regprocedure('public.resolve_employee_custom_schedule(uuid,date)') IS NULL THEN
    RAISE EXCEPTION 'Batch 3B2 prerequisites are missing';
  END IF;
END;
$guard$;

ALTER FUNCTION public.process_attendance_penalties(uuid)
  RENAME TO process_attendance_penalties_legacy;

REVOKE ALL ON FUNCTION public.process_attendance_penalties_legacy(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.process_attendance_penalties_custom_early_leave(
  p_attendance_day_id uuid
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_day public.hr_attendance_days%ROWTYPE;
  v_schedule record;
  v_scheduled_end time;
  v_scheduled_minutes integer;
  v_legacy_count integer := 0;
  v_removed_legacy_early integer := 0;
  v_count integer := 0;
  v_uncovered_minutes integer;
  v_covered_minutes integer := 0;
  v_perm record;
  v_early_start timestamptz;
  v_early_end timestamptz;
  v_perm_start timestamptz;
  v_perm_end timestamptz;
  v_overlap_start timestamptz;
  v_overlap_end timestamptz;
  v_occurrence integer;
  v_deduct_days numeric(5,4);
BEGIN
  SELECT *
  INTO v_day
  FROM public.hr_attendance_days
  WHERE id = p_attendance_day_id;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  -- Resolve only the two schedule values that the Legacy early-leave branch reads
  -- from company settings: official end and official daily duration.
  IF v_day.custom_schedule_id IS NOT NULL THEN
    v_scheduled_end := v_day.custom_scheduled_end;
    v_scheduled_minutes := v_day.custom_scheduled_minutes;
  ELSE
    SELECT *
    INTO v_schedule
    FROM public.resolve_employee_custom_schedule(v_day.employee_id, v_day.shift_date);

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Batch 3B2 custom path invoked without an effective custom schedule';
    END IF;

    IF NOT v_schedule.is_working_day THEN
      RAISE EXCEPTION 'Batch 3B2 refuses early-leave penalty calculation on a custom non-working day';
    END IF;

    v_scheduled_end := v_schedule.end_time;
    v_scheduled_minutes := v_schedule.scheduled_minutes;
  END IF;

  IF v_scheduled_end IS NULL OR COALESCE(v_scheduled_minutes, 0) <= 0 THEN
    RAISE EXCEPTION 'Batch 3B2 custom attendance snapshot is incomplete for attendance day %', p_attendance_day_id;
  END IF;

  -- Let the exact Legacy engine own late, absence, occurrence, rule selection,
  -- cleanup and every non-schedule policy. We replace only its auto-generated
  -- early-leave instance inside this same transaction.
  SELECT public.process_attendance_penalties_legacy(p_attendance_day_id)
  INTO v_legacy_count;

  DELETE FROM public.hr_penalty_instances
  WHERE attendance_day_id = p_attendance_day_id
    AND penalty_type = 'early_leave_unauthorized'
    AND payroll_run_id IS NULL
    AND is_overridden = false
    AND COALESCE(is_manual, false) = false;

  GET DIAGNOSTICS v_removed_legacy_early = ROW_COUNT;
  v_count := GREATEST(0, COALESCE(v_legacy_count, 0) - v_removed_legacy_early);

  IF v_day.checkout_status <> 'early_unauthorized'
     OR COALESCE(v_day.early_leave_minutes, 0) <= 0 THEN
    RETURN v_count;
  END IF;

  v_uncovered_minutes := COALESCE(v_day.early_leave_minutes, 0);
  v_early_start := v_day.punch_out_time;
  v_early_end :=
    (v_day.shift_date::text || ' ' || v_scheduled_end::text)::timestamp
    AT TIME ZONE 'Africa/Cairo';

  -- Preserve the current production overlap algorithm exactly; Batch 3B2 changes
  -- only the end of the official work window, not permission policy.
  FOR v_perm IN
    SELECT *
    FROM public.hr_permission_requests
    WHERE employee_id = v_day.employee_id
      AND permission_date = v_day.shift_date
      AND status = 'approved'
  LOOP
    v_perm_start :=
      (v_day.shift_date::text || ' ' || v_perm.leave_time::text)::timestamp
      AT TIME ZONE 'Africa/Cairo';

    IF v_perm.actual_return IS NOT NULL THEN
      v_perm_end :=
        (v_day.shift_date::text || ' ' || v_perm.actual_return::text)::timestamp
        AT TIME ZONE 'Africa/Cairo';
    ELSIF v_perm.expected_return IS NOT NULL THEN
      v_perm_end :=
        (v_day.shift_date::text || ' ' || v_perm.expected_return::text)::timestamp
        AT TIME ZONE 'Africa/Cairo';
    ELSE
      v_perm_end := v_perm_start
        + (COALESCE(v_perm.duration_minutes, 0) || ' minutes')::interval;
    END IF;

    v_overlap_start := GREATEST(v_early_start, v_perm_start);
    v_overlap_end := LEAST(v_early_end, v_perm_end);

    IF v_overlap_start < v_overlap_end THEN
      v_covered_minutes := v_covered_minutes
        + (EXTRACT(EPOCH FROM (v_overlap_end - v_overlap_start)) / 60)::integer;
    END IF;
  END LOOP;

  v_uncovered_minutes := GREATEST(
    0,
    COALESCE(v_day.early_leave_minutes, 0) - v_covered_minutes
  );

  IF v_uncovered_minutes <= 0 THEN
    RETURN v_count;
  END IF;

  SELECT COUNT(*) + 1
  INTO v_occurrence
  FROM public.hr_penalty_instances pi
  JOIN public.hr_attendance_days ad ON ad.id = pi.attendance_day_id
  WHERE pi.employee_id = v_day.employee_id
    AND pi.penalty_type = 'early_leave_unauthorized'
    AND ad.shift_date BETWEEN date_trunc('month', v_day.shift_date)::date
                          AND (date_trunc('month', v_day.shift_date) + interval '1 month - 1 day')::date
    AND pi.attendance_day_id <> p_attendance_day_id;

  v_deduct_days := ROUND(
    (v_uncovered_minutes::numeric / v_scheduled_minutes::numeric),
    4
  );

  INSERT INTO public.hr_penalty_instances (
    employee_id,
    attendance_day_id,
    penalty_rule_id,
    penalty_type,
    occurrence_in_month,
    deduction_type,
    deduction_days,
    deduction_minutes
  ) VALUES (
    v_day.employee_id,
    p_attendance_day_id,
    NULL,
    'early_leave_unauthorized',
    v_occurrence,
    'custom_minutes',
    v_deduct_days,
    v_uncovered_minutes
  );

  RETURN v_count + 1;
END;
$function$;

REVOKE ALL ON FUNCTION public.process_attendance_penalties_custom_early_leave(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.process_attendance_penalties(
  p_attendance_day_id uuid
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_day public.hr_attendance_days%ROWTYPE;
  v_schedule record;
  v_has_custom_schedule boolean := false;
  v_is_custom_working_day boolean := false;
BEGIN
  IF NOT public.hr_variable_schedules_v2_runtime_enabled() THEN
    RETURN public.process_attendance_penalties_legacy(p_attendance_day_id);
  END IF;

  SELECT *
  INTO v_day
  FROM public.hr_attendance_days
  WHERE id = p_attendance_day_id;

  IF NOT FOUND THEN
    RETURN public.process_attendance_penalties_legacy(p_attendance_day_id);
  END IF;

  -- Late and absence penalties do not consume schedule duration/end here, so keep
  -- them on the exact Legacy engine even for a custom-schedule employee.
  IF v_day.checkout_status <> 'early_unauthorized'
     OR COALESCE(v_day.early_leave_minutes, 0) <= 0 THEN
    RETURN public.process_attendance_penalties_legacy(p_attendance_day_id);
  END IF;

  IF v_day.custom_schedule_id IS NOT NULL THEN
    v_has_custom_schedule := true;
    v_is_custom_working_day :=
      COALESCE(v_day.custom_scheduled_minutes, 0) > 0
      AND v_day.custom_scheduled_end IS NOT NULL;
  ELSE
    SELECT *
    INTO v_schedule
    FROM public.resolve_employee_custom_schedule(v_day.employee_id, v_day.shift_date);

    IF FOUND THEN
      v_has_custom_schedule := true;
      v_is_custom_working_day :=
        v_schedule.is_working_day
        AND COALESCE(v_schedule.scheduled_minutes, 0) > 0
        AND v_schedule.end_time IS NOT NULL;
    END IF;
  END IF;

  IF NOT v_has_custom_schedule THEN
    RETURN public.process_attendance_penalties_legacy(p_attendance_day_id);
  END IF;

  IF NOT v_is_custom_working_day THEN
    RAISE EXCEPTION 'Batch 3B2 refuses unauthorized early-leave penalty processing on a custom non-working day';
  END IF;

  RETURN public.process_attendance_penalties_custom_early_leave(p_attendance_day_id);
END;
$function$;

COMMENT ON FUNCTION public.process_attendance_penalties(uuid) IS
  'V2 compatibility wrapper: exact Legacy penalties except custom-schedule unauthorized early leave uses custom end/minutes; custom off-days fail closed.';

REVOKE ALL ON FUNCTION public.process_attendance_penalties(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.process_attendance_penalties(uuid)
  TO PUBLIC, anon, authenticated, service_role;

COMMIT;
