import { supabase } from '@/lib/supabase/client'
import { getAuthUserId } from '@/lib/services/_get-user-id'
import type { PostgrestError } from '@supabase/supabase-js'
import type {
  Activity, ActivityInput,
  CallDetail, CallDetailInput,
  ActivityType,
  VisitPlan, VisitPlanInput, VisitPlanItem, VisitPlanItemInput,
  VisitPlanTemplate,
  CallPlan, CallPlanInput, CallPlanItem, CallPlanItemInput,
  CallPlanTemplate,
  Target, TargetInput, TargetProgress, TargetAdjustment,
  TargetType, AdjustTargetInput,
  TargetRewardTier, TargetCustomer, TargetRewardPayout,
  RepPerformanceRow, PlanDailySummaryRow, TargetStatusRow,
  PlanStatus,
  ChecklistTemplate, ChecklistQuestion, ChecklistResponse,
  ChecklistResponseInput,
  ChecklistTemplateInput, ChecklistQuestionInput,
  ActivityTypeInput, TargetTypeInput,
  // RPC Inputs
  CreateVisitPlanAtomicInput,
  ConfirmVisitPlanAtomicInput,
  CancelVisitPlanAtomicInput,
  ReorderVisitPlanItemsAtomicInput,
  CloseVisitPlanAdministrativelyAtomicInput,
  StartVisitItemAtomicInput,
  CompleteVisitItemAtomicInput,
  SkipVisitItemAtomicInput,
  RescheduleVisitItemAtomicInput,
  RescheduleVisitItemToDateAtomicInput,
  CloseVisitDayMissedAtomicInput,
  AddVisitPlanItemAtomicInput,
  DeleteVisitPlanItemAtomicInput,
  // RPC Results
  CreateVisitPlanAtomicResult,
  ConfirmVisitPlanAtomicResult,
  CancelVisitPlanAtomicResult,
  ReorderVisitPlanItemsAtomicResult,
  CloseVisitPlanAdministrativelyAtomicResult,
  StartVisitItemAtomicResult,
  CompleteVisitItemAtomicResult,
  SkipVisitItemAtomicResult,
  RescheduleVisitItemAtomicResult,
  RescheduleVisitItemToDateAtomicResult,
  CloseVisitDayMissedAtomicResult,
  AddVisitPlanItemAtomicResult,
  DeleteVisitPlanItemAtomicResult,
  // RPC Types & Unions
  VisitRpcResult,
  VisitOperationName,
  VisitStoragePath,
  VisitOutcomeType,
  VisitCompletionChecklistPhotoResponseInput,
  VisitCompletionChecklistResponseInput,
} from '@/lib/types/activities'

// ============================================================
// Helper — جلب UID المستخدم الحالي
// ============================================================


/** تنظيف مدخلات UUID — تحويل '' إلى null */
function sanitize<T extends Record<string, any>>(input: T): T {
  const cleaned = { ...input } as any
  for (const key of Object.keys(cleaned)) {
    if (cleaned[key] === '') cleaned[key] = null
  }
  return cleaned as T
}

// ============================================================
// Reference Data — قراءة فقط (staleTime: 10min في الـ hooks)
// ============================================================

export async function getActivityTypes(onlyActive = true): Promise<ActivityType[]> {
  let query = supabase
    .from('activity_types')
    .select('*')
    .order('sort_order')

  if (onlyActive) query = query.eq('is_active', true)

  const { data, error } = await query
  if (error) throw error
  return data as ActivityType[]
}

export async function createActivityType(input: ActivityTypeInput): Promise<ActivityType> {
  const { data, error } = await supabase
    .from('activity_types')
    .insert(sanitize(input))
    .select()
    .single()
  if (error) throw error
  return data as ActivityType
}

export async function updateActivityType(id: string, input: Partial<ActivityTypeInput>): Promise<ActivityType> {
  const { data, error } = await supabase
    .from('activity_types')
    .update(sanitize(input))
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as ActivityType
}

export async function getTargetTypes(onlyActive = true): Promise<TargetType[]> {
  let query = supabase
    .from('target_types')
    .select('*')
    .order('name')

  if (onlyActive) query = query.eq('is_active', true)

  const { data, error } = await query
  if (error) throw error
  return data as TargetType[]
}

export async function createTargetType(input: TargetTypeInput): Promise<TargetType> {
  const { data, error } = await supabase
    .from('target_types')
    .insert(sanitize(input))
    .select()
    .single()
  if (error) throw error
  return data as TargetType
}

export async function updateTargetType(id: string, input: Partial<TargetTypeInput>): Promise<TargetType> {
  const { data, error } = await supabase
    .from('target_types')
    .update(sanitize(input))
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as TargetType
}

export async function getVisitPlanTemplates(params?: { includeInactive?: boolean }): Promise<VisitPlanTemplate[]> {
  let q = supabase
    .from('visit_plan_templates')
    .select('*')
    .order('name')
  if (!params?.includeInactive) q = q.eq('is_active', true)
  const { data, error } = await q
  if (error) throw error
  return data as VisitPlanTemplate[]
}

export async function getCallPlanTemplates(params?: { includeInactive?: boolean }): Promise<CallPlanTemplate[]> {
  let q = supabase
    .from('call_plan_templates')
    .select('*')
    .order('name')
  if (!params?.includeInactive) q = q.eq('is_active', true)
  const { data, error } = await q
  if (error) throw error
  return data as CallPlanTemplate[]
}

// ============================================================
// Activities — الأنشطة
// ============================================================

// ✅ أعمدة مطابقة للـ schema — Wave A: أضفنا employee + plan_link
const ACTIVITY_SELECT = `
  *,
  type:activity_types!activities_type_id_fkey(id, name, code, category, icon, requires_gps, requires_customer),
  customer:customers(id, name, code, phone, latitude, longitude),
  call_detail:call_details(*),
  employee:hr_employees!activities_employee_id_fkey(id, full_name),
  visit_plan_item:visit_plan_items!activities_visit_plan_item_id_fkey(id, plan_id),
  call_plan_item:call_plan_items!activities_call_plan_item_id_fkey(id, plan_id)
`

export async function getActivities(params?: {
  employeeId?: string
  dateFrom?: string
  dateTo?: string
  typeCategory?: string       // 'visit' | 'call' | 'task' — يُفلتر بعد الجلب أو بـ inner join آمن
  outcomeType?: string
  customerId?: string
  includeDeleted?: boolean
  page?: number
  pageSize?: number
}) {
  const page     = params?.page     ?? 1
  const pageSize = params?.pageSize ?? 25
  const from     = (page - 1) * pageSize
  const to       = from + pageSize - 1

  let q = supabase
    .from('activities')
    .select(`
      *,
      type:activity_types!activities_type_id_fkey(id, name, code, category, icon),
      customer:customers(id, name, code)
    `, { count: 'estimated' })
    .order('activity_date', { ascending: false })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (!params?.includeDeleted) q = q.is('deleted_at', null)
  if (params?.employeeId)      q = q.eq('employee_id', params.employeeId)
  if (params?.dateFrom)        q = q.gte('activity_date', params.dateFrom)
  if (params?.dateTo)          q = q.lte('activity_date', params.dateTo)
  if (params?.outcomeType)     q = q.eq('outcome_type', params.outcomeType)
  if (params?.customerId)      q = q.eq('customer_id', params.customerId)

  // typeCategory: resolve to type_ids first so the filter hits the main table's
  // type_id column directly — guarantees accurate pagination counts regardless
  // of the PostgREST version's embedded-resource filter semantics.
  if (params?.typeCategory) {
    const { data: typeRows, error: typeLookupError } = await supabase
      .from('activity_types')
      .select('id')
      .eq('category', params.typeCategory)
    if (typeLookupError) throw typeLookupError

    const typeIds = (typeRows ?? []).map(t => t.id)
    if (typeIds.length === 0) {
      return { data: [], count: 0, page, pageSize, totalPages: 0 }
    }
    q = q.in('type_id', typeIds)
  }

  const { data, error, count } = await q
  if (error) throw error

  return {
    data: (data ?? []) as Activity[],
    count: count ?? 0,
    page,
    pageSize,
    totalPages: Math.ceil((count ?? 0) / pageSize),
  }
}

