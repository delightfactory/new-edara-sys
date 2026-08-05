-- =============================================================================
-- EDARA — Employee Work Schedules M1: additive schema foundation
--
-- IMPORTANT:
--   * This migration is intentionally additive.
--   * It does not replace any attendance/payroll function.
--   * It does not backfill historical attendance.
--   * The runtime feature switch is created as FALSE.
--   * Apply manually only after disposable-environment rehearsal and approval.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

-- ----------------------------------------------------------------------------
-- 0. Fail fast on an unexpected/partial environment
-- ----------------------------------------------------------------------------
DO $preflight$
BEGIN
  IF to_regclass('public.hr_employees') IS NULL THEN
    RAISE EXCEPTION 'M1 preflight failed: public.hr_employees is missing';
  END IF;

  IF to_regclass('public.hr_attendance_days') IS NULL THEN
    RAISE EXCEPTION 'M1 preflight failed: public.hr_attendance_days is missing';
  END IF;

  IF to_regclass('public.profiles') IS NULL THEN
    RAISE EXCEPTION 'M1 preflight failed: public.profiles is missing';
  END IF;

  IF to_regclass('public.company_settings') IS NULL THEN
    RAISE EXCEPTION 'M1 preflight failed: public.company_settings is missing';
  END IF;

  IF to_regtype('public.hr_day_of_week') IS NULL THEN
    RAISE EXCEPTION 'M1 preflight failed: public.hr_day_of_week is missing';
  END IF;

  IF to_regprocedure('public.set_updated_at()') IS NULL THEN
    RAISE EXCEPTION 'M1 preflight failed: public.set_updated_at() is missing';
  END IF;

  IF to_regprocedure('public.check_permission(uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'M1 preflight failed: public.check_permission(uuid,text) is missing';
  END IF;

  IF to_regclass('public.hr_employee_work_schedules') IS NOT NULL
     OR to_regclass('public.hr_employee_work_schedule_days') IS NOT NULL THEN
    RAISE EXCEPTION 'M1 preflight failed: employee schedule tables already exist';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'hr_attendance_days'
      AND column_name IN (
        'schedule_day_kind',
        'scheduled_start_at',
        'scheduled_end_at',
        'scheduled_minutes',
        'schedule_source',
        'work_schedule_id',
        'schedule_snapshot_at'
      )
  ) THEN
    RAISE EXCEPTION 'M1 preflight failed: one or more attendance snapshot columns already exist';
  END IF;
END;
$preflight$;

-- ----------------------------------------------------------------------------
-- 1. Required operator classes for a concurrent-safe date-range exclusion rule
-- ----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions;

-- ----------------------------------------------------------------------------
-- 2. Versioned employee weekly schedule header
-- ----------------------------------------------------------------------------
CREATE TABLE public.hr_employee_work_schedules (
  id                UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  employee_id       UUID NOT NULL
                    REFERENCES public.hr_employees(id) ON DELETE RESTRICT,
  effective_from    DATE NOT NULL,
  effective_to      DATE,
  effective_range   DATERANGE GENERATED ALWAYS AS (
                      daterange(
                        effective_from,
                        COALESCE(effective_to, 'infinity'::DATE),
                        '[]'
                      )
                    ) STORED,
  status            TEXT NOT NULL DEFAULT 'draft',
  notes             TEXT,

  activated_by      UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  activated_at      TIMESTAMPTZ,
  retired_by        UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  retired_at        TIMESTAMPTZ,

  created_by        UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by        UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT hr_employee_work_schedules_status_check
    CHECK (status IN ('draft', 'active', 'retired')),

  CONSTRAINT hr_employee_work_schedules_dates_check
    CHECK (effective_to IS NULL OR effective_to >= effective_from),

  CONSTRAINT hr_employee_work_schedules_lifecycle_check
    CHECK (
      (
        status = 'draft'
        AND activated_by IS NULL
        AND activated_at IS NULL
        AND retired_by IS NULL
        AND retired_at IS NULL
      )
      OR
      (
        status = 'active'
        AND activated_by IS NOT NULL
        AND activated_at IS NOT NULL
        AND retired_by IS NULL
        AND retired_at IS NULL
      )
      OR
      (
        status = 'retired'
        AND effective_to IS NOT NULL
        AND activated_by IS NOT NULL
        AND activated_at IS NOT NULL
        AND retired_by IS NOT NULL
        AND retired_at IS NOT NULL
        AND retired_at >= activated_at
      )
    ),

  CONSTRAINT hr_employee_work_schedules_no_effective_overlap
    EXCLUDE USING gist (
      employee_id WITH =,
      effective_range WITH &&
    )
    WHERE (status IN ('active', 'retired'))
);

