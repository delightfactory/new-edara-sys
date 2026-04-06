// ============================================================
// HR Module Types — موديول الموارد البشرية
// نسخة 2 — مراجعة مزدوجة مع SQL مباشرة
// Maps to:
//   17_hr_core.sql
//   18_hr_attendance_leaves.sql
//   19_hr_payroll_loans.sql
//   19b_hr_core_hotfixes.sql
// ============================================================

// ─────────────────────────────────────────────────────────────
// ENUMS — مطابقة حرفية للـ CREATE TYPE في SQL
// ─────────────────────────────────────────────────────────────

// 17_hr_core.sql
export type HRGender         = 'male' | 'female'
export type HRMaritalStatus  = 'single' | 'married' | 'divorced' | 'widowed'
export type HREmployeeStatus = 'active' | 'on_leave' | 'suspended' | 'terminated'
export type HRContractType   = 'permanent' | 'fixed_term' | 'part_time' | 'freelance' | 'probation'
export type HRDayOfWeek      = 'saturday' | 'sunday' | 'monday' | 'tuesday' | 'wednesday' | 'thursday' | 'friday'
export type HRDocumentType   =
  | 'national_id' | 'passport' | 'driving_license'
  | 'employment_contract' | 'educational_certificate'
  | 'social_insurance' | 'medical_certificate' | 'other'

// 18_hr_attendance_leaves.sql
export type HRAttendanceStatus =
  | 'present' | 'late' | 'half_day'
  | 'absent_unauthorized' | 'absent_authorized'
  | 'on_leave' | 'weekly_off' | 'public_holiday'

export type HRCheckoutStatus =
  | 'on_time' | 'early_authorized' | 'early_unauthorized'
  | 'overtime' | 'auto'

export type HRReviewStatus = 'ok' | 'needs_review' | 'reviewed'
export type HRAttendancePolicyMode = 'assigned_only' | 'field_allowed'
export type HRTrackingStatus = 'idle' | 'active' | 'ended' | 'stale' | 'outside_zone'
export type HRAttendanceAlertType =
  | 'tracking_gap'
  | 'outside_allowed_zone'
  | 'permission_no_return'
  | 'auto_checkout'
  | 'manual_correction'
  | 'missing_day'
  | 'open_day_unclosed'
export type HRAttendanceAlertStatus = 'open' | 'resolved' | 'dismissed'
export type HRAttendanceAlertSeverity = 'low' | 'medium' | 'high'

export type HRLeaveRequestStatus =
  | 'draft' | 'pending_supervisor' | 'approved_supervisor'
  | 'pending_hr' | 'approved' | 'rejected' | 'cancelled'

export type HRPenaltyType =
  | 'late' | 'absent_unauthorized' | 'early_leave_unauthorized' | 'out_of_range'

export type HRDeductionType =
  | 'none' | 'warning' | 'quarter_day' | 'half_day' | 'full_day' | 'custom_minutes'

// 19_hr_payroll_loans.sql
export type HRPayrollRunStatus =
  | 'draft' | 'calculating' | 'review' | 'approved' | 'paid' | 'cancelled'

export type HRAdvanceType = 'instant' | 'scheduled'

export type HRAdvanceStatus =
  | 'pending_supervisor' | 'pending_hr' | 'pending_finance'
  | 'approved' | 'rejected' | 'paid' | 'fully_repaid' | 'cancelled'

export type HRInstallmentStatus = 'pending' | 'deducted' | 'deferred' | 'skipped'

export type HRCommissionSourceType = 'sales' | 'collection' | 'delivery'

// ─────────────────────────────────────────────────────────────
// 17. DEPARTMENTS — hr_departments
// ─────────────────────────────────────────────────────────────

export interface HRDepartment {
  id: string
  name: string
  name_en: string | null
  code: string | null
  parent_id: string | null
  manager_id: string | null
  branch_id: string | null
  is_active: boolean
  created_at: string
  updated_at: string
  // joined
  parent?: Pick<HRDepartment, 'id' | 'name'>
  manager?: Pick<HREmployee, 'id' | 'full_name'>
  children?: HRDepartment[]
}

export interface HRDepartmentInput {
  name: string
  name_en?: string | null
  code?: string | null
  parent_id?: string | null
  manager_id?: string | null
  branch_id?: string | null
  is_active?: boolean
}

// ─────────────────────────────────────────────────────────────
// 17. POSITIONS — hr_positions
// ─────────────────────────────────────────────────────────────

export interface HRPosition {
  id: string
  name: string
  name_en: string | null
  department_id: string | null
  grade: number | null              // INTEGER درجة وظيفية
  min_salary: number | null
  max_salary: number | null
  is_field: boolean                 // وظيفة ميدانية (مندوب، سائق)
  is_active: boolean
  created_at: string
  updated_at: string
  // joined
  department?: Pick<HRDepartment, 'id' | 'name'>
}

