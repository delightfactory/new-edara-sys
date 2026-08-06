-- =============================================================================
-- EDARA — Employee Work Schedules: schedule-aware leave integration
--
-- Narrow scope:
--   1. derive leave days server-side from the employee's resolved work days;
--   2. keep pending/used balances aligned with the same derived count;
--   3. synchronize final approval AFTER the approved row is persisted;
--   4. create/link attendance with a complete immutable schedule snapshot;
--   5. exclude salary-affecting unpaid leave from paid attendance in payroll.
--
-- Disabled mode preserves the existing leave submission/approval/sync behavior.
-- This migration does not enable the feature, seed schedules, backfill leave or
-- attendance data, recalculate payroll, or modify approved/paid payroll runs.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

DO $preflight$
DECLARE
  v_hash TEXT;
BEGIN
  IF to_regprocedure('public.hr_employee_work_schedules_enabled()') IS NULL
     OR to_regprocedure('public.hr_employee_work_schedules_activation_ready()') IS NULL
     OR to_regprocedure('public.resolve_employee_work_schedule_core(uuid,date,boolean)') IS NULL
     OR to_regprocedure('public.normalize_attendance_day_schedule_metrics(uuid)') IS NULL
     OR to_regprocedure('public.calculate_employee_payroll_scheduled(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'Leave integration preflight failed: schedule runtime is incomplete';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Leave integration preflight failed: feature/readiness must remain false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Leave integration preflight failed: no schedule/snapshot runtime data is expected';
  END IF;

  IF to_regprocedure('public.sync_approved_leave_to_attendance_legacy_20260806(uuid)') IS NOT NULL
     OR to_regprocedure('public.cleanup_approved_leave_sync_legacy_20260806(uuid)') IS NOT NULL
     OR to_regprocedure('public.calculate_employee_leave_workdays(uuid,date,date,boolean)') IS NOT NULL
     OR to_regprocedure('public.preview_employee_leave_workday_count(uuid,date,date)') IS NOT NULL
     OR to_regprocedure('public.sync_approved_leave_to_attendance_scheduled(uuid)') IS NOT NULL
     OR to_regprocedure('public.cleanup_approved_leave_sync_scheduled(uuid)') IS NOT NULL
     OR to_regprocedure('public.sync_approved_leave_after_status_change()') IS NOT NULL THEN
    RAISE EXCEPTION 'Leave integration preflight failed: one or more target functions already exist';
  END IF;

  SELECT md5(pg_get_functiondef('public.handle_leave_submission()'::regprocedure)) INTO v_hash;
  IF v_hash <> '5a7810b0020444b79288cb06a2c341f1' THEN
    RAISE EXCEPTION 'Leave integration preflight failed: handle_leave_submission drifted (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.handle_leave_approval()'::regprocedure)) INTO v_hash;
  IF v_hash <> 'c889ea273497d81136400be80ddb15b0' THEN
    RAISE EXCEPTION 'Leave integration preflight failed: handle_leave_approval drifted (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.sync_approved_leave_to_attendance(uuid)'::regprocedure)) INTO v_hash;
  IF v_hash <> '3c3d2222e3d24ac1246fdff05799f9be' THEN
    RAISE EXCEPTION 'Leave integration preflight failed: leave sync drifted (%)', v_hash;
  END IF;

  SELECT md5(pg_get_functiondef('public.cleanup_approved_leave_sync(uuid)'::regprocedure)) INTO v_hash;
  IF v_hash <> '2b26c6150df6ef8ae045c7874d66d316' THEN
    RAISE EXCEPTION 'Leave integration preflight failed: leave cleanup drifted (%)', v_hash;
  END IF;
END;
$preflight$;

-- Preserve the exact normal-function behavior for disabled mode.
DO $clone_legacy$
DECLARE
  v_definition TEXT;
BEGIN
  SELECT pg_get_functiondef('public.sync_approved_leave_to_attendance(uuid)'::regprocedure)
  INTO v_definition;
  v_definition := replace(
    v_definition,
    'FUNCTION public.sync_approved_leave_to_attendance(',
    'FUNCTION public.sync_approved_leave_to_attendance_legacy_20260806('
  );
  EXECUTE v_definition;

  SELECT pg_get_functiondef('public.cleanup_approved_leave_sync(uuid)'::regprocedure)
  INTO v_definition;
  v_definition := replace(
    v_definition,
    'FUNCTION public.cleanup_approved_leave_sync(',
    'FUNCTION public.cleanup_approved_leave_sync_legacy_20260806('
  );
  EXECUTE v_definition;
END;
$clone_legacy$;