export async function getActivity(id: string): Promise<Activity> {
  const { data, error } = await supabase
    .from('activities')
    .select(ACTIVITY_SELECT)
    .eq('id', id)
    .single()
  if (error) throw error
  return data as Activity
}

export async function createActivity(input: ActivityInput): Promise<Activity> {
  const userId = await getAuthUserId()

  // ✅ حل P0: employee_id NOT NULL — نجلبه من hr_employees(user_id)
  const { data: empRow, error: empErr } = await supabase
    .from('hr_employees')
    .select('id')
    .eq('user_id', userId)
    .maybeSingle()
  if (empErr) throw empErr
  if (!empRow?.id) {
    throw new Error('لا يوجد سجل موظف مرتبط بهذا الحساب. يرجى التواصل مع مسؤول النظام.')
  }

  const clean = sanitize(input)

  if (clean.visit_plan_item_id) {
    throw new Error('تسجيل أنشطة الزيارات المخططة محظور عبر هذا النموذج. يجب تنفيذ الزيارة من شاشة التنفيذ الميداني لضمان المزامنة الذرية.')
  }

  // نُزيل employee_id من input (قد يكون '') ونحدده دائماً من hr_employees
  const { employee_id: _ignored, ...rest } = clean as any

  const { data, error } = await supabase
    .from('activities')
    .insert({ ...rest, employee_id: empRow.id, created_by: userId })
    .select(ACTIVITY_SELECT)
    .single()
  if (error) throw error
  return data as Activity
}

export async function updateActivity(id: string, input: Partial<ActivityInput>): Promise<Activity> {
  const clean = sanitize(input)
  const { data, error } = await supabase
    .from('activities')
    .update({ ...clean, updated_at: new Date().toISOString() })
    .eq('id', id)
    .is('deleted_at', null)
    .select(ACTIVITY_SELECT)
    .single()
  if (error) throw error
  return data as Activity
}

/**
 * الحذف الناعم — يمر حصراً عبر soft_delete_activity() RPC
 */
export async function softDeleteActivity(activityId: string): Promise<void> {
  const { error } = await supabase.rpc('soft_delete_activity', {
    p_activity_id: activityId,
  })
  if (error) throw error
}

// ─── Call Details ──────────────────────────────────────────────
// ✅ أعمدة call_details: direction, call_result, phone_number, attempt_count,
//    callback_at, call_recording_url (لا recording_url, لا phone_used, لا duration_seconds)

export async function saveCallDetail(
  activityId: string,
  input: CallDetailInput
): Promise<CallDetail> {
  const dbRow = {
    activity_id:        activityId,
    direction:          input.direction,
    call_result:        input.call_result   ?? 'answered',
    phone_number:       input.phone_number  ?? null,    // ✅ 1:1 مع DB
    attempt_count:      input.attempt_count ?? 1,
    callback_at:        input.callback_at   ?? null,
    call_recording_url: input.call_recording_url ?? null,
  }
  const { data, error } = await supabase
    .from('call_details')
    .upsert(dbRow, { onConflict: 'activity_id' })
    .select()
    .single()
  if (error) throw error
  return data as CallDetail
}

// ============================================================
// Visit Plans — خطط الزيارات
// ============================================================

// ✅ Join employee عبر hr_employees (لا profiles) لأن employee_id → hr_employees(id)
// hr_employees.full_name موجود في جدول hr_employees مباشرة
const VISIT_PLAN_SELECT = `
  *,
  employee:hr_employees!visit_plans_employee_id_fkey(id, full_name, branch_id),
  template:visit_plan_templates(id, name)
`

export async function getVisitPlans(params?: {
  employeeId?: string
  dateFrom?: string
  dateTo?: string
  status?: PlanStatus
  branchId?: string
  planType?: VisitPlan['plan_type']
  page?: number
  pageSize?: number
}) {
  const page     = params?.page     ?? 1
  const pageSize = params?.pageSize ?? 25
  const from     = (page - 1) * pageSize
  const to       = from + pageSize - 1

  let q = supabase
    .from('visit_plans')
    .select(`
      *,
      employee:hr_employees!visit_plans_employee_id_fkey(id, full_name, branch_id)
    `, { count: 'estimated' })
    .order('plan_date', { ascending: false })
    .range(from, to)

  if (params?.employeeId) q = q.eq('employee_id', params.employeeId)
  if (params?.dateFrom)   q = q.gte('plan_date', params.dateFrom)
  if (params?.dateTo)     q = q.lte('plan_date', params.dateTo)
  if (params?.status)     q = q.eq('status', params.status)
  if (params?.planType)   q = q.eq('plan_type', params.planType)

  // branchId: resolve to employee_ids first so the filter hits the main table's
  // employee_id column directly — guarantees accurate pagination counts.
  if (params?.branchId) {
    const { data: empRows, error: employeeLookupError } = await supabase
      .from('hr_employees')
      .select('id')
      .eq('branch_id', params.branchId)
    if (employeeLookupError) throw employeeLookupError

    const empIds = (empRows ?? []).map(e => e.id)
    if (empIds.length === 0) {
      return { data: [], count: 0, page, pageSize, totalPages: 0 }
    }
    q = q.in('employee_id', empIds)
  }

  const { data, error, count } = await q
  if (error) throw error

  return {
    data: (data ?? []) as VisitPlan[],
    count: count ?? 0,
    page,
    pageSize,
    totalPages: Math.ceil((count ?? 0) / pageSize),
  }
}

export async function getVisitPlan(id: string): Promise<VisitPlan> {
  const { data, error } = await supabase
    .from('visit_plans')
    .select(`
      ${VISIT_PLAN_SELECT},
      items:visit_plan_items(
        *,
        customer:customers(id, name, code, phone, latitude, longitude)
      )
    `)
    .eq('id', id)
    .order('sequence', { referencedTable: 'items', ascending: true })
    .single()
  if (error) throw error
  return data as VisitPlan
}

export async function getVisitPlanItems(planId: string): Promise<VisitPlanItem[]> {
  const { data, error } = await supabase
    .from('visit_plan_items')
    .select('*, customer:customers(id, name, code, phone, latitude, longitude)')
    .eq('plan_id', planId)
    .order('sequence')                     // ✅ sequence (لا sequence_order)
  if (error) throw error
  return (data ?? []) as VisitPlanItem[]
}