export interface HRPositionInput {
  name: string
  name_en?: string | null
  department_id?: string | null
  grade?: number | null
  min_salary?: number | null
  max_salary?: number | null
  is_field?: boolean
  is_active?: boolean
}

// ─────────────────────────────────────────────────────────────
// 17. EMPLOYEES — hr_employees
// ─────────────────────────────────────────────────────────────

export interface HREmployee {
  id: string
  employee_number: string           // EMP-00001 (Trigger auto-generated)
  user_id: string | null            // ربط بـ auth.users (NULL = بدون حساب)

  // البيانات الشخصية
  full_name: string
  full_name_en: string | null
  national_id: string | null
  birth_date: string | null          // DATE
  gender: HRGender | null
  marital_status: HRMaritalStatus | null
  address: string | null
  personal_phone: string            // NOT NULL
  emergency_phone: string | null
  emergency_contact: string | null  // اسم جهة الاتصال الطارئ

  // بيانات التوظيف
  department_id: string | null
  position_id: string | null
  branch_id: string | null
  direct_manager_id: string | null
  status: HREmployeeStatus
  hire_date: string                  // DATE
  probation_end_date: string | null  // DATE
  termination_date: string | null    // DATE
  termination_reason: string | null

  // العطلة الأسبوعية (NULL = يتبع إعداد الشركة)
  weekly_off_day: HRDayOfWeek | null

  // نمط العمل
  is_field_employee: boolean
  work_location_id: string | null   // موقع الحضور الافتراضي
  attendance_checkin_mode: HRAttendancePolicyMode
  attendance_checkout_mode: HRAttendancePolicyMode
  allowed_checkin_location_ids: string[]
  allowed_checkout_location_ids: string[]

  // الراتب الحالي (cached — يُحدَّث بالـ Trigger)
  base_salary: number
  transport_allowance: number
  housing_allowance: number
  other_allowances: number
  readonly gross_salary: number     // GENERATED ALWAYS AS

  notes: string | null
  created_by: string | null
  created_at: string
  updated_at: string

  // joined
  department?: Pick<HRDepartment, 'id' | 'name'>
  position?: Pick<HRPosition, 'id' | 'name'>
  direct_manager?: Pick<HREmployee, 'id' | 'full_name'>
  work_location?: Pick<HRWorkLocation, 'id' | 'name'>
}

export interface HREmployeeInput {
  full_name: string
  full_name_en?: string | null
  national_id?: string | null
  birth_date?: string | null
  gender?: HRGender | null
  marital_status?: HRMaritalStatus | null
  address?: string | null
  personal_phone: string
  emergency_phone?: string | null
  emergency_contact?: string | null
  department_id?: string | null
  position_id?: string | null
  branch_id?: string | null
  direct_manager_id?: string | null
  status?: HREmployeeStatus
  hire_date: string
  probation_end_date?: string | null
  termination_date?: string | null
  termination_reason?: string | null
  weekly_off_day?: HRDayOfWeek | null
  is_field_employee?: boolean
  work_location_id?: string | null
  attendance_checkin_mode?: HRAttendancePolicyMode
  attendance_checkout_mode?: HRAttendancePolicyMode
  allowed_checkin_location_ids?: string[]
  allowed_checkout_location_ids?: string[]
  base_salary: number
  transport_allowance?: number
  housing_allowance?: number
  other_allowances?: number
  notes?: string | null
}

// ─────────────────────────────────────────────────────────────
// 17. CONTRACTS — hr_contracts
// ─────────────────────────────────────────────────────────────

export interface HRContract {
  id: string
  employee_id: string
  contract_type: HRContractType
  start_date: string                // DATE
  end_date: string | null           // DATE (NULL = دائم)
  base_salary: number
  transport_allowance: number
  housing_allowance: number
  other_allowances: number
  // لا gross_salary هنا — الجدول لا يحتوي على GENERATED COLUMN
  notes: string | null
  document_url: string | null
  created_by: string | null
  created_at: string
  // لا updated_at — سجل تاريخي ثابت
}

export interface HRContractInput {
  employee_id: string
  contract_type: HRContractType
  start_date: string
  end_date?: string | null
  base_salary: number
  transport_allowance?: number
  housing_allowance?: number
  other_allowances?: number
  notes?: string | null
  document_url?: string | null
}

// ─────────────────────────────────────────────────────────────
// 17. SALARY HISTORY — hr_salary_history
// ─────────────────────────────────────────────────────────────

export interface HRSalaryHistory {
  id: string
  employee_id: string
  effective_date: string            // DATE تاريخ سريان هذا الراتب
  base_salary: number
  transport_allowance: number
  housing_allowance: number
  other_allowances: number
  readonly gross_salary: number     // GENERATED ALWAYS AS
  change_reason: string | null
  changed_by: string | null
  created_at: string
}

// ─────────────────────────────────────────────────────────────
// 17. WORK LOCATIONS — hr_work_locations
// ─────────────────────────────────────────────────────────────

