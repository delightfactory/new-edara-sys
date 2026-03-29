import { supabase } from '@/lib/supabase/client'
import type {
  HREmployee, HREmployeeInput,
  HRDepartment, HRDepartmentInput,
  HRPosition, HRPositionInput,
  HRContract, HRContractInput,
  HRSalaryHistory,
  HRWorkLocation, HRWorkLocationInput,
  HRDelegation, HRDelegationInput,
  HRDocumentType, HREmployeeDocument, HREmployeeDocumentInput,
  HRAttendanceDay, HRAttendanceDayInput,
  HRAttendanceLog, HRAttendanceLogInput,
  HRPublicHoliday, HRPublicHolidayInput,
  HRLeaveType, HRLeaveBalance, HRLeaveRequest, HRLeaveRequestInput,
  HRPermissionRequest, HRPermissionRequestInput,
  HRPenaltyRule, HRPenaltyInstance,
  HRPayrollPeriod, HRPayrollPeriodInput, HRPayrollRun, HRPayrollRunInput, HRPayrollLine,
  HRAdvance, HRAdvanceInput, HRAdvanceInstallment,
  HRAdvanceStatus,
  HRCommissionTarget, HRCommissionTargetInput,
  HRCommissionRecord,
  LocationValidationResult, EmployeeSalaryAtDate, MonthlyAttendanceSummary,
  PayrollApprovalResult, AdvanceRequestResult,
  LinkEmployeeResult, EmployeeLiveStatement,
} from '@/lib/types/hr'

// ─────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────

async function getCurrentUserId(): Promise<string> {
  const { data } = await supabase.auth.getUser()
  if (!data.user) throw new Error('المستخدم غير مسجل دخوله')
  return data.user.id
}

// ─────────────────────────────────────────────────────────────
// DEPARTMENTS — الأقسام
// ─────────────────────────────────────────────────────────────

export async function getDepartments(onlyActive = true) {
  let query = supabase
    .from('hr_departments')
    .select('*, parent:parent_id(id, name)')
    .order('name')
  if (onlyActive) query = query.eq('is_active', true)
  const { data, error } = await query
  if (error) throw error
  return data as HRDepartment[]
}

export async function createDepartment(input: HRDepartmentInput) {
  const { data, error } = await supabase
    .from('hr_departments')
    .insert(input)
    .select('*')
    .single()
  if (error) throw error
  return data as HRDepartment
}

export async function updateDepartment(id: string, input: Partial<HRDepartmentInput>) {
  const { data, error } = await supabase
    .from('hr_departments')
    .update(input)
    .eq('id', id)
    .select('*')
    .single()
  if (error) throw error
  return data as HRDepartment
}

/**
 * حذف ناعم للقسم: يُوقفه (is_active=false) بدلاً من الحذف الفعلي
 * الـ FK constraint في DB ستمنع تلقائياً حذف قسم فيه موظفون نشطون
 */
export async function deleteDepartment(id: string) {
  const { error } = await supabase
    .from('hr_departments')
    .update({ is_active: false })
    .eq('id', id)
  if (error) throw error
}

// ─────────────────────────────────────────────────────────────
// POSITIONS — المسميات الوظيفية
// ─────────────────────────────────────────────────────────────

export async function getPositions(departmentId?: string) {
  let query = supabase
    .from('hr_positions')
    .select('*, department:hr_departments(id, name)')
    .eq('is_active', true)
    .order('name')
  if (departmentId) query = query.eq('department_id', departmentId)
  const { data, error } = await query
  if (error) throw error
  return data as HRPosition[]
}

export async function createPosition(input: HRPositionInput) {
  const { data, error } = await supabase
    .from('hr_positions')
    .insert(input)
    .select('*, department:hr_departments(id, name)')
    .single()
  if (error) throw error
  return data as HRPosition
}

export async function updatePosition(id: string, input: Partial<HRPositionInput>) {
  const { data, error } = await supabase
    .from('hr_positions')
    .update(input)
    .eq('id', id)
    .select('*, department:hr_departments(id, name)')
    .single()
  if (error) throw error
  return data as HRPosition
}

/** حذف ناعم: is_active=false — يمنع حذف مسمى له موظفون (FK في DB) */
export async function deletePosition(id: string) {
  const { error } = await supabase
    .from('hr_positions')
    .update({ is_active: false })
    .eq('id', id)
  if (error) throw error
}

// ─────────────────────────────────────────────────────────────
// EMPLOYEES — الموظفون
// ─────────────────────────────────────────────────────────────