/**
 * @deprecated يرجى استخدام createVisitPlanAtomic لضمان الذرية ومنع التكرار.
 * TODO: استبدالها بـ createVisitPlanAtomic في مرحلة الواجهة (المرتجع ز/ي).
 */
export async function createVisitPlan(input: VisitPlanInput): Promise<VisitPlan> {
  const userId = await getAuthUserId()
  const clean  = sanitize(input)
  const { data, error } = await supabase
    .from('visit_plans')
    .insert({ ...clean, created_by: userId, status: 'draft' })
    .select(VISIT_PLAN_SELECT)
    .single()
  if (error) throw error
  return data as VisitPlan
}

/**
 * @deprecated يرجى تحديث الخطة عبر الدوال الذرية المعنية.
 * TODO: استبدالها بالـ RPCs الذرية في مرحلة الواجهة (المرتجع ز/ي).
 */
export async function updateVisitPlan(id: string, input: Partial<VisitPlanInput>): Promise<VisitPlan> {
  const clean = sanitize(input)
  const { data, error } = await supabase
    .from('visit_plans')
    .update(clean)
    .eq('id', id)
    .eq('status', 'draft')
    .select(VISIT_PLAN_SELECT)
    .single()
  if (error) throw error
  return data as VisitPlan
}

/**
 * @deprecated يرجى استخدام confirmVisitPlanAtomic لضمان الذرية ومنع التكرار.
 * TODO: استبدالها بـ confirmVisitPlanAtomic في مرحلة الواجهة (المرتجع ز/ي).
 */
export async function confirmVisitPlan(id: string): Promise<void> {
  const userId = await getAuthUserId()
  const { error } = await supabase
    .from('visit_plans')
    .update({ status: 'confirmed', confirmed_at: new Date().toISOString(), confirmed_by: userId })
    .eq('id', id)
    .eq('status', 'draft')
  if (error) throw error
}

/**
 * @deprecated يرجى استخدام cancelVisitPlanAtomic لضمان الذرية ومنع التكرار.
 * TODO: استبدالها بـ cancelVisitPlanAtomic في مرحلة الواجهة (المرتجع ز/ي).
 */
export async function cancelVisitPlan(id: string, reason?: string): Promise<void> {
  const { error } = await supabase
    .from('visit_plans')
    .update({ status: 'cancelled', cancellation_reason: reason ?? null })  // ✅ cancellation_reason
    .eq('id', id)
    .in('status', ['draft', 'confirmed'])  // ✅ state-machine: لا إلغاء بعد in_progress/completed/cancelled
  if (error) throw error
}

/**
 * @deprecated يرجى استخدام createVisitPlanAtomic الذي ينشئ الخطة والبنود معاً ذرياً.
 * TODO: استبدالها بـ createVisitPlanAtomic في مرحلة الواجهة (المرتجع ز/ي).
 */
export async function addVisitPlanItem(
  planId: string,
  item: VisitPlanItemInput
): Promise<VisitPlanItem> {
  const clean = sanitize(item)
  const { data, error } = await supabase
    .from('visit_plan_items')
    .insert({ plan_id: planId, ...clean, status: 'pending' })
    .select('*, customer:customers(id, name, code, phone, latitude, longitude)')
    .single()
  if (error) throw error
  return data as VisitPlanItem
}

/**
 * @deprecated يرجى استخدام startVisitItemAtomic أو completeVisitItemAtomic أو skipVisitItemAtomic أو rescheduleVisitItemAtomic.
 * TODO: استبدالها بالـ RPCs الذرية المقابلة في مرحلة الواجهة (المرتجع ز/ي).
 */
export async function updateVisitPlanItem(
  itemId: string,
  input: Partial<VisitPlanItemInput> & {
    status?: string
    activity_id?: string | null
    skip_reason?: string | null
    reschedule_to?: string | null
    actual_start_time?: string | null
    actual_end_time?: string | null
    actual_arrival_time?: string | null
    gps_lat?: number | null
    gps_lng?: number | null
    end_gps_lat?: number | null
    end_gps_lng?: number | null
    metadata?: Record<string, unknown> | null
  }
): Promise<VisitPlanItem> {
  const clean = sanitize(input)
  const { data, error } = await supabase
    .from('visit_plan_items')
    .update(clean)
    .eq('id', itemId)
    .select('*, customer:customers(id, name, code, phone, latitude, longitude)')
    .single()
  if (error) throw error
  return data as VisitPlanItem
}

// ============================================================
// Call Plans — خطط المكالمات
// ============================================================

const CALL_PLAN_SELECT = `
  *,
  employee:hr_employees!call_plans_employee_id_fkey(id, full_name, branch_id),
  template:call_plan_templates(id, name)
`

export async function getCallPlans(params?: {
  employeeId?: string
  dateFrom?: string
  dateTo?: string
  status?: PlanStatus
  branchId?: string
  page?: number
  pageSize?: number
}) {
  const page     = params?.page     ?? 1
  const pageSize = params?.pageSize ?? 25
  const from     = (page - 1) * pageSize
  const to       = from + pageSize - 1

  let q = supabase
    .from('call_plans')
    .select(`
      *,
      employee:hr_employees!call_plans_employee_id_fkey(id, full_name, branch_id)
    `, { count: 'estimated' })
    .order('plan_date', { ascending: false })
    .range(from, to)

  if (params?.employeeId) q = q.eq('employee_id', params.employeeId)
  if (params?.dateFrom)   q = q.gte('plan_date', params.dateFrom)
  if (params?.dateTo)     q = q.lte('plan_date', params.dateTo)
  if (params?.status)     q = q.eq('status', params.status)

  // branchId: resolve to employee_ids first so the filter hits the main table's
  // employee_id column directly — guarantees accurate pagination counts.
  if (params?.branchId) {
    const { data: empRows, error: employeeLookupError } = await supabase
      .from('hr_employees')
      .select('id')
      .eq('branch_id', params.branchId)
    if (employeeLookupError) throw employeeLookupError

    const empIds = (empRows ?? []).map(e => e.id)
    if (empIds.length === 0) {
      return { data: [], count: 0, page, pageSize, totalPages: 0 }
    }
    q = q.in('employee_id', empIds)
  }

  const { data, error, count } = await q
  if (error) throw error

  return {
    data: (data ?? []) as CallPlan[],
    count: count ?? 0,
    page,
    pageSize,
    totalPages: Math.ceil((count ?? 0) / pageSize),
  }
}

export async function getCallPlan(id: string): Promise<CallPlan> {
  const { data, error } = await supabase
    .from('call_plans')
    .select(`
      ${CALL_PLAN_SELECT},
      items:call_plan_items(
        *,
        customer:customers(id, name, code, phone)
      )
    `)
    .eq('id', id)
    .order('sequence', { referencedTable: 'items', ascending: true })
    .single()
  if (error) throw error
  return data as CallPlan
}

export async function getCallPlanItems(planId: string): Promise<CallPlanItem[]> {
  const { data, error } = await supabase
    .from('call_plan_items')
    .select('*, customer:customers(id, name, code, phone)')
    .eq('plan_id', planId)
    .order('sequence')                     // ✅ sequence
  if (error) throw error
  return (data ?? []) as CallPlanItem[]
}