export interface HRWorkLocation {
  id: string
  name: string
  branch_id: string | null
  latitude: number
  longitude: number
  radius_meters: number             // INTEGER الدائرة بالأمتار
  require_selfie: boolean
  gps_accuracy_threshold: number    // INTEGER أقصى قيمة GPS مقبولة
  is_active: boolean
  notes: string | null
  created_by: string | null
  created_at: string
  updated_at: string
  // joined
  branch?: { id: string; name: string }
}

export interface HRWorkLocationInput {
  name: string
  branch_id?: string | null
  latitude: number
  longitude: number
  radius_meters?: number
  require_selfie?: boolean
  gps_accuracy_threshold?: number
  is_active?: boolean
  notes?: string | null
}

// ─────────────────────────────────────────────────────────────
// 17. DELEGATIONS — hr_delegations
// ─────────────────────────────────────────────────────────────

export interface HRDelegation {
  id: string
  delegator_id: string
  delegate_id: string
  permissions: string[]             // TEXT[]
  scope_type: 'team' | 'branch' | 'all'
  scope_id: string | null
  valid_from: string                // TIMESTAMPTZ
  valid_until: string               // TIMESTAMPTZ
  reason: string | null
  is_active: boolean
  created_by: string | null
  created_at: string
  // joined
  delegator?: Pick<HREmployee, 'id' | 'full_name'>
  delegate?: Pick<HREmployee, 'id' | 'full_name'>
}

// ─────────────────────────────────────────────────────────────
// 17. EMPLOYEE DOCUMENTS — hr_employee_documents
// ─────────────────────────────────────────────────────────────

export interface HREmployeeDocument {
  id: string
  employee_id: string
  document_type: HRDocumentType
  document_number: string | null
  issue_date: string | null         // DATE
  expiry_date: string | null        // DATE
  file_url: string | null
  notes: string | null
  uploaded_by: string | null
  created_at: string
}

// ─────────────────────────────────────────────────────────────
// 18. PUBLIC HOLIDAYS — hr_public_holidays
// ─────────────────────────────────────────────────────────────

export interface HRPublicHoliday {
  id: string
  name: string
  holiday_date: string              // DATE
  readonly year: number             // GENERATED ALWAYS AS — INTEGER
  is_recurring: boolean
  notes: string | null
  created_by: string | null
  created_at: string
}

export interface HRPublicHolidayInput {
  name: string
  holiday_date: string
  is_recurring?: boolean
  notes?: string | null
}

// ─────────────────────────────────────────────────────────────
// 18. ATTENDANCE DAYS — hr_attendance_days
// ─────────────────────────────────────────────────────────────

export interface HRAttendanceDay {
  id: string
  employee_id: string
  shift_date: string                // DATE تاريخ الوردية (للتجميع)
  work_date: string                 // DATE تاريخ الدخول الفعلي
  punch_in_time: string | null      // TIMESTAMPTZ
  punch_out_time: string | null     // TIMESTAMPTZ
  location_in_id: string | null
  location_out_id: string | null
  gps_accuracy_in: number | null    // NUMERIC(8,2) بالأمتار
  gps_accuracy_out: number | null
  status: HRAttendanceStatus
  checkout_status: HRCheckoutStatus | null
  late_minutes: number              // INTEGER
  early_leave_minutes: number       // INTEGER
  overtime_minutes: number          // INTEGER
  effective_hours: number | null    // NUMERIC(4,2)
  day_value: number                 // NUMERIC(4,4) 1=كامل 0.5=نصف 0=غياب
  is_auto_checkout: boolean
  review_status: HRReviewStatus
  tracking_started_at: string | null
  tracking_ended_at: string | null
  last_tracking_ping_at: string | null
  last_tracking_lat: number | null
  last_tracking_lng: number | null
  last_tracking_accuracy: number | null
  tracking_status: HRTrackingStatus
  tracking_ping_count: number
  outside_zone_count: number
  reviewed_by: string | null
  reviewed_at: string | null        // TIMESTAMPTZ
  notes: string | null
  created_at: string
  updated_at: string
  // joined
  employee?: Pick<HREmployee, 'id' | 'full_name' | 'employee_number'>
  location_in?: Pick<HRWorkLocation, 'id' | 'name'>
  location_out?: Pick<HRWorkLocation, 'id' | 'name'>
}

export interface HRAttendanceDayInput {
  employee_id: string
  shift_date: string
  work_date?: string
  punch_in_time?: string | null
  punch_out_time?: string | null
  location_in_id?: string | null
  location_out_id?: string | null
  gps_accuracy_in?: number | null
  gps_accuracy_out?: number | null
  status?: HRAttendanceStatus
  late_minutes?: number
  early_leave_minutes?: number
  overtime_minutes?: number
  effective_hours?: number | null
  day_value?: number
  review_status?: HRReviewStatus
  notes?: string | null
}

// ─────────────────────────────────────────────────────────────
// 18. ATTENDANCE LOGS — hr_attendance_logs (Append-only GPS)
// ─────────────────────────────────────────────────────────────