export async function getEmployees(params?: {
  search?: string
  departmentId?: string
  branchId?: string
  status?: string
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 50
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('hr_employees')
    .select(`
      *,
      department:department_id(id, name),
      position:position_id(id, name),
      direct_manager:direct_manager_id(id, full_name)
    `, { count: 'estimated' })
    .order('full_name')
    .range(from, to)

  if (params?.search)       query = query.or(`full_name.ilike.%${params.search}%,employee_number.ilike.%${params.search}%`)
  if (params?.departmentId) query = query.eq('department_id', params.departmentId)
  if (params?.branchId)     query = query.eq('branch_id', params.branchId)
  if (params?.status)       query = query.eq('status', params.status)

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as HREmployee[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

export async function getEmployee(id: string) {
  const { data, error } = await supabase
    .from('hr_employees')
    .select(`
      *,
      department:department_id(id, name),
      position:position_id(id, name),
      direct_manager:direct_manager_id(id, full_name),
      contracts:hr_contracts(*),
      documents:hr_employee_documents(*)
    `)
    .eq('id', id)
    .single()
  if (error) throw error
  return data as HREmployee & { contracts: HRContract[]; documents: HREmployeeDocument[] }
}

/**
 * الموظف المرتبط بالمستخدم الحالي — للشاشات الذاتية (Self-Service)
 * يبحث عن سجل hr_employees حيث user_id = auth.uid()
 * يُرجع null إذا لم يكن المستخدم موظفاً مسجلاً
 */
export async function getCurrentEmployeeRecord(): Promise<HREmployee | null> {
  const userId = await getCurrentUserId()
  const { data, error } = await supabase
    .from('hr_employees')
    .select(`
      *,
      department:department_id(id, name),
      position:position_id(id, name),
      work_location:work_location_id(id, name, latitude, longitude, radius_meters)
    `)
    .eq('user_id', userId)
    .maybeSingle()
  if (error) throw error
  return data as HREmployee | null
}

export async function createEmployee(input: HREmployeeInput) {
  const userId = await getCurrentUserId()
  const { data, error } = await supabase
    .from('hr_employees')
    .insert({ ...input, created_by: userId })
    .select(`
      *,
      department:hr_departments(id, name),
      position:hr_positions(id, name)
    `)
    .single()
  if (error) throw error
  return data as HREmployee
}

export async function updateEmployee(id: string, input: Partial<HREmployeeInput>) {
  const { data, error } = await supabase
    .from('hr_employees')
    .update(input)
    .eq('id', id)
    .select(`
      *,
      department:hr_departments(id, name),
      position:hr_positions(id, name)
    `)
    .single()
  if (error) throw error
  return data as HREmployee
}

/**
 * ربط موظف بمستخدم موجود في auth.users — عبر RPC
 * يُستخدم لمنح الموظف صلاحية الدخول لواجهة الموظف الذاتية
 */
export async function linkEmployeeToUser(employeeId: string, email: string): Promise<LinkEmployeeResult> {
  const { data, error } = await supabase.rpc('link_employee_to_user', {
    p_employee_id: employeeId,
    p_email: email,
  })
  if (error) throw error
  return data as LinkEmployeeResult
}

// ─────────────────────────────────────────────────────────────
// SALARY HISTORY — تاريخ الراتب
// ─────────────────────────────────────────────────────────────

export async function getEmployeeSalaryHistory(employeeId: string) {
  const { data, error } = await supabase
    .from('hr_salary_history')
    .select('*')
    .eq('employee_id', employeeId)
    .order('effective_date', { ascending: false })
  if (error) throw error
  return data as HRSalaryHistory[]
}

/**
 * الراتب الفعّال لموظف في تاريخ محدد — عبر RPC
 * يُستخدم في حساب الرواتب للتعامل مع الترقيات في منتصف الشهر
 */
export async function getEmployeeSalaryAtDate(
  employeeId: string,
  date = new Date().toISOString().split('T')[0]
): Promise<EmployeeSalaryAtDate> {
  const { data, error } = await supabase.rpc('get_employee_salary_at_date', {
    p_employee_id: employeeId,
    p_date: date,
  })
  if (error) throw error
  // الدالة تُرجع SETOF - نأخذ أول صف
  const rows = data as EmployeeSalaryAtDate[]
  if (!rows || rows.length === 0) throw new Error('لا توجد بيانات راتب لهذا الموظف')
  return rows[0]
}

// ─────────────────────────────────────────────────────────────
// CONTRACTS — العقود
// ─────────────────────────────────────────────────────────────

export async function createContract(input: HRContractInput) {
  const userId = await getCurrentUserId()
  const { data, error } = await supabase
    .from('hr_contracts')
    .insert({ ...input, created_by: userId })
    .select('*')
    .single()
  if (error) throw error
  return data as HRContract
}

export async function getContracts(employeeId: string) {
  const { data, error } = await supabase
    .from('hr_contracts')
    .select('*')
    .eq('employee_id', employeeId)
    .order('start_date', { ascending: false })
  if (error) throw error
  return (data ?? []) as HRContract[]
}

// ─────────────────────────────────────────────────────────────
// WORK LOCATIONS — مواقع العمل GPS
// ─────────────────────────────────────────────────────────────

export async function getWorkLocations() {
  const { data, error } = await supabase
    .from('hr_work_locations')
    .select('*, branch:branches(id, name)')
    .eq('is_active', true)
    .order('name')
  if (error) throw error
  return data as HRWorkLocation[]
}

export async function createWorkLocation(input: HRWorkLocationInput) {
  const { data, error } = await supabase
    .from('hr_work_locations')
    .insert(input)
    .select('*')
    .single()
  if (error) throw error
  return data as HRWorkLocation
}

export async function updateWorkLocation(id: string, input: Partial<HRWorkLocationInput>) {
  const { data, error } = await supabase
    .from('hr_work_locations')
    .update(input)
    .eq('id', id)
    .select('*')
    .single()
  if (error) throw error
  return data as HRWorkLocation
}

/** حذف ناعم لموقع الحضور: is_active=false (يمنع مرور الحضور عليه) */
export async function deleteWorkLocation(id: string) {
  const { error } = await supabase
    .from('hr_work_locations')
    .update({ is_active: false })
    .eq('id', id)
  if (error) throw error
}

/**
 * التحقق من صحة موقع GPS للحضور — عبر RPC
 * @param gpsAccuracy دقة GPS بالأمتار (من navigator.geolocation)
 */
export async function validateAttendanceLocation(params: {
  employeeId: string
  latitude: number
  longitude: number
  gpsAccuracy?: number | null
}): Promise<LocationValidationResult> {
  const { data, error } = await supabase.rpc('validate_attendance_location', {
    p_employee_id: params.employeeId,
    p_latitude:    params.latitude,
    p_longitude:   params.longitude,
    p_gps_accuracy: params.gpsAccuracy ?? null,
  })
  if (error) throw error
  return data as LocationValidationResult
}

// ─────────────────────────────────────────────────────────────
// DELEGATIONS — التفويضات
// ─────────────────────────────────────────────────────────────

export async function checkDelegatedPermission(userId: string, permission: string): Promise<boolean> {
  const { data, error } = await supabase.rpc('check_delegated_permission', {
    p_user_id:    userId,
    p_permission: permission,
  })
  if (error) throw error
  return data as boolean
}

// ─────────────────────────────────────────────────────────────
// ATTENDANCE — الحضور
// ─────────────────────────────────────────────────────────────

export async function getAttendanceDays(params: {
  employeeId?: string
  dateFrom: string
  dateTo: string
  page?: number
  pageSize?: number
}) {
  const page = params.page || 1
  const pageSize = params.pageSize || 31
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('hr_attendance_days')
    .select(`
      *,
      employee:hr_employees(id, full_name, employee_number),
      location_in:hr_work_locations!hr_attendance_days_location_in_id_fkey(id, name),
      location_out:hr_work_locations!hr_attendance_days_location_out_id_fkey(id, name)
    `, { count: 'estimated' })
    .gte('shift_date', params.dateFrom)
    .lte('shift_date', params.dateTo)
    .order('shift_date', { ascending: false })
    .range(from, to)

  if (params.employeeId) query = query.eq('employee_id', params.employeeId)

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as HRAttendanceDay[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

export async function upsertAttendanceDay(input: HRAttendanceDayInput) {
  const { data, error } = await supabase
    .from('hr_attendance_days')
    .upsert(input, { onConflict: 'employee_id,shift_date' })
    .select('*')
    .single()
  if (error) throw error
  return data as HRAttendanceDay
}

/**
 * ✅ تسجيل الحضور/الانصراف الذري عبر RPC
 * يقوم بكل شيء في معاملة واحدة SECURITY DEFINER:
 *   1. التحقق من هوية الموظف (user_id → employee_id)
 *   2. التحقق من GPS وصحة الموقع
 *   3. كتابة سجل في hr_attendance_logs
 *   4. إنشاء/تحديث hr_attendance_days
 */
export interface AttendanceGPSResult {
  success: boolean
  action?: 'check_in' | 'check_out'
  attendance_day_id?: string
  log_id?: string
  location_name?: string
  location_id?: string
  shift_date?: string
  event_time?: string
  code?: string
  error?: string
  nearest_location?: string
  distance_meters?: number
}

export async function recordAttendanceGPS(params: {
  latitude:    number
  longitude:   number
  gps_accuracy: number
  log_type:    'check_in' | 'check_out'
  event_time?: string
}): Promise<AttendanceGPSResult> {
  const { data, error } = await supabase.rpc('record_attendance_gps', {
    p_latitude:    params.latitude,
    p_longitude:   params.longitude,
    p_gps_accuracy: params.gps_accuracy,
    p_log_type:    params.log_type,
    p_event_time:  params.event_time ?? null,
  })
  if (error) throw error
  return data as AttendanceGPSResult
}

/**
 * @deprecated استخدم recordAttendanceGPS بدلاً منها
 * hذه الدالة تكتب في hr_attendance_logs فقط بدون إنشاء hr_attendance_days
 */
export async function logAttendanceGPS(input: HRAttendanceLogInput) {
  const logEntry = {
    ...input,
    event_time: input.event_time ?? new Date().toISOString(),
    synced_at:  input.is_offline_sync ? new Date().toISOString() : null,
  }
  const { data, error } = await supabase
    .from('hr_attendance_logs')
    .insert(logEntry)
    .select('*')
    .single()
  if (error) throw error
  return data as HRAttendanceLog
}


/**
 * تطبيق الجزاءات على يوم حضور — عبر RPC
 * تُستدعى بعد تسجيل/تعديل سجل الحضور اليومي
 */
export async function processAttendancePenalties(attendanceDayId: string): Promise<number> {
  const { data, error } = await supabase.rpc('process_attendance_penalties', {
    p_attendance_day_id: attendanceDayId,
  })
  if (error) throw error
  return data as number // عدد الجزاءات المطبقة
}

/**
 * ملخص الحضور الشهري لموظف — عبر RPC
 * يُستخدم في كشف الحساب اللحظي (Live Statement)
 */
export async function getMonthlyAttendanceSummary(
  employeeId: string,
  year: number,
  month: number
): Promise<MonthlyAttendanceSummary> {
  const { data, error } = await supabase.rpc('get_monthly_attendance_summary', {
    p_employee_id: employeeId,
    p_year:        year,
    p_month:       month,
  })
  if (error) throw error
  return data as MonthlyAttendanceSummary
}

// ─────────────────────────────────────────────────────────────
// PUBLIC HOLIDAYS — العطل الرسمية
// ─────────────────────────────────────────────────────────────

export async function getPublicHolidays(year?: number) {
  let query = supabase
    .from('hr_public_holidays')
    .select('*')
    .order('holiday_date')
  if (year) query = query.eq('year', year)
  const { data, error } = await query
  if (error) throw error
  return data as HRPublicHoliday[]
}

export async function createPublicHoliday(input: HRPublicHolidayInput) {
  const userId = await getCurrentUserId()
  const { data, error } = await supabase
    .from('hr_public_holidays')
    .insert({ ...input, created_by: userId })
    .select('*')
    .single()
  if (error) throw error
  return data as HRPublicHoliday
}

/** حذف فعلي لعطلة رسمية — آمن: لا FK يعتمد عليها (تُستخدم في الحساب وقت التشغيل فقط) */
export async function deletePublicHoliday(id: string) {
  const { error } = await supabase
    .from('hr_public_holidays')
    .delete()
    .eq('id', id)
  if (error) throw error
}

// ─────────────────────────────────────────────────────────────
// LEAVES — الإجازات
// ─────────────────────────────────────────────────────────────

export async function getLeaveTypes(onlyActive = true) {
  let query = supabase.from('hr_leave_types').select('*').order('name')
  if (onlyActive) query = query.eq('is_active', true)
  const { data, error } = await query
  if (error) throw error
  return data as HRLeaveType[]
}

export async function getLeaveBalances(employeeId: string, year?: number) {
  let query = supabase
    .from('hr_leave_balances')
    .select('*, leave_type:hr_leave_types(id, name, code)')
    .eq('employee_id', employeeId)
  if (year) query = query.eq('year', year)
  const { data, error } = await query
  if (error) throw error
  return data as HRLeaveBalance[]
}

export async function getLeaveRequests(params?: {
  employeeId?: string
  status?: string
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 25
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('hr_leave_requests')
    .select(`
      *,
      employee:hr_employees(id, full_name, employee_number),
      leave_type:hr_leave_types(id, name, code, is_paid),
      supervisor:hr_employees!hr_leave_requests_supervisor_id_fkey(id, full_name)
    `, { count: 'estimated' })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.employeeId) query = query.eq('employee_id', params.employeeId)
  if (params?.status)     query = query.eq('status', params.status)

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as HRLeaveRequest[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

export async function createLeaveRequest(input: HRLeaveRequestInput) {
  const { data, error } = await supabase
    .from('hr_leave_requests')
    .insert(input)
    .select(`
      *,
      leave_type:hr_leave_types(id, name, code, is_paid)
    `)
    .single()
  if (error) throw error
  return data as HRLeaveRequest
}

export async function updateLeaveRequestStatus(
  id: string,
  status: string,
  notes?: string | null,
  rejectionReason?: string | null
) {
  const { data, error } = await supabase
    .from('hr_leave_requests')
    .update({
      status,
      ...(notes && { supervisor_notes: notes }),
      ...(rejectionReason && { rejection_reason: rejectionReason }),
    })
    .eq('id', id)
    .select('*')
    .single()
  if (error) throw error
  return data as HRLeaveRequest
}

/**
 * إلغاء طلب إجازة من قِبَل الموظف نفسه
 * مشروط: يعمل فقط إذا كان الطلب (draft) أو (pending_supervisor)
 * لا يمكن إلغاء طلب معتمد نهائياً أو مرفوض
 */
export async function cancelLeaveRequest(id: string) {
  const { data, error } = await supabase
    .from('hr_leave_requests')
    .update({ status: 'cancelled' })
    .eq('id', id)
    .in('status', ['draft', 'pending_supervisor'])   // ← حماية صارمة
    .select('*')
    .single()
  if (error) throw error
  if (!data) throw new Error('لا يمكن إلغاء هذا الطلب — تأكد أنه في حالة (مسودة) أو (بانتظار المشرف)')
  return data as HRLeaveRequest
}

// ─────────────────────────────────────────────────────────────
// PERMISSION REQUESTS — أذونات الانصراف
// ─────────────────────────────────────────────────────────────

export async function getPermissionRequests(params?: {
  employeeId?: string
  status?: string
  month?: string   // 'YYYY-MM'
}) {
  let query = supabase
    .from('hr_permission_requests')
    .select(`
      *,
      employee:hr_employees(id, full_name)
    `)
    .order('permission_date', { ascending: false })

  if (params?.employeeId) query = query.eq('employee_id', params.employeeId)
  if (params?.status)     query = query.eq('status', params.status)
  if (params?.month) {
    query = query
      .gte('permission_date', `${params.month}-01`)
      .lt('permission_date',  `${params.month}-32`)
  }

  const { data, error } = await query
  if (error) throw error
  return data as HRPermissionRequest[]
}

export async function createPermissionRequest(input: HRPermissionRequestInput) {
  const { data, error } = await supabase
    .from('hr_permission_requests')
    .insert(input)
    .select('*')
    .single()
  if (error) throw error
  return data as HRPermissionRequest
}

export async function approvePermissionRequest(id: string, approverId: string) {
  const { data, error } = await supabase
    .from('hr_permission_requests')
    .update({ status: 'approved', approved_by: approverId, action_at: new Date().toISOString() })
    .eq('id', id)
    .select('*')
    .single()
  if (error) throw error
  return data as HRPermissionRequest
}

/** رفض طلب إذن الانصراف — مشروط بحالة 'pending' فقط لمنع رفض معتمَد */
export async function rejectPermissionRequest(
  id: string,
  approverId: string,
  rejectionReason: string
) {
  const { data, error } = await supabase
    .from('hr_permission_requests')
    .update({
      status: 'rejected',
      approved_by: approverId,
      action_at: new Date().toISOString(),
      rejection_reason: rejectionReason.trim() || null,
    })
    .eq('id', id)
    .eq('status', 'pending')   // ← حماية: لا يرفض إلا المعلَّق
    .select('*')
    .single()
  if (error) throw error
  if (!data) throw new Error('الطلب غير موجود أو ليس في حالة (قيد المراجعة)')
  return data as HRPermissionRequest
}

// ─────────────────────────────────────────────────────────────
// PENALTY RULES & INSTANCES — الجزاءات
// ─────────────────────────────────────────────────────────────

export async function getPenaltyRules() {
  const { data, error } = await supabase
    .from('hr_penalty_rules')
    .select('*')
    .order('sort_order')
  if (error) throw error
  return data as HRPenaltyRule[]
}

export async function getPenaltyInstances(params: {
  employeeId?: string
  payrollRunId?: string
  month?: string   // 'YYYY-MM'
}) {
  let query = supabase
    .from('hr_penalty_instances')
    .select(`
      *,
      employee:hr_employees(id, full_name),
      penalty_rule:hr_penalty_rules(id, name, deduction_type)
    `)
    .order('created_at', { ascending: false })

  if (params.employeeId)  query = query.eq('employee_id', params.employeeId)
  if (params.payrollRunId) query = query.eq('payroll_run_id', params.payrollRunId)
  if (params.month) {
    query = query
      .gte('created_at', `${params.month}-01T00:00:00.000Z`)
      .lt('created_at',  `${params.month}-32T00:00:00.000Z`)
  }

  const { data, error } = await query
  if (error) throw error
  return data as HRPenaltyInstance[]
}

export async function overridePenalty(id: string, reason: string) {
  const userId = await getCurrentUserId()
  const { data, error } = await supabase
    .from('hr_penalty_instances')
    .update({
      is_overridden:   true,
      overridden_by:   userId,
      override_reason: reason,
      overridden_at:   new Date().toISOString(),
    })
    .eq('id', id)
    .select('*')
    .single()
  if (error) throw error
  return data as HRPenaltyInstance
}

// ─────────────────────────────────────────────────────────────
// PAYROLL — مسير الرواتب
// ─────────────────────────────────────────────────────────────

export async function getPayrollPeriods() {
  const { data, error } = await supabase
    .from('hr_payroll_periods')
    .select('*')
    .order('start_date', { ascending: false })
  if (error) throw error
  return data as HRPayrollPeriod[]
}

export async function createPayrollPeriod(input: HRPayrollPeriodInput) {
  const userId = await getCurrentUserId()
  const { data, error } = await supabase
    .from('hr_payroll_periods')
    .insert({ ...input, created_by: userId })
    .select('*')
    .single()
  if (error) throw error
  return data as HRPayrollPeriod
}

export async function createPayrollRun(input: HRPayrollRunInput): Promise<HRPayrollRun> {
  const userId = await getCurrentUserId()
  const { data, error } = await supabase
    .from('hr_payroll_runs')
    .insert({ ...input, created_by: userId, status: 'draft' })
    .select(`*, period:hr_payroll_periods(id, name, start_date, end_date)`)
    .single()
  if (error) throw error
  return data as HRPayrollRun
}

export async function getPayrollRuns(params?: { periodId?: string; branchId?: string }) {
  let query = supabase
    .from('hr_payroll_runs')
    .select(`
      *,
      period:hr_payroll_periods(id, name, start_date, end_date)
    `)
    .order('created_at', { ascending: false })

  if (params?.periodId) query = query.eq('period_id', params.periodId)
  if (params?.branchId) query = query.eq('branch_id', params.branchId)

  const { data, error } = await query
  if (error) throw error
  return data as HRPayrollRun[]
}

export async function getPayrollLines(runId: string) {
  const { data, error } = await supabase
    .from('hr_payroll_lines')
    .select(`
      *,
      employee:hr_employees(id, full_name, employee_number)
    `)
    .eq('payroll_run_id', runId)
    .order('employee_id')
  if (error) throw error
  return data as HRPayrollLine[]
}

/**
 * حساب راتب موظف واحد في مسير مُحدَّد — عبر RPC
 * التوقيع الحقيقي في 19_hr_payroll_loans.sql السطر 544:
 *   calculate_employee_payroll(p_employee_id UUID, p_run_id UUID) RETURNS UUID
 * لا يوجد p_employee_ids ولا p_user_id — موظف واحد في كل استدعاء
 */
export async function calculateEmployeePayroll(
  employeeId: string,
  runId: string
): Promise<string> {          // UUID of the created/updated payroll_line
  const { data, error } = await supabase.rpc('calculate_employee_payroll', {
    p_employee_id: employeeId,
    p_run_id:      runId,
  })
  if (error) throw error
  return data as string
}

/**
 * اعتماد مسير الرواتب وإنشاء القيد المحاسبي — عبر RPC
 * يُنشئ journal_entry مفصل (Dr. 5310/5320/5330 / Cr. 2310/2320/2330/2340)
 * يرفض EXCEPTION إذا كان القيد غير متوازن
 */
export async function approvePayrollRun(runId: string): Promise<PayrollApprovalResult> {
  const userId = await getCurrentUserId()
  const { data, error } = await supabase.rpc('approve_payroll_run', {
    p_run_id:  runId,
    p_user_id: userId,
  })
  if (error) throw error
  return data as PayrollApprovalResult
}

// ─────────────────────────────────────────────────────────────
// ADVANCES — السلف
// ─────────────────────────────────────────────────────────────

export async function getAdvances(params?: {
  employeeId?: string
  status?: HRAdvanceStatus
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 25
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('hr_advances')
    .select(`
      *,
      employee:hr_employees(id, full_name, employee_number),
      installments:hr_advance_installments(*)
    `, { count: 'estimated' })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.employeeId) query = query.eq('employee_id', params.employeeId)
  if (params?.status)     query = query.eq('status', params.status)

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as HRAdvance[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

/**
 * طلب سلفة عبر RPC request_advance
 * المعاملات مطابقة لـ 19_hr_payroll_loans.sql السطر 846
 */
export async function requestAdvance(input: HRAdvanceInput): Promise<AdvanceRequestResult> {
  const userId = await getCurrentUserId()
  const { data, error } = await supabase.rpc('request_advance', {
    p_employee_id:      input.employee_id,
    p_advance_type:     input.advance_type,
    p_amount:           input.amount,
    p_installments:     input.advance_type === 'instant' ? 1 : input.installments_count,
    p_reason:           input.reason,
    p_requested_by_uid: userId,           // ✅ الاسم الحقيقي في DB (لا p_user_id)
  })
  if (error) throw error
  // الـ RPC يُعيد JSONB وليس scalar — نتحقق من success
  const result = data as AdvanceRequestResult & { success: boolean; code?: string; message: string }
  if (result.success === false) {
    throw new Error(result.message ?? 'فشل طلب السلفة')
  }
  return result
}

export async function approveAdvance(id: string) {
  const userId = await getCurrentUserId()
  const { data, error } = await supabase
    .from('hr_advances')
    .update({ status: 'approved', approved_by: userId, approved_at: new Date().toISOString() })
    .eq('id', id)
    .select('*')
    .single()
  if (error) throw error
  return data as HRAdvance
}

export async function rejectAdvance(id: string, reason: string) {
  const { data, error } = await supabase
    .from('hr_advances')
    .update({ status: 'rejected', rejection_reason: reason })
    .eq('id', id)
    .select('*')
    .single()
  if (error) throw error
  return data as HRAdvance
}

/**
 * إلغاء طلب سلفة من قِبَل الموظف نفسه
 * مشروط: يعمل فقط إذا كانت السلفة (pending_supervisor) أو (pending_hr)
 * لا يمكن إلغاء سلفة مصروفة (approved/paid) أو مسددة (fully_repaid)
 */
export async function cancelAdvance(id: string) {
  const { data, error } = await supabase
    .from('hr_advances')
    .update({ status: 'cancelled' })
    .eq('id', id)
    .in('status', ['pending_supervisor', 'pending_hr'])   // ← حماية صارمة
    .select('*')
    .single()
  if (error) throw error
  if (!data) throw new Error('لا يمكن إلغاء هذه السلفة — يجب أن تكون في طور المراجعة فقط')
  return data as HRAdvance
}

/**
 * صرف السلفة — ذري محاسبياً (Finance Crossing Point)
 * يستدعي RPC disburse_employee_advance الذي يُنفِّذ في Transaction واحد:
 *   ① فحص حالة السلفة (pending_finance guard)
 *   ② سحب من الخزنة عبر add_vault_transaction (يفحص الرصيد الكافي)
 *   ③ قيد يومية متوازن Dr 2320 / Cr 1110-1120-1130
 *   ④ تحديث السلفة → approved → يُفعِّل Trigger توليد الأقساط
 *
 * الملف: supabase/migrations/19c_advances_finance_sync.sql
 */
export async function disburseAdvance(
  id: string,
  vaultId: string,
  notes?: string | null
): Promise<{ success: boolean; advance_id: string; journal_entry_id: string; vault_txn_id: string; amount: number; vault_name: string; message: string }> {
  const userId = await getCurrentUserId()
  const { data, error } = await supabase.rpc('disburse_employee_advance', {
    p_advance_id:       id,
    p_vault_id:         vaultId,
    p_finance_user_id:  userId,
    p_notes:            notes ?? null,
  })
  if (error) throw error
  return data
}

/**
 * تحديث حالة السلفة من قِبَل المشرف أو مدير الموارد البشرية
 * pending_supervisor → approved_supervisor / rejected
 * pending_hr         → pending_finance / rejected
 */
export async function updateAdvanceStatus(
  id: string,
  status: HRAdvanceStatus,
  notes?: string | null,
  rejectionReason?: string | null
): Promise<HRAdvance> {
  const userId = await getCurrentUserId()
  const { data, error } = await supabase
    .from('hr_advances')
    .update({
      status,
      ...(notes            && { hr_notes: notes }),
      ...(rejectionReason  && { rejection_reason: rejectionReason }),
    })
    .eq('id', id)
    .select('*')
    .single()
  if (error) throw error
  return data as HRAdvance
}


// ─────────────────────────────────────────────────────────────
// COMMISSION TARGETS — الأهداف والعمولات
// ─────────────────────────────────────────────────────────────

export async function getCommissionTargets(params?: {
  employeeId?: string
  periodId?: string
}) {
  let query = supabase
    .from('hr_commission_targets')
    .select(`
      *,
      employee:hr_employees(id, full_name, employee_number),
      period:hr_payroll_periods(id, name, year, month)
    `)
    .order('created_at', { ascending: false })

  if (params?.employeeId) query = query.eq('employee_id', params.employeeId)
  if (params?.periodId)   query = query.eq('period_id', params.periodId)

  const { data, error } = await query
  if (error) throw error
  return data as HRCommissionTarget[]
}

export async function createCommissionTarget(input: HRCommissionTargetInput) {
  const userId = await getCurrentUserId()
  const { data, error } = await supabase
    .from('hr_commission_targets')
    .insert({ ...input, created_by: userId })
    .select('*')
    .single()
  if (error) throw error
  return data as HRCommissionTarget
}

// ─────────────────────────────────────────────────────────────
// COMMISSION RECORDS — سجلات العمولات المحققة
// ─────────────────────────────────────────────────────────────

export async function getCommissionRecords(params?: {
  employeeId?: string
  periodId?: string
  sourceType?: string
}) {
  let query = supabase
    .from('hr_commission_records')
    .select(`
      *,
      employee:hr_employees(id, full_name, employee_number),
      period:hr_payroll_periods(id, name)
    `)
    .order('created_at', { ascending: false })

  if (params?.employeeId)  query = query.eq('employee_id', params.employeeId)
  if (params?.periodId)    query = query.eq('period_id', params.periodId)
  if (params?.sourceType)  query = query.eq('source_type', params.sourceType)

  const { data, error } = await query
  if (error) throw error
  return data as HRCommissionRecord[]
}

// ─────────────────────────────────────────────────────────────
// LIVE STATEMENT — كشف الحساب اللحظي للموظف
// ─────────────────────────────────────────────────────────────

/**
 * كشف الحساب اللحظي للموظف — عبر RPC
 * يجمع: بيانات الراتب + ملخص الحضور + الإجازات + السلف
 */
export async function getEmployeeLiveStatement(
  employeeId: string,
  year?: number,
  month?: number
): Promise<EmployeeLiveStatement> {
  const now = new Date()
  const { data, error } = await supabase.rpc('get_employee_live_statement', {
    p_employee_id: employeeId,
    p_year:        year  ?? now.getFullYear(),
    p_month:       month ?? now.getMonth() + 1,
  })
  if (error) throw error
  return data as EmployeeLiveStatement
}

// ─────────────────────────────────────────────────────────────
// EMPLOYEE DOCUMENTS — وثائق الموظف
// ─────────────────────────────────────────────────────────────

/**
 * رفع ملف وثيقة إلى Supabase Storage ثم تسجيل المسار في DB
 * Bucket: hr-documents (موجود مع RLS)
 */
export async function uploadEmployeeDocument(params: {
  employeeId: string
  documentType: HRDocumentType
  documentNumber?: string | null
  issueDate?: string | null
  expiryDate?: string | null
  notes?: string | null
  file: File
}): Promise<HREmployeeDocument> {
  const userId = await getCurrentUserId()

  // 1. رفع الملف إلى Storage
  const ext       = params.file.name.split('.').pop() ?? 'pdf'
  const path      = `${params.employeeId}/${params.documentType}_${Date.now()}.${ext}`
  const { error: uploadErr } = await supabase.storage
    .from('hr-documents')
    .upload(path, params.file, { cacheControl: '3600', upsert: false })
  if (uploadErr) throw uploadErr

  // 2. استخراج الـ public URL
  const { data: urlData } = supabase.storage.from('hr-documents').getPublicUrl(path)
  const fileUrl = urlData.publicUrl

  // 3. تسجيل في قاعدة البيانات
  const { data, error } = await supabase
    .from('hr_employee_documents')
    .insert({
      employee_id:     params.employeeId,
      document_type:   params.documentType,
      document_number: params.documentNumber  ?? null,
      issue_date:      params.issueDate       ?? null,
      expiry_date:     params.expiryDate      ?? null,
      notes:           params.notes           ?? null,
      file_url:        fileUrl,
      uploaded_by:     userId,
    })
    .select('*')
    .single()
  if (error) throw error
  return data as HREmployeeDocument
}

export async function createEmployeeDocument(input: HREmployeeDocumentInput): Promise<HREmployeeDocument> {
  const userId = await getCurrentUserId()
  const { data, error } = await supabase
    .from('hr_employee_documents')
    .insert({ ...input, uploaded_by: userId })
    .select('*')
    .single()
  if (error) throw error
  return data as HREmployeeDocument
}

// ─────────────────────────────────────────────────────────────
// DELEGATIONS — التفويضات الزمنية
// ─────────────────────────────────────────────────────────────

export async function getDelegations(params?: {
  delegatorId?: string
  delegateId?: string   // DB column: delegate_id (المفوَّض إليه)
  activeOnly?: boolean
}) {
  let query = supabase
    .from('hr_delegations')
    .select(`
      *,
      delegator:hr_employees!hr_delegations_delegator_id_fkey(id, full_name),
      delegate:hr_employees!hr_delegations_delegate_id_fkey(id, full_name)
    `)
    .order('created_at', { ascending: false })

  if (params?.delegatorId) query = query.eq('delegator_id', params.delegatorId)
  if (params?.delegateId)  query = query.eq('delegate_id',  params.delegateId)  // DB column
  if (params?.activeOnly)  query = query.eq('is_active', true)

  const { data, error } = await query
  if (error) throw error
  return data as HRDelegation[]
}

export async function createDelegation(input: HRDelegationInput): Promise<HRDelegation> {
  const userId = await getCurrentUserId()
  const { data, error } = await supabase
    .from('hr_delegations')
    .insert({
      delegator_id: input.delegator_id,
      delegate_id:  input.delegate_id,   // DB column name
      permissions:  input.permissions,   // TEXT[]
      scope_type:   input.scope_type  ?? 'all',
      scope_id:     input.scope_id    ?? null,
      valid_from:   input.valid_from,
      valid_until:  input.valid_until,
      reason:       input.reason      ?? null,
      is_active: true,
      created_by: userId,
    })
    .select('*')
    .single()
  if (error) throw error
  return data as HRDelegation
}

export async function cancelDelegation(id: string): Promise<void> {
  const { error } = await supabase
    .from('hr_delegations')
    .update({ is_active: false })
    .eq('id', id)
  if (error) throw error
}

// ─────────────────────────────────────────────────────────────
// ADVANCE INSTALLMENTS — تأجيل القسط (F-C)
// ─────────────────────────────────────────────────────────────

/**
 * تأجيل قسط سلفة إلى شهر لاحق (F-C)
 * يستخدم عند: إجازة بدون راتب، قرار إداري موثق
 */
export async function deferInstallment(
  installmentId: string,
  reason: string,
  deferToMonth: number,
  deferToYear: number
): Promise<HRAdvanceInstallment> {
  const { data, error } = await supabase
    .from('hr_advance_installments')
    .update({
      status:           'deferred',
      deferred_reason:  reason,
      deferred_to_month: deferToMonth,
      deferred_to_year:  deferToYear,
    })
    .eq('id', installmentId)
    .select('*')
    .single()
  if (error) throw error
  return data as HRAdvanceInstallment
}

export async function getAdvanceInstallments(advanceId: string): Promise<HRAdvanceInstallment[]> {
  const { data, error } = await supabase
    .from('hr_advance_installments')
    .select('*')
    .eq('advance_id', advanceId)
    .order('installment_number')
  if (error) throw error
  return data as HRAdvanceInstallment[]
}

// ─────────────────────────────────────────────────────────────
// SALARY HISTORY — تعديل الراتب المباشر بدون عقد (F-D)
// ─────────────────────────────────────────────────────────────

/**
 * تعديل راتب الموظف مباشرة عبر إدخال سجل جديد في hr_salary_history
 * يترتب عليه تحديث تلقائي لـ hr_employees عبر Trigger
 */
export async function updateSalaryDirectly(params: {
  employeeId: string
  baseSalary: number
  transportAllowance?: number
  housingAllowance?: number
  otherAllowances?: number
  reason: string
  effectiveDate?: string
}): Promise<HRSalaryHistory> {
  const userId = await getCurrentUserId()

  // جلب بيانات الراتب الحالية
  const { data: emp } = await supabase
    .from('hr_employees')
    .select('base_salary, transport_allowance, housing_allowance, other_allowances')
    .eq('id', params.employeeId)
    .single()

  const transport  = params.transportAllowance ?? emp?.transport_allowance ?? 0
  const housing    = params.housingAllowance   ?? emp?.housing_allowance   ?? 0
  const other      = params.otherAllowances    ?? emp?.other_allowances    ?? 0
  const grossSalary = params.baseSalary + transport + housing + other

  // إنشاء سجل تاريخي (الـ Trigger سيحدّث hr_employees تلقائياً في بعض التكوينات)
  const { data, error } = await supabase
    .from('hr_salary_history')
    .insert({
      employee_id:          params.employeeId,
      base_salary:          params.baseSalary,
      transport_allowance:  transport,
      housing_allowance:    housing,
      other_allowances:     other,
      gross_salary:         grossSalary,
      effective_date:       params.effectiveDate ?? new Date().toISOString().split('T')[0],
      change_reason:        params.reason,
      changed_by:           userId,
    })
    .select('*')
    .single()
  if (error) throw error

  // تحديث hr_employees بالقيم الجديدة
  await supabase
    .from('hr_employees')
    .update({
      base_salary:         params.baseSalary,
      transport_allowance: transport,
      housing_allowance:   housing,
      other_allowances:    other,
      gross_salary:        grossSalary,
    })
    .eq('id', params.employeeId)

  return data as HRSalaryHistory
}

// ─────────────────────────────────────────────────────────────
// PAYROLL LINES — تعديل يدوي لمكافأة وخصومات و override (F-E + F-F)
// ─────────────────────────────────────────────────────────────

/**
 * تعديل سطر مسير رواتب يدوياً قبل الاعتماد
 * يستخدم لـ:
 *   F-E: إدخال bonus_amount و other_deductions
 *   F-F: تحديد override_net مع سبب محفوظ للتدقيق
 * محمي: لا يعمل بعد الاعتماد (status = 'approved')
 */
export async function updatePayrollLine(
  lineId: string,
  updates: {
    bonus_amount?: number
    other_deductions?: number
    override_net?: number | null
    override_reason?: string | null
    notes?: string | null
  }
): Promise<HRPayrollLine> {
  const { data, error } = await supabase
    .from('hr_payroll_lines')
    .update(updates)
    .eq('id', lineId)
    .select('*, employee:hr_employees(id, full_name, employee_number)')
    .single()
  if (error) throw error
  return data as HRPayrollLine
}
