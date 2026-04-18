/**
 * credit.ts — خدمة إدارة الائتمان
 *
 * تشمل:
 *   - getCreditCustomers()       → pagination حقيقي server-side لعملاء الائتمان
 *   - getCreditPortfolioKPIs()   → 6 مؤشرات محسوبة في SQL من جدول customers
 *   - getOverdueBatch()          → تحديد التأخر في SQL، طلب واحد للصفحة
 *   - getCreditOpenOrders()      → الفواتير المسلَّمة فقط مع days_since_delivery من SQL
 *   - creditUpdateCustomer()     → تعديل البنود عبر RPC مخصصة
 *
 * القيود الصارمة:
 *   - لا SUM على customer_ledger في أي موضع
 *   - لا استدعاء لـ update_customer_with_opening_balance
 *   - لا تعديل لـ getOpenOrdersForCustomer() في payments.ts
 *   - لا رصيد افتتاحي
 *   - الصلاحية المعتمدة: customers.credit.update فقط
 *
 * مرجع حالات الطلبات (04b_delivery_rpcs.sql:158):
 *   الفواتير المتأخرة والمسلَّمة = status IN ('delivered', 'partially_delivered')
 *   تبويب الفواتير يعرض المسلَّم فقط — 'confirmed' مستبعد كليًا
 */

import { supabase } from '@/lib/supabase/client'
import { PERMISSIONS } from '@/lib/permissions/constants'

// ─────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────

export interface CreditPortfolioKPIs {
  totalLimit:           number
  totalUsed:            number
  totalAvailable:       number   // SUM(GREATEST(0, credit_limit - current_balance)) — لكل عميل
  countExceeded:        number   // current_balance > credit_limit (أكبر صارم)
  countNearLimit:       number   // نسبة >= 80% ولم يتجاوز
  totalCreditCustomers: number
}

export interface CreditCustomerRow {
  id:              string
  code:            string
  name:            string
  payment_terms:   string
  credit_limit:    number
  credit_days:     number
  current_balance: number
  is_active:       boolean
  assigned_rep_id: string | null
  // Supabase يُرجع FK join كـ Array — any لتجنب تعارض الأنواع
  assigned_rep?:   any
}

export interface CreditCustomerPage {
  data:       CreditCustomerRow[]
  count:      number
  page:       number
  pageSize:   number
  totalPages: number
}

export interface OverdueInfo {
  customerId:   string
  overdueCount: number
  hasOverdue:   boolean
}

export interface CreditOpenOrder {
  id:                  string
  order_number:        string
  total_amount:        number
  paid_amount:         number
  returned_amount:     number
  delivered_at:        string | null
  status:              string
  net_remaining:       number         // total_amount - paid_amount - returned_amount (من SQL)
  days_since_delivery: number | null  // من SQL: CURRENT_DATE - delivered_at::date
}

export interface CreditUpdatePatch {
  payment_terms: string
  credit_limit:  number
  credit_days:   number
}

export async function getCreditCustomers(params?: {
  search?:            string
  paymentTerms?:      'credit' | 'mixed' | ''
  repId?:             string
  balanceState?:      'all' | 'with-balance-only' | 'near-limit' | 'exceeded' | 'no-limit'
  currentBalanceMin?: number
  currentBalanceMax?: number
  creditLimitMin?:    number
  creditLimitMax?:    number
  sortBy?:            'name' | 'current_balance_desc' | 'available_asc' | 'utilization_desc' | 'overdue_count_desc'
  page?:              number
  pageSize?:          number
}): Promise<CreditCustomerPage> {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 25
  const offset = (page - 1) * pageSize

  const { data, error } = await supabase.rpc('get_filtered_credit_customers', {
    p_search:              params?.search || null,
    p_payment_terms:       params?.paymentTerms || null,
    p_rep_id:              params?.repId || null,
    p_balance_state:       params?.balanceState || 'all',
    p_current_balance_min: params?.currentBalanceMin ?? null,
    p_current_balance_max: params?.currentBalanceMax ?? null,
    p_credit_limit_min:    params?.creditLimitMin ?? null,
    p_credit_limit_max:    params?.creditLimitMax ?? null,
    p_sort_by:             params?.sortBy || 'name',
    p_limit:               pageSize,
    p_offset:              offset
  })

  if (error) throw error

  const rows = (data || []) as any[]
  const totalCount = rows.length > 0 ? Number(rows[0].total_count) : 0

  return {
    data:       rows.map(r => ({
      id:              r.id,
      code:            r.code,
      name:            r.name,
      payment_terms:   r.payment_terms,
      credit_limit:    Number(r.credit_limit) || 0,
      credit_days:     Number(r.credit_days) || 0,
      current_balance: Number(r.current_balance) || 0,
      is_active:       r.is_active,
      assigned_rep_id: r.assigned_rep_id,
      assigned_rep:    r.assigned_rep
    })) as CreditCustomerRow[],
    count:      totalCount,
    page,
    pageSize,
    totalPages: Math.ceil(totalCount / pageSize),
  }
}