export interface HRAttendanceLog {
  id: string
  employee_id: string
  attendance_day_id: string | null  // NULL إذا لم يُنشأ اليوم بعد
  log_type: 'check_in' | 'check_out' | 'location_ping' | 'auto_checkout'
  latitude: number                  // NUMERIC(10,7)
  longitude: number                 // NUMERIC(10,7)
  gps_accuracy: number | null       // NUMERIC(8,2) بالأمتار
  location_id: string | null        // أقرب موقع عمل مُعتمَد
  is_offline_sync: boolean          // هل سُجِّل أثناء انقطاع الإنترنت؟
  event_time: string                // TIMESTAMPTZ — الوقت الفعلي للحدث
  synced_at: string | null          // TIMESTAMPTZ — متى وصل للسيرفر
  requires_review: boolean
  device_info: string | null
  created_at: string
  // لا updated_at — Append-only
}

export interface HRAttendanceLogInput {
  employee_id: string
  attendance_day_id?: string | null
  log_type: 'check_in' | 'check_out' | 'location_ping' | 'auto_checkout'
  latitude: number
  longitude: number
  gps_accuracy?: number | null
  location_id?: string | null
  /** true إذا كان السجل مُخزَّناً محلياً ويُزامَن الآن */
  is_offline_sync?: boolean
  /** وقت الحدث الفعلي — ضروري في Offline Mode */
  event_time?: string
  device_info?: string | null
}

export interface HRAttendanceAlert {
  id: string
  employee_id: string
  attendance_day_id: string | null
  alert_type: HRAttendanceAlertType
  severity: HRAttendanceAlertSeverity
  status: HRAttendanceAlertStatus
  title: string
  details: string | null
  metadata: Record<string, unknown> | null
  started_at: string
  resolved_at: string | null
  resolved_by: string | null
  resolution_note: string | null
  created_at: string
  updated_at: string
  employee?: Pick<HREmployee, 'id' | 'full_name' | 'employee_number'>
}

export interface HRAttendanceAlertInput {
  employee_id: string
  attendance_day_id?: string | null
  alert_type: HRAttendanceAlertType
  severity?: HRAttendanceAlertSeverity
  status?: HRAttendanceAlertStatus
  title: string
  details?: string | null
  metadata?: Record<string, unknown> | null
  started_at?: string
  resolution_note?: string | null
}

// ─────────────────────────────────────────────────────────────
// 18. LEAVE TYPES — hr_leave_types
// ─────────────────────────────────────────────────────────────

export interface HRLeaveType {
  id: string
  name: string
  name_en: string | null
  code: string
  max_days_per_year: number | null
  max_days_per_request: number | null
  is_paid: boolean
  has_balance: boolean
  deducts_from_balance: boolean
  requires_approval: boolean
  approval_levels: 1 | 2
  requires_document: boolean
  can_carry_forward: boolean
  affects_salary: boolean           // يؤثر على الراتب (بدون أجر)
  is_system: boolean                // لا يمكن حذفه
  eligible_gender: 'all' | 'male' | 'female'
  is_active: boolean
  created_at: string
}

export interface HRLeaveTypeInput {
  name: string
  name_en?: string | null
  code: string
  max_days_per_year?: number | null
  max_days_per_request?: number | null
  is_paid?: boolean
  has_balance?: boolean
  deducts_from_balance?: boolean
  requires_approval?: boolean
  approval_levels?: 1 | 2
  requires_document?: boolean
  can_carry_forward?: boolean
  affects_salary?: boolean
  eligible_gender?: 'all' | 'male' | 'female'
  is_active?: boolean
}

// ─────────────────────────────────────────────────────────────
// 18. LEAVE BALANCES — hr_leave_balances
// ─────────────────────────────────────────────────────────────

export interface HRLeaveBalance {
  id: string
  employee_id: string
  leave_type_id: string
  year: number                      // INTEGER
  total_days: number
  used_days: number
  pending_days: number
  carried_forward: number
  readonly remaining_days: number   // GENERATED ALWAYS AS
  updated_at: string
  // joined
  leave_type?: Pick<HRLeaveType, 'id' | 'name' | 'code'>
}

// ─────────────────────────────────────────────────────────────
// 18. LEAVE REQUESTS — hr_leave_requests
// ─────────────────────────────────────────────────────────────

export interface HRLeaveRequest {
  id: string
  employee_id: string
  leave_type_id: string
  start_date: string                // DATE
  end_date: string                  // DATE
  days_count: number
  reason: string | null
  document_url: string | null
  status: HRLeaveRequestStatus
  supervisor_id: string | null
  supervisor_action_at: string | null  // TIMESTAMPTZ
  supervisor_notes: string | null
  hr_manager_id: string | null
  hr_action_at: string | null          // TIMESTAMPTZ
  hr_notes: string | null
  rejection_reason: string | null
  rejected_by: string | null
  rejected_at: string | null           // TIMESTAMPTZ
  created_at: string
  updated_at: string
  // joined
  employee?: Pick<HREmployee, 'id' | 'full_name' | 'employee_number'>
  leave_type?: Pick<HRLeaveType, 'id' | 'name' | 'code' | 'is_paid'>
  supervisor?: Pick<HREmployee, 'id' | 'full_name'>
}

