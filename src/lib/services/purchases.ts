import { supabase } from '@/lib/supabase/client'
import type {
  PurchaseInvoice,
  PurchaseInvoiceItem,
  PurchaseInvoiceInput,
  PurchaseInvoiceItemInput,
  PurchaseInvoiceStatus,
  PurchasePaymentMethod,
} from '@/lib/types/master-data'

// ============================================================
// Helper — جلب معرف المستخدم الحالي
// ============================================================

async function getUserId(): Promise<string> {
  const { data } = await supabase.auth.getUser()
  if (!data.user?.id) throw new Error('يجب تسجيل الدخول')
  return data.user.id
}

// تنظيف سلاسل فارغة → null (لمنع فشل UUID في Postgres)
function sanitize(input: Record<string, any>): Record<string, any> {
  const cleaned = { ...input }
  for (const key of Object.keys(cleaned)) {
    if (cleaned[key] === '') cleaned[key] = null
  }
  return cleaned
}

// ============================================================
// Select Query — قالب الاستعلام الكامل
// ============================================================

const PURCHASE_INVOICE_SELECT = `
  *,
  supplier:suppliers(id, name, code),
  warehouse:warehouses(id, name),
  vault:vaults(id, name, type),
  items:purchase_invoice_items(
    *,
    product:products(
      id, name, sku,
      base_unit:units!products_base_unit_id_fkey(id, name, symbol)
    ),
    unit:units(id, name, symbol)
  )
`

// ============================================================
// CRUD — قراءة وإنشاء وتعديل
// ============================================================

/**
 * جلب قائمة فواتير الشراء مع فلترة وترقيم
 */
