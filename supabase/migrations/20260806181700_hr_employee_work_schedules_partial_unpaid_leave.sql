-- =============================================================================
-- EDARA — Employee Work Schedules: partial work during unpaid leave
--
-- Paid leave keeps the established V1 policy: partial work remains a fully paid
-- leave day. For an unpaid/salary-affecting leave, actual partial work is paid by
-- its day fraction, while the approved leave interval creates no late/early/OT
-- penalty. No other attendance path changes.
-- =============================================================================

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
DECLARE
  v_definition TEXT;
BEGIN
  IF to_regprocedure('public.normalize_attendance_day_schedule_metrics(uuid)') IS NULL
     OR to_regprocedure('public.calculate_employee_leave_workdays(uuid,date,date,boolean)') IS NULL THEN
    RAISE EXCEPTION 'Partial unpaid leave preflight failed: leave/schedule integration is missing';
  END IF;

  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Partial unpaid leave preflight failed: feature/readiness must remain false';
  END IF;

  SELECT pg_get_functiondef(
    'public.normalize_attendance_day_schedule_metrics(uuid)'::regprocedure
  ) INTO v_definition;

  IF v_definition NOT ILIKE '%Safe V1 policy: partial work during an approved full-day leave stays a%'
     OR v_definition ILIKE '%COALESCE(lt.is_paid, true) = false%' THEN
    RAISE EXCEPTION 'Partial unpaid leave preflight failed: expected normalizer block is absent or already patched';
  END IF;
END;
$preflight$;

DO $patch_normalizer$
DECLARE
  v_definition TEXT;
  v_old TEXT;
  v_new TEXT;
  v_occurrences INTEGER;
BEGIN
  SELECT pg_get_functiondef(
    'public.normalize_attendance_day_schedule_metrics(uuid)'::regprocedure
  ) INTO v_definition;

  v_definition := replace(v_definition, E'\r\n', E'\n');
  v_definition := replace(v_definition, E'\r', E'\n');

  v_old := $old$
    -- Safe V1 policy: partial work during an approved full-day leave stays a
    -- fully paid leave day. Only a completed scheduled day restores the balance.
    IF v_day.source_leave_request_id IS NOT NULL
       AND COALESCE(v_day.leave_balance_restored, false) = false
       AND COALESCE(v_day.effective_hours, 0) < (v_day.scheduled_minutes / 60.0) THEN
      UPDATE public.hr_attendance_days
      SET status = 'on_leave',
          day_value = 1.00,
          late_minutes = 0,
          early_leave_minutes = 0,
          overtime_minutes = 0,
          checkout_status = 'on_time',
          updated_at = now()
      WHERE id = v_day.id;
    END IF;
$old$;

  v_new := $new$
    -- Paid leave: partial work remains a fully paid leave day.
    -- Unpaid/salary-affecting leave: pay only the actual worked fraction and
    -- suppress penalties for the approved remainder of the scheduled day.
    IF v_day.source_leave_request_id IS NOT NULL
       AND COALESCE(v_day.leave_balance_restored, false) = false
       AND COALESCE(v_day.effective_hours, 0) < (v_day.scheduled_minutes / 60.0) THEN
      IF EXISTS (
        SELECT 1
        FROM public.hr_leave_requests lr
        JOIN public.hr_leave_types lt ON lt.id = lr.leave_type_id
        WHERE lr.id = v_day.source_leave_request_id
          AND lr.status = 'approved'
          AND (
            COALESCE(lt.is_paid, true) = false
            OR COALESCE(lt.affects_salary, false) = true
          )
      ) THEN
        UPDATE public.hr_attendance_days
        SET status = 'present',
            day_value = LEAST(
              1.00,
              ROUND(
                (COALESCE(effective_hours, 0) / (scheduled_minutes / 60.0))::NUMERIC,
                2
              )
            ),
            late_minutes = 0,
            early_leave_minutes = 0,
            overtime_minutes = 0,
            checkout_status = 'on_time',
            updated_at = now()
        WHERE id = v_day.id;
      ELSE
        UPDATE public.hr_attendance_days
        SET status = 'on_leave',
            day_value = 1.00,
            late_minutes = 0,
            early_leave_minutes = 0,
            overtime_minutes = 0,
            checkout_status = 'on_time',
            updated_at = now()
        WHERE id = v_day.id;
      END IF;
    END IF;
$new$;

  v_occurrences := (
    length(v_definition) - length(replace(v_definition, v_old, ''))
  ) / length(v_old);

  IF v_occurrences <> 1 THEN
    RAISE EXCEPTION 'Partial unpaid leave patch failed: expected one policy block, found %', v_occurrences;
  END IF;

  v_definition := replace(v_definition, v_old, v_new);
  EXECUTE v_definition;
END;
$patch_normalizer$;

REVOKE ALL ON FUNCTION public.normalize_attendance_day_schedule_metrics(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

DO $assertions$
DECLARE
  v_definition TEXT;
BEGIN
  IF public.hr_employee_work_schedules_enabled()
     OR public.hr_employee_work_schedules_activation_ready() THEN
    RAISE EXCEPTION 'Partial unpaid leave assertion failed: feature/readiness changed';
  END IF;

  SELECT pg_get_functiondef(
    'public.normalize_attendance_day_schedule_metrics(uuid)'::regprocedure
  ) INTO v_definition;

  IF v_definition NOT ILIKE '%COALESCE(lt.is_paid, true) = false%'
     OR v_definition NOT ILIKE '%COALESCE(lt.affects_salary, false) = true%'
     OR v_definition NOT ILIKE '%COALESCE(effective_hours, 0) / (scheduled_minutes / 60.0)%'
     OR v_definition NOT ILIKE '%status = ''on_leave''%'
     OR v_definition NOT ILIKE '%status = ''present''%' THEN
    RAISE EXCEPTION 'Partial unpaid leave assertion failed: paid/unpaid branch is incomplete';
  END IF;
END;
$assertions$;

COMMIT;