CREATE INDEX hr_employee_work_schedules_employee_effective_idx
  ON public.hr_employee_work_schedules(employee_id, effective_from DESC);

CREATE INDEX hr_employee_work_schedules_active_lookup_idx
  ON public.hr_employee_work_schedules(employee_id, effective_from, effective_to)
  WHERE status = 'active';

DROP TRIGGER IF EXISTS trg_hr_employee_work_schedules_updated_at
  ON public.hr_employee_work_schedules;
CREATE TRIGGER trg_hr_employee_work_schedules_updated_at
  BEFORE UPDATE ON public.hr_employee_work_schedules
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE public.hr_employee_work_schedules IS
  'Effective-dated employee weekly work schedule versions. Runtime use is guarded by hr.employee_work_schedules_enabled.';
COMMENT ON COLUMN public.hr_employee_work_schedules.effective_to IS
  'Inclusive final effective date. NULL means open-ended.';
COMMENT ON COLUMN public.hr_employee_work_schedules.effective_range IS
  'Generated inclusive range used by the overlap exclusion constraint.';

-- ----------------------------------------------------------------------------
-- 3. Seven weekday rows for each schedule version
-- ----------------------------------------------------------------------------
CREATE TABLE public.hr_employee_work_schedule_days (
  id                UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  schedule_id       UUID NOT NULL
                    REFERENCES public.hr_employee_work_schedules(id) ON DELETE CASCADE,
  day_of_week       public.hr_day_of_week NOT NULL,
  is_working_day    BOOLEAN NOT NULL,
  start_time        TIME,
  end_time          TIME,
  scheduled_minutes INTEGER GENERATED ALWAYS AS (
                      CASE
                        WHEN is_working_day
                          THEN (EXTRACT(EPOCH FROM (end_time - start_time)) / 60)::INTEGER
                        ELSE 0
                      END
                    ) STORED,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT hr_employee_work_schedule_days_schedule_day_key
    UNIQUE (schedule_id, day_of_week),

  CONSTRAINT hr_employee_work_schedule_days_window_check
    CHECK (
      (
        is_working_day
        AND start_time IS NOT NULL
        AND end_time IS NOT NULL
        AND end_time > start_time
      )
      OR
      (
        NOT is_working_day
        AND start_time IS NULL
        AND end_time IS NULL
      )
    ),

  CONSTRAINT hr_employee_work_schedule_days_minutes_check
    CHECK (
      (is_working_day AND scheduled_minutes > 0 AND scheduled_minutes < 1440)
      OR
      (NOT is_working_day AND scheduled_minutes = 0)
    )
);

DROP TRIGGER IF EXISTS trg_hr_employee_work_schedule_days_updated_at
  ON public.hr_employee_work_schedule_days;
CREATE TRIGGER trg_hr_employee_work_schedule_days_updated_at
  BEFORE UPDATE ON public.hr_employee_work_schedule_days
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE public.hr_employee_work_schedule_days IS
  'Exactly seven validated weekday definitions belonging to one employee schedule version.';
COMMENT ON COLUMN public.hr_employee_work_schedule_days.scheduled_minutes IS
  'Generated same-day duration; cannot diverge from start_time/end_time.';

