-- =============================================================================
-- EDARA — Employee Work Schedules M4B
-- Snapshot-aware attendance penalties and leave settlement.
--
-- Disabled mode remains byte-equivalent to production through cloned helpers.
-- Enabled mode changes schedule inputs only; penalty rules, occurrences,
-- payroll locks, leave balances, and status logic remain scoped as before.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '90s';

DO $preflight$
DECLARE
  v_hash TEXT;
BEGIN
  IF to_regprocedure('public.ensure_attendance_schedule_snapshot(uuid)') IS NULL
     OR to_regprocedure('public.hr_employee_work_schedules_activation_ready()') IS NULL THEN
    RAISE EXCEPTION 'M4B preflight failed: M2 snapshot helper/activation guard is missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'M4B preflight failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'M4B preflight failed: no runtime schedule/snapshot data is expected';
  END IF;

  IF to_regprocedure('public.process_attendance_penalties_legacy_20260805(uuid)') IS NOT NULL
     OR to_regprocedure('public.process_attendance_penalties_scheduled(uuid)') IS NOT NULL
     OR to_regprocedure('public.settle_attendance_day_against_leave_legacy_20260805(uuid,boolean)') IS NOT NULL
     OR to_regprocedure('public.settle_attendance_day_against_leave_scheduled(uuid,boolean)') IS NOT NULL THEN
    RAISE EXCEPTION 'M4B preflight failed: one or more M4B helpers already exist';
  END IF;

  SELECT md5(pg_get_functiondef('public.process_attendance_penalties(uuid)'::regprocedure)) INTO v_hash;
  IF v_hash <> '7ea1046753bbcfbbb47bcb35c27f986e' THEN
    RAISE EXCEPTION 'M4B preflight failed: process_attendance_penalties drifted (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.settle_attendance_day_against_leave(uuid,boolean)'::regprocedure)) INTO v_hash;
  IF v_hash <> 'c5724ab559a12ca470bcd0bae8ad8206' THEN
    RAISE EXCEPTION 'M4B preflight failed: settle_attendance_day_against_leave drifted (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.reprocess_attendance_day_penalties(uuid)'::regprocedure)) INTO v_hash;
  IF v_hash <> '5d1d271f18585e9d2381b9d1c12fa684' THEN
    RAISE EXCEPTION 'M4B preflight failed: reprocess_attendance_day_penalties drifted (%)', v_hash;
  END IF;
END;
$preflight$;

DO $clone_legacy$
DECLARE
  v_definition TEXT;
BEGIN
  SELECT pg_get_functiondef('public.process_attendance_penalties(uuid)'::regprocedure)
  INTO v_definition;
  v_definition := replace(
    v_definition,
    'FUNCTION public.process_attendance_penalties(',
    'FUNCTION public.process_attendance_penalties_legacy_20260805('
  );
  EXECUTE v_definition;

  SELECT pg_get_functiondef('public.settle_attendance_day_against_leave(uuid,boolean)'::regprocedure)
  INTO v_definition;
  v_definition := replace(
    v_definition,
    'FUNCTION public.settle_attendance_day_against_leave(',
    'FUNCTION public.settle_attendance_day_against_leave_legacy_20260805('
  );
  EXECUTE v_definition;
END;
$clone_legacy$;