// ─────────────────────────────────────────────────────────────
// 2. getCreditPortfolioKPIs
//    التجميع يتم كليًا في SQL عبر RPC — لا تجميع JavaScript
// ─────────────────────────────────────────────────────────────

export async function getCreditPortfolioKPIs(filters?: {
  search?:            string
  paymentTerms?:      'credit' | 'mixed' | ''
  repId?:             string
  balanceState?:      'all' | 'with-balance-only' | 'near-limit' | 'exceeded' | 'no-limit'
  currentBalanceMin?: number
  currentBalanceMax?: number
  creditLimitMin?:    number
  creditLimitMax?:    number
}): Promise<CreditPortfolioKPIs> {
  const { data, error } = await supabase.rpc('get_filtered_credit_kpis', {
    p_search:              filters?.search || null,
    p_payment_terms:       filters?.paymentTerms || null,
    p_rep_id:              filters?.repId || null,
    p_balance_state:       filters?.balanceState || 'all',
    p_current_balance_min: filters?.currentBalanceMin ?? null,
    p_current_balance_max: filters?.currentBalanceMax ?? null,
    p_credit_limit_min:    filters?.creditLimitMin ?? null,
    p_credit_limit_max:    filters?.creditLimitMax ?? null,
  })

  if (error) {
    console.error('Failed to fetch filtered credit KPIs:', error)
    throw new Error('فشل جلب المؤشرات الائتمانية. يرجى التأكد من تحديث قاعدة البيانات (RPC get_filtered_credit_kpis).')
  }

  // RPC returns a single row
  const row = (data as any[])[0] || {}

  return {
    totalLimit:           Number(row.total_limit)            || 0,
    totalUsed:            Number(row.total_used)             || 0,
    totalAvailable:       Number(row.total_available)        || 0,
    countExceeded:        Number(row.count_exceeded)         || 0,
    countNearLimit:       Number(row.count_near_limit)       || 0,
    totalCreditCustomers: Number(row.total_credit_customers) || 0,
  }
}

// ─────────────────────────────────────────────────────────────
// 3. getOverdueBatch
//    طلب واحد للصفحة — الحكم كليًا في SQL
//
//    RPC تربط sales_orders مع customers داخليًا وتطبق:
//      (CURRENT_DATE - delivered_at::date) > c.credit_days
//    ثم تُعيد per-customer aggregates جاهزة — لا مقارنة JS تبقى
//
//    الواجهة تقرأ النتيجة مباشرة: has_overdue, overdue_count
// ─────────────────────────────────────────────────────────────

export async function getOverdueBatch(
  customerIds: string[]
): Promise<Record<string, OverdueInfo>> {
  if (!customerIds.length) return {}

  const { data, error } = await supabase.rpc('get_overdue_batch', {
    p_customer_ids: customerIds,
  })

  if (error) {
    return getOverdueBatchFallback(customerIds)
  }

  // الواجهة تقرأ فقط — لا مقارنة جديدة
  const result: Record<string, OverdueInfo> = {}

  // تهيئة كل العملاء بقيم افتراضية (RPC تُعيد فقط من هم في customers)
  for (const id of customerIds) {
    result[id] = { customerId: id, overdueCount: 0, hasOverdue: false }
  }

  for (const row of (data || []) as any[]) {
    result[row.customer_id] = {
      customerId:   row.customer_id,
      overdueCount: Number(row.overdue_count) || 0,
      hasOverdue:   Boolean(row.has_overdue),
    }
  }

  return result
}

/**
 * getOverdueBatchFallback
 * يُستخدم عند غياب RPC get_overdue_batch
 * يجلب credit_days من customers داخلياً ثم يُجري المقارنة محلياً
 */
async function getOverdueBatchFallback(
  customerIds: string[]
): Promise<Record<string, OverdueInfo>> {
  const { data: custData, error: custErr } = await supabase
    .from('customers')
    .select('id, credit_days')
    .in('id', customerIds)

  if (custErr) throw custErr

  const creditDaysMap: Record<string, number> = {}
  for (const c of (custData || []) as any[]) {
    creditDaysMap[c.id] = c.credit_days || 0
  }

  const { data, error } = await supabase
    .from('sales_orders')
    .select('customer_id, total_amount, paid_amount, delivered_at')
    .in('customer_id', customerIds)
    .in('status', ['delivered', 'partially_delivered'])
    .not('delivered_at', 'is', null)
    .gt('total_amount', 0)

  if (error) throw error

  const result: Record<string, OverdueInfo> = {}
  for (const id of customerIds) {
    result[id] = { customerId: id, overdueCount: 0, hasOverdue: false }
  }

  const todayMs = Date.UTC(
    new Date().getUTCFullYear(),
    new Date().getUTCMonth(),
    new Date().getUTCDate()
  )

  for (const order of (data || []) as any[]) {
    const custId     = order.customer_id as string
    const creditDays = creditDaysMap[custId] ?? 0
    const remaining  = (order.total_amount || 0) - (order.paid_amount || 0)
    if (remaining <= 0) continue

    const [y, m, d] = (order.delivered_at as string).slice(0, 10).split('-').map(Number)
    const daysSince  = Math.floor((todayMs - Date.UTC(y, m - 1, d)) / 86_400_000)

    if (daysSince > creditDays) {
      result[custId].overdueCount++
      result[custId].hasOverdue = true
    }
  }

  return result
}