-- ----------------------------------------------------------------------------
-- 4. Immutable-per-day expected-schedule snapshot on attendance rows
--    All columns are nullable so historical rows remain untouched.
-- ----------------------------------------------------------------------------
ALTER TABLE public.hr_attendance_days
  ADD COLUMN schedule_day_kind TEXT,
  ADD COLUMN scheduled_start_at TIMESTAMPTZ,
  ADD COLUMN scheduled_end_at TIMESTAMPTZ,
  ADD COLUMN scheduled_minutes INTEGER,
  ADD COLUMN schedule_source TEXT,
  ADD COLUMN work_schedule_id UUID,
  ADD COLUMN schedule_snapshot_at TIMESTAMPTZ;

ALTER TABLE public.hr_attendance_days
  ADD CONSTRAINT hr_attendance_days_work_schedule_id_fkey
    FOREIGN KEY (work_schedule_id)
    REFERENCES public.hr_employee_work_schedules(id)
    ON DELETE RESTRICT,

  ADD CONSTRAINT hr_attendance_days_schedule_snapshot_check
    CHECK (
      -- Legacy attendance row: no snapshot at all.
      (
        schedule_day_kind IS NULL
        AND scheduled_start_at IS NULL
        AND scheduled_end_at IS NULL
        AND scheduled_minutes IS NULL
        AND schedule_source IS NULL
        AND work_schedule_id IS NULL
        AND schedule_snapshot_at IS NULL
      )
      OR
      -- Complete, internally consistent snapshot.
      (
        schedule_day_kind IN ('work_day', 'weekly_off', 'public_holiday')
        AND schedule_source IN ('employee', 'company', 'public_holiday')
        AND scheduled_minutes IS NOT NULL
        AND scheduled_minutes >= 0
        AND schedule_snapshot_at IS NOT NULL

        AND (
          (schedule_source = 'employee' AND work_schedule_id IS NOT NULL)
          OR
          (schedule_source IN ('company', 'public_holiday') AND work_schedule_id IS NULL)
        )

        AND (
          (schedule_day_kind = 'public_holiday' AND schedule_source = 'public_holiday')
          OR
          (schedule_day_kind <> 'public_holiday' AND schedule_source <> 'public_holiday')
        )

        AND (
          (
            schedule_day_kind = 'work_day'
            AND scheduled_start_at IS NOT NULL
            AND scheduled_end_at IS NOT NULL
            AND scheduled_end_at > scheduled_start_at
            AND scheduled_minutes > 0
          )
          OR
          (
            schedule_day_kind IN ('weekly_off', 'public_holiday')
            AND scheduled_start_at IS NULL
            AND scheduled_end_at IS NULL
            AND scheduled_minutes = 0
          )
        )
      )
    );

CREATE INDEX hr_attendance_days_work_schedule_id_idx
  ON public.hr_attendance_days(work_schedule_id)
  WHERE work_schedule_id IS NOT NULL;

COMMENT ON COLUMN public.hr_attendance_days.schedule_day_kind IS
  'Resolved day state fixed for this attendance date: work_day, weekly_off, or public_holiday.';
COMMENT ON COLUMN public.hr_attendance_days.scheduled_start_at IS
  'Expected Cairo-local start represented as timestamptz when the day snapshot was created.';
COMMENT ON COLUMN public.hr_attendance_days.scheduled_end_at IS
  'Expected Cairo-local end represented as timestamptz when the day snapshot was created.';
COMMENT ON COLUMN public.hr_attendance_days.scheduled_minutes IS
  'Expected minutes for this date: positive on work days and zero on non-working days.';
COMMENT ON COLUMN public.hr_attendance_days.schedule_source IS
  'Snapshot source: employee custom schedule, company fallback, or public holiday.';
COMMENT ON COLUMN public.hr_attendance_days.work_schedule_id IS
  'Employee schedule version used by the snapshot; NULL for company/holiday sources.';
COMMENT ON COLUMN public.hr_attendance_days.schedule_snapshot_at IS
  'Timestamp when the expected schedule state became immutable for this attendance row.';

