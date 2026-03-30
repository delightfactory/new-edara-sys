import { supabase } from '@/lib/supabase/client'
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
  RepPerformanceRow, PlanDailySummaryRow, TargetStatusRow,
  PlanStatus,
} from '@/lib/types/activities'

// ============================================================
// Helper — جلب UID المستخدم الحالي
// ============================================================
async function getUserId(): Promise<string> {
  const { data } = await supabase.auth.getUser()
  if (!data.user?.id) throw new Error('يجب تسجيل الدخول')
  return data.user.id
}

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

export async function getActivityTypes(): Promise<ActivityType[]> {
  const { data, error } = await supabase
    .from('activity_types')
    .select('*')
    .eq('is_active', true)
    .order('sort_order')
  if (error) throw error
  return data as ActivityType[]
}

export async function getTargetTypes(): Promise<TargetType[]> {
  const { data, error } = await supabase
    .from('target_types')
    .select('*')
    .eq('is_active', true)
    .order('name')
  if (error) throw error
  return data as TargetType[]
}

export async function getVisitPlanTemplates(): Promise<VisitPlanTemplate[]> {
  const { data, error } = await supabase
    .from('visit_plan_templates')
    .select('*')
    .eq('is_active', true)
    .order('name')
  if (error) throw error
  return data as VisitPlanTemplate[]
}

export async function getCallPlanTemplates(): Promise<CallPlanTemplate[]> {
  const { data, error } = await supabase
    .from('call_plan_templates')
    .select('*')
    .eq('is_active', true)
    .order('name')
  if (error) throw error
  return data as CallPlanTemplate[]
}

// ============================================================
// Activities — الأنشطة
// ============================================================

// ✅ أعمدة مطابقة للـ schema (type_id لا activity_type_id)
const ACTIVITY_SELECT = `
  *,
  type:activity_types!activities_type_id_fkey(id, name, code, category, icon, requires_gps, requires_customer),
  customer:customers(id, name, code, phone, latitude, longitude),
  call_detail:call_details(*)
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
  // ✅ typeCategory: PostgREST لا يدعم فلترة على joined table مباشرة بشكل آمن
  // نُحضر البيانات ونُفلتر client-side إذا لزم (كمية صغيرة مع date filter)

  const { data, error, count } = await q
  if (error) throw error

  let rows = (data ?? []) as Activity[]

  // فلترة typeCategory client-side بعد الجلب
  if (params?.typeCategory) {
    const cat = params.typeCategory
    rows = rows.filter(a => (a as any).type?.category === cat)
  }

  return {
    data: rows,
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
  const userId = await getUserId()

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
  // ✅ branchId: فلترة عبر employee.branch_id يتطلب join — نُفلتر بعد الجلب
  const { data, error, count } = await q
  if (error) throw error

  let rows = (data ?? []) as VisitPlan[]
  if (params?.branchId) {
    rows = rows.filter(p => (p as any).employee?.branch_id === params.branchId)
  }

  return {
    data: rows,
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

export async function createVisitPlan(input: VisitPlanInput): Promise<VisitPlan> {
  const userId = await getUserId()
  const clean  = sanitize(input)
  const { data, error } = await supabase
    .from('visit_plans')
    .insert({ ...clean, created_by: userId, status: 'draft' })
    .select(VISIT_PLAN_SELECT)
    .single()
  if (error) throw error
  return data as VisitPlan
}

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

export async function confirmVisitPlan(id: string): Promise<void> {
  const userId = await getUserId()
  const { error } = await supabase
    .from('visit_plans')
    .update({ status: 'confirmed', confirmed_at: new Date().toISOString(), confirmed_by: userId })
    .eq('id', id)
    .eq('status', 'draft')
  if (error) throw error
}

export async function cancelVisitPlan(id: string, reason?: string): Promise<void> {
  const { error } = await supabase
    .from('visit_plans')
    .update({ status: 'cancelled', cancellation_reason: reason ?? null })  // ✅ cancellation_reason
    .eq('id', id)
    .not('status', 'eq', 'completed')
  if (error) throw error
}

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

export async function updateVisitPlanItem(
  itemId: string,
  input: Partial<VisitPlanItemInput> & { status?: string; activity_id?: string | null; skip_reason?: string | null }
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

  const { data, error, count } = await q
  if (error) throw error

  let rows = (data ?? []) as CallPlan[]
  if (params?.branchId) {
    rows = rows.filter(p => (p as any).employee?.branch_id === params.branchId)
  }

  return {
    data: rows,
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
  const userId = await getUserId()
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
  const userId = await getUserId()
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
    .not('status', 'eq', 'completed')
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

// ============================================================
// Targets — الأهداف
// ============================================================

// ✅ targets.type_id → target_types(id)
// ✅ targets.assigned_by → profiles(id)
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
  if (params?.typeCode)   q = q.eq('type_code', params.typeCode)   // ✅ type_code في targets مباشرة
  if (params?.isActive !== undefined) q = q.eq('is_active', params.isActive)
  // ✅ فلترة بـ scope_id مع scope بدلاً من scope_label
  if (params?.employeeId) {
    q = q.eq('scope_id', params.employeeId).eq('scope', 'individual')
  }
  if (params?.branchId) {
    q = q.eq('scope_id', params.branchId).eq('scope', 'branch')
  }

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

export async function getTarget(id: string): Promise<Target & {
  progress_history: TargetProgress[]
  adjustments: TargetAdjustment[]
}> {
  const [targetRes, progressRes, adjRes] = await Promise.all([
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
      .order('adjusted_at', { ascending: false }),   // ✅ adjusted_at (لا created_at)
  ])
  if (targetRes.error) throw targetRes.error
  return {
    ...(targetRes.data as Target),
    progress_history: (progressRes.data ?? []) as TargetProgress[],
    adjustments:      (adjRes.data   ?? []) as TargetAdjustment[],
  }
}

/** يتطلب صلاحية targets.assign */
export async function createTarget(input: TargetInput): Promise<Target> {
  const userId = await getUserId()
  const clean  = sanitize(input)
  const { data, error } = await supabase
    .from('targets')
    .insert({ ...clean, assigned_by: userId })   // ✅ assigned_by (لا created_by)
    .select(TARGET_SELECT)
    .single()
  if (error) throw error
  return data as Target
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