export async function getPurchaseInvoices(params?: {
  search?: string
  status?: PurchaseInvoiceStatus
  supplierId?: string
  warehouseId?: string
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
    .from('purchase_invoices')
    .select(
      `*,
      supplier:suppliers(id, name, code),
      warehouse:warehouses(id, name)`,
      { count: 'estimated' }
    )
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.search) {
    query = query.or(
      `number.ilike.%${params.search}%,supplier_invoice_ref.ilike.%${params.search}%`
    )
  }
  if (params?.status)      query = query.eq('status', params.status)
  if (params?.supplierId)  query = query.eq('supplier_id', params.supplierId)
  if (params?.warehouseId) query = query.eq('warehouse_id', params.warehouseId)
  if (params?.dateFrom)    query = query.gte('invoice_date', params.dateFrom)
  if (params?.dateTo)      query = query.lte('invoice_date', params.dateTo)

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as PurchaseInvoice[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

/**
 * جلب فاتورة شراء واحدة بكامل تفاصيلها
 */
export async function getPurchaseInvoice(id: string): Promise<PurchaseInvoice> {
  const { data, error } = await supabase
    .from('purchase_invoices')
    .select(PURCHASE_INVOICE_SELECT)
    .eq('id', id)
    .single()
  if (error) throw error
  return data as PurchaseInvoice
}

/**
 * إنشاء فاتورة مشتريات جديدة (مسودة) + بنودها
 * الرقم التسلسلي (PIN-YYYYMMDD-XXXX) يتولّده Trigger تلقائياً
 */
export async function createPurchaseInvoice(
  header: PurchaseInvoiceInput,
  items: PurchaseInvoiceItemInput[]
): Promise<PurchaseInvoice> {
  const userId = await getUserId()
  const cleanHeader = sanitize(header)

  // حساب إجماليات الرأسية من البنود
  const subtotal = items.reduce((s, i) => s + i.ordered_quantity * i.unit_price, 0)
  const discountAmt = items.reduce(
    (s, i) => s + i.ordered_quantity * i.unit_price * ((i.discount_rate ?? 0) / 100),
    0
  )
  const netBase = subtotal - discountAmt
  const taxAmt = items.reduce(
    (s, i) =>
      s +
      i.ordered_quantity *
        i.unit_price *
        (1 - (i.discount_rate ?? 0) / 100) *
        ((i.tax_rate ?? 0) / 100),
    0
  )
  const landedCosts = header.landed_costs ?? 0
  const total = netBase + taxAmt + landedCosts

  // إنشاء الرأسية
  const { data: inv, error } = await supabase
    .from('purchase_invoices')
    .insert({
      ...cleanHeader,
      subtotal:         Math.round(subtotal  * 100) / 100,
      discount_amount:  Math.round(discountAmt * 100) / 100,
      tax_amount:       Math.round(taxAmt    * 100) / 100,
      total_amount:     Math.round(total     * 100) / 100,
      status:           'draft',
      created_by:       userId,
    })
    .select()
    .single()
  if (error) throw error

  // إنشاء البنود
  if (items.length > 0) {
    const rows = items.map(item => ({
      invoice_id:        inv.id,
      product_id:        item.product_id,
      unit_id:           item.unit_id || null,
      ordered_quantity:  item.ordered_quantity,
      received_quantity: item.received_quantity ?? 0,
      unit_price:        item.unit_price,
      discount_rate:     item.discount_rate ?? 0,
      tax_rate:          item.tax_rate ?? 0,
    }))
    const { error: itemsError } = await supabase
      .from('purchase_invoice_items')
      .insert(rows)
    if (itemsError) throw itemsError
  }

  // إعادة الجلب بكامل التفاصيل
  return getPurchaseInvoice(inv.id)
}

/**
 * تحديث فاتورة المشتريات (مسودة فقط) + إعادة حساب البنود
 * يُستخدم لتعديل الرأسية أو إعادة كتابة كل البنود
 */
export async function updatePurchaseInvoice(
  id: string,
  header: Partial<PurchaseInvoiceInput>,
  items?: PurchaseInvoiceItemInput[]
): Promise<PurchaseInvoice> {
  const cleanHeader = sanitize(header)

  // تحديث الرأسية (الحماية: draft فقط)
  const { error: hdrError } = await supabase
    .from('purchase_invoices')
    .update(cleanHeader)
    .eq('id', id)
    .eq('status', 'draft')
  if (hdrError) throw hdrError

  // إعادة كتابة البنود إن مُررت
  if (items !== undefined) {
    const { error: delError } = await supabase
      .from('purchase_invoice_items')
      .delete()
      .eq('invoice_id', id)
    if (delError) throw delError

    if (items.length > 0) {
      const rows = items.map(item => ({
        invoice_id:        id,
        product_id:        item.product_id,
        unit_id:           item.unit_id || null,
        ordered_quantity:  item.ordered_quantity,
        received_quantity: item.received_quantity ?? 0,
        unit_price:        item.unit_price,
        discount_rate:     item.discount_rate ?? 0,
        tax_rate:          item.tax_rate ?? 0,
      }))
      const { error: insError } = await supabase
        .from('purchase_invoice_items')
        .insert(rows)
      if (insError) throw insError
    }

    // إعادة حساب إجماليات الرأسية
    await recalcPurchaseInvoiceTotals(id, items, header.landed_costs)
  }

  return getPurchaseInvoice(id)
}

/**
 * مساعد: إعادة حساب إجماليات رأسية الفاتورة من البنود
 * يُستدعى بعد تعديل البنود في وضع المسودة
 */
export async function recalcPurchaseInvoiceTotals(
  invoiceId: string,
  items: PurchaseInvoiceItemInput[],
  landedCosts?: number
) {
  const subtotal    = items.reduce((s, i) => s + i.ordered_quantity * i.unit_price, 0)
  const discountAmt = items.reduce(
    (s, i) => s + i.ordered_quantity * i.unit_price * ((i.discount_rate ?? 0) / 100),
    0
  )
  const taxAmt = items.reduce(
    (s, i) =>
      s +
      i.ordered_quantity *
        i.unit_price *
        (1 - (i.discount_rate ?? 0) / 100) *
        ((i.tax_rate ?? 0) / 100),
    0
  )
  const lc = landedCosts ?? 0
  const total = subtotal - discountAmt + taxAmt + lc

  const { error } = await supabase
    .from('purchase_invoices')
    .update({
      subtotal:         Math.round(subtotal    * 100) / 100,
      discount_amount:  Math.round(discountAmt * 100) / 100,
      tax_amount:       Math.round(taxAmt      * 100) / 100,
      landed_costs:     Math.round(lc          * 100) / 100,
      total_amount:     Math.round(total       * 100) / 100,
    })
    .eq('id', invoiceId)
  if (error) throw error
}

// ============================================================
// RPC Wrappers — العمليات الذرية
// ============================================================

/**
 * RPC: تسجيل استلام البضاعة + تحديث WAC
 * (المرحلة الثالثة — تُحدَّث received_quantity في البنود قبل الاستدعاء)
 */
export async function receivePurchaseInvoice(invoiceId: string): Promise<void> {
  const userId = await getUserId()
  const { error } = await supabase.rpc('receive_purchase_invoice', {
    p_invoice_id: invoiceId,
    p_user_id:    userId,
  })
  if (error) throw error
}

/**
 * RPC: الاعتماد المالي للفاتورة + قيد محاسبي
 * p_vault_id + p_payment_method → دفع فوري
 * بدونهما → يُحوَّل الدين للـ AP (billed)
 */
export async function billPurchaseInvoice(
  invoiceId: string,
  options?: {
    vaultId?: string | null
    paymentMethod?: PurchasePaymentMethod | null
  }
): Promise<void> {
  const userId = await getUserId()
  const { error } = await supabase.rpc('bill_purchase_invoice', {
    p_invoice_id:     invoiceId,
    p_user_id:        userId,
    p_vault_id:       options?.vaultId       ?? null,
    p_payment_method: options?.paymentMethod ?? null,
  })
  if (error) throw error
}

/**
 * RPC: سداد جزئي أو كلي لفاتورة مؤجلة (billed)
 */
export async function paySupplier(
  invoiceId: string,
  params: {
    amount: number
    paymentMethod: PurchasePaymentMethod
    vaultId?: string | null
    notes?: string | null
  }
): Promise<void> {
  const userId = await getUserId()
  const { error } = await supabase.rpc('pay_supplier', {
    p_invoice_id:     invoiceId,
    p_user_id:        userId,
    p_amount:         params.amount,
    p_payment_method: params.paymentMethod,
    p_vault_id:       params.vaultId  ?? null,
    p_notes:          params.notes    ?? null,
  })
  if (error) throw error
}

// ============================================================
// Received-Quantity helpers — مساعدات تحديث بنود الاستلام
// ============================================================

/**
 * تحديث received_quantity لبند واحد قبل استدعاء receive_purchase_invoice
 * (يعمل على جانب الـ Client في وضع المسودة)
 */
export async function updateItemReceivedQty(
  itemId: string,
  receivedQty: number
): Promise<void> {
  const { error } = await supabase
    .from('purchase_invoice_items')
    .update({ received_quantity: receivedQty })
    .eq('id', itemId)
  if (error) throw error
}

/**
 * تحديث landed_costs في الرأسية (قبل التسليم)
 */
export async function updateLandedCosts(
  invoiceId: string,
  landedCosts: number
): Promise<void> {
  const { error } = await supabase
    .from('purchase_invoices')
    .update({
      landed_costs: landedCosts,
      // إعادة حساب الإجمالي تلقائياً (frontend side)
    })
    .eq('id', invoiceId)
    .eq('status', 'draft')
  if (error) throw error
}
