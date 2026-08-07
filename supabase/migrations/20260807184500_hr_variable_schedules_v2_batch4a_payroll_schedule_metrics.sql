-- HR Variable Schedules V2 — Batch 4A
-- Additive payroll schedule metrics only.
--
-- This batch deliberately does NOT modify calculate_employee_payroll or any
-- payroll row. It only introduces private helpers that can later supply the
-- schedule-dependent inputs to the separately reviewed Batch 4B adapter.
--
-- Contracts:
--   * custom date -> central custom resolver is authoritative;
--   * no custom date -> exact Legacy work-day classifier is authoritative;
--   * official public holiday precedence is inherited from Batch 3C / Legacy;
--   * legacy scheduled minutes use the same hr.work_hours_per_day setting and
--     default (8 hours) used by the current payroll function;
--   * zero scheduled workdays is represented as zero, never synthesized to one;
--   * helpers are internal only and do not activate V2.

BEGIN;

DO $guard$
DECLARE
  v_payroll_hash text;
BEGIN
  IF to_regprocedure('public.resolve_employee_custom_schedule(uuid,date)') IS NULL
     OR to_regprocedure('public.is_employee_work_day_legacy(uuid,date)') IS NULL
     OR to_regprocedure('public.hr_variable_schedules_v2_runtime_enabled()') IS NULL THEN
    RAISE EXCEPTION 'Batch 4A prerequisites are missing';
  END IF;

  IF to_regprocedure('public.hr_v2_resolve_payroll_schedule_day(uuid,date)') IS NOT NULL
     OR to_regprocedure('public.hr_v2_get_payroll_schedule_metrics(uuid,date,date)') IS NOT NULL THEN
    RAISE EXCEPTION 'Batch 4A helper function name collision';
  END IF;

  -- Batch 4A must be financially inert: refuse to install unless the production
  -- employee-payroll function is still the captured baseline.
  SELECT md5(replace(p.prosrc, E'\r\n', E'\n'))
  INTO v_payroll_hash
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'calculate_employee_payroll'
    AND pg_get_function_identity_arguments(p.oid) = 'p_payroll_run_id uuid, p_employee_id uuid';

  IF v_payroll_hash IS DISTINCT FROM '89ebda07b9a367f3a5e56e3ae398c642' THEN
    RAISE EXCEPTION 'Batch 4A payroll baseline mismatch; review production drift before continuing';
  END IF;
END;
$guard$;

CREATE OR REPLACE FUNCTION public.hr_v2_resolve_payroll_schedule_day(
  p_employee_id uuid,
  p_date date
)
RETURNS TABLE (
  schedule_source text,
  custom_schedule_id uuid,
  day_kind text,
  is_working_day boolean,
  scheduled_minutes integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_custom record;
  v_legacy_kind text;
  v_legacy_hours numeric;
BEGIN
  IF p_employee_id IS NULL OR p_date IS NULL THEN
    RAISE EXCEPTION 'Payroll schedule day requires employee and date';
  END IF;

  SELECT *
  INTO v_custom
  FROM public.resolve_employee_custom_schedule(p_employee_id, p_date);

  IF FOUND THEN
    schedule_source := 'custom';
    custom_schedule_id := v_custom.schedule_id;
    is_working_day := v_custom.is_working_day;
    scheduled_minutes := COALESCE(v_custom.scheduled_minutes, 0);

    IF EXISTS (
      SELECT 1
      FROM public.hr_public_holidays h
      WHERE h.holiday_date = p_date
    ) THEN
      day_kind := 'public_holiday';
    ELSIF v_custom.is_working_day THEN
      day_kind := 'work_day';
    ELSE
      day_kind := 'custom_off';
    END IF;

    IF is_working_day AND scheduled_minutes <= 0 THEN
      RAISE EXCEPTION
        'Custom payroll workday has non-positive scheduled minutes for employee % on %',
        p_employee_id, p_date;
    END IF;

    IF NOT is_working_day AND scheduled_minutes <> 0 THEN
      RAISE EXCEPTION
        'Custom payroll non-working day has non-zero scheduled minutes for employee % on %',
        p_employee_id, p_date;
    END IF;

    RETURN NEXT;
    RETURN;
  END IF;

  -- Exact pre-V2 classification for dates not covered by an effective custom
  -- schedule. This preserves employee/company weekly-off + public-holiday rules.
  v_legacy_kind := public.is_employee_work_day_legacy(p_employee_id, p_date);

  schedule_source := 'legacy';
  custom_schedule_id := NULL;
  day_kind := v_legacy_kind;
  is_working_day := (v_legacy_kind = 'work_day');

  IF is_working_day THEN
    SELECT COALESCE(value::numeric, 8)
    INTO v_legacy_hours
    FROM public.company_settings
    WHERE key = 'hr.work_hours_per_day';

    v_legacy_hours := COALESCE(v_legacy_hours, 8);

    IF v_legacy_hours <= 0 THEN
      RAISE EXCEPTION 'Legacy payroll work hours must be positive';
    END IF;

    scheduled_minutes := ROUND(v_legacy_hours * 60)::integer;
  ELSE
    scheduled_minutes := 0;
  END IF;

  RETURN NEXT;
END;
$function$;

COMMENT ON FUNCTION public.hr_v2_resolve_payroll_schedule_day(uuid, date) IS
  'Private V2 payroll helper. Resolves one date to custom schedule metrics when present, otherwise exact Legacy work-day classification and company daily minutes.';

REVOKE ALL ON FUNCTION public.hr_v2_resolve_payroll_schedule_day(uuid, date)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.hr_v2_get_payroll_schedule_metrics(
  p_employee_id uuid,
  p_date_from date,
  p_date_to date
)
RETURNS TABLE (
  work_days integer,
  scheduled_minutes bigint,
  custom_dates integer,
  custom_work_days integer,
  legacy_work_days integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_date date;
  v_day record;
BEGIN
  IF p_employee_id IS NULL OR p_date_from IS NULL OR p_date_to IS NULL THEN
    RAISE EXCEPTION 'Payroll schedule metrics require employee and date range';
  END IF;

  IF p_date_from > p_date_to THEN
    RAISE EXCEPTION 'Payroll schedule metrics date_from must not exceed date_to';
  END IF;

  work_days := 0;
  scheduled_minutes := 0;
  custom_dates := 0;
  custom_work_days := 0;
  legacy_work_days := 0;

  FOR v_date IN
    SELECT gs::date
    FROM generate_series(p_date_from::timestamp, p_date_to::timestamp, interval '1 day') gs
  LOOP
    SELECT *
    INTO v_day
    FROM public.hr_v2_resolve_payroll_schedule_day(p_employee_id, v_date);

    IF v_day.schedule_source = 'custom' THEN
      custom_dates := custom_dates + 1;
    END IF;

    IF v_day.is_working_day THEN
      work_days := work_days + 1;
      scheduled_minutes := scheduled_minutes + v_day.scheduled_minutes;

      IF v_day.schedule_source = 'custom' THEN
        custom_work_days := custom_work_days + 1;
      ELSE
        legacy_work_days := legacy_work_days + 1;
      END IF;
    END IF;
  END LOOP;

  RETURN NEXT;
END;
$function$;

COMMENT ON FUNCTION public.hr_v2_get_payroll_schedule_metrics(uuid, date, date) IS
  'Private V2 payroll helper. Counts exact scheduled workdays/minutes over a mixed Legacy/custom interval without synthesizing a minimum day.';

REVOKE ALL ON FUNCTION public.hr_v2_get_payroll_schedule_metrics(uuid, date, date)
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
