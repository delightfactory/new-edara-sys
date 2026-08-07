-- HR V2 isolated rehearsal — production-derived runtime table snapshot
-- Source: NEW-EDARA-SYS production catalog, read-only capture on 2026-08-07.
-- Scope is intentionally narrow: only current tables required by HR attendance,
-- leave, payroll baseline guards, and permission helpers used by Batch 1–4A.
-- No production rows are included.

CREATE TABLE public.company_settings (
  key text NOT NULL,
  value text NOT NULL,
  type text DEFAULT 'text'::text NOT NULL,
  description text,
  category text DEFAULT 'general'::text NOT NULL,
  is_public boolean DEFAULT false NOT NULL,
  updated_by uuid,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.company_settings ADD CONSTRAINT company_settings_pkey PRIMARY KEY (key);
ALTER TABLE public.company_settings ADD CONSTRAINT company_settings_type_check CHECK (type = ANY (ARRAY['text'::text, 'number'::text, 'boolean'::text, 'json'::text]));

CREATE TABLE public.hr_attendance_alerts (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  employee_id uuid NOT NULL,
  attendance_day_id uuid,
  alert_type text NOT NULL,
  severity text DEFAULT 'medium'::text NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  title text NOT NULL,
  details text,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  started_at timestamp with time zone DEFAULT now() NOT NULL,
  resolved_at timestamp with time zone,
  resolved_by uuid,
  resolution_note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.hr_attendance_alerts ADD CONSTRAINT hr_attendance_alerts_alert_type_check CHECK (alert_type = ANY (ARRAY['tracking_gap'::text, 'outside_allowed_zone'::text, 'permission_no_return'::text, 'auto_checkout'::text, 'manual_correction'::text, 'missing_day'::text, 'open_day_unclosed'::text]));
ALTER TABLE public.hr_attendance_alerts ADD CONSTRAINT hr_attendance_alerts_pkey PRIMARY KEY (id);
ALTER TABLE public.hr_attendance_alerts ADD CONSTRAINT hr_attendance_alerts_severity_check CHECK (severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text]));
ALTER TABLE public.hr_attendance_alerts ADD CONSTRAINT hr_attendance_alerts_status_check CHECK (status = ANY (ARRAY['open'::text, 'resolved'::text, 'dismissed'::text]));

CREATE TABLE public.hr_attendance_days (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  employee_id uuid NOT NULL,
  shift_date date NOT NULL,
  work_date date NOT NULL,
  punch_in_time timestamp with time zone,
  punch_out_time timestamp with time zone,
  location_in_id uuid,
  location_out_id uuid,
  gps_accuracy_in numeric(8,2),
  gps_accuracy_out numeric(8,2),
  status hr_attendance_status DEFAULT 'absent_unauthorized'::hr_attendance_status NOT NULL,
  checkout_status hr_checkout_status,
  late_minutes integer DEFAULT 0 NOT NULL,
  early_leave_minutes integer DEFAULT 0 NOT NULL,
  overtime_minutes integer DEFAULT 0 NOT NULL,
  effective_hours numeric(5,2),
  day_value numeric(5,4) DEFAULT 1.0 NOT NULL,
  is_auto_checkout boolean DEFAULT false NOT NULL,
  review_status hr_review_status DEFAULT 'ok'::hr_review_status NOT NULL,
  reviewed_by uuid,
  reviewed_at timestamp with time zone,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  tracking_started_at timestamp with time zone,
  tracking_ended_at timestamp with time zone,
  last_tracking_ping_at timestamp with time zone,
  last_tracking_lat numeric(10,7),
  last_tracking_lng numeric(10,7),
  last_tracking_accuracy numeric(8,2),
  tracking_status text DEFAULT 'idle'::text NOT NULL,
  tracking_ping_count integer DEFAULT 0 NOT NULL,
  outside_zone_count integer DEFAULT 0 NOT NULL,
  is_manually_locked boolean DEFAULT false NOT NULL,
  source_leave_request_id uuid,
  leave_balance_restored boolean DEFAULT false NOT NULL,
  leave_balance_restored_at timestamp with time zone
);
ALTER TABLE public.hr_attendance_days ADD CONSTRAINT chk_effective_hours_range CHECK (effective_hours IS NULL OR effective_hours >= 0::numeric AND effective_hours <= 24.00);
ALTER TABLE public.hr_attendance_days ADD CONSTRAINT hr_attendance_days_employee_id_shift_date_key UNIQUE (employee_id, shift_date);
ALTER TABLE public.hr_attendance_days ADD CONSTRAINT hr_attendance_days_pkey PRIMARY KEY (id);
ALTER TABLE public.hr_attendance_days ADD CONSTRAINT hr_attendance_days_tracking_status_check CHECK (tracking_status = ANY (ARRAY['idle'::text, 'active'::text, 'ended'::text, 'stale'::text, 'outside_zone'::text]));