export interface HRLeaveRequestInput {
  employee_id: string
  leave_type_id: string
  start_date: string
  end_date: string
  days_count: number
  reason?: string | null
  document_url?: string | null
  supervisor_id?: string | null
}

// ─────────────────────────────────────────────────────────────
// 18. PERMISSION REQUESTS — hr_permission_requests
// ─────────────────────────────────────────────────────────────

export interface HRPermissionRequest {
  id: string
  employee_id: string
  permission_date: string           // DATE
  leave_time: string                // TIME → 'HH:MM:SS'
  expected_return: string | null    // TIME
  actual_return: string | null      // TIME
  duration_minutes: number | null   // INTEGER
  reason: string
  status: 'pending' | 'approved' | 'rejected'
  approved_by: string | null
  action_at: string | null          // TIMESTAMPTZ
  rejection_reason: string | null
  return_note: string | null
  month_permit_count: number | null // عدد مرات الإذن في الشهر
  created_at: string
  updated_at: string
  // joined
  employee?: Pick<HREmployee, 'id' | 'full_name'>
  approved_by_emp?: Pick<HREmployee, 'id' | 'full_name'>
}

export interface HRPermissionRequestInput {
  employee_id: string
  permission_date: string
  leave_time: string
  expected_return?: string | null
  actual_return?: string | null
  reason: string
}

// ─────────────────────────────────────────────────────────────
// 18. PENALTY RULES — hr_penalty_rules
// ─────────────────────────────────────────────────────────────

export interface HRPenaltyRule {
  id: string
  name: string
  penalty_type: HRPenaltyType
  min_minutes: number               // INTEGER
  max_minutes: number | null        // INTEGER (NULL = بلا حد)
  occurrence_from: number           // INTEGER من التكرار رقم
  occurrence_to: number | null      // INTEGER (NULL = كل المرات)
  deduction_type: HRDeductionType
  deduction_custom_minutes: number  // INTEGER
  escalate_to_disciplinary: boolean
  notify_manager: boolean
  notify_hr: boolean
  notify_ceo: boolean
  is_active: boolean
  sort_order: number                // INTEGER
  created_at: string
}

export interface HRPenaltyRuleInput {
  name: string
  penalty_type: HRPenaltyType
  min_minutes: number
  max_minutes: number | null
  occurrence_from: number
  occurrence_to: number | null
  deduction_type: HRDeductionType
  is_active: boolean
  sort_order: number
}

// ─────────────────────────────────────────────────────────────
// 18. PENALTY INSTANCES — hr_penalty_instances
// ─────────────────────────────────────────────────────────────

export interface HRPenaltyInstance {
  id: string
  employee_id: string
  attendance_day_id: string | null
  penalty_rule_id: string | null
  penalty_type: HRPenaltyType
  occurrence_in_month: number       // INTEGER
  deduction_type: HRDeductionType
  deduction_days: number            // NUMERIC(4,4): 0.25, 0.5, 1.0
  notes: string | null
  is_overridden: boolean
  overridden_by: string | null
  override_reason: string | null
  overridden_at: string | null      // TIMESTAMPTZ
  payroll_run_id: string | null
  created_at: string
  // joined
  employee?: Pick<HREmployee, 'id' | 'full_name'>
  penalty_rule?: Pick<HRPenaltyRule, 'id' | 'name' | 'deduction_type'>
}

// ─────────────────────────────────────────────────────────────
// 19. PAYROLL PERIODS — hr_payroll_periods
// ─────────────────────────────────────────────────────────────

export interface HRPayrollPeriod {
  id: string
  year: number                      // INTEGER
  month: number                     // INTEGER 1-12
  name: string                      // مثل: "مارس 2026"
  start_date: string                // DATE
  end_date: string                  // DATE
  is_closed: boolean                // فترة مغلقة: لا تعديل
  created_at: string
}

export interface HRPayrollPeriodInput {
  year: number
  month: number
  name: string
  start_date: string
  end_date: string
}

// ─────────────────────────────────────────────────────────────
// 19. PAYROLL RUNS — hr_payroll_runs
// ─────────────────────────────────────────────────────────────

export interface HRPayrollRun {
  id: string
  number: string | null             // PAY-2026-03-001 (Trigger)
  period_id: string
  branch_id: string | null          // NULL = كل الفروع
  status: HRPayrollRunStatus
  total_gross: number               // NUMERIC(16,2)
  total_deductions: number          // NUMERIC(16,2)
  total_net: number                 // NUMERIC(16,2)
  total_employees: number           // INTEGER
  calculated_by: string | null
  calculated_at: string | null      // TIMESTAMPTZ
  approved_by: string | null
  approved_at: string | null        // TIMESTAMPTZ
  paid_by: string | null
  paid_at: string | null            // TIMESTAMPTZ
  journal_entry_id: string | null
  notes: string | null
  created_by: string | null
  created_at: string
  updated_at: string
  // joined
  period?: Pick<HRPayrollPeriod, 'id' | 'name' | 'year' | 'month' | 'start_date' | 'end_date'>
}