export async function createCallPlan(input: CallPlanInput): Promise<CallPlan> {
  const userId = await getAuthUserId()
  const clean  = sanitize(input)
  const { data, error } = await supabase
    .from('call_plans')
    .insert({ ...clean, created_by: userId, status: 'draft' })
    .select(CALL_PLAN_SELECT)
    .single()
  if (error) throw error
  return data as CallPlan
}

export async function updateCallPlan(id: string, input: Partial<CallPlanInput>): Promise<CallPlan> {
  const clean = sanitize(input)
  const { data, error } = await supabase
    .from('call_plans')
    .update(clean)
    .eq('id', id)
    .eq('status', 'draft')
    .select(CALL_PLAN_SELECT)
    .single()
  if (error) throw error
  return data as CallPlan
}

export async function confirmCallPlan(id: string): Promise<void> {
  const userId = await getAuthUserId()
  const { error } = await supabase
    .from('call_plans')
    .update({ status: 'confirmed', confirmed_at: new Date().toISOString(), confirmed_by: userId })
    .eq('id', id)
    .eq('status', 'draft')
  if (error) throw error
}

export async function cancelCallPlan(id: string, reason?: string): Promise<void> {
  const { error } = await supabase
    .from('call_plans')
    .update({ status: 'cancelled', cancellation_reason: reason ?? null })   // ✅ cancellation_reason
    .eq('id', id)
    .in('status', ['draft', 'confirmed'])  // ✅ state-machine: لا إلغاء بعد in_progress/completed/cancelled
  if (error) throw error
}

export async function addCallPlanItem(
  planId: string,
  item: CallPlanItemInput
): Promise<CallPlanItem> {
  const clean = sanitize(item)
  const { data, error } = await supabase
    .from('call_plan_items')
    .insert({ plan_id: planId, ...clean, status: 'pending' })
    .select('*, customer:customers(id, name, code, phone)')
    .single()
  if (error) throw error
  return data as CallPlanItem
}

export async function updateCallPlanItem(
  itemId: string,
  input: Partial<CallPlanItemInput> & { status?: string; activity_id?: string | null; skip_reason?: string | null }
): Promise<CallPlanItem> {
  const clean = sanitize(input)
  const { data, error } = await supabase
    .from('call_plan_items')
    .update(clean)
    .eq('id', itemId)
    .select('*, customer:customers(id, name, code, phone)')
    .single()
  if (error) throw error
  return data as CallPlanItem
}

// ──────────────────────────────────────────────────────────────
// Targets — الأهداف
// ★ Phase 22: تم نقل الدوال المتخصصة لذ src/lib/services/targets.ts
// بقي هنا فقط الدوال المتوافضة مع Phase 21
// ──────────────────────────────────────────────────────────────

// ★ targets.type_id → target_types(id)
// ★ targets.assigned_by → profiles(id)
// ★ Phase 22: reward_* + auto_payout + payout_month_offset مضمنة في SELECT *
const TARGET_SELECT = `
  *,
  target_type:target_types!targets_type_id_fkey(id, name, code, unit, category)
`

export async function getTargets(params?: {
  scope?: string
  typeCode?: string
  isActive?: boolean
  employeeId?: string
  branchId?: string
  parentTargetId?: string
  periodFrom?: string
  periodTo?: string
  page?: number
  pageSize?: number
}) {
  const page     = params?.page     ?? 1
  const pageSize = params?.pageSize ?? 25
  const from     = (page - 1) * pageSize
  const to       = from + pageSize - 1

  let q = supabase
    .from('targets')
    .select(TARGET_SELECT, { count: 'estimated' })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.scope)      q = q.eq('scope', params.scope)
  if (params?.typeCode)   q = q.eq('type_code', params.typeCode)
  if (params?.isActive !== undefined) q = q.eq('is_active', params.isActive)
  if (params?.employeeId) {
    q = q.eq('scope_id', params.employeeId).eq('scope', 'individual')
  }
  if (params?.branchId) {
    q = q.eq('scope_id', params.branchId).eq('scope', 'branch')
  }
  if (params?.parentTargetId) {
    q = q.eq('parent_target_id', params.parentTargetId)
  }
  if (params?.periodFrom) q = q.gte('period_start', params.periodFrom)
  if (params?.periodTo)   q = q.lte('period_end', params.periodTo)

  const { data, error, count } = await q
  if (error) throw error
  return {
    data: (data ?? []) as Target[],
    count: count ?? 0,
    page,
    pageSize,
    totalPages: Math.ceil((count ?? 0) / pageSize),
  }
}

/**
 * ★ Phase 22: جلب هدف كامل مع بيانات المكافأة
 * للتفاصيل الكاملة استخدم getTargetDetail() في targets.ts
 */
export async function getTarget(id: string): Promise<Target & {
  progress_history: TargetProgress[]
  adjustments: TargetAdjustment[]
  reward_tiers: TargetRewardTier[]
  target_customers: TargetCustomer[]
  reward_payouts: TargetRewardPayout[]
}> {
  const [targetRes, progressRes, adjRes, tiersRes, customersRes, payoutsRes] = await Promise.all([
    supabase.from('targets').select(TARGET_SELECT).eq('id', id).single(),
    supabase
      .from('target_progress')
      .select('*')
      .eq('target_id', id)
      .order('snapshot_date', { ascending: false })
      .limit(30),
    supabase
      .from('target_adjustments')
      .select('*, adjusted_by_profile:profiles!target_adjustments_adjusted_by_fkey(id, full_name)')
      .eq('target_id', id)
      .order('adjusted_at', { ascending: false }),
    // ★ Phase 22: شرائح المكافأة
    supabase
      .from('target_reward_tiers')
      .select('id, target_id, sequence, threshold_pct, reward_pct, label, created_at')
      .eq('target_id', id)
      .order('sequence'),
    // ★ Phase 22: العملاء المستهدفون
    supabase
      .from('target_customers')
      .select('*, customer:customers(id, name, code, phone)')
      .eq('target_id', id),
    // ★ Phase 22: استحقاقات الصرف
    supabase
      .from('target_reward_payouts')
      .select('*, period:hr_payroll_periods(id, name, year, month), employee:hr_employees(id, full_name)')
      .eq('target_id', id)
      .order('computed_at', { ascending: false }),
  ])
  if (targetRes.error) throw targetRes.error
  return {
    ...(targetRes.data as Target),
    progress_history: (progressRes.data ?? []) as TargetProgress[],
    adjustments:      (adjRes.data   ?? []) as TargetAdjustment[],
    reward_tiers:     (tiersRes.data ?? []) as TargetRewardTier[],       // ★ Phase 22
    target_customers: (customersRes.data ?? []) as TargetCustomer[],    // ★ Phase 22
    reward_payouts:   (payoutsRes.data ?? []) as TargetRewardPayout[],  // ★ Phase 22
  }
}

/**
 * @deprecated
 * ✗ الإدخال المباشر ب INSERT محظور بواسطة Trigger في 22a_target_schema.sql
 * ✓ استخدم: createTargetWithRewards() من src/lib/services/targets.ts
 */