CREATE TABLE public.hr_attendance_logs (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  employee_id uuid NOT NULL,
  attendance_day_id uuid,
  log_type text NOT NULL,
  latitude numeric(10,7) NOT NULL,
  longitude numeric(10,7) NOT NULL,
  gps_accuracy numeric(8,2),
  location_id uuid,
  is_offline_sync boolean DEFAULT false NOT NULL,
  event_time timestamp with time zone DEFAULT now() NOT NULL,
  synced_at timestamp with time zone,
  requires_review boolean DEFAULT false NOT NULL,
  device_info text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.hr_attendance_logs ADD CONSTRAINT hr_attendance_logs_log_type_check CHECK (log_type = ANY (ARRAY['check_in'::text, 'check_out'::text, 'location_ping'::text, 'auto_checkout'::text]));
ALTER TABLE public.hr_attendance_logs ADD CONSTRAINT hr_attendance_logs_pkey PRIMARY KEY (id);

CREATE TABLE public.hr_employees (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  employee_number text NOT NULL,
  user_id uuid,
  full_name text NOT NULL,
  full_name_en text,
  national_id text,
  birth_date date,
  gender hr_gender,
  marital_status hr_marital_status,
  address text,
  personal_phone text NOT NULL,
  emergency_phone text,
  emergency_contact text,
  department_id uuid,
  position_id uuid,
  branch_id uuid,
  direct_manager_id uuid,
  status hr_employee_status DEFAULT 'active'::hr_employee_status NOT NULL,
  hire_date date NOT NULL,
  probation_end_date date,
  termination_date date,
  termination_reason text,
  weekly_off_day hr_day_of_week,
  is_field_employee boolean DEFAULT false NOT NULL,
  work_location_id uuid,
  base_salary numeric(12,2) DEFAULT 0 NOT NULL,
  transport_allowance numeric(12,2) DEFAULT 0 NOT NULL,
  housing_allowance numeric(12,2) DEFAULT 0 NOT NULL,
  other_allowances numeric(12,2) DEFAULT 0 NOT NULL,
  gross_salary numeric(12,2) GENERATED ALWAYS AS ((((base_salary + transport_allowance) + housing_allowance) + other_allowances)) STORED,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  attendance_checkin_mode text DEFAULT 'assigned_only'::text NOT NULL,
  attendance_checkout_mode text DEFAULT 'assigned_only'::text NOT NULL,
  allowed_checkin_location_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  allowed_checkout_location_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL
);
ALTER TABLE public.hr_employees ADD CONSTRAINT hr_employees_attendance_checkin_mode_check CHECK (attendance_checkin_mode = ANY (ARRAY['assigned_only'::text, 'field_allowed'::text]));
ALTER TABLE public.hr_employees ADD CONSTRAINT hr_employees_attendance_checkout_mode_check CHECK (attendance_checkout_mode = ANY (ARRAY['assigned_only'::text, 'field_allowed'::text]));
ALTER TABLE public.hr_employees ADD CONSTRAINT hr_employees_employee_number_key UNIQUE (employee_number);
ALTER TABLE public.hr_employees ADD CONSTRAINT hr_employees_national_id_key UNIQUE (national_id);
ALTER TABLE public.hr_employees ADD CONSTRAINT hr_employees_pkey PRIMARY KEY (id);
ALTER TABLE public.hr_employees ADD CONSTRAINT hr_employees_user_id_key UNIQUE (user_id);

CREATE TABLE public.hr_leave_balances (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  employee_id uuid NOT NULL,
  leave_type_id uuid NOT NULL,
  year integer NOT NULL,
  total_days numeric(5,1) DEFAULT 0 NOT NULL,
  used_days numeric(5,1) DEFAULT 0 NOT NULL,
  pending_days numeric(5,1) DEFAULT 0 NOT NULL,
  carried_forward numeric(5,1) DEFAULT 0 NOT NULL,
  remaining_days numeric(5,1) GENERATED ALWAYS AS (((total_days + carried_forward) - used_days)) STORED,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.hr_leave_balances ADD CONSTRAINT hr_leave_balances_employee_id_leave_type_id_year_key UNIQUE (employee_id, leave_type_id, year);
ALTER TABLE public.hr_leave_balances ADD CONSTRAINT hr_leave_balances_pkey PRIMARY KEY (id);

CREATE TABLE public.hr_leave_requests (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  employee_id uuid NOT NULL,
  leave_type_id uuid NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  days_count numeric(5,1) NOT NULL,
  reason text,
  document_url text,
  status hr_leave_request_status DEFAULT 'pending_supervisor'::hr_leave_request_status NOT NULL,
  supervisor_id uuid,
  supervisor_action_at timestamp with time zone,
  supervisor_notes text,
  hr_manager_id uuid,
  hr_action_at timestamp with time zone,
  hr_notes text,
  rejection_reason text,
  rejected_by uuid,
  rejected_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.hr_leave_requests ADD CONSTRAINT chk_leave_dates CHECK (end_date >= start_date);
ALTER TABLE public.hr_leave_requests ADD CONSTRAINT hr_leave_requests_days_count_check CHECK (days_count > 0::numeric);
ALTER TABLE public.hr_leave_requests ADD CONSTRAINT hr_leave_requests_pkey PRIMARY KEY (id);

CREATE TABLE public.hr_leave_types (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  name_en text,
  code text NOT NULL,
  max_days_per_year integer,
  max_days_per_request integer,
  is_paid boolean DEFAULT true NOT NULL,
  has_balance boolean DEFAULT true NOT NULL,
  deducts_from_balance boolean DEFAULT true NOT NULL,
  requires_approval boolean DEFAULT true NOT NULL,
  approval_levels integer DEFAULT 2 NOT NULL,
  requires_document boolean DEFAULT false NOT NULL,
  can_carry_forward boolean DEFAULT false NOT NULL,
  affects_salary boolean DEFAULT false NOT NULL,
  is_system boolean DEFAULT false NOT NULL,
  is_active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  eligible_gender text DEFAULT 'all'::text
);
ALTER TABLE public.hr_leave_types ADD CONSTRAINT hr_leave_types_approval_levels_check CHECK (approval_levels = ANY (ARRAY[1, 2]));
ALTER TABLE public.hr_leave_types ADD CONSTRAINT hr_leave_types_code_key UNIQUE (code);
ALTER TABLE public.hr_leave_types ADD CONSTRAINT hr_leave_types_eligible_gender_check CHECK (eligible_gender = ANY (ARRAY['all'::text, 'male'::text, 'female'::text]));
ALTER TABLE public.hr_leave_types ADD CONSTRAINT hr_leave_types_pkey PRIMARY KEY (id);

CREATE TABLE public.hr_payroll_lines (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  payroll_run_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  period_id uuid NOT NULL,
  total_working_days integer DEFAULT 0 NOT NULL,
  actual_work_days numeric(5,2) DEFAULT 0 NOT NULL,
  absent_days numeric(5,2) DEFAULT 0 NOT NULL,
  deducted_days numeric(5,2) DEFAULT 0 NOT NULL,
  overtime_hours numeric(5,2) DEFAULT 0 NOT NULL,
  base_salary numeric(12,2) DEFAULT 0 NOT NULL,
  transport_allowance numeric(12,2) DEFAULT 0 NOT NULL,
  housing_allowance numeric(12,2) DEFAULT 0 NOT NULL,
  other_allowances numeric(12,2) DEFAULT 0 NOT NULL,
  overtime_amount numeric(12,2) DEFAULT 0 NOT NULL,
  commission_amount numeric(12,2) DEFAULT 0 NOT NULL,
  bonus_amount numeric(12,2) DEFAULT 0 NOT NULL,
  gross_earned numeric(12,2) DEFAULT 0 NOT NULL,
  absence_deduction numeric(12,2) DEFAULT 0 NOT NULL,
  penalty_deduction numeric(12,2) DEFAULT 0 NOT NULL,
  advance_deduction numeric(12,2) DEFAULT 0 NOT NULL,
  social_insurance numeric(12,2) DEFAULT 0 NOT NULL,
  income_tax numeric(12,2) DEFAULT 0 NOT NULL,
  health_insurance numeric(12,2) DEFAULT 0 NOT NULL,
  other_deductions numeric(12,2) DEFAULT 0 NOT NULL,
  total_deductions numeric(12,2) DEFAULT 0 NOT NULL,
  net_salary numeric(12,2) DEFAULT 0 NOT NULL,
  is_partial_month boolean DEFAULT false NOT NULL,
  hire_date_in_period date,
  term_date_in_period date,
  override_net numeric(12,2),
  override_reason text,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  deficit_carryover numeric(12,2) DEFAULT 0 NOT NULL
);
ALTER TABLE public.hr_payroll_lines ADD CONSTRAINT hr_payroll_lines_payroll_run_id_employee_id_key UNIQUE (payroll_run_id, employee_id);
ALTER TABLE public.hr_payroll_lines ADD CONSTRAINT hr_payroll_lines_pkey PRIMARY KEY (id);

CREATE TABLE public.hr_payroll_periods (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  year integer NOT NULL,
  month integer NOT NULL,
  name text NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  is_closed boolean DEFAULT false NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.hr_payroll_periods ADD CONSTRAINT hr_payroll_periods_month_check CHECK (month >= 1 AND month <= 12);
ALTER TABLE public.hr_payroll_periods ADD CONSTRAINT hr_payroll_periods_pkey PRIMARY KEY (id);
ALTER TABLE public.hr_payroll_periods ADD CONSTRAINT hr_payroll_periods_year_month_key UNIQUE (year, month);

CREATE TABLE public.hr_payroll_runs (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  number text,
  period_id uuid NOT NULL,
  branch_id uuid,
  status hr_payroll_run_status DEFAULT 'draft'::hr_payroll_run_status NOT NULL,
  total_gross numeric(16,2) DEFAULT 0 NOT NULL,
  total_deductions numeric(16,2) DEFAULT 0 NOT NULL,
  total_net numeric(16,2) DEFAULT 0 NOT NULL,
  total_employees integer DEFAULT 0 NOT NULL,
  calculated_by uuid,
  calculated_at timestamp with time zone,
  approved_by uuid,
  approved_at timestamp with time zone,
  paid_by uuid,
  paid_at timestamp with time zone,
  journal_entry_id uuid,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  calculation_mode text,
  calculated_through_date date
);
ALTER TABLE public.hr_payroll_runs ADD CONSTRAINT hr_payroll_runs_calculation_mode_check CHECK (calculation_mode = ANY (ARRAY['interim'::text, 'final'::text]));
ALTER TABLE public.hr_payroll_runs ADD CONSTRAINT hr_payroll_runs_number_key UNIQUE (number);
ALTER TABLE public.hr_payroll_runs ADD CONSTRAINT hr_payroll_runs_pkey PRIMARY KEY (id);

CREATE TABLE public.hr_penalty_instances (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  employee_id uuid NOT NULL,
  attendance_day_id uuid,
  penalty_rule_id uuid,
  penalty_type hr_penalty_type NOT NULL,
  occurrence_in_month integer DEFAULT 1 NOT NULL,
  deduction_type hr_deduction_type DEFAULT 'none'::hr_deduction_type NOT NULL,
  deduction_days numeric(5,4) DEFAULT 0.0 NOT NULL,
  notes text,
  is_overridden boolean DEFAULT false NOT NULL,
  overridden_by uuid,
  override_reason text,
  overridden_at timestamp with time zone,
  payroll_run_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  is_manual boolean DEFAULT false NOT NULL,
  manual_reason text,
  deduction_minutes integer DEFAULT 0
);
ALTER TABLE public.hr_penalty_instances ADD CONSTRAINT hr_penalty_instances_pkey PRIMARY KEY (id);
ALTER TABLE public.hr_penalty_instances ADD CONSTRAINT uq_penalty_day_type UNIQUE (attendance_day_id, penalty_type);

CREATE TABLE public.hr_penalty_rules (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  penalty_type hr_penalty_type NOT NULL,
  min_minutes integer DEFAULT 0 NOT NULL,
  max_minutes integer,
  occurrence_from integer DEFAULT 1 NOT NULL,
  occurrence_to integer,
  deduction_type hr_deduction_type DEFAULT 'none'::hr_deduction_type NOT NULL,
  deduction_custom_minutes integer DEFAULT 0,
  escalate_to_disciplinary boolean DEFAULT false NOT NULL,
  notify_manager boolean DEFAULT true NOT NULL,
  notify_hr boolean DEFAULT false NOT NULL,
  notify_ceo boolean DEFAULT false NOT NULL,
  is_active boolean DEFAULT true NOT NULL,
  sort_order integer DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.hr_penalty_rules ADD CONSTRAINT hr_penalty_rules_pkey PRIMARY KEY (id);

CREATE TABLE public.hr_permission_requests (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  employee_id uuid NOT NULL,
  permission_date date NOT NULL,
  leave_time time without time zone NOT NULL,
  expected_return time without time zone,
  actual_return time without time zone,
  duration_minutes integer,
  reason text NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  approved_by uuid,
  action_at timestamp with time zone,
  rejection_reason text,
  month_permit_count integer,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  return_note text
);
ALTER TABLE public.hr_permission_requests ADD CONSTRAINT hr_permission_requests_pkey PRIMARY KEY (id);
ALTER TABLE public.hr_permission_requests ADD CONSTRAINT hr_permission_requests_status_check CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text]));

CREATE TABLE public.hr_public_holidays (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  holiday_date date NOT NULL,
  year integer GENERATED ALWAYS AS ((EXTRACT(year FROM holiday_date))::integer) STORED NOT NULL,
  is_recurring boolean DEFAULT false NOT NULL,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.hr_public_holidays ADD CONSTRAINT hr_public_holidays_holiday_date_key UNIQUE (holiday_date);
ALTER TABLE public.hr_public_holidays ADD CONSTRAINT hr_public_holidays_pkey PRIMARY KEY (id);

CREATE TABLE public.hr_work_locations (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  branch_id uuid,
  latitude numeric(10,7) NOT NULL,
  longitude numeric(10,7) NOT NULL,
  radius_meters integer DEFAULT 200 NOT NULL,
  require_selfie boolean DEFAULT false NOT NULL,
  gps_accuracy_threshold integer DEFAULT 150 NOT NULL,
  is_active boolean DEFAULT true NOT NULL,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.hr_work_locations ADD CONSTRAINT hr_work_locations_pkey PRIMARY KEY (id);

CREATE TABLE public.role_permissions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  role_id uuid NOT NULL,
  permission text NOT NULL
);
ALTER TABLE public.role_permissions ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (id);
ALTER TABLE public.role_permissions ADD CONSTRAINT role_permissions_role_id_permission_key UNIQUE (role_id, permission);

CREATE TABLE public.roles (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  name_ar text NOT NULL,
  description text,
  is_system boolean DEFAULT false NOT NULL,
  color text DEFAULT '#6b7280'::text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  grade integer DEFAULT 10 NOT NULL
);
ALTER TABLE public.roles ADD CONSTRAINT roles_name_key UNIQUE (name);
ALTER TABLE public.roles ADD CONSTRAINT roles_pkey PRIMARY KEY (id);

CREATE TABLE public.user_permission_overrides (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id uuid NOT NULL,
  permission text NOT NULL,
  granted boolean NOT NULL,
  granted_by uuid NOT NULL,
  reason text,
  expires_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.user_permission_overrides ADD CONSTRAINT user_permission_overrides_pkey PRIMARY KEY (id);
ALTER TABLE public.user_permission_overrides ADD CONSTRAINT user_permission_overrides_user_id_permission_key UNIQUE (user_id, permission);

CREATE TABLE public.user_roles (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id uuid NOT NULL,
  role_id uuid NOT NULL,
  branch_id uuid,
  is_active boolean DEFAULT true NOT NULL,
  assigned_by uuid,
  assigned_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_pkey PRIMARY KEY (id);
ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_user_id_role_id_key UNIQUE (user_id, role_id);