export interface HRPayrollRunInput {
  period_id: string
  branch_id?: string | null
  notes?: string | null
}

// ─────────────────────────────────────────────────────────────
// 19. PAYROLL LINES — hr_payroll_lines
// ─────────────────────────────────────────────────────────────

export interface HRPayrollLine {
  id: string
  payroll_run_id: string
  employee_id: string
  period_id: string

  // أيام العمل
  total_working_days: number        // INTEGER أيام العمل الإجمالية في الشهر
  actual_work_days: number          // NUMERIC(5,2) الأيام الصافية
  absent_days: number               // NUMERIC(5,2)
  deducted_days: number             // NUMERIC(5,2) من الجزاءات
  overtime_hours: number            // NUMERIC(5,2)

  // المستحقات
  base_salary: number
  transport_allowance: number
  housing_allowance: number
  other_allowances: number
  overtime_amount: number
  commission_amount: number
  bonus_amount: number              // مكافأة استثنائية
  gross_earned: number              // المستحق الفعلي (Pro-rata)

  // الخصومات
  absence_deduction: number
  penalty_deduction: number
  advance_deduction: number         // خصم السلفة/الأقساط
  social_insurance: number
  income_tax: number
  health_insurance: number
  other_deductions: number          // خصومات أخرى
  total_deductions: number

  // الصافي
  net_salary: number
  deficit_carryover: number         // المبلغ المُرحّل للشهر التالي عند عجز الراتب

  // حالة الموظف في هذا الشهر
  is_partial_month: boolean         // انضم أو غادر في منتصف الشهر
  hire_date_in_period: string | null   // DATE بداية الاستحقاق
  term_date_in_period: string | null   // DATE نهاية الاستحقاق

  // Overrides
  override_net: number | null       // تعديل يدوي للصافي
  override_reason: string | null
  notes: string | null
  created_at: string

  // joined
  employee?: Pick<HREmployee, 'id' | 'full_name' | 'employee_number'>
}

// ─────────────────────────────────────────────────────────────
// 19. ADVANCES — hr_advances
// ─────────────────────────────────────────────────────────────

export interface HRAdvance {
  id: string
  number: string | null             // ADV-00001 (Trigger)
  employee_id: string
  advance_type: HRAdvanceType       // 'instant' | 'scheduled'
  amount: number                    // NUMERIC(12,2) > 0
  installments_count: number        // 1 = فورية
  monthly_installment: number | null // القسط الشهري
  reason: string
  status: HRAdvanceStatus

  // دورة الاعتماد
  supervisor_id: string | null
  supervisor_action_at: string | null   // TIMESTAMPTZ
  supervisor_notes: string | null

  hr_manager_id: string | null
  hr_action_at: string | null           // TIMESTAMPTZ
  hr_notes: string | null

  finance_user_id: string | null    // profile المالية التي تصرف
  finance_action_at: string | null  // TIMESTAMPTZ
  finance_notes: string | null
  vault_id: string | null           // الخزنة التي صُرفت منها

  rejection_reason: string | null
  rejected_by: string | null        // hr_employees FK

  // متبقي السلفة (cached)
  paid_amount: number
  readonly remaining_amount: number // GENERATED ALWAYS AS (amount - paid_amount)

  created_by: string | null
  created_at: string
  updated_at: string

  // joined
  employee?: Pick<HREmployee, 'id' | 'full_name' | 'employee_number'>
  installments?: HRAdvanceInstallment[]
}

export interface HRAdvanceInput {
  employee_id: string
  advance_type: HRAdvanceType
  amount: number
  installments_count: number
  reason: string
  supervisor_id?: string | null
}

// ─────────────────────────────────────────────────────────────
// 19. ADVANCE INSTALLMENTS — hr_advance_installments
// ─────────────────────────────────────────────────────────────

export interface HRAdvanceInstallment {
  id: string
  advance_id: string
  installment_number: number        // INTEGER
  period_id: string | null
  due_year: number                  // INTEGER
  due_month: number                 // INTEGER 1-12
  amount: number                    // NUMERIC(12,2)
  status: HRInstallmentStatus
  deducted_in_run_id: string | null // hr_payroll_runs FK
  deferred_reason: string | null
  deferred_to_month: number | null  // INTEGER
  deferred_to_year: number | null   // INTEGER
  created_at: string
}

// ─────────────────────────────────────────────────────────────
// 19. COMMISSION TARGETS — hr_commission_targets
// ─────────────────────────────────────────────────────────────