export async function createTarget(_input: TargetInput): Promise<any> {
  throw new Error(
    '[EDARA] createTarget() محظور. '
    + 'استخدم createTargetWithRewards() من src/lib/services/targets.ts'
  )
}

/** تحديث مباشر للحقول غير المحمية (target_value, min_value, notes...)
 *  @deprecated استخدم adjustTarget() بدلاً من هذا
 */
export async function updateTarget(id: string, input: Partial<TargetInput>): Promise<Target> {
  const clean = { ...input }
  const { data, error } = await supabase
    .from('targets')
    .update({ ...clean, updated_at: new Date().toISOString() })
    .eq('id', id)
    .select(TARGET_SELECT)
    .single()
  if (error) throw error
  return data as Target
}

/** جلب الأهداف الفرعية لهدف أب */
export async function getTargetChildren(parentId: string): Promise<Target[]> {
  const { data, error } = await supabase
    .from('targets')
    .select(TARGET_SELECT)
    .eq('parent_target_id', parentId)
    .order('scope')
    .order('created_at')
  if (error) throw error
  return (data ?? []) as Target[]
}

/**
 * تعديل قيمة الهدف — يمر حصراً عبر adjust_target() RPC
 *
 * التوقيع الحقيقي (21b_activities_rls_engine.sql line 581):
 *   p_target_id UUID
 *   p_field     TEXT  ('target_value' | 'min_value' | ...)
 *   p_new_value TEXT  (RPC يحوّله للنوع المناسب)
 *   p_reason    TEXT
 *   p_user_id   UUID
 */
export async function adjustTarget(input: AdjustTargetInput): Promise<void> {
  const { error } = await supabase.rpc('adjust_target', {
    p_target_id: input.p_target_id,
    p_field:     input.p_field,
    p_new_value: input.p_new_value,        // TEXT — RPC يحوّله
    p_reason:    input.p_reason,           // ✅ p_reason (لا p_business_reason)
    p_user_id:   input.p_user_id,
  })
  if (error) throw error
}

// ============================================================
// Views — تقارير الأداء
// ============================================================

/**
 * v_rep_performance
 * الأعمدة: employee_id, employee_name, branch_id, branch_name, period,
 *          visits_count, calls_count, orders_from_activities,
 *          sales_value, collection_value, active_customers
 */
export async function getRepPerformance(params?: {
  periodFrom?: string    // ✅ period = DATE_TRUNC('month') — نُفلتر بـ >=
  periodTo?: string
  employeeId?: string
  branchId?: string
}): Promise<RepPerformanceRow[]> {
  let q = supabase
    .from('v_rep_performance')
    .select('*')
    .order('employee_name')

  if (params?.periodFrom) q = q.gte('period', params.periodFrom)
  if (params?.periodTo)   q = q.lte('period', params.periodTo)
  if (params?.employeeId) q = q.eq('employee_id', params.employeeId)
  if (params?.branchId)   q = q.eq('branch_id',   params.branchId)

  const { data, error } = await q
  if (error) throw error
  return (data ?? []) as RepPerformanceRow[]
}

/**
 * v_plan_daily_summary
 * الأعمدة: plan_module, id, employee_id, plan_date, plan_type,
 *          plan_status, total_items, completed_count, skipped_count,
 *          missed_count, completion_pct, pending_count, high_priority_pending
 */
export async function getPlanDailySummary(params?: {
  date?: string
  employeeId?: string
  planModule?: 'visit' | 'call'
}): Promise<PlanDailySummaryRow[]> {
  let q = supabase
    .from('v_plan_daily_summary')
    .select('*')
    .order('plan_date', { ascending: false })
    .limit(50)

  if (params?.date)        q = q.eq('plan_date',    params.date)
  if (params?.employeeId)  q = q.eq('employee_id',  params.employeeId)
  if (params?.planModule)  q = q.eq('plan_module',  params.planModule)  // ✅ plan_module

  const { data, error } = await q
  if (error) throw error
  return (data ?? []) as PlanDailySummaryRow[]
}

/**
 * v_target_status
 * الأعمدة: id, name, type_code, scope, scope_id, period_start, period_end,
 *          target_value, min_value, stretch_value, is_active, is_paused,
 *          achieved_value, achievement_pct, trend, last_calc_at,
 *          data_as_of, remaining_value, days_remaining, forecasted_value
 */
export async function getTargetStatus(params?: {
  scope?: string
  scopeId?: string          // ✅ scope_id مباشرة (لا scope_label)
  isActive?: boolean
}): Promise<TargetStatusRow[]> {
  let q = supabase
    .from('v_target_status')
    .select('*')
    .order('achievement_pct', { ascending: false })

  if (params?.scope)    q = q.eq('scope',    params.scope)
  if (params?.scopeId)  q = q.eq('scope_id', params.scopeId)  // ✅ scope_id
  if (params?.isActive !== undefined) q = q.eq('is_active', params.isActive)

  const { data, error } = await q
  if (error) throw error
  return (data ?? []) as TargetStatusRow[]
}

// ============================================================
// Visit Checklists — استبيانات الزيارات والمكالمات
// ============================================================

/**
 * جلب قوالب الاستبيانات حسب الفئة والغرض
 * إذا purposeType = null → يجلب القوالب العامة فقط
 * إذا purposeType = 'sales' → يجلب العامة + المخصصة لـ sales
 */
export async function getChecklistTemplates(params?: {
  category?: string
  purposeType?: string | null
  includeInactive?: boolean
}): Promise<ChecklistTemplate[]> {
  let q = supabase
    .from('visit_checklist_templates')
    .select('*, questions:visit_checklist_questions(*)')
    .order('sort_order')

  if (!params?.includeInactive) q = q.eq('is_active', true)
  if (params?.category) q = q.eq('category', params.category)
  if (params && Object.prototype.hasOwnProperty.call(params, 'purposeType')) {
    q = params.purposeType
      ? q.or(`purpose_type.is.null,purpose_type.eq.${params.purposeType}`)
      : q.is('purpose_type', null)
  }

  const { data, error } = await q
  if (error) throw error

  return (data ?? []).map(t => ({
    ...t,
    questions: (t.questions ?? []).sort((a: any, b: any) => a.sort_order - b.sort_order),
  })) as ChecklistTemplate[]
}

/**
 * جلب أسئلة قالب استبيان محدد
 */
export async function getChecklistQuestions(templateId: string): Promise<ChecklistQuestion[]> {
  const { data, error } = await supabase
    .from('visit_checklist_questions')
    .select('*')
    .eq('template_id', templateId)
    .order('sort_order')
  if (error) throw error
  return (data ?? []) as ChecklistQuestion[]
}

/**
 * جلب إجابات نشاط محدد
 */
export async function getChecklistResponses(activityId: string): Promise<ChecklistResponse[]> {
  const { data, error } = await supabase
    .from('visit_checklist_responses')
    .select(`
      *,
      question:visit_checklist_questions(id, question_text, question_type)
    `)
    .eq('activity_id', activityId)
  if (error) throw error
  return (data ?? []) as ChecklistResponse[]
}

/**
 * حفظ إجابات الاستبيان لنشاط (upsert — يحدّث الموجود أو ينشئ جديد)
 */