REVOKE ALL ON FUNCTION public.sync_approved_leave_to_attendance_legacy_20260806(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cleanup_approved_leave_sync_legacy_20260806(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- One server-side definition of chargeable leave days.
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.calculate_employee_leave_workdays(
  p_employee_id UUID,
  p_start_date DATE,
  p_end_date DATE,
  p_use_custom BOOLEAN DEFAULT true
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_hire_date DATE;
  v_termination_date DATE;
  v_count INTEGER;
BEGIN
  IF p_employee_id IS NULL OR p_start_date IS NULL OR p_end_date IS NULL THEN
    RAISE EXCEPTION 'employee_id, start_date, and end_date are required';
  END IF;

  IF p_end_date < p_start_date THEN
    RAISE EXCEPTION 'Leave end date cannot be before start date';
  END IF;

  IF EXTRACT(YEAR FROM p_start_date)::INTEGER
     <> EXTRACT(YEAR FROM p_end_date)::INTEGER THEN
    RAISE EXCEPTION 'A leave request cannot cross calendar years';
  END IF;

  SELECT e.hire_date, e.termination_date
  INTO v_hire_date, v_termination_date
  FROM public.hr_employees e
  WHERE e.id = p_employee_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Employee % does not exist', p_employee_id;
  END IF;

  IF v_hire_date IS NOT NULL AND p_start_date < v_hire_date THEN
    RAISE EXCEPTION 'Leave cannot start before the employee hire date';
  END IF;

  IF v_termination_date IS NOT NULL AND p_end_date > v_termination_date THEN
    RAISE EXCEPTION 'Leave cannot extend beyond the employee termination date';
  END IF;

  SELECT count(*)::INTEGER
  INTO v_count
  FROM generate_series(p_start_date, p_end_date, INTERVAL '1 day') g(target_date)
  CROSS JOIN LATERAL public.resolve_employee_work_schedule_core(
    p_employee_id,
    g.target_date::DATE,
    COALESCE(p_use_custom, false)
  ) r
  WHERE r.day_kind = 'work_day';

  RETURN COALESCE(v_count, 0);
END;
$function$;

REVOKE ALL ON FUNCTION public.calculate_employee_leave_workdays(UUID, DATE, DATE, BOOLEAN)
  FROM PUBLIC, anon, authenticated, service_role;

-- UI preview follows the active runtime contract. While disabled, it preserves
-- the existing inclusive-calendar-day estimate; when enabled, it uses schedules.
CREATE FUNCTION public.preview_employee_leave_workday_count(
  p_employee_id UUID,
  p_start_date DATE,
  p_end_date DATE
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_actor UUID := auth.uid();
  v_is_self BOOLEAN;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.hr_employees e
    WHERE e.id = p_employee_id
      AND e.user_id = v_actor
  ) INTO v_is_self;

  IF NOT v_is_self
     AND NOT public.check_permission(v_actor, 'hr.leaves.request')
     AND NOT public.check_permission(v_actor, 'hr.leaves.create')
     AND NOT public.check_permission(v_actor, 'hr.leaves.read')
     AND NOT public.check_permission(v_actor, 'hr.leaves.approve') THEN
    RAISE EXCEPTION 'لا تملك صلاحية معاينة أيام إجازة هذا الموظف';
  END IF;

  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN
    RETURN 0;
  END IF;

  IF NOT public.hr_employee_work_schedules_enabled() THEN
    RETURN (p_end_date - p_start_date) + 1;
  END IF;

  RETURN public.calculate_employee_leave_workdays(
    p_employee_id,
    p_start_date,
    p_end_date,
    true
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.preview_employee_leave_workday_count(UUID, DATE, DATE)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.preview_employee_leave_workday_count(UUID, DATE, DATE)
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Submission trigger: exact legacy branch while disabled; schedule-derived days
-- and atomic balance reservation while enabled.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_leave_submission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_has_balance BOOLEAN;
  v_deducts_from_balance BOOLEAN;
  v_remaining NUMERIC;
  v_days INTEGER;
  v_balance public.hr_leave_balances%ROWTYPE;
BEGIN
  IF NOT public.hr_employee_work_schedules_enabled() THEN
    SELECT has_balance INTO v_has_balance
    FROM public.hr_leave_types WHERE id = NEW.leave_type_id;

    IF v_has_balance THEN
      SELECT remaining_days INTO v_remaining
      FROM public.hr_leave_balances
      WHERE employee_id = NEW.employee_id
        AND leave_type_id = NEW.leave_type_id
        AND year = EXTRACT(YEAR FROM NEW.start_date)::INTEGER;

      IF v_remaining IS NULL OR (v_remaining - NEW.days_count) < 0 THEN
        RAISE EXCEPTION 'رصيد الإجازة غير كافٍ. المتبقي: %', COALESCE(v_remaining, 0);
      END IF;

      UPDATE public.hr_leave_balances
      SET pending_days = pending_days + NEW.days_count,
          updated_at = now()
      WHERE employee_id = NEW.employee_id
        AND leave_type_id = NEW.leave_type_id
        AND year = EXTRACT(YEAR FROM NEW.start_date)::INTEGER;
    END IF;

    RETURN NEW;
  END IF;

  v_days := public.calculate_employee_leave_workdays(
    NEW.employee_id,
    NEW.start_date,
    NEW.end_date,
    true
  );

  IF v_days <= 0 THEN
    RAISE EXCEPTION 'فترة الإجازة لا تحتوي على أي يوم عمل مقرر للموظف';
  END IF;

  NEW.days_count := v_days;

  SELECT lt.has_balance, lt.deducts_from_balance
  INTO v_has_balance, v_deducts_from_balance
  FROM public.hr_leave_types lt
  WHERE lt.id = NEW.leave_type_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'نوع الإجازة غير موجود';
  END IF;

  IF COALESCE(v_has_balance, false) AND COALESCE(v_deducts_from_balance, false) THEN
    SELECT * INTO v_balance
    FROM public.hr_leave_balances b
    WHERE b.employee_id = NEW.employee_id
      AND b.leave_type_id = NEW.leave_type_id
      AND b.year = EXTRACT(YEAR FROM NEW.start_date)::INTEGER
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'لا يوجد رصيد إجازة مسجل للموظف في السنة المطلوبة';
    END IF;

    v_remaining := COALESCE(v_balance.total_days, 0)
      + COALESCE(v_balance.carried_forward, 0)
      - COALESCE(v_balance.used_days, 0)
      - COALESCE(v_balance.pending_days, 0);

    IF v_remaining < v_days THEN
      RAISE EXCEPTION 'رصيد الإجازة غير كافٍ. المتبقي: %', GREATEST(v_remaining, 0);
    END IF;

    UPDATE public.hr_leave_balances
    SET pending_days = COALESCE(pending_days, 0) + v_days,
        remaining_days = GREATEST(0,
          COALESCE(total_days, 0) + COALESCE(carried_forward, 0)
          - COALESCE(used_days, 0) - (COALESCE(pending_days, 0) + v_days)
        ),
        updated_at = now()
    WHERE id = v_balance.id;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.handle_leave_submission()
  FROM PUBLIC, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Approval trigger: exact legacy branch while disabled. Enabled mode keeps core
-- request scope immutable, recalculates the reserved count, and leaves attendance
-- synchronization to an AFTER UPDATE trigger so the approved row is visible.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_leave_approval()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_approval_levels INTEGER;
  v_has_balance BOOLEAN;
  v_deducts_from_balance BOOLEAN;
  v_days INTEGER;
  v_available NUMERIC;
  v_balance public.hr_leave_balances%ROWTYPE;
BEGIN
  IF NOT public.hr_employee_work_schedules_enabled() THEN
    SELECT approval_levels INTO v_approval_levels
    FROM public.hr_leave_types WHERE id = NEW.leave_type_id;

    IF NEW.status = 'approved_supervisor' AND OLD.status = 'pending_supervisor' THEN
      NEW.supervisor_action_at := COALESCE(NEW.supervisor_action_at, now());
    END IF;

    IF NEW.status = 'approved' AND OLD.status = 'pending_hr' THEN
      NEW.hr_action_at := COALESCE(NEW.hr_action_at, now());
    END IF;

    IF NEW.status = 'rejected' AND OLD.status <> 'rejected' THEN
      NEW.rejected_at := COALESCE(NEW.rejected_at, now());
      IF NEW.rejected_by IS NULL THEN
        SELECT id INTO NEW.rejected_by
        FROM public.hr_employees WHERE user_id = auth.uid() LIMIT 1;
      END IF;
    END IF;

    IF NEW.status = 'approved_supervisor' AND v_approval_levels = 1 THEN
      NEW.status := 'approved';
    END IF;

    IF NEW.status = 'approved_supervisor' AND v_approval_levels = 2 THEN
      NEW.status := 'pending_hr';
    END IF;

    IF NEW.status = 'approved' AND OLD.status <> 'approved' THEN
      UPDATE public.hr_leave_balances
      SET used_days = used_days + NEW.days_count,
          pending_days = GREATEST(0, pending_days - NEW.days_count),
          updated_at = now()
      WHERE employee_id = NEW.employee_id
        AND leave_type_id = NEW.leave_type_id
        AND year = EXTRACT(YEAR FROM NEW.start_date)::INTEGER;

      PERFORM public.sync_approved_leave_to_attendance(NEW.id);
    END IF;

    IF NEW.status IN ('rejected', 'cancelled')
       AND OLD.status IN ('pending_supervisor', 'approved_supervisor', 'pending_hr') THEN
      UPDATE public.hr_leave_balances
      SET pending_days = GREATEST(0, pending_days - NEW.days_count),
          updated_at = now()
      WHERE employee_id = NEW.employee_id
        AND leave_type_id = NEW.leave_type_id
        AND year = EXTRACT(YEAR FROM NEW.start_date)::INTEGER;
    END IF;

    IF NEW.status = 'cancelled' AND OLD.status = 'approved' THEN
      IF EXISTS (
        SELECT 1
        FROM public.hr_payroll_runs pr
        JOIN public.hr_payroll_periods pp ON pp.id = pr.period_id
        JOIN public.hr_payroll_lines pl ON pl.payroll_run_id = pr.id
        WHERE pl.employee_id = NEW.employee_id
          AND pr.status IN ('approved', 'paid')
          AND pp.start_date <= NEW.end_date
          AND pp.end_date >= NEW.start_date
      ) THEN
        RAISE EXCEPTION 'لا يمكن إلغاء إجازة تتقاطع مع مسير رواتب معتمد أو مدفوع';
      END IF;

      IF EXISTS (
        SELECT 1
        FROM public.hr_attendance_days
        WHERE source_leave_request_id = NEW.id
          AND (COALESCE(leave_balance_restored, false) = true OR punch_in_time IS NOT NULL)
      ) THEN
        RAISE EXCEPTION 'لا يمكن إلغاء إجازة تحتوي على أيام تم حضورها فعليًا أو تمت تسويتها';
      END IF;

      UPDATE public.hr_leave_balances
      SET used_days = GREATEST(0, used_days - NEW.days_count),
          updated_at = now()
      WHERE employee_id = NEW.employee_id
        AND leave_type_id = NEW.leave_type_id
        AND year = EXTRACT(YEAR FROM NEW.start_date)::INTEGER;

      PERFORM public.cleanup_approved_leave_sync(NEW.id);
    END IF;

    RETURN NEW;
  END IF;

  IF NEW.employee_id IS DISTINCT FROM OLD.employee_id
     OR NEW.leave_type_id IS DISTINCT FROM OLD.leave_type_id
     OR NEW.start_date IS DISTINCT FROM OLD.start_date
     OR NEW.end_date IS DISTINCT FROM OLD.end_date THEN
    RAISE EXCEPTION 'لا يمكن تعديل الموظف أو نوع الإجازة أو مدتها بعد تقديم الطلب؛ ألغِ الطلب وأنشئ طلبًا جديدًا';
  END IF;

  SELECT lt.approval_levels, lt.has_balance, lt.deducts_from_balance
  INTO v_approval_levels, v_has_balance, v_deducts_from_balance
  FROM public.hr_leave_types lt
  WHERE lt.id = NEW.leave_type_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'نوع الإجازة غير موجود';
  END IF;

  IF NEW.status = 'approved_supervisor' AND OLD.status = 'pending_supervisor' THEN
    NEW.supervisor_action_at := COALESCE(NEW.supervisor_action_at, now());
  END IF;

  IF NEW.status = 'approved' AND OLD.status = 'pending_hr' THEN
    NEW.hr_action_at := COALESCE(NEW.hr_action_at, now());
  END IF;

  IF NEW.status = 'rejected' AND OLD.status <> 'rejected' THEN
    NEW.rejected_at := COALESCE(NEW.rejected_at, now());
    IF NEW.rejected_by IS NULL THEN
      SELECT id INTO NEW.rejected_by
      FROM public.hr_employees WHERE user_id = auth.uid() LIMIT 1;
    END IF;
  END IF;

  IF NEW.status = 'approved_supervisor' AND v_approval_levels = 1 THEN
    NEW.status := 'approved';
  ELSIF NEW.status = 'approved_supervisor' AND v_approval_levels = 2 THEN
    NEW.status := 'pending_hr';
  END IF;

  IF OLD.status = 'approved' THEN
    NEW.days_count := OLD.days_count;
  ELSE
    v_days := public.calculate_employee_leave_workdays(
      NEW.employee_id,
      NEW.start_date,
      NEW.end_date,
      true
    );

    IF v_days <= 0 THEN
      RAISE EXCEPTION 'فترة الإجازة لا تحتوي على أي يوم عمل مقرر للموظف';
    END IF;

    NEW.days_count := v_days;
  END IF;

  IF COALESCE(v_has_balance, false) AND COALESCE(v_deducts_from_balance, false) THEN
    SELECT * INTO v_balance
    FROM public.hr_leave_balances b
    WHERE b.employee_id = NEW.employee_id
      AND b.leave_type_id = NEW.leave_type_id
      AND b.year = EXTRACT(YEAR FROM NEW.start_date)::INTEGER
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'لا يوجد رصيد إجازة مسجل للموظف في السنة المطلوبة';
    END IF;

    IF OLD.status IN ('draft', 'pending_supervisor', 'approved_supervisor', 'pending_hr')
       AND NEW.status IN ('draft', 'pending_supervisor', 'approved_supervisor', 'pending_hr')
       AND NEW.days_count IS DISTINCT FROM OLD.days_count THEN
      v_available := COALESCE(v_balance.total_days, 0)
        + COALESCE(v_balance.carried_forward, 0)
        - COALESCE(v_balance.used_days, 0)
        - COALESCE(v_balance.pending_days, 0)
        + COALESCE(OLD.days_count, 0);

      IF v_available < NEW.days_count THEN
        RAISE EXCEPTION 'رصيد الإجازة غير كافٍ بعد إعادة احتساب أيام العمل. المتاح: %', GREATEST(v_available, 0);
      END IF;

      UPDATE public.hr_leave_balances
      SET pending_days = GREATEST(0,
            COALESCE(pending_days, 0) - COALESCE(OLD.days_count, 0) + NEW.days_count
          ),
          remaining_days = GREATEST(0,
            COALESCE(total_days, 0) + COALESCE(carried_forward, 0)
            - COALESCE(used_days, 0)
            - GREATEST(0, COALESCE(pending_days, 0) - COALESCE(OLD.days_count, 0) + NEW.days_count)
          ),
          updated_at = now()
      WHERE id = v_balance.id;
    END IF;

    IF NEW.status = 'approved' AND OLD.status <> 'approved' THEN
      v_available := COALESCE(v_balance.total_days, 0)
        + COALESCE(v_balance.carried_forward, 0)
        - COALESCE(v_balance.used_days, 0)
        - COALESCE(v_balance.pending_days, 0)
        + COALESCE(OLD.days_count, 0);

      IF v_available < NEW.days_count THEN
        RAISE EXCEPTION 'رصيد الإجازة غير كافٍ عند الاعتماد النهائي. المتاح: %', GREATEST(v_available, 0);
      END IF;

      UPDATE public.hr_leave_balances
      SET used_days = COALESCE(used_days, 0) + NEW.days_count,
          pending_days = GREATEST(0, COALESCE(pending_days, 0) - COALESCE(OLD.days_count, 0)),
          remaining_days = GREATEST(0,
            COALESCE(total_days, 0) + COALESCE(carried_forward, 0)
            - (COALESCE(used_days, 0) + NEW.days_count)
            - GREATEST(0, COALESCE(pending_days, 0) - COALESCE(OLD.days_count, 0))
          ),
          updated_at = now()
      WHERE id = v_balance.id;
    ELSIF NEW.status IN ('rejected', 'cancelled')
       AND OLD.status IN ('draft', 'pending_supervisor', 'approved_supervisor', 'pending_hr') THEN
      UPDATE public.hr_leave_balances
      SET pending_days = GREATEST(0, COALESCE(pending_days, 0) - COALESCE(OLD.days_count, 0)),
          remaining_days = GREATEST(0,
            COALESCE(total_days, 0) + COALESCE(carried_forward, 0)
            - COALESCE(used_days, 0)
            - GREATEST(0, COALESCE(pending_days, 0) - COALESCE(OLD.days_count, 0))
          ),
          updated_at = now()
      WHERE id = v_balance.id;
    ELSIF NEW.status = 'cancelled' AND OLD.status = 'approved' THEN
      IF EXISTS (
        SELECT 1
        FROM public.hr_payroll_runs pr
        JOIN public.hr_payroll_periods pp ON pp.id = pr.period_id
        JOIN public.hr_payroll_lines pl ON pl.payroll_run_id = pr.id
        WHERE pl.employee_id = NEW.employee_id
          AND pr.status IN ('approved', 'paid')
          AND pp.start_date <= NEW.end_date
          AND pp.end_date >= NEW.start_date
      ) THEN
        RAISE EXCEPTION 'لا يمكن إلغاء إجازة تتقاطع مع مسير رواتب معتمد أو مدفوع';
      END IF;

      IF EXISTS (
        SELECT 1
        FROM public.hr_attendance_days
        WHERE source_leave_request_id = NEW.id
          AND (COALESCE(leave_balance_restored, false) OR punch_in_time IS NOT NULL)
      ) THEN
        RAISE EXCEPTION 'لا يمكن إلغاء إجازة تحتوي على أيام تم حضورها فعليًا أو تمت تسويتها';
      END IF;

      UPDATE public.hr_leave_balances
      SET used_days = GREATEST(0, COALESCE(used_days, 0) - COALESCE(OLD.days_count, 0)),
          remaining_days = GREATEST(0,
            COALESCE(total_days, 0) + COALESCE(carried_forward, 0)
            - GREATEST(0, COALESCE(used_days, 0) - COALESCE(OLD.days_count, 0))
            - COALESCE(pending_days, 0)
          ),
          updated_at = now()
      WHERE id = v_balance.id;

      PERFORM public.cleanup_approved_leave_sync_scheduled(NEW.id);
    END IF;
  ELSIF NEW.status = 'cancelled' AND OLD.status = 'approved' THEN
    IF EXISTS (
      SELECT 1
      FROM public.hr_payroll_runs pr
      JOIN public.hr_payroll_periods pp ON pp.id = pr.period_id
      JOIN public.hr_payroll_lines pl ON pl.payroll_run_id = pr.id
      WHERE pl.employee_id = NEW.employee_id
        AND pr.status IN ('approved', 'paid')
        AND pp.start_date <= NEW.end_date
        AND pp.end_date >= NEW.start_date
    ) THEN
      RAISE EXCEPTION 'لا يمكن إلغاء إجازة تتقاطع مع مسير رواتب معتمد أو مدفوع';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.hr_attendance_days
      WHERE source_leave_request_id = NEW.id
        AND (COALESCE(leave_balance_restored, false) OR punch_in_time IS NOT NULL)
    ) THEN
      RAISE EXCEPTION 'لا يمكن إلغاء إجازة تحتوي على أيام تم حضورها فعليًا أو تمت تسويتها';
    END IF;

    PERFORM public.cleanup_approved_leave_sync_scheduled(NEW.id);
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.handle_leave_approval()
  FROM PUBLIC, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Schedule-aware attendance synchronization.
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.sync_approved_leave_to_attendance_scheduled(
  p_leave_request_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_leave public.hr_leave_requests%ROWTYPE;
  v_date DATE;
  v_resolved RECORD;
  v_existing public.hr_attendance_days%ROWTYPE;
  v_day_id UUID;
  v_linked_count INTEGER := 0;
BEGIN
  SELECT * INTO v_leave
  FROM public.hr_leave_requests
  WHERE id = p_leave_request_id
    AND status = 'approved'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Approved leave request % is not visible for synchronization', p_leave_request_id;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_payroll_runs pr
    JOIN public.hr_payroll_periods pp ON pp.id = pr.period_id
    JOIN public.hr_payroll_lines pl ON pl.payroll_run_id = pr.id
    WHERE pl.employee_id = v_leave.employee_id
      AND pr.status IN ('approved', 'paid')
      AND pp.start_date <= v_leave.end_date
      AND pp.end_date >= v_leave.start_date
  ) THEN
    RAISE EXCEPTION 'لا يمكن اعتماد إجازة تتقاطع مع مسير رواتب معتمد أو مدفوع';
  END IF;

  FOR v_date IN
    SELECT g.target_date::DATE
    FROM generate_series(v_leave.start_date, v_leave.end_date, INTERVAL '1 day') g(target_date)
    CROSS JOIN LATERAL public.resolve_employee_work_schedule_core(
      v_leave.employee_id,
      g.target_date::DATE,
      true
    ) r
    WHERE r.day_kind = 'work_day'
    ORDER BY g.target_date
  LOOP
    SELECT * INTO v_resolved
    FROM public.resolve_employee_work_schedule_core(v_leave.employee_id, v_date, true);

    SELECT * INTO v_existing
    FROM public.hr_attendance_days d
    WHERE d.employee_id = v_leave.employee_id
      AND d.shift_date = v_date
    FOR UPDATE;

    IF FOUND THEN
      IF COALESCE(v_existing.is_manually_locked, false) THEN
        RAISE EXCEPTION 'لا يمكن مزامنة الإجازة في % لأن يوم الحضور مقفل يدويًا', v_date;
      END IF;

      IF v_existing.source_leave_request_id IS NOT NULL
         AND v_existing.source_leave_request_id <> p_leave_request_id THEN
        RAISE EXCEPTION 'يوجد طلب إجازة آخر مرتبط بيوم %', v_date;
      END IF;

      UPDATE public.hr_attendance_days
      SET source_leave_request_id = p_leave_request_id,
          status = CASE WHEN punch_in_time IS NULL THEN 'on_leave'::public.hr_attendance_status ELSE status END,
          day_value = CASE WHEN punch_in_time IS NULL THEN 1.00 ELSE day_value END,
          review_status = CASE WHEN punch_in_time IS NULL THEN 'ok'::public.hr_review_status ELSE review_status END,
          schedule_day_kind = COALESCE(schedule_day_kind, v_resolved.day_kind),
          scheduled_start_at = COALESCE(scheduled_start_at, v_resolved.scheduled_start_at),
          scheduled_end_at = COALESCE(scheduled_end_at, v_resolved.scheduled_end_at),
          scheduled_minutes = COALESCE(scheduled_minutes, v_resolved.scheduled_minutes),
          schedule_source = COALESCE(schedule_source, v_resolved.schedule_source),
          work_schedule_id = COALESCE(work_schedule_id, v_resolved.work_schedule_id),
          schedule_snapshot_at = COALESCE(schedule_snapshot_at, now()),
          updated_at = now()
      WHERE id = v_existing.id
      RETURNING id INTO v_day_id;
    ELSE
      INSERT INTO public.hr_attendance_days (
        employee_id,
        shift_date,
        work_date,
        status,
        day_value,
        review_status,
        source_leave_request_id,
        schedule_day_kind,
        scheduled_start_at,
        scheduled_end_at,
        scheduled_minutes,
        schedule_source,
        work_schedule_id,
        schedule_snapshot_at,
        updated_at
      ) VALUES (
        v_leave.employee_id,
        v_date,
        v_date,
        'on_leave',
        1.00,
        'ok',
        p_leave_request_id,
        v_resolved.day_kind,
        v_resolved.scheduled_start_at,
        v_resolved.scheduled_end_at,
        v_resolved.scheduled_minutes,
        v_resolved.schedule_source,
        v_resolved.work_schedule_id,
        now(),
        now()
      )
      RETURNING id INTO v_day_id;
    END IF;

    IF v_day_id IS NULL THEN
      RAISE EXCEPTION 'Failed to synchronize leave request % on %', p_leave_request_id, v_date;
    END IF;

    IF v_existing.id IS NOT NULL AND v_existing.punch_in_time IS NOT NULL THEN
      IF v_existing.punch_out_time IS NOT NULL THEN
        PERFORM public.normalize_attendance_day_schedule_metrics(v_day_id);
      END IF;
    ELSE
      PERFORM public.reprocess_attendance_day_penalties(v_day_id);
    END IF;

    v_linked_count := v_linked_count + 1;
    v_existing := NULL;
    v_day_id := NULL;
  END LOOP;

  IF v_linked_count <> v_leave.days_count::INTEGER THEN
    RAISE EXCEPTION
      'Leave synchronization count mismatch for request %: expected %, linked %',
      p_leave_request_id,
      v_leave.days_count,
      v_linked_count;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.sync_approved_leave_to_attendance_scheduled(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.sync_approved_leave_to_attendance(
  p_leave_request_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF NOT public.hr_employee_work_schedules_enabled() THEN
    PERFORM public.sync_approved_leave_to_attendance_legacy_20260806(p_leave_request_id);
    RETURN;
  END IF;

  PERFORM public.sync_approved_leave_to_attendance_scheduled(p_leave_request_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.sync_approved_leave_to_attendance(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Schedule-aware cleanup for cancellation.
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.cleanup_approved_leave_sync_scheduled(
  p_leave_request_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_leave public.hr_leave_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_leave
  FROM public.hr_leave_requests
  WHERE id = p_leave_request_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_payroll_runs pr
    JOIN public.hr_payroll_periods pp ON pp.id = pr.period_id
    JOIN public.hr_payroll_lines pl ON pl.payroll_run_id = pr.id
    WHERE pl.employee_id = v_leave.employee_id
      AND pr.status IN ('approved', 'paid')
      AND pp.start_date <= v_leave.end_date
      AND pp.end_date >= v_leave.start_date
  ) THEN
    RAISE EXCEPTION 'لا يمكن تنظيف إجازة تتقاطع مع مسير رواتب معتمد أو مدفوع';
  END IF;

  DELETE FROM public.hr_attendance_days d
  WHERE d.source_leave_request_id = p_leave_request_id
    AND COALESCE(d.is_manually_locked, false) = false
    AND d.punch_in_time IS NULL;

  UPDATE public.hr_attendance_days d
  SET source_leave_request_id = NULL,
      updated_at = now()
  WHERE d.source_leave_request_id = p_leave_request_id
    AND COALESCE(d.is_manually_locked, false) = false
    AND d.punch_in_time IS NOT NULL;
END;
$function$;

REVOKE ALL ON FUNCTION public.cleanup_approved_leave_sync_scheduled(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.cleanup_approved_leave_sync(
  p_leave_request_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF NOT public.hr_employee_work_schedules_enabled() THEN
    PERFORM public.cleanup_approved_leave_sync_legacy_20260806(p_leave_request_id);
    RETURN;
  END IF;

  PERFORM public.cleanup_approved_leave_sync_scheduled(p_leave_request_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.cleanup_approved_leave_sync(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

-- Synchronize only after the approved status and normalized days_count are stored.
CREATE FUNCTION public.sync_approved_leave_after_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     AND NEW.status = 'approved'
     AND OLD.status <> 'approved' THEN
    PERFORM public.sync_approved_leave_to_attendance_scheduled(NEW.id);
  END IF;

  RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION public.sync_approved_leave_after_status_change()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_leave_schedule_sync_after_approval
  ON public.hr_leave_requests;
CREATE TRIGGER trg_leave_schedule_sync_after_approval
  AFTER UPDATE OF status ON public.hr_leave_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_approved_leave_after_status_change();

-- -----------------------------------------------------------------------------
-- Unpaid/salary-affecting leave remains an authorized leave day without a
-- penalty, but it must not be added back as a paid attendance day in payroll.
-- -----------------------------------------------------------------------------
DO $patch_scheduled_payroll$
DECLARE
  v_definition TEXT;
  v_old TEXT;
  v_new TEXT;
  v_occurrences INTEGER;
BEGIN
  SELECT pg_get_functiondef('public.calculate_employee_payroll_scheduled(uuid,uuid)'::regprocedure)
  INTO v_definition;

  v_definition := replace(v_definition, E'\r\n', E'\n');
  v_definition := replace(v_definition, E'\r', E'\n');

  v_old := $old$
  SELECT COALESCE(SUM(day_value), 0) INTO v_on_leave_days
  FROM hr_attendance_days
  WHERE employee_id = p_employee_id
    AND shift_date BETWEEN v_period.start_date AND v_calc_date
    AND status = 'on_leave'
    AND (schedule_day_kind = 'work_day' OR schedule_snapshot_at IS NULL);
$old$;

  v_new := $new$
  SELECT COALESCE(SUM(ad.day_value), 0) INTO v_on_leave_days
  FROM hr_attendance_days ad
  LEFT JOIN hr_leave_requests lr ON lr.id = ad.source_leave_request_id
  LEFT JOIN hr_leave_types lt ON lt.id = lr.leave_type_id
  WHERE ad.employee_id = p_employee_id
    AND ad.shift_date BETWEEN v_period.start_date AND v_calc_date
    AND ad.status = 'on_leave'
    AND (ad.schedule_day_kind = 'work_day' OR ad.schedule_snapshot_at IS NULL)
    AND COALESCE(lt.is_paid, true) = true
    AND COALESCE(lt.affects_salary, false) = false;
$new$;

  v_occurrences := (
    length(v_definition) - length(replace(v_definition, v_old, ''))
  ) / length(v_old);

  IF v_occurrences <> 1 THEN
    RAISE EXCEPTION 'Leave integration payroll patch failed: paid-leave marker count=%', v_occurrences;
  END IF;

  v_definition := replace(v_definition, v_old, v_new);

  IF v_definition NOT ILIKE '%LEFT JOIN hr_leave_types%'
     OR v_definition NOT ILIKE '%COALESCE(lt.is_paid, true) = true%'
     OR v_definition NOT ILIKE '%COALESCE(lt.affects_salary, false) = false%' THEN
    RAISE EXCEPTION 'Leave integration payroll patch failed: unpaid leave exclusion is incomplete';
  END IF;

  EXECUTE v_definition;
END;
$patch_scheduled_payroll$;

REVOKE ALL ON FUNCTION public.calculate_employee_payroll_scheduled(UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Assertions: no runtime data or feature state may change.
-- -----------------------------------------------------------------------------
DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Leave integration assertion failed: feature/readiness changed';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days)
     OR EXISTS (SELECT 1 FROM public.hr_attendance_days WHERE schedule_snapshot_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Leave integration assertion failed: migration changed runtime data';
  END IF;

  SELECT pg_get_functiondef('public.handle_leave_submission()'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%calculate_employee_leave_workdays%'
     OR v_definition NOT ILIKE '%IF NOT public.hr_employee_work_schedules_enabled()%' THEN
    RAISE EXCEPTION 'Leave integration assertion failed: submission dispatch is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.handle_leave_approval()'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%calculate_employee_leave_workdays%'
     OR v_definition ILIKE '%PERFORM public.sync_approved_leave_to_attendance(NEW.id)%'
        AND v_definition ILIKE '%IF NOT public.hr_employee_work_schedules_enabled()%' = false THEN
    RAISE EXCEPTION 'Leave integration assertion failed: approval dispatch is incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'hr_leave_requests'
      AND t.tgname = 'trg_leave_schedule_sync_after_approval'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'Leave integration assertion failed: AFTER approval sync trigger is missing';
  END IF;

  SELECT pg_get_functiondef('public.sync_approved_leave_to_attendance_scheduled(uuid)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%resolve_employee_work_schedule_core%'
     OR v_definition NOT ILIKE '%schedule_snapshot_at%'
     OR v_definition NOT ILIKE '%v_linked_count <> v_leave.days_count%' THEN
    RAISE EXCEPTION 'Leave integration assertion failed: scheduled attendance sync is incomplete';
  END IF;

  SELECT pg_get_functiondef('public.calculate_employee_payroll_scheduled(uuid,uuid)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT ILIKE '%LEFT JOIN hr_leave_types%'
     OR v_definition NOT ILIKE '%COALESCE(lt.is_paid, true) = true%'
     OR v_definition NOT ILIKE '%COALESCE(lt.affects_salary, false) = false%' THEN
    RAISE EXCEPTION 'Leave integration assertion failed: unpaid leave payroll isolation is missing';
  END IF;

  IF has_function_privilege('anon', 'public.preview_employee_leave_workday_count(uuid,date,date)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.calculate_employee_leave_workdays(uuid,date,date,boolean)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.sync_approved_leave_to_attendance_scheduled(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Leave integration assertion failed: internal leave helpers are exposed';
  END IF;
END;
$assertions$;

COMMIT;
