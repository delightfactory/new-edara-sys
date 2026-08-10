CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$ BEGIN
  CREATE ROLE anon;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE ROLE authenticated;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE ROLE service_role;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TYPE public.hr_day_of_week AS ENUM (
  'saturday','sunday','monday','tuesday','wednesday','thursday','friday'
);
CREATE TYPE public.hr_attendance_status AS ENUM (
  'present','late','half_day','absent_unauthorized','absent_authorized',
  'on_leave','weekly_off','public_holiday'
);
CREATE TYPE public.hr_checkout_status AS ENUM (
  'on_time','early_authorized','early_unauthorized','overtime','auto'
);

CREATE TABLE public.company_settings (
  key TEXT PRIMARY KEY,
  value TEXT
);
INSERT INTO public.company_settings(key, value) VALUES
  ('hr.work_start_time', '11:00'),
  ('hr.work_end_time', '19:00'),
  ('hr.weekly_off_day', 'friday'),
  ('hr.work_hours_per_day', '8'),
  ('hr.late_grace_minutes', '15'),
  ('hr.absence_run_delay_minutes', '120'),
  ('hr.auto_checkout_minutes', '15'),
  ('hr.open_day_review_delay_minutes', '120');

CREATE TABLE public.hr_employees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID,
  full_name TEXT NOT NULL DEFAULT 'Test',
  direct_manager_id UUID,
  status TEXT NOT NULL DEFAULT 'active',
  hire_date DATE,
  termination_date DATE,
  weekly_off_day public.hr_day_of_week
);

CREATE TABLE public.hr_public_holidays (
  holiday_date DATE PRIMARY KEY
);

CREATE TABLE public.hr_attendance_days (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES public.hr_employees(id),
  shift_date DATE NOT NULL,
  work_date DATE,
  punch_in_time TIMESTAMPTZ,
  punch_out_time TIMESTAMPTZ,
  status public.hr_attendance_status DEFAULT 'present',
  checkout_status public.hr_checkout_status,
  late_minutes INTEGER DEFAULT 0,
  early_leave_minutes INTEGER DEFAULT 0,
  overtime_minutes INTEGER DEFAULT 0,
  effective_hours NUMERIC(5,2),
  day_value NUMERIC DEFAULT 1,
  notes TEXT,
  review_status TEXT DEFAULT 'ok',
  is_manually_locked BOOLEAN DEFAULT false,
  reviewed_by UUID,
  reviewed_at TIMESTAMPTZ,
  source_leave_request_id UUID,
  is_auto_checkout BOOLEAN DEFAULT false,
  tracking_status TEXT,
  tracking_ended_at TIMESTAMPTZ,
  last_tracking_ping_at TIMESTAMPTZ,
  last_tracking_lat NUMERIC,
  last_tracking_lng NUMERIC,
  last_tracking_accuracy NUMERIC,
  location_in_id UUID,
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(employee_id, shift_date)
);

CREATE TABLE public.hr_payroll_periods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), start_date DATE, end_date DATE
);
CREATE TABLE public.hr_payroll_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), period_id UUID, status TEXT
);
CREATE TABLE public.hr_payroll_lines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), payroll_run_id UUID, employee_id UUID
);
CREATE TABLE public.hr_leave_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), employee_id UUID,
  start_date DATE, end_date DATE, status TEXT
);
CREATE TABLE public.hr_permission_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), employee_id UUID,
  permission_date DATE, status TEXT
);
CREATE TABLE public.hr_attendance_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), employee_id UUID,
  attendance_day_id UUID, alert_type TEXT, severity TEXT, status TEXT DEFAULT 'open',
  title TEXT, details TEXT, metadata JSONB DEFAULT '{}'::JSONB,
  resolved_at TIMESTAMPTZ, resolution_note TEXT, updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE public.hr_attendance_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), employee_id UUID,
  attendance_day_id UUID, log_type TEXT, latitude NUMERIC, longitude NUMERIC,
  gps_accuracy NUMERIC, location_id UUID, event_time TIMESTAMPTZ,
  synced_at TIMESTAMPTZ, requires_review BOOLEAN
);
CREATE TABLE public.notification_alert_state (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), alert_key TEXT UNIQUE,
  event_key TEXT, entity_type TEXT, entity_id UUID, last_sent_at TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ, send_count INTEGER, cooldown_hours INTEGER
);