export async function saveChecklistResponses(
  responses: ChecklistResponseInput[]
): Promise<ChecklistResponse[]> {
  if (responses.length === 0) return []

  const { data, error } = await supabase
    .from('visit_checklist_responses')
    .upsert(
      responses.map(r => ({
        activity_id: r.activity_id,
        template_id: r.template_id,
        question_id: r.question_id,
        answer_value: r.answer_value ?? null,
        answer_json: r.answer_json ?? null,
      })),
      { onConflict: 'activity_id,question_id' }
    )
    .select('*')
  if (error) throw error
  return (data ?? []) as ChecklistResponse[]
}

// ============================================================
// Plan Item Management — إدارة بنود الخطط
// ============================================================

/**
 * حذف بند من خطة الزيارات
 */
export async function deleteVisitPlanItem(itemId: string): Promise<void> {
  const { error } = await supabase
    .from('visit_plan_items')
    .delete()
    .eq('id', itemId)
  if (error) throw error
}

/**
 * حذف بند من خطة المكالمات
 */
export async function deleteCallPlanItem(itemId: string): Promise<void> {
  const { error } = await supabase
    .from('call_plan_items')
    .delete()
    .eq('id', itemId)
  if (error) throw error
}

/**
 * @deprecated يرجى استخدام reorderVisitPlanItemsAtomic لضمان الذرية ومنع التعارضات.
 * TODO: استبدالها بـ reorderVisitPlanItemsAtomic في مرحلة الواجهة (المرتجع ز/ي).
 */
export async function reorderVisitPlanItems(
  planId: string,
  orderedItemIds: string[]
): Promise<void> {
  // update sequence لكل بند — بالتتابع لتجنب UNIQUE constraint violation
  for (let i = 0; i < orderedItemIds.length; i++) {
    // نستخدم sequence سالب مؤقت لتجنب تعارض UNIQUE
    const { error } = await supabase
      .from('visit_plan_items')
      .update({ sequence: -(i + 1) })
      .eq('id', orderedItemIds[i])
      .eq('plan_id', planId)
    if (error) throw error
  }
  // ثم نحوّل السالب إلى موجب
  for (let i = 0; i < orderedItemIds.length; i++) {
    const { error } = await supabase
      .from('visit_plan_items')
      .update({ sequence: i + 1 })
      .eq('id', orderedItemIds[i])
      .eq('plan_id', planId)
    if (error) throw error
  }
}

/**
 * إعادة ترتيب بنود خطة المكالمات
 */
export async function reorderCallPlanItems(
  planId: string,
  orderedItemIds: string[]
): Promise<void> {
  for (let i = 0; i < orderedItemIds.length; i++) {
    const { error } = await supabase
      .from('call_plan_items')
      .update({ sequence: -(i + 1) })
      .eq('id', orderedItemIds[i])
      .eq('plan_id', planId)
    if (error) throw error
  }
  for (let i = 0; i < orderedItemIds.length; i++) {
    const { error } = await supabase
      .from('call_plan_items')
      .update({ sequence: i + 1 })
      .eq('id', orderedItemIds[i])
      .eq('plan_id', planId)
    if (error) throw error
  }
}

// ============================================================
// Checklist Template CRUD — Wave A Admin Surface
// ============================================================

export async function createChecklistTemplate(input: ChecklistTemplateInput): Promise<ChecklistTemplate> {
  const userId = await getAuthUserId()
  const { data, error } = await supabase
    .from('visit_checklist_templates')
    .insert({
      ...input,
      is_active: input.is_active ?? true,
      sort_order: input.sort_order ?? 0,
      created_by: userId,
    })
    .select('*, questions:visit_checklist_questions(*)')
    .single()
  if (error) throw error
  return data as ChecklistTemplate
}

export async function updateChecklistTemplate(id: string, input: Partial<ChecklistTemplateInput>): Promise<ChecklistTemplate> {
  const { data, error } = await supabase
    .from('visit_checklist_templates')
    .update({ ...input, updated_at: new Date().toISOString() })
    .eq('id', id)
    .select('*, questions:visit_checklist_questions(*)')
    .single()
  if (error) throw error
  return data as ChecklistTemplate
}

export async function deleteChecklistTemplate(id: string): Promise<void> {
  const { error } = await supabase
    .from('visit_checklist_templates')
    .delete()
    .eq('id', id)
  if (error) throw error
}

export async function createChecklistQuestion(templateId: string, input: ChecklistQuestionInput): Promise<ChecklistQuestion> {
  const { data, error } = await supabase
    .from('visit_checklist_questions')
    .insert({
      template_id:    templateId,
      question_text:  input.question_text,
      question_type:  input.question_type,
      options:        input.options ?? [],
      default_value:  input.default_value ?? null,
      hint_text:      input.hint_text ?? null,
      min_value:      input.min_value ?? null,
      max_value:      input.max_value ?? null,
      is_required:    input.is_required ?? false,
      sort_order:     input.sort_order ?? 0,
    })
    .select()
    .single()
  if (error) throw error
  return data as ChecklistQuestion
}

export async function updateChecklistQuestion(id: string, input: Partial<ChecklistQuestionInput>): Promise<ChecklistQuestion> {
  const { data, error } = await supabase
    .from('visit_checklist_questions')
    .update(input)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as ChecklistQuestion
}

export async function deleteChecklistQuestion(id: string): Promise<void> {
  const { error } = await supabase
    .from('visit_checklist_questions')
    .delete()
    .eq('id', id)
  if (error) throw error
}

// ============================================================
// Plan Template CRUD — Wave A Admin Surface
// ============================================================

export interface PlanTemplateInput {
  name: string
  branch_id?: string | null
  employee_id?: string | null
  recurrence?: 'none' | 'daily' | 'weekly' | 'monthly'
  day_of_week?: number[] | null
  is_active?: boolean
  items?: any[]
}

export async function createVisitPlanTemplate(input: PlanTemplateInput): Promise<VisitPlanTemplate> {
  const userId = await getAuthUserId()
  const { data, error } = await supabase
    .from('visit_plan_templates')
    .insert({
      name:         input.name,
      branch_id:    input.branch_id    ?? null,
      employee_id:  input.employee_id  ?? null,
      recurrence:   input.recurrence   ?? 'none',
      day_of_week:  input.day_of_week  ?? null,
      is_active:    input.is_active    ?? true,
      items:        input.items        ?? [],
      created_by:   userId,
    })
    .select()
    .single()
  if (error) throw error
  return data as VisitPlanTemplate
}

export async function updateVisitPlanTemplate(id: string, input: Partial<PlanTemplateInput>): Promise<VisitPlanTemplate> {
  const { data, error } = await supabase
    .from('visit_plan_templates')
    .update(input)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as VisitPlanTemplate
}

export async function deleteVisitPlanTemplate(id: string): Promise<void> {
  const { error } = await supabase
    .from('visit_plan_templates')
    .delete()
    .eq('id', id)
  if (error) throw error
}

export async function createCallPlanTemplate(input: PlanTemplateInput): Promise<CallPlanTemplate> {
  const userId = await getAuthUserId()
  const { data, error } = await supabase
    .from('call_plan_templates')
    .insert({
      name:         input.name,
      branch_id:    input.branch_id    ?? null,
      employee_id:  input.employee_id  ?? null,
      recurrence:   input.recurrence   ?? 'none',
      day_of_week:  input.day_of_week  ?? null,
      is_active:    input.is_active    ?? true,
      items:        input.items        ?? [],
      created_by:   userId,
    })
    .select()
    .single()
  if (error) throw error
  return data as CallPlanTemplate
}