export interface HRCommissionTarget {
  id: string
  employee_id: string
  period_id: string
  target_amount: number             // NUMERIC(14,2) الهدف البيعي
  commission_rate: number           // NUMERIC(5,2) النسبة الأساسية
  // شرائح العمولة المتدرجة
  tier_50_rate: number | null       // نسبة عند 50% من الهدف
  tier_75_rate: number | null       // نسبة عند 75% من الهدف
  tier_100_rate: number | null      // نسبة عند 100% من الهدف
  tier_120_rate: number | null      // نسبة عند تجاوز 120%
  notes: string | null
  created_by: string | null
  created_at: string
  // joined
  employee?: Pick<HREmployee, 'id' | 'full_name' | 'employee_number'>
  period?: Pick<HRPayrollPeriod, 'id' | 'name' | 'year' | 'month'>
}

export interface HRCommissionTargetInput {
  employee_id: string
  period_id: string
  target_amount: number
  commission_rate: number
  tier_50_rate?: number | null
  tier_75_rate?: number | null
  tier_100_rate?: number | null
  tier_120_rate?: number | null
  notes?: string | null
}

// ─────────────────────────────────────────────────────────────
// 19. COMMISSION RECORDS — hr_commission_records
//     تُغذَّى تلقائياً من موديول المبيعات والتحصيلات
// ─────────────────────────────────────────────────────────────

export interface HRCommissionRecord {
  id: string
  employee_id: string
  period_id: string
  source_type: HRCommissionSourceType  // 'sales' | 'collection' | 'delivery'
  source_id: string                    // معرّف الفاتورة أو الإيصال
  gross_amount: number                 // قيمة البيع NUMERIC(14,2)
  collected_amount: number             // المحصَّل فعلاً NUMERIC(14,2)
  commission_rate: number              // NUMERIC(5,2)
  commission_amount: number            // NUMERIC(12,2)
  is_eligible: boolean                 // هل المبلغ محصَّل فعلاً؟
  included_in_run: string | null       // hr_payroll_runs FK
  created_at: string
  // joined
  employee?: Pick<HREmployee, 'id' | 'full_name' | 'employee_number'>
  period?: Pick<HRPayrollPeriod, 'id' | 'name'>
}

// ─────────────────────────────────────────────────────────────
// RPC RESPONSE TYPES — أنواع نتائج الدوال المخزنة
// ─────────────────────────────────────────────────────────────

/** نتيجة validate_attendance_location */
export interface LocationValidationResult {
  valid: boolean
  location_id?: string
  location_name?: string
  distance_meters?: number
  require_selfie?: boolean
  is_field_employee?: boolean
  code?: 'NO_LOCATION_FOUND' | 'OUT_OF_RANGE' | 'LOW_GPS_ACCURACY'
  message?: string
  nearest_location?: string
  requires_review?: boolean
}

/** نتيجة get_employee_salary_at_date — SETOF */
export interface EmployeeSalaryAtDate {
  base_salary: number
  transport_allowance: number
  housing_allowance: number
  other_allowances: number
  gross_salary: number
  effective_date: string            // DATE
}

/** نتيجة get_monthly_attendance_summary */
export interface MonthlyAttendanceSummary {
  working_days: number
  present_days: number
  absent_unauthorized: number
  absent_authorized: number
  on_leave_days: number
  weekly_off_days: number
  public_holidays: number
  total_late_minutes: number
  total_overtime_minutes: number
  penalty_deduction_days: number
}

/** نتيجة approve_payroll_run */
export interface PayrollApprovalResult {
  success: boolean
  run_id: string
  journal_entry_id: string
  accounting_summary: {
    debit: {
      dr_5310_salaries: number
      dr_5320_overtime: number
      dr_5330_commission: number
      total_debit: number
    }
    credit: {
      cr_2310_net_payable: number
      cr_2320_advances: number
      cr_2330_insurance: number
      cr_2340_income_tax: number
      total_credit: number
    }
    balanced: boolean
  }
  total_employees: number
}

export interface HRAttendanceReviewSummary {
  open_alerts: number
  unresolved_days: number
  permission_no_return: number
  auto_checkout_days: number
  tracking_gap_days: number
  open_day_unclosed: number
  total_blocking_items: number
}

/** نتيجة request_advance */
export interface AdvanceRequestResult {
  success: boolean
  advance_id: string
  installments_created: number
  message: string
}

/** نتيجة link_employee_to_user */
export interface LinkEmployeeResult {
  success: boolean
  user_id?: string
  code?: 'USER_NOT_FOUND' | 'USER_ALREADY_LINKED'
  message: string
}

/**
 * نتيجة get_employee_live_statement RPC
 * هيكل متداخل — ليس كائناً مسطحاً
 * ملاحظة: net_salary و income_tax لا تُحسب هنا،
 *   تُحسب فقط عند اعتماد مسير الرواتب النهائي (approve_payroll_run)
 */
