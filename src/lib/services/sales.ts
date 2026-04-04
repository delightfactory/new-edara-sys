import { supabase } from '@/lib/supabase/client'
import { getAuthUserId } from '@/lib/services/_get-user-id'
import type {
  SalesOrder, SalesOrderInput, SalesOrderItem, SalesOrderItemInput,
  SalesReturn, SalesReturnInput, SalesReturnItem, SalesReturnItemInput,
  ShippingCompany, ShippingCompanyInput, SalesSettings,
  SalesOrderStatus, SalesReturnStatus,
  PaymentTerms, PaymentMethod,
} from '@/lib/types/master-data'

// ============================================================
// Shipping Companies — شركات الشحن
// ============================================================

export async function getShippingCompanies(onlyActive = false) {
  let query = supabase
    .from('shipping_companies')
    .select('*')
    .order('name')

  if (onlyActive) query = query.eq('is_active', true)

  const { data, error } = await query
  if (error) throw error
  return data as ShippingCompany[]
}

export async function saveShippingCompany(input: ShippingCompanyInput, id?: string) {
  if (id) {
    const { data, error } = await supabase
      .from('shipping_companies')
      .update(input)
      .eq('id', id)
      .select()
      .single()
    if (error) throw error
    return data as ShippingCompany
  } else {
    const userId = await getAuthUserId()
    const { data, error } = await supabase
      .from('shipping_companies')
      .insert({ ...input, created_by: userId })
      .select()
      .single()
    if (error) throw error
    return data as ShippingCompany
  }
}

export async function toggleShippingCompany(id: string, isActive: boolean) {
  const { error } = await supabase
    .from('shipping_companies')
    .update({ is_active: isActive })
    .eq('id', id)
  if (error) throw error
}

// ============================================================
// Sales Settings — إعدادات المبيعات
// ============================================================

export async function getSalesSettings(): Promise<SalesSettings> {
  const keys = [
    'sales.max_discount_percent',
    'sales.min_order_amount',
    'sales.tax_enabled',
    'sales.default_tax_rate',
  ]
  const { data, error } = await supabase
    .from('company_settings')
    .select('key, value')
    .in('key', keys)

  if (error) throw error

  const map = new Map((data || []).map((r: any) => [r.key, r.value]))
  return {
    maxDiscountPercent: Number(map.get('sales.max_discount_percent') ?? 100),
    minOrderAmount: Number(map.get('sales.min_order_amount') ?? 0),
    taxEnabled: map.get('sales.tax_enabled') === 'true',
    defaultTaxRate: Number(map.get('sales.default_tax_rate') ?? 0),
  }
}

// ============================================================
// Sales Orders — أوامر البيع
// ============================================================

const SALES_ORDER_SELECT = `
  *,
  customer:customers(id, name, code, phone, payment_terms, credit_limit, credit_days),
  rep:profiles!sales_orders_rep_id_fkey(id, full_name),
  created_by_profile:profiles!sales_orders_created_by_id_fkey(id, full_name),
  branch:branches(id, name),
  warehouse:warehouses(id, name),
  shipping_company:shipping_companies(id, name),
  delivery_address:customer_branches!sales_orders_delivery_address_id_fkey(id, name, address),
  vault:vaults(id, name, type),
  items:sales_order_items(
    *,
    product:products(id, name, sku, selling_price, tax_rate, base_unit:units!products_base_unit_id_fkey(id, name, symbol)),
    unit:units(id, name, symbol)
  )
`

/**
 * جلب قائمة أوامر البيع مع فلترة وترقيم
 */