export async function updateCallPlanTemplate(id: string, input: Partial<PlanTemplateInput>): Promise<CallPlanTemplate> {
  const { data, error } = await supabase
    .from('call_plan_templates')
    .update(input)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as CallPlanTemplate
}

export async function deleteCallPlanTemplate(id: string): Promise<void> {
  const { error } = await supabase
    .from('call_plan_templates')
    .delete()
    .eq('id', id)
  if (error) throw error
}

// ============================================================
// Phase F additions: Atomic RPC Services & Helpers
// ============================================================

export class VisitRpcTransportError extends Error {
  readonly supabaseError: PostgrestError | null;

  constructor(message: string, supabaseError: PostgrestError | null) {
    super(message);
    this.name = 'VisitRpcTransportError';
    this.supabaseError = supabaseError;
    Object.setPrototypeOf(this, VisitRpcTransportError.prototype);
  }
}

export function isRetryableVisitErrorCode(code: string): boolean {
  return code === 'RETRYABLE_ERROR';
}

/**
 * دالة مساعدة للتحقق من أن المدخل هو كائن JSON صالح وليس Array أو null
 */
export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/**
 * Runtime Validator لمسار الصورة يطابق تماماً قيود قاعدة البيانات
 */
export function validateVisitStoragePath(path: string): VisitStoragePath {
  if (path.length > 2048) {
    throw new Error('مسار تخزين الصورة طويل جداً');
  }
  if (
    path.includes('\\') ||
    path.includes('%') ||
    path.includes('?') ||
    path.includes('//') ||
    path.startsWith('/') ||
    path.startsWith('.')
  ) {
    throw new Error('مسار تخزين الصورة غير صالح أو غير آمن');
  }
  const segments = path.split('/');
  if (segments.includes('.') || segments.includes('..')) {
    throw new Error('مسار تخزين الصورة غير صالح أو غير آمن');
  }
  const allowedChars = /^[a-zA-Z0-9_\-\./]+$/;
  if (!allowedChars.test(path)) {
    throw new Error('مسار تخزين الصورة غير صالح أو غير آمن');
  }
  return path as VisitStoragePath;
}

/**
 * Type guard آمن للتحقق من أن الاستجابة هي استجابة صورة
 */
export function isPhotoResponse(
  response: VisitCompletionChecklistResponseInput
): response is VisitCompletionChecklistPhotoResponseInput {
  const json = response.answer_json;
  if (!isRecord(json)) {
    return false;
  }
  if (!Object.prototype.hasOwnProperty.call(json, 'storage_path')) {
    throw new Error('مسار تخزين الصورة غير صالح أو غير آمن');
  }
  if (typeof json.storage_path !== 'string') {
    throw new Error('مسار تخزين الصورة غير صالح أو غير آمن');
  }
  return true;
}

/**
 * معالج استدعاء RPC موحد آمن لحماية سلامة البيانات والتعامل مع الأخطاء
 */
async function callVisitRpc<T>(
  operation: VisitOperationName,
  operationId: string,
  params: Record<string, unknown>
): Promise<VisitRpcResult<T>> {
  const rpcRequest = Promise.resolve(supabase.rpc(operation, params));
  let timeoutId: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timeoutId = setTimeout(() => {
      reject(new VisitRpcTransportError('انتهت مهلة الاتصال بالخادم. تم حفظ العملية لإعادة المحاولة بأمان.', null));
    }, 30_000);
  });
  const response = await Promise.race([rpcRequest, timeout]).finally(() => {
    if (timeoutId) clearTimeout(timeoutId);
  });
  const rawData: unknown = response.data;
  const error: PostgrestError | null = response.error;

  if (error) {
    throw new VisitRpcTransportError(`فشل الاتصال بالخادم أثناء تنفيذ العملية: ${error.message}`, error);
  }

  // Runtime validation to ensure the response is not malformed
  if (!isRecord(rawData)) {
    throw new Error('رد غير صالح أو مشوه من الخادم');
  }

  const obj = rawData;

  if (
    typeof obj.ok !== 'boolean' ||
    obj.operation_id !== operationId ||
    obj.operation !== operation ||
    typeof obj.replayed !== 'boolean'
  ) {
    throw new Error('رد غير صالح أو مشوه من الخادم');
  }

  if (obj.ok) {
    if (!isRecord(obj.data)) {
      throw new Error('رد غير صالح أو مشوه من الخادم');
    }
    return {
      ok: true,
      operation_id: operationId,
      operation: operation,
      replayed: obj.replayed,
      data: obj.data as T
    };
  } else {
    if (!isRecord(obj.error)) {
      throw new Error('رد غير صالح أو مشوه من الخادم');
    }
    const errObj = obj.error;
    if (
      typeof errObj.code !== 'string' ||
      !errObj.code ||
      typeof errObj.message !== 'string' ||
      !errObj.message
    ) {
      throw new Error('رد غير صالح أو مشوه من الخادم');
    }
    return {
      ok: false,
      operation_id: operationId,
      operation: operation,
      replayed: obj.replayed,
      error: {
        code: errObj.code,
        message: errObj.message
      }
    };
  }
}

/**
 * إنشاء خطة زيارة متكاملة مع بنودها ذرياً
 */
export async function createVisitPlanAtomic(
  input: CreateVisitPlanAtomicInput
): Promise<VisitRpcResult<CreateVisitPlanAtomicResult>> {
  return callVisitRpc<CreateVisitPlanAtomicResult>('create_visit_plan_atomic', input.operationId, {
    p_operation_id: input.operationId,
    p_employee_id: input.employeeId,
    p_plan_date: input.planDate,
    p_plan_type: input.planType,
    p_notes: input.notes,
    p_items: input.items
  });
}

/**
 * تأكيد خطة الزيارة لنقلها لحالة مؤكدة ذرياً
 */
export async function confirmVisitPlanAtomic(
  input: ConfirmVisitPlanAtomicInput
): Promise<VisitRpcResult<ConfirmVisitPlanAtomicResult>> {
  return callVisitRpc<ConfirmVisitPlanAtomicResult>('confirm_visit_plan_atomic', input.operationId, {
    p_operation_id: input.operationId,
    p_plan_id: input.planId
  });
}

/**
 * إلغاء خطة الزيارة ذرياً
 */
export async function cancelVisitPlanAtomic(
  input: CancelVisitPlanAtomicInput
): Promise<VisitRpcResult<CancelVisitPlanAtomicResult>> {
  return callVisitRpc<CancelVisitPlanAtomicResult>('cancel_visit_plan_atomic', input.operationId, {
    p_operation_id: input.operationId,
    p_plan_id: input.planId,
    p_cancellation_reason: input.reason
  });
}

/**
 * إعادة ترتيب بنود خطة الزيارة ذرياً
 */