export interface EmployeeLiveStatement {
  /** بيانات الموظف الأساسية */
  employee: {
    id: string
    full_name: string
    employee_number: string
    position_name: string | null
    department_name: string | null
  }
  /** المستحقات — من بيانات الراتب الحالية */
  earnings: {
    base_salary: number
    transport_allowance: number
    housing_allowance: number
    other_allowances: number
    gross_salary: number
    /** عمولات مسجلة (is_eligible = true) */
    commission_amount: number
  }
  /**
   * مؤشرات الحضور والخصومات (تقديرية)
   * من get_monthly_attendance_summary — لا تُمثل خصماً مالياً موثقاً
   */
  attendance: {
    working_days: number
    present_days: number
    /** أيام الغياب غير المبرر */
    absent_unauthorized: number
    /** إجمالي دقائق التأخير */
    total_late_minutes: number
    /** أيام الجزاءات (تقديري — تُحتسب فعلاً في المسير) */
    penalty_deduction_days: number
    total_overtime_minutes: number
  }
  /**
   * السلف النشطة وأقساطها الحالية
   * فقط السلف بحالة 'approved' | 'paid' (لم تُسدَّد بالكامل)
   */
  advances: Array<{
    id: string
    number: string | null
    amount: number
    remaining_amount: number
    /** القسط الشهري الذي سيُخصم في المسير */
    monthly_installment: number | null
    reason: string
  }>
  /** بيانات الفترة */
  period: {
    year: number
    month: number
    /** الاسم بالعربية، مثل: "مارس 2026" */
    month_name: string
  }
  /** هل الموظف انضم أو غادر في هذا الشهر؟ */
  is_partial_month: boolean
}

// ─────────────────────────────────────────────────────────────
// DELEGATIONS — hr_delegations
// ─────────────────────────────────────────────────────────────

export type HRDelegationScopeType = 'team' | 'branch' | 'all'

export interface HRDelegation {
  id: string
  delegator_id: string    // hr_employees FK — المفوِّض
  delegate_id: string     // hr_employees FK — المفوَّض إليه (DB column: delegate_id)
  permissions: string[]   // TEXT[] — مصفوفة الصلاحيات مثل: ['hr.leaves.approve']
  scope_type: HRDelegationScopeType   // 'team' | 'branch' | 'all'
  scope_id: string | null // فرع أو فريق محدد (NULL = كل)
  valid_from: string      // TIMESTAMPTZ — بداية التفويض
  valid_until: string     // TIMESTAMPTZ — نهاية التفويض
  reason: string | null
  is_active: boolean
  created_by: string | null
  created_at: string
  // joined (Supabase allows custom alias in select — we use 'delegator' and 'delegate')
  delegator?: Pick<HREmployee, 'id' | 'full_name'>
  delegate?: Pick<HREmployee, 'id' | 'full_name'>
}

export interface HRDelegationInput {
  delegator_id: string
  delegate_id: string     // DB column name
  permissions: string[]   // مصفوفة الصلاحيات
  scope_type?: HRDelegationScopeType
  scope_id?: string | null
  valid_from: string      // ISO datetime
  valid_until: string     // ISO datetime
  reason?: string | null
}

// ─────────────────────────────────────────────────────────────
// DOCUMENT INPUT — رفع وثيقة للموظف
// ─────────────────────────────────────────────────────────────

export interface HREmployeeDocumentInput {
  employee_id: string
  document_type: HRDocumentType
  document_number?: string | null
  issue_date?: string | null
  expiry_date?: string | null
  file_url?: string | null
  notes?: string | null
}

// ─────────────────────────────────────────────────────────────
// HR PAYROLL ADJUSTMENTS — مكافآت / خصومات / جزاءات يدوية
// ─────────────────────────────────────────────────────────────

export type HRAdjustmentType = 'bonus' | 'deduction' | 'penalty'
export type HRAdjustmentStatus = 'pending' | 'approved' | 'rejected'

export interface HRPayrollAdjustment {
  id: string
  employee_id: string
  type: HRAdjustmentType
  amount: number
  reason: string
  effective_date: string
  status: HRAdjustmentStatus
  created_by: string | null
  approved_by: string | null
  approved_at: string | null
  rejection_reason: string | null
  payroll_line_id: string | null
  created_at: string
  updated_at: string
  // joins
  employee?: Pick<HREmployee, 'id' | 'full_name' | 'employee_number'>
  creator?: { full_name: string }
  approver?: { full_name: string }
}

export interface HRPayrollAdjustmentInput {
  employee_id: string
  type: HRAdjustmentType
  amount: number
  reason: string
  effective_date: string
}

// ─────────────────────────────────────────────────────────────
// HR SELF-SERVICE PAYSLIP SUMMARY
// ─────────────────────────────────────────────────────────────

export interface EmployeePayslipSummary {
  line_id: string
  period_year: number
  period_month: number
  period_name: string
  run_status: 'approved' | 'paid'
  base_salary: number
  total_allowances: number
  total_deductions: number
  net_salary: number
  
  // Breakdown
  transport_allowance: number
  housing_allowance: number
  other_allowances: number
  overtime_amount: number
  commission_amount: number
  bonus_amount: number

  absence_deduction: number
  penalty_deduction: number
  advance_deduction: number
  social_insurance: number
  health_insurance: number
  other_deductions: number
}