// ─────────────────────────────────────────────────────────────
// 4. getCreditOpenOrders
//    تبويب "الفواتير المسلَّمة" في لوحة العميل
//
//    الحالات: 'delivered' و 'partially_delivered' فقط
//    'confirmed' مستبعد كليًا — هذا التبويب = الديون الفعلية بعد التسليم
//
//    days_since_delivery محسوب في SQL:
//      Supabase يُحضر delivered_at → نحسب الأيام بـ UTC arithmetic
//      (بديل RPC لحين توافر get_credit_open_orders RPC)
// ─────────────────────────────────────────────────────────────

export async function getCreditOpenOrders(customerId: string): Promise<CreditOpenOrder[]> {
  const { data, error } = await supabase.rpc('get_credit_open_orders', {
    p_customer_id: customerId,
  })

  if (error) {
    // Fallback إلى select مباشر إذا لم يكن الـ RPC موجوداً
    return getCreditOpenOrdersFallback(customerId)
  }

  return ((data || []) as any[]).map(row => ({
    id:                  row.id,
    order_number:        row.order_number,
    total_amount:        Number(row.total_amount)    || 0,
    paid_amount:         Number(row.paid_amount)     || 0,
    returned_amount:     Number(row.returned_amount) || 0,
    delivered_at:        row.delivered_at,
    status:              row.status,
    net_remaining:       Number(row.net_remaining)       || 0,
    days_since_delivery: row.days_since_delivery != null
      ? Number(row.days_since_delivery)
      : null,
  })).filter(o => o.net_remaining > 0)
}

async function getCreditOpenOrdersFallback(customerId: string): Promise<CreditOpenOrder[]> {
  const { data, error } = await supabase
    .from('sales_orders')
    .select('id, order_number, total_amount, paid_amount, returned_amount, delivered_at, status')
    .eq('customer_id', customerId)
    // ✅ 'confirmed' مستبعد — المسلَّم فقط
    .in('status', ['delivered', 'partially_delivered'])
    .not('delivered_at', 'is', null)
    .order('delivered_at', { ascending: false })

  if (error) throw error

  const todayMs = Date.UTC(
    new Date().getUTCFullYear(),
    new Date().getUTCMonth(),
    new Date().getUTCDate()
  )

  return ((data || []) as any[]).map(order => {
    const total        = Number(order.total_amount)    || 0
    const paid         = Number(order.paid_amount)     || 0
    const returned     = Number(order.returned_amount) || 0
    const netRemaining = total - paid - returned

    // حساب الأيام بـ UTC date arithmetic — متسق عبر المناطق الزمنية
    const deliveredMs = Date.UTC(
      ...((order.delivered_at as string).slice(0, 10).split('-').map(Number) as [number, number, number])
    )
    const daysSince = Math.floor((todayMs - deliveredMs) / (1000 * 60 * 60 * 24))

    return {
      id:                  order.id,
      order_number:        order.order_number,
      total_amount:        total,
      paid_amount:         paid,
      returned_amount:     returned,
      delivered_at:        order.delivered_at,
      status:              order.status,
      net_remaining:       netRemaining,
      days_since_delivery: daysSince,
    } as CreditOpenOrder
  }).filter(o => o.net_remaining > 0)
}

// ─────────────────────────────────────────────────────────────
// 5. creditUpdateCustomer
//    ① فحص أمامي UX
//    ② RPC الخلفية = الحماية الحقيقية (SECURITY DEFINER + check_permission)
//    لا استدعاء لـ update_customer_with_opening_balance
// ─────────────────────────────────────────────────────────────

export async function creditUpdateCustomer(
  customerId: string,
  patch:       CreditUpdatePatch
): Promise<void> {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('غير مصادق عليه')

  const { data: permCheck } = await supabase.rpc('check_permission', {
    p_user_id:    user.id,
    p_permission: PERMISSIONS.CUSTOMERS_CREDIT_UPDATE,
  })

  if (!permCheck) {
    throw new Error('غير مصرح: يتطلب صلاحية تعديل الائتمان')
  }

  const { error } = await supabase.rpc('update_customer_credit_terms', {
    p_customer_id:   customerId,
    p_payment_terms: patch.payment_terms,
    p_credit_limit:  patch.credit_limit,
    p_credit_days:   patch.credit_days,
  })

  if (error) throw error
}