export async function reorderVisitPlanItemsAtomic(
  input: ReorderVisitPlanItemsAtomicInput
): Promise<VisitRpcResult<ReorderVisitPlanItemsAtomicResult>> {
  return callVisitRpc<ReorderVisitPlanItemsAtomicResult>('reorder_visit_plan_items_atomic', input.operationId, {
    p_operation_id: input.operationId,
    p_plan_id: input.planId,
    p_reorder_data: input.items
  });
}

/**
 * الإغلاق الإداري لخطة الزيارة بعد بدء التنفيذ ذرياً
 */
export async function closeVisitPlanAdministrativelyAtomic(
  input: CloseVisitPlanAdministrativelyAtomicInput
): Promise<VisitRpcResult<CloseVisitPlanAdministrativelyAtomicResult>> {
  return callVisitRpc<CloseVisitPlanAdministrativelyAtomicResult>('close_visit_plan_administratively_atomic', input.operationId, {
    p_operation_id: input.operationId,
    p_plan_id: input.planId,
    p_close_reason: input.reason
  });
}

/**
 * بدء زيارة بند مع تحديد الوقت وموقع المندوب ذرياً
 */
export async function startVisitItemAtomic(
  input: StartVisitItemAtomicInput
): Promise<VisitRpcResult<StartVisitItemAtomicResult>> {
  return callVisitRpc<StartVisitItemAtomicResult>('start_visit_item_atomic', input.operationId, {
    p_operation_id: input.operationId,
    p_item_id: input.itemId,
    p_start_lat: input.startLat,
    p_start_lng: input.startLng,
    p_start_accuracy_m: input.startAccuracyM,
    p_client_started_at: input.clientStartedAt,
    p_device_timezone: input.deviceTimezone
  });
}

/**
 * إكمال الزيارة ميدانياً وحفظ الأنشطة والاستبيانات ذرياً
 */
export async function completeVisitItemAtomic(
  input: CompleteVisitItemAtomicInput
): Promise<VisitRpcResult<CompleteVisitItemAtomicResult>> {
  // Create a new responses array replacing storage_path with validated path
  const validatedResponses = input.responses.map(resp => {
    if (isPhotoResponse(resp)) {
      const validatedPath = validateVisitStoragePath(resp.answer_json.storage_path);
      return {
        ...resp,
        answer_json: {
          storage_path: validatedPath
        }
      };
    }
    return resp;
  });

  return callVisitRpc<CompleteVisitItemAtomicResult>('complete_visit_item_atomic', input.operationId, {
    p_operation_id: input.operationId,
    p_item_id: input.itemId,
    p_end_lat: input.endLat,
    p_end_lng: input.endLng,
    p_end_accuracy_m: input.endAccuracyM,
    p_client_completed_at: input.clientCompletedAt,
    p_device_timezone: input.deviceTimezone,
    p_outcome_type: input.outcomeType,
    p_outcome_notes: input.outcomeNotes,
    p_responses: validatedResponses,
    p_order_id: input.orderId,
    p_collection_id: input.collectionId,
    p_gps_exception_reason: input.gpsExceptionReason
  });
}

/**
 * تخطي زيارة بند ميدانياً مع توضيح السبب ذرياً
 */
export async function skipVisitItemAtomic(
  input: SkipVisitItemAtomicInput
): Promise<VisitRpcResult<SkipVisitItemAtomicResult>> {
  return callVisitRpc<SkipVisitItemAtomicResult>('skip_visit_item_atomic', input.operationId, {
    p_operation_id: input.operationId,
    p_item_id: input.itemId,
    p_skip_reason: input.skipReason,
    p_client_event_at: input.clientEventAt,
    p_device_timezone: input.deviceTimezone
  });
}

/**
 * إعادة جدولة بند زيارة لليوم التالي ذرياً
 */
export async function rescheduleVisitItemAtomic(
  input: RescheduleVisitItemAtomicInput
): Promise<VisitRpcResult<RescheduleVisitItemAtomicResult>> {
  return callVisitRpc<RescheduleVisitItemAtomicResult>('reschedule_visit_item_atomic', input.operationId, {
    p_operation_id: input.operationId,
    p_item_id: input.itemId,
    p_target_plan_id: input.targetPlanId,
    p_reschedule_reason: input.rescheduleReason,
    p_planned_time: input.plannedTime,
    p_client_event_at: input.clientEventAt,
    p_device_timezone: input.deviceTimezone
  });
}

/**
 * إعادة جدولة بند زيارة بتاريخ محدد ذرياً (لحل فجوات التنفيذ الميداني)
 */
export async function rescheduleVisitItemToDateAtomic(
  input: RescheduleVisitItemToDateAtomicInput
): Promise<VisitRpcResult<RescheduleVisitItemToDateAtomicResult>> {
  return callVisitRpc<RescheduleVisitItemToDateAtomicResult>('reschedule_visit_item_to_date_atomic', input.operationId, {
    p_operation_id: input.operationId,
    p_item_id: input.itemId,
    p_target_date: input.targetDate,
    p_reschedule_reason: input.rescheduleReason,
    p_planned_time: input.plannedTime || null,
    p_client_event_at: input.clientEventAt || null,
    p_device_timezone: input.deviceTimezone || null
  });
}

/**
 * إنهاء يومية الزيارات وتحويل كافة البنود المعلقة إلى ضائعة ذرياً
 */
export async function closeVisitDayMissedAtomic(
  input: CloseVisitDayMissedAtomicInput
): Promise<VisitRpcResult<CloseVisitDayMissedAtomicResult>> {
  return callVisitRpc<CloseVisitDayMissedAtomicResult>('close_visit_day_missed_atomic', input.operationId, {
    p_operation_id: input.operationId,
    p_plan_id: input.planId,
    p_close_reason: input.closeReason,
    p_client_event_at: input.clientEventAt || null,
    p_device_timezone: input.deviceTimezone || null
  });
}

/**
 * إضافة بند إلى خطة الزيارة ذرياً
 */
export async function addVisitPlanItemAtomic(
  input: AddVisitPlanItemAtomicInput
): Promise<VisitRpcResult<AddVisitPlanItemAtomicResult>> {
  return callVisitRpc<AddVisitPlanItemAtomicResult>('add_visit_plan_item_atomic', input.operationId, {
    p_operation_id: input.operationId,
    p_plan_id: input.planId,
    p_customer_id: input.customerId,
    p_customer_branch_id: input.customerBranchId || null,
    p_purpose: input.purpose || null,
    p_purpose_type: input.purposeType ?? null,
    p_priority: input.priority || 'normal',
    p_planned_time: input.plannedTime || null,
    p_estimated_duration_min: input.estimatedDurationMin || 30,
    p_client_event_at: input.clientEventAt || null,
    p_device_timezone: input.deviceTimezone || null
  });
}

/**
 * حذف بند من خطة الزيارة ذرياً
 */
export async function deleteVisitPlanItemAtomic(
  input: DeleteVisitPlanItemAtomicInput
): Promise<VisitRpcResult<DeleteVisitPlanItemAtomicResult>> {
  return callVisitRpc<DeleteVisitPlanItemAtomicResult>('delete_visit_plan_item_atomic', input.operationId, {
    p_operation_id: input.operationId,
    p_item_id: input.itemId,
    p_client_event_at: input.clientEventAt || null,
    p_device_timezone: input.deviceTimezone || null
  });
}