-- ----------------------------------------------------------------------------
-- 5. Read-only RLS surface. All writes will be through reviewed RPCs in M2.
-- ----------------------------------------------------------------------------
ALTER TABLE public.hr_employee_work_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_employee_work_schedule_days ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.hr_employee_work_schedules
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.hr_employee_work_schedule_days
  FROM PUBLIC, anon, authenticated;

GRANT SELECT ON TABLE public.hr_employee_work_schedules TO authenticated;
GRANT SELECT ON TABLE public.hr_employee_work_schedule_days TO authenticated;

CREATE POLICY hr_employee_work_schedules_read
  ON public.hr_employee_work_schedules
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.hr_employees e
      WHERE e.id = employee_id
        AND e.user_id = (SELECT auth.uid())
    )
    OR (SELECT public.check_permission((SELECT auth.uid()), 'hr.employees.read'))
    OR (SELECT public.check_permission((SELECT auth.uid()), 'hr.attendance.read'))
  );

CREATE POLICY hr_employee_work_schedule_days_read
  ON public.hr_employee_work_schedule_days
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.hr_employee_work_schedules s
      WHERE s.id = schedule_id
    )
  );

-- No INSERT/UPDATE/DELETE policies are intentionally created.

-- ----------------------------------------------------------------------------
-- 6. Disabled runtime feature switch — never overwrite an enabled existing key
-- ----------------------------------------------------------------------------
DO $feature_flag$
DECLARE
  v_existing_value TEXT;
BEGIN
  SELECT value
  INTO v_existing_value
  FROM public.company_settings
  WHERE key = 'hr.employee_work_schedules_enabled'
  FOR UPDATE;

  IF FOUND THEN
    IF lower(btrim(v_existing_value)) NOT IN ('false', '0', 'off', 'no') THEN
      RAISE EXCEPTION
        'M1 safety stop: hr.employee_work_schedules_enabled already exists with non-false value %',
        v_existing_value;
    END IF;

    UPDATE public.company_settings
    SET type = 'boolean',
        description = 'Enable effective-dated employee work schedules in attendance and payroll runtime',
        category = 'hr',
        is_public = false,
        updated_at = now()
    WHERE key = 'hr.employee_work_schedules_enabled';
  ELSE
    INSERT INTO public.company_settings (
      key,
      value,
      type,
      description,
      category,
      is_public
    ) VALUES (
      'hr.employee_work_schedules_enabled',
      'false',
      'boolean',
      'Enable effective-dated employee work schedules in attendance and payroll runtime',
      'hr',
      false
    );
  END IF;
END;
$feature_flag$;

-- ----------------------------------------------------------------------------
-- 7. In-transaction structural assertions
-- ----------------------------------------------------------------------------
DO $assertions$
DECLARE
  v_snapshot_columns INTEGER;
BEGIN
  SELECT count(*)
  INTO v_snapshot_columns
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'hr_attendance_days'
    AND column_name IN (
      'schedule_day_kind',
      'scheduled_start_at',
      'scheduled_end_at',
      'scheduled_minutes',
      'schedule_source',
      'work_schedule_id',
      'schedule_snapshot_at'
    );

  IF v_snapshot_columns <> 7 THEN
    RAISE EXCEPTION 'M1 assertion failed: expected 7 attendance snapshot columns, found %', v_snapshot_columns;
  END IF;

  IF (SELECT value FROM public.company_settings WHERE key = 'hr.employee_work_schedules_enabled') <> 'false' THEN
    RAISE EXCEPTION 'M1 assertion failed: feature switch is not false';
  END IF;

  IF EXISTS (SELECT 1 FROM public.hr_employee_work_schedules)
     OR EXISTS (SELECT 1 FROM public.hr_employee_work_schedule_days) THEN
    RAISE EXCEPTION 'M1 assertion failed: schema migration must not seed schedule data';
  END IF;
END;
$assertions$;

COMMIT;