export async function getSalesOrders(params?: {
  search?: string
  status?: SalesOrderStatus
  customerId?: string
  repId?: string
  dateFrom?: string
  dateTo?: string
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 25
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('sales_orders')
    .select(`
      *,
      customer:customers(id, name, code, phone),
      rep:profiles!sales_orders_rep_id_fkey(id, full_name),
      branch:branches(id, name),
      warehouse:warehouses(id, name)
    `, { count: 'estimated' })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.search) {
    const trimmed = params.search.trim()
    // PostgREST لا يدعم الفلترة على أعمدة الجداول المرتبطة داخل .or()
    // لذلك نجلب customer_ids أولاً ثم نبني OR صحيح
    const { data: matchedCustomers } = await supabase
      .from('customers')
      .select('id')
      .or(`name.ilike.%${trimmed}%,code.ilike.%${trimmed}%`)
      .limit(100)

    const customerIds = (matchedCustomers || []).map((c: { id: string }) => c.id)

    if (customerIds.length > 0) {
      query = query.or(
        `order_number.ilike.%${trimmed}%,customer_id.in.(${customerIds.join(',')})`
      )
    } else {
      query = query.ilike('order_number', `%${trimmed}%`)
    }
  }
  if (params?.status) {
    query = query.eq('status', params.status)
  }
  if (params?.customerId) {
    query = query.eq('customer_id', params.customerId)
  }
  if (params?.repId) {
    query = query.eq('rep_id', params.repId)
  }
  if (params?.dateFrom) {
    query = query.gte('order_date', params.dateFrom)
  }
  if (params?.dateTo) {
    query = query.lte('order_date', params.dateTo)
  }

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as SalesOrder[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

// ============================================================
// searchSalesOrders — Keyset Pagination via RPC (O(log N))
// يحل مشكلتين معاً:
//   1. البحث في اسم العميل (كان معطوباً سابقاً)
//   2. أداء OFFSET التنازلي مع كبر الجدول
// ============================================================

export interface SalesOrderSearchPage {
  data: SalesOrder[]
  hasMore: boolean
  nextCursor: string | null
  nextCursorId: string | null
}

/**
 * searchSalesOrders — يستخدم RPC search_sales_orders مع Keyset cursor
 * مثالي للبحث وInfinite Scroll في الموبايل وعند الحاجة لأداء أقصى
 */
export async function searchSalesOrders(params?: {
  search?: string
  status?: SalesOrderStatus
  repId?: string
  dateFrom?: string
  dateTo?: string
  cursor?: string | null
  cursorId?: string | null
  pageSize?: number
}): Promise<SalesOrderSearchPage> {
  const pageSize = params?.pageSize ?? 25

  const { data, error } = await supabase.rpc('search_sales_orders', {
    p_search:    params?.search    || null,
    p_status:    params?.status    || null,
    p_rep_id:    params?.repId     || null,
    p_date_from: params?.dateFrom  || null,
    p_date_to:   params?.dateTo    || null,
    p_cursor_ts: params?.cursor    || null,
    p_cursor_id: params?.cursorId  || null,
    p_limit:     pageSize,
  })

  if (error) throw error

  const rows = (data || []) as any[]
  const hasMore = rows.length > 0 && rows[rows.length - 1]?.has_more === true
  const lastRow = rows[rows.length - 1]

  // تحويل نتائج RPC إلى نوع SalesOrder المتوافق
  const mapped = rows.map(r => ({
    ...r,
    customer: r.customer_id ? {
      id: r.customer_id, name: r.customer_name,
      code: r.customer_code, phone: null,
    } : null,
    rep: r.rep_id ? { id: r.rep_id, full_name: r.rep_name } : null,
    branch: r.branch_id ? { id: r.branch_id, name: r.branch_name } : null,
  })) as SalesOrder[]

  return {
    data: mapped,
    hasMore,
    nextCursor: hasMore ? lastRow?.created_at ?? null : null,
    nextCursorId: hasMore ? lastRow?.id ?? null : null,
  }
}

/**
 * جلب أمر بيع واحد بكامل تفاصيله
 */
export async function getSalesOrder(id: string) {
  const { data, error } = await supabase
    .from('sales_orders')
    .select(SALES_ORDER_SELECT)
    .eq('id', id)
    .single()
  if (error) throw error
  return data as SalesOrder
}

/**
 * تنظيف المدخلات: تحويل السلاسل الفارغة '' إلى null
 * لأن Postgres يرفض '' في حقول UUID
 */
function sanitize(input: Record<string, any>): Record<string, any> {
  const cleaned = { ...input }
  for (const key of Object.keys(cleaned)) {
    if (cleaned[key] === '') cleaned[key] = null
  }
  return cleaned
}

/**
 * إنشاء أمر بيع (مسودة)
 */
export async function createSalesOrder(input: SalesOrderInput) {
  const userId = await getAuthUserId()
  const clean = sanitize(input)
  const { data, error } = await supabase
    .from('sales_orders')
    .insert({
      ...clean,
      created_by_id: userId,
      rep_id: clean.rep_id || userId,
      order_number: '', // Trigger يولّده
    })
    .select(SALES_ORDER_SELECT)
    .single()
  if (error) throw error
  return data as SalesOrder
}

/**
 * تحديث أمر بيع (المسودة فقط)
 */
export async function updateSalesOrder(id: string, input: Partial<SalesOrderInput>) {
  const clean = sanitize(input)
  const { data, error } = await supabase
    .from('sales_orders')
    .update(clean)
    .eq('id', id)
    .eq('status', 'draft')
    .select(SALES_ORDER_SELECT)
    .single()
  if (error) throw error
  return data as SalesOrder
}

// ============================================================
// Sales Order Items — بنود أمر البيع
// ============================================================

/**
 * حفظ بنود الطلب (حذف الحالي + إدراج الجديد)
 * يعمل فقط على المسودات (ON DELETE CASCADE يحذف تلقائياً)
 */
export async function saveSalesOrderItems(orderId: string, items: SalesOrderItemInput[]) {
  // حذف البنود الحالية
  const { error: delError } = await supabase
    .from('sales_order_items')
    .delete()
    .eq('order_id', orderId)
  if (delError) throw delError

  if (items.length === 0) return []

  // إدراج البنود الجديدة
  const rows = items.map(item => ({
    order_id: orderId,
    ...item,
  }))

  const { data, error } = await supabase
    .from('sales_order_items')
    .insert(rows)
    .select(`
      *,
      product:products(id, name, sku, selling_price, tax_rate, base_unit:units!products_base_unit_id_fkey(id, name, symbol)),
      unit:units(id, name, symbol)
    `)
  if (error) throw error
  return data as SalesOrderItem[]
}

/**
 * تحديث إجماليات الرأسية بناءً على البنود المحسوبة (بعد الحفظ)
 */
export async function recalcOrderTotals(orderId: string) {
  const { data: items, error } = await supabase
    .from('sales_order_items')
    .select('line_total, discount_amount, tax_amount, quantity, unit_price')
    .eq('order_id', orderId)
  if (error) throw error

  const subtotal = (items || []).reduce((s, i) => s + i.quantity * i.unit_price, 0)
  const discount_amount = (items || []).reduce((s, i) => s + i.discount_amount, 0)
  const tax_amount = (items || []).reduce((s, i) => s + i.tax_amount, 0)
  const total_amount = (items || []).reduce((s, i) => s + i.line_total, 0)

  // جلب الشحن لإضافته
  const { data: order } = await supabase
    .from('sales_orders')
    .select('shipping_cost, shipping_on_customer')
    .eq('id', orderId)
    .single()

  const shippingAdd = order?.shipping_on_customer ? (order.shipping_cost || 0) : 0

  const { error: updError } = await supabase
    .from('sales_orders')
    .update({
      subtotal: Math.round(subtotal * 100) / 100,
      discount_amount: Math.round(discount_amount * 100) / 100,
      tax_amount: Math.round(tax_amount * 100) / 100,
      total_amount: Math.round((total_amount + shippingAdd) * 100) / 100,
    })
    .eq('id', orderId)
  if (updError) throw updError
}


// ============================================================
// Sales Order RPC Actions — الإجراءات الذرية
// ============================================================

/**
 * تأكيد أمر البيع → حجز المخزون
 */
export async function confirmSalesOrder(orderId: string) {
  const userId = await getAuthUserId()
  const { error } = await supabase.rpc('confirm_sales_order', {
    p_order_id: orderId,
    p_user_id: userId,
  })
  if (error) throw error
}

/**
 * تسليم أمر البيع → خصم المخزون + قيد محاسبي
 */
export async function deliverSalesOrder(orderId: string, params: {
  paymentTerms: PaymentTerms
  cashAmount?: number
  paymentMethod?: PaymentMethod | null
  vaultId?: string | null
  custodyId?: string | null
  overrideCredit?: boolean
  bankReference?: string | null   // مرجع التحويل البنكي/إنستاباي
  checkNumber?: string | null     // رقم الشيك
  checkDate?: string | null       // تاريخ استحقاق الشيك (YYYY-MM-DD)
  proofUrl?: string | null        // رابط إثبات الدفع (صورة/PDF)
}) {
  const userId = await getAuthUserId()
  // نُحدّث proof_url في إيصال الدفع المُنشأ تلقائياً بعد التسليم
  const { error } = await supabase.rpc('deliver_sales_order', {
    p_order_id: orderId,
    p_user_id: userId,
    p_payment_terms: params.paymentTerms,
    p_cash_amount: params.cashAmount || 0,
    p_payment_method: params.paymentMethod || null,
    p_vault_id: params.vaultId || null,
    p_custody_id: params.custodyId || null,
    p_override_credit: params.overrideCredit || false,
    p_bank_reference: params.bankReference || null,
    p_check_number: params.checkNumber || null,
    p_check_date: params.checkDate || null,
  })
  if (error) throw error

  // إذا كان هناك إثبات دفع، نُحدّث الإيصال المُنشأ تلقائياً
  if (params.proofUrl) {
    await supabase
      .from('payment_receipts')
      .update({ proof_url: params.proofUrl })
      .eq('sales_order_id', orderId)
      .in('status', ['pending', 'confirmed'])
      .is('proof_url', null)
  }
}

/**
 * إلغاء أمر البيع → إلغاء حجز المخزون
 */
export async function cancelSalesOrder(orderId: string, reason?: string) {
  const userId = await getAuthUserId()
  const { error } = await supabase.rpc('cancel_sales_order', {
    p_order_id: orderId,
    p_user_id: userId,
    p_reason: reason || null,
  })
  if (error) throw error
}

// ============================================================
// Smart Delivery RPCs — دوال التسليم الذكي (04b_delivery_rpcs)
// ============================================================

/** نتيجة فحص الائتمان */
export interface CustomerCreditInfo {
  customer_name: string
  payment_terms: 'cash' | 'credit' | 'mixed'
  credit_limit: number
  current_balance: number
  available_credit: number
  requested_amount: number
  can_use_credit: boolean
  credit_ok: boolean
  exceeds_limit: boolean
  overdue_count: number
  overdue_days: number
  oldest_invoice: string | null
  has_overdue: boolean
}

/** فحص ائتمان العميل قبل التسليم */
export async function checkCustomerCredit(customerId: string, amount: number): Promise<CustomerCreditInfo> {
  const { data, error } = await supabase.rpc('check_customer_credit', {
    p_customer_id: customerId,
    p_amount: amount,
  })
  if (error) throw error
  return data as CustomerCreditInfo
}

/** نتيجة خيارات الدفع */
export interface UserPaymentOptions {
  has_custody: boolean
  custody_id: string | null
  custody_balance: number
  custody_max: number
  can_manage_vaults: boolean
  available_vaults: Array<{ id: string; name: string; type: string; balance: number }>
  cash_destination: 'custody' | 'vault' | null
}

/** خيارات الدفع المتاحة للمستخدم الحالي */
export async function getUserPaymentOptions(branchId?: string | null): Promise<UserPaymentOptions> {
  const userId = await getAuthUserId()
  const { data, error } = await supabase.rpc('get_user_payment_options', {
    p_user_id: userId,
    p_branch_id: branchId || null,
  })
  if (error) throw error
  return data as UserPaymentOptions
}

/** تأكيد الطلب مع تحديد المخزن (يُحدَّد عند التأكيد لا في المسودة) */
export async function confirmSalesOrderWithWarehouse(orderId: string, warehouseId: string) {
  // أولاً: تحديث warehouse_id على الطلب
  const { error: updError } = await supabase
    .from('sales_orders')
    .update({ warehouse_id: warehouseId })
    .eq('id', orderId)
    .eq('status', 'draft')
  if (updError) throw updError
  // ثانياً: تأكيد الطلب (حجز المخزون ذرياً في الـ backend)
  await confirmSalesOrder(orderId)
}


// ============================================================
// Sales Returns — المرتجعات
// ============================================================

const SALES_RETURN_SELECT = `
  *,
  order:sales_orders(id, order_number, payment_terms, total_amount),
  customer:customers(id, name, code),
  warehouse:warehouses(id, name),
  confirmed_by_profile:profiles!sales_returns_confirmed_by_fkey(id, full_name),
  created_by_profile:profiles!sales_returns_created_by_fkey(id, full_name),
  items:sales_return_items(
    *,
    product:products(id, name, sku),
    unit:units(id, name, symbol)
  )
`

/**
 * جلب قائمة المرتجعات
 */
export async function getSalesReturns(params?: {
  search?: string
  status?: SalesReturnStatus
  customerId?: string
  orderId?: string
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 25
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('sales_returns')
    .select(`
      *,
      order:sales_orders(id, order_number),
      customer:customers(id, name, code),
      created_by_profile:profiles!sales_returns_created_by_fkey(id, full_name)
    `, { count: 'estimated' })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.search) {
    query = query.or(`return_number.ilike.%${params.search}%`)
  }
  if (params?.status) query = query.eq('status', params.status)
  if (params?.customerId) query = query.eq('customer_id', params.customerId)
  if (params?.orderId) query = query.eq('order_id', params.orderId)

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as SalesReturn[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

/**
 * جلب مرتجع واحد بالتفاصيل
 */
export async function getSalesReturn(id: string) {
  const { data, error } = await supabase
    .from('sales_returns')
    .select(SALES_RETURN_SELECT)
    .eq('id', id)
    .single()
  if (error) throw error
  return data as SalesReturn
}

/**
 * إنشاء مرتجع (مسودة) + بنوده
 */
export async function createSalesReturn(
  input: SalesReturnInput,
  items: SalesReturnItemInput[]
) {
  const userId = await getAuthUserId()

  // إنشاء الرأسية
  const { data: ret, error } = await supabase
    .from('sales_returns')
    .insert({
      ...input,
      created_by: userId,
      return_number: '', // Trigger يولّده
    })
    .select()
    .single()
  if (error) throw error

  // إنشاء البنود
  if (items.length > 0) {
    const rows = items.map(item => ({
      return_id: ret.id,
      ...item,
    }))
    const { error: itemsError } = await supabase
      .from('sales_return_items')
      .insert(rows)
    if (itemsError) throw itemsError
  }

  // حساب الإجمالي
  const total = items.reduce((s, i) => s + (i.line_total || 0), 0)
  await supabase.from('sales_returns').update({ total_amount: total }).eq('id', ret.id)

  return ret as SalesReturn
}

/**
 * تأكيد المرتجع → إعادة المخزون + قيد عكسي
 */
export async function confirmSalesReturn(returnId: string, params?: {
  vaultId?: string | null
  custodyId?: string | null
}) {
  const userId = await getAuthUserId()
  const { error } = await supabase.rpc('confirm_sales_return', {
    p_return_id: returnId,
    p_user_id: userId,
    p_vault_id: params?.vaultId || null,
    p_custody_id: params?.custodyId || null,
  })
  if (error) throw error
}


// ============================================================
// Payment Allocation — التوزيع الذكي
// ============================================================

/**
 * توزيع دفعة على فواتير العميل (FIFO)
 */
export async function allocatePayment(
  customerId: string,
  amount: number,
  sourceType: string,
  sourceId: string
) {
  const userId = await getAuthUserId()
  const { data, error } = await supabase.rpc('allocate_payment_to_invoices', {
    p_customer_id: customerId,
    p_amount: amount,
    p_source_type: sourceType,
    p_source_id: sourceId,
    p_user_id: userId,
  })
  if (error) throw error
  return data as any[]
}


// ============================================================
// Sales Stats — إحصائيات المبيعات
// ============================================================

/**
 * جلب إحصائيات عدد الطلبات حسب الحالة
 */
export async function getSalesStats() {
  // استعلام واحد مُجمَّع في PostgreSQL بدلاً من 6 استعلامات منفصلة
  const { data, error } = await supabase.rpc('get_sales_stats')
  if (error) throw error

  const result = data as {
    status_counts: Record<string, number>
    total_sales: number
    total_orders: number
  }

  return {
    statusCounts: result.status_counts ?? {},
    totalSales: result.total_sales ?? 0,
    totalOrders: result.total_orders ?? 0,
  }
}

/**
 * جلب البنود القابلة للإرجاع من فاتورة
 * (المسلّم - المرتجع > 0)
 */
export async function getReturnableItems(orderId: string) {
  const { data, error } = await supabase
    .from('sales_order_items')
    .select(`
      *,
      product:products(id, name, sku),
      unit:units(id, name, symbol)
    `)
    .eq('order_id', orderId)
    .gt('delivered_quantity', 0)

  if (error) throw error

  // تصفية: فقط البنود التي لا تزال قابلة للإرجاع
  return (data as SalesOrderItem[]).filter(
    item => (item.delivered_quantity - item.returned_quantity) > 0
  )
}