CREATE OR REPLACE FUNCTION public.check_permission(UUID, TEXT)
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$ SELECT true $$;
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at := now(); RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION public.upsert_attendance_alert(UUID, UUID, TEXT, TEXT, TEXT, TEXT, JSONB)
RETURNS UUID LANGUAGE sql AS $$ SELECT gen_random_uuid() $$;
CREATE OR REPLACE FUNCTION public.call_dispatch_notification(TEXT, UUID[], JSONB, TEXT, UUID)
RETURNS VOID LANGUAGE plpgsql AS $$ BEGIN NULL; END $$;
CREATE OR REPLACE FUNCTION public.reprocess_attendance_day_penalties(UUID)
RETURNS INTEGER LANGUAGE sql AS $$ SELECT 0 $$;

CREATE OR REPLACE FUNCTION public.record_attendance_gps(
  p_latitude NUMERIC, p_longitude NUMERIC, p_gps_accuracy NUMERIC,
  p_log_type TEXT, p_event_time TIMESTAMPTZ DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_employee_id UUID := gen_random_uuid();
  v_shift_date DATE := CURRENT_DATE;
  v_work_start TIME := '11:00';
  v_work_end TIME := '19:00';
  v_scheduled_start TIMESTAMPTZ;
  v_sched_end TIMESTAMPTZ;
BEGIN
  v_scheduled_start := (v_shift_date + v_work_start) AT TIME ZONE 'Africa/Cairo';
  v_sched_end := (v_shift_date + v_work_end) AT TIME ZONE 'Africa/Cairo';
  RETURN '{}'::JSONB;
END $$;

CREATE OR REPLACE FUNCTION public.record_attendance_gps_v2(
  p_latitude NUMERIC, p_longitude NUMERIC, p_gps_accuracy NUMERIC,
  p_log_type TEXT, p_event_time TIMESTAMPTZ DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_employee public.hr_employees%ROWTYPE;
  v_shift_date DATE := CURRENT_DATE;
  v_work_start TIME := '11:00';
  v_work_end TIME := '19:00';
  v_scheduled_start TIMESTAMPTZ;
  v_scheduled_end TIMESTAMPTZ;
BEGIN
  v_scheduled_start := (v_shift_date::TEXT || ' ' || v_work_start::TEXT)::TIMESTAMP AT TIME ZONE 'Africa/Cairo';
  v_scheduled_end := (v_shift_date::TEXT || ' ' || v_work_end::TEXT)::TIMESTAMP AT TIME ZONE 'Africa/Cairo';
  RETURN '{}'::JSONB;
END $$;

CREATE OR REPLACE FUNCTION public.upsert_attendance_and_reprocess(
  p_employee_id UUID, p_shift_date DATE,
  p_punch_in_time TIMESTAMPTZ DEFAULT NULL,
  p_punch_out_time TIMESTAMPTZ DEFAULT NULL,
  p_status public.hr_attendance_status DEFAULT NULL,
  p_notes TEXT DEFAULT NULL, p_user_id UUID DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_work_start TIME := '11:00';
  v_work_end TIME := '19:00';
  v_sched_start TIMESTAMPTZ;
  v_sched_end TIMESTAMPTZ;
BEGIN
  v_sched_start := (p_shift_date + v_work_start) AT TIME ZONE 'Africa/Cairo';
  v_sched_start := (p_shift_date + v_work_start) AT TIME ZONE 'Africa/Cairo';
  v_sched_end := (p_shift_date + v_work_end) AT TIME ZONE 'Africa/Cairo';
  RETURN '{}'::JSONB;
END $$;

CREATE OR REPLACE FUNCTION public.settle_attendance_day_against_leave(
  p_attendance_day_id UUID, p_force BOOLEAN DEFAULT false
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_day public.hr_attendance_days%ROWTYPE;
  v_work_hours NUMERIC;
BEGIN
  SELECT * INTO v_day FROM public.hr_attendance_days WHERE id=p_attendance_day_id;
  SELECT COALESCE((value)::NUMERIC, 8) INTO v_work_hours
  FROM company_settings WHERE key = 'hr.work_hours_per_day';
END $$;

CREATE OR REPLACE FUNCTION public.process_attendance_penalties(p_attendance_day_id UUID)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_day public.hr_attendance_days%ROWTYPE;
  v_work_hours NUMERIC;
  v_work_end TIME;
  v_early_start TIMESTAMPTZ;
  v_early_end TIMESTAMPTZ;
BEGIN
  SELECT * INTO v_day FROM public.hr_attendance_days WHERE id=p_attendance_day_id;
  SELECT COALESCE((value)::NUMERIC, 8) INTO v_work_hours
  FROM company_settings WHERE key = 'hr.work_hours_per_day';
  SELECT COALESCE(value, '17:00')::TIME INTO v_work_end
  FROM company_settings WHERE key = 'hr.work_end_time';
  v_early_start := v_day.punch_out_time;
  v_early_end := (v_day.shift_date::TEXT || ' ' || v_work_end::TEXT)::TIMESTAMP AT TIME ZONE 'Africa/Cairo';
  RETURN 0;
END $$;

CREATE OR REPLACE FUNCTION public.calculate_employee_payroll(p_employee_id UUID, p_run_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_off_day_name TEXT;
  v_off_dow INTEGER;
  v_calendar_days INTEGER := 0;
  v_working_days INTEGER;
  v_work_hours_per_day NUMERIC;
  v_partial_working INTEGER := 0;
  v_public_holidays INTEGER := 0;
  v_d DATE := CURRENT_DATE;
  v_period public.hr_payroll_periods%ROWTYPE;
  v_emp public.hr_employees%ROWTYPE;
BEGIN
  SELECT * INTO v_period FROM public.hr_payroll_periods LIMIT 1;
  v_off_day_name := COALESCE(v_emp.weekly_off_day::TEXT, NULL);
  IF v_off_day_name IS NULL THEN
    SELECT value INTO v_off_day_name FROM company_settings WHERE key = 'hr.weekly_off_day';
  END IF;
  v_off_day_name := COALESCE(v_off_day_name, 'friday');
  v_off_dow := 5;
  v_calendar_days := 0;
  IF EXTRACT(DOW FROM v_d)::INTEGER <> v_off_dow THEN
    v_calendar_days := v_calendar_days + 1;
  END IF;
  SELECT COUNT(*) INTO v_public_holidays FROM hr_public_holidays
  WHERE EXTRACT(DOW FROM holiday_date)::INTEGER <> v_off_dow;
  v_calendar_days := v_calendar_days - COALESCE(v_public_holidays, 0);
  IF v_calendar_days <= 0 THEN v_calendar_days := 26; END IF;
  v_working_days := v_calendar_days;
  SELECT COALESCE(value::NUMERIC, 8) INTO v_work_hours_per_day
  FROM company_settings WHERE key = 'hr.work_hours_per_day';
  IF EXTRACT(DOW FROM v_d)::INTEGER <> v_off_dow THEN
    IF NOT EXISTS (SELECT 1 FROM hr_public_holidays WHERE holiday_date = v_d) THEN
      v_partial_working := v_partial_working + 1;
    END IF;
  END IF;
  IF EXTRACT(DOW FROM v_d)::INTEGER <> v_off_dow THEN
    IF NOT EXISTS (SELECT 1 FROM hr_public_holidays WHERE holiday_date = v_d) THEN
      v_partial_working := v_partial_working + 1;
    END IF;
  END IF;
  IF EXTRACT(DOW FROM v_d)::INTEGER <> v_off_dow THEN
    IF NOT EXISTS (SELECT 1 FROM hr_public_holidays WHERE holiday_date = v_d) THEN
      v_partial_working := v_partial_working + 1;
    END IF;
  END IF;
  RETURN gen_random_uuid();
END $$;

CREATE SCHEMA cron;
CREATE TABLE cron.job (jobid BIGINT PRIMARY KEY, schedule TEXT, command TEXT);
INSERT INTO cron.job VALUES (3, '0 14 * * *', 'SELECT public.notify_absent_employees();');
CREATE OR REPLACE FUNCTION cron.alter_job(
  job_id BIGINT, schedule TEXT DEFAULT NULL, command TEXT DEFAULT NULL,
  database TEXT DEFAULT NULL, username TEXT DEFAULT NULL, active BOOLEAN DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  UPDATE cron.job SET schedule=COALESCE(alter_job.schedule, cron.job.schedule)
  WHERE jobid=job_id;
END $$;