REVOKE ALL ON FUNCTION public.process_attendance_penalties_legacy_20260805(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.settle_attendance_day_against_leave_legacy_20260805(UUID, BOOLEAN)
  FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Schedule-aware penalties
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.process_attendance_penalties_scheduled(
  p_attendance_day_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_day public.hr_attendance_days%ROWTYPE;
  v_rule public.hr_penalty_rules%ROWTYPE;
  v_penalty_type public.hr_penalty_type;
  v_minutes INTEGER;
  v_occurrence INTEGER;
  v_deduct_days NUMERIC(5,4);
  v_count INTEGER := 0;
  v_month_start DATE;
  v_month_end DATE;
  v_work_hours NUMERIC;
BEGIN
  SELECT * INTO v_day
  FROM public.hr_attendance_days
  WHERE id = p_attendance_day_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  IF v_day.schedule_snapshot_at IS NULL THEN
    PERFORM public.ensure_attendance_schedule_snapshot(v_day.id);

    SELECT * INTO v_day
    FROM public.hr_attendance_days
    WHERE id = v_day.id
    FOR UPDATE;
  END IF;

  -- Never create automatic monetary effects on a non-working date. Clear only
  -- unposted, non-overridden, auto-generated penalties and preserve manual or
  -- payroll-linked records exactly as the current engine does.
  IF v_day.schedule_day_kind <> 'work_day' THEN
    DELETE FROM public.hr_penalty_instances
    WHERE attendance_day_id = p_attendance_day_id
      AND payroll_run_id IS NULL
      AND is_overridden = false
      AND COALESCE(is_manual, false) = false;

    RETURN 0;
  END IF;

  IF v_day.scheduled_minutes IS NULL OR v_day.scheduled_minutes <= 0
     OR v_day.scheduled_end_at IS NULL THEN
    RAISE EXCEPTION 'Attendance day % has an invalid work-day schedule snapshot', v_day.id;
  END IF;

  v_work_hours := v_day.scheduled_minutes / 60.0;
  v_month_start := date_trunc('month', v_day.shift_date)::DATE;
  v_month_end := (date_trunc('month', v_day.shift_date) + INTERVAL '1 month - 1 day')::DATE;

  DELETE FROM public.hr_penalty_instances
  WHERE attendance_day_id = p_attendance_day_id
    AND payroll_run_id IS NULL
    AND is_overridden = false
    AND COALESCE(is_manual, false) = false;

  -- Late arrival: preserve rule selection and occurrence semantics.
  IF v_day.late_minutes > 0
     AND v_day.status IN ('present', 'late', 'half_day') THEN
    v_penalty_type := 'late';

    IF v_day.status <> 'half_day' THEN
      v_minutes := v_day.late_minutes;

      SELECT COUNT(*) + 1 INTO v_occurrence
      FROM public.hr_penalty_instances pi
      JOIN public.hr_attendance_days ad ON ad.id = pi.attendance_day_id
      WHERE pi.employee_id = v_day.employee_id
        AND pi.penalty_type = v_penalty_type
        AND ad.shift_date BETWEEN v_month_start AND v_month_end
        AND pi.attendance_day_id <> p_attendance_day_id;

      SELECT * INTO v_rule
      FROM public.hr_penalty_rules
      WHERE penalty_type = v_penalty_type
        AND is_active = true
        AND v_minutes >= min_minutes
        AND (max_minutes IS NULL OR v_minutes < max_minutes)
        AND v_occurrence >= occurrence_from
        AND (occurrence_to IS NULL OR v_occurrence <= occurrence_to)
      ORDER BY sort_order DESC
      LIMIT 1;

      IF FOUND THEN
        v_deduct_days := CASE v_rule.deduction_type
          WHEN 'quarter_day' THEN 0.25
          WHEN 'half_day' THEN 0.5
          WHEN 'full_day' THEN 1.0
          ELSE 0
        END;

        INSERT INTO public.hr_penalty_instances (
          employee_id,
          attendance_day_id,
          penalty_rule_id,
          penalty_type,
          occurrence_in_month,
          deduction_type,
          deduction_days
        ) VALUES (
          v_day.employee_id,
          p_attendance_day_id,
          v_rule.id,
          v_penalty_type,
          v_occurrence,
          v_rule.deduction_type,
          v_deduct_days
        );

        v_count := v_count + 1;
      END IF;
    END IF;
  END IF;

  -- Unauthorized absence: preserve existing rule/occurrence semantics.
  IF v_day.status = 'absent_unauthorized' THEN
    v_penalty_type := 'absent_unauthorized';

    SELECT COUNT(*) + 1 INTO v_occurrence
    FROM public.hr_penalty_instances pi
    JOIN public.hr_attendance_days ad ON ad.id = pi.attendance_day_id
    WHERE pi.employee_id = v_day.employee_id
      AND pi.penalty_type = v_penalty_type
      AND ad.shift_date BETWEEN v_month_start AND v_month_end
      AND pi.attendance_day_id <> p_attendance_day_id;

    SELECT * INTO v_rule
    FROM public.hr_penalty_rules
    WHERE penalty_type = v_penalty_type
      AND is_active = true
      AND v_occurrence >= occurrence_from
      AND (occurrence_to IS NULL OR v_occurrence <= occurrence_to)
    ORDER BY sort_order DESC
    LIMIT 1;

    IF FOUND THEN
      v_deduct_days := CASE v_rule.deduction_type
        WHEN 'quarter_day' THEN 0.25
        WHEN 'half_day' THEN 0.5
        WHEN 'full_day' THEN 1.0
        ELSE 0
      END;

      INSERT INTO public.hr_penalty_instances (
        employee_id,
        attendance_day_id,
        penalty_rule_id,
        penalty_type,
        occurrence_in_month,
        deduction_type,
        deduction_days
      ) VALUES (
        v_day.employee_id,
        p_attendance_day_id,
        v_rule.id,
        v_penalty_type,
        v_occurrence,
        v_rule.deduction_type,
        v_deduct_days
      );

      v_count := v_count + 1;
    END IF;
  END IF;

  -- Unauthorized early leave: preserve permission-overlap semantics; replace
  -- only company end/hour inputs with the immutable day snapshot.
  IF v_day.checkout_status = 'early_unauthorized'
     AND COALESCE(v_day.early_leave_minutes, 0) > 0 THEN
    v_penalty_type := 'early_leave_unauthorized';

    DECLARE
      v_uncovered_minutes INTEGER := COALESCE(v_day.early_leave_minutes, 0);
      v_covered_minutes INTEGER := 0;
      v_perm RECORD;
      v_early_start TIMESTAMPTZ;
      v_early_end TIMESTAMPTZ;
      v_perm_start TIMESTAMPTZ;
      v_perm_end TIMESTAMPTZ;
      v_overlap_start TIMESTAMPTZ;
      v_overlap_end TIMESTAMPTZ;
    BEGIN
      v_early_start := v_day.punch_out_time;
      v_early_end := v_day.scheduled_end_at;

      FOR v_perm IN
        SELECT *
        FROM public.hr_permission_requests
        WHERE employee_id = v_day.employee_id
          AND permission_date = v_day.shift_date
          AND status = 'approved'
      LOOP
        v_perm_start := (v_day.shift_date + v_perm.leave_time) AT TIME ZONE 'Africa/Cairo';

        IF v_perm.actual_return IS NOT NULL THEN
          v_perm_end := (v_day.shift_date + v_perm.actual_return) AT TIME ZONE 'Africa/Cairo';
        ELSIF v_perm.expected_return IS NOT NULL THEN
          v_perm_end := (v_day.shift_date + v_perm.expected_return) AT TIME ZONE 'Africa/Cairo';
        ELSE
          v_perm_end := v_perm_start + make_interval(mins => COALESCE(v_perm.duration_minutes, 0));
        END IF;

        v_overlap_start := GREATEST(v_early_start, v_perm_start);
        v_overlap_end := LEAST(v_early_end, v_perm_end);

        IF v_overlap_start < v_overlap_end THEN
          v_covered_minutes := v_covered_minutes
            + (EXTRACT(EPOCH FROM (v_overlap_end - v_overlap_start)) / 60)::INTEGER;
        END IF;
      END LOOP;

      v_uncovered_minutes := GREATEST(
        0,
        COALESCE(v_day.early_leave_minutes, 0) - v_covered_minutes
      );

      IF v_uncovered_minutes > 0 THEN
        SELECT COUNT(*) + 1 INTO v_occurrence
        FROM public.hr_penalty_instances pi
        JOIN public.hr_attendance_days ad ON ad.id = pi.attendance_day_id
        WHERE pi.employee_id = v_day.employee_id
          AND pi.penalty_type = v_penalty_type
          AND ad.shift_date BETWEEN v_month_start AND v_month_end
          AND pi.attendance_day_id <> p_attendance_day_id;

        v_deduct_days := ROUND(
          (v_uncovered_minutes / v_day.scheduled_minutes::NUMERIC),
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
          v_penalty_type,
          v_occurrence,
          'custom_minutes',
          v_deduct_days,
          v_uncovered_minutes
        );

        v_count := v_count + 1;
      END IF;
    END;
  END IF;

  RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.process_attendance_penalties_scheduled(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Schedule-aware leave settlement
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.settle_attendance_day_against_leave_scheduled(
  p_attendance_day_id UUID,
  p_force BOOLEAN DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_day public.hr_attendance_days%ROWTYPE;
  v_leave_req public.hr_leave_requests%ROWTYPE;
  v_work_hours NUMERIC;
  v_new_status public.hr_attendance_status;
BEGIN
  SELECT * INTO v_day
  FROM public.hr_attendance_days
  WHERE id = p_attendance_day_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_day.source_leave_request_id IS NULL
     OR v_day.punch_in_time IS NULL
     OR v_day.punch_out_time IS NULL THEN
    RETURN;
  END IF;

  IF COALESCE(v_day.leave_balance_restored, false) THEN
    RETURN;
  END IF;

  IF NOT p_force AND COALESCE(v_day.is_manually_locked, false) THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_payroll_runs pr
    JOIN public.hr_payroll_periods pp ON pp.id = pr.period_id
    JOIN public.hr_payroll_lines pl ON pl.payroll_run_id = pr.id
    WHERE pl.employee_id = v_day.employee_id
      AND pr.status IN ('approved', 'paid')
      AND v_day.shift_date BETWEEN pp.start_date AND pp.end_date
  ) THEN
    RETURN;
  END IF;

  SELECT * INTO v_leave_req
  FROM public.hr_leave_requests
  WHERE id = v_day.source_leave_request_id;

  IF NOT FOUND OR v_leave_req.status <> 'approved' THEN
    RETURN;
  END IF;

  IF v_day.schedule_snapshot_at IS NULL THEN
    PERFORM public.ensure_attendance_schedule_snapshot(v_day.id);

    SELECT * INTO v_day
    FROM public.hr_attendance_days
    WHERE id = v_day.id
    FOR UPDATE;
  END IF;

  IF v_day.schedule_day_kind <> 'work_day' THEN
    -- Leave accounting on a non-working date is a policy/data reconciliation,
    -- not an automatic hours calculation. Preserve balances and request review.
    UPDATE public.hr_attendance_days
    SET review_status = CASE
          WHEN review_status = 'reviewed' THEN 'reviewed'::public.hr_review_status
          ELSE 'needs_review'::public.hr_review_status
        END,
        updated_at = now()
    WHERE id = v_day.id;

    RETURN;
  END IF;

  IF v_day.scheduled_minutes IS NULL OR v_day.scheduled_minutes <= 0 THEN
    RAISE EXCEPTION 'Attendance day % has invalid scheduled minutes', v_day.id;
  END IF;

  v_work_hours := v_day.scheduled_minutes / 60.0;

  IF COALESCE(v_day.effective_hours, 0) >= v_work_hours THEN
    UPDATE public.hr_leave_balances
    SET used_days = GREATEST(0, used_days - 1),
        updated_at = now()
    WHERE employee_id = v_day.employee_id
      AND leave_type_id = v_leave_req.leave_type_id
      AND year = EXTRACT(YEAR FROM v_leave_req.start_date)::INTEGER;

    v_new_status := 'present';
    IF COALESCE(v_day.late_minutes, 0) > 0 THEN
      v_new_status := 'late';
    END IF;

    UPDATE public.hr_attendance_days
    SET status = v_new_status,
        leave_balance_restored = true,
        leave_balance_restored_at = now(),
        updated_at = now()
    WHERE id = p_attendance_day_id;
  ELSE
    v_new_status := 'present';
    IF COALESCE(v_day.late_minutes, 0) > 0 THEN
      v_new_status := 'late';
    END IF;

    UPDATE public.hr_attendance_days
    SET status = v_new_status,
        day_value = LEAST(
          1.00,
          ROUND((COALESCE(v_day.effective_hours, 0) / v_work_hours)::NUMERIC, 2)
        ),
        leave_balance_restored = false,
        updated_at = now()
    WHERE id = p_attendance_day_id;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.settle_attendance_day_against_leave_scheduled(UUID, BOOLEAN)
  FROM PUBLIC, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Public wrappers. reprocess_attendance_day_penalties remains unchanged and
-- continues to call the public process_attendance_penalties function.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.process_attendance_penalties(
  p_attendance_day_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF NOT public.hr_employee_work_schedules_enabled() THEN
    RETURN public.process_attendance_penalties_legacy_20260805(p_attendance_day_id);
  END IF;

  RETURN public.process_attendance_penalties_scheduled(p_attendance_day_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.settle_attendance_day_against_leave(
  p_attendance_day_id UUID,
  p_force BOOLEAN DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF NOT public.hr_employee_work_schedules_enabled() THEN
    PERFORM public.settle_attendance_day_against_leave_legacy_20260805(
      p_attendance_day_id,
      p_force
    );
    RETURN;
  END IF;

  PERFORM public.settle_attendance_day_against_leave_scheduled(
    p_attendance_day_id,
    p_force
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.process_attendance_penalties(UUID)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.settle_attendance_day_against_leave(UUID, BOOLEAN)
  TO anon, authenticated, service_role;

DO $assertions$
DECLARE
  v_definition TEXT;
  v_hash TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'M4B assertion failed: feature/readiness changed';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'M4B assertion failed: migration changed runtime data';
  END IF;

  SELECT pg_get_functiondef('public.process_attendance_penalties_scheduled(uuid)'::regprocedure)
  INTO v_definition;
  IF v_definition ILIKE '%hr.work_hours_per_day%'
     OR v_definition ILIKE '%hr.work_end_time%'
     OR v_definition NOT ILIKE '%scheduled_minutes%'
     OR v_definition NOT ILIKE '%scheduled_end_at%' THEN
    RAISE EXCEPTION 'M4B assertion failed: scheduled penalty engine bypasses snapshot inputs';
  END IF;

  SELECT pg_get_functiondef('public.settle_attendance_day_against_leave_scheduled(uuid,boolean)'::regprocedure)
  INTO v_definition;
  IF v_definition ILIKE '%hr.work_hours_per_day%'
     OR v_definition NOT ILIKE '%scheduled_minutes%' THEN
    RAISE EXCEPTION 'M4B assertion failed: scheduled leave settlement bypasses snapshot duration';
  END IF;

  -- Reprocess helper is intentionally not rewritten; it should remain exact and
  -- dispatch dynamically through the replaced public penalty function.
  SELECT md5(pg_get_functiondef('public.reprocess_attendance_day_penalties(uuid)'::regprocedure))
  INTO v_hash;
  IF v_hash <> '5d1d271f18585e9d2381b9d1c12fa684' THEN
    RAISE EXCEPTION 'M4B assertion failed: reprocess helper changed (%)', v_hash;
  END IF;
END;
$assertions$;

COMMIT;
