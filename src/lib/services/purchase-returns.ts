import { supabase } from '@/lib/supabase/client'
import type {
  PurchaseReturn,
  PurchaseReturnInput,
  PurchaseReturnItemInput,
  PurchaseReturnStatus,
} from '@/lib/types/master-data'

// ============================================================
// Helpers
// ============================================================

async function getUserId(): Promise<string> {
  const { data } = await supabase.auth.getUser()
  if (!data.user?.id) throw new Error('يجب تسجيل الدخول')
  return data.user.id
}

function sanitize(input: Record<string, any>): Record<string, any> {
  const cleaned = { ...input }
  for (const key of Object.keys(cleaned)) {
    if (cleaned[key] === '') cleaned[key] = null
  }
  return cleaned
}

/** Translate backend RPC constraint errors → Arabic UI messages */
function translateError(err: any): Error {
  const msg: string = err?.message || ''
  if (msg.includes('الكمية المتوفرة'))   return new Error(msg)
  if (msg.includes('لا يمكن الإلغاء'))   return new Error(msg)
  if (msg.includes('الفاتورة ملغاة'))     return new Error('هذه الفاتورة ملغاة بالفعل')
  if (msg.includes('مسددة بالكامل'))      return new Error('لا يمكن إلغاء فاتورة مسددة — استخدم مرتجع المشتريات')
  if (msg.includes('paid_amount'))        return new Error('يوجد مدفوعات على الفاتورة — ألغِ الدفع أولاً')
  if (msg.includes('المرتجع مؤكد'))       return new Error('هذا المرتجع مؤكد بالفعل')
  if (msg.includes('لا توجد بنود'))       return new Error('أضف منتجاً واحداً على الأقل قبل التأكيد')
  if (msg.includes('رصيد الخزنة'))        return new Error('رصيد الخزنة غير كافٍ')
  if (msg.includes('billed') || msg.includes('paid'))
    return new Error('الفاتورة المرتبطة يجب أن تكون في حالة (billed) أو (paid)')
  return new Error(msg || 'حدث خطأ غير متوقع')
}

// ============================================================
// Selects
// ============================================================

const RETURN_SELECT = `
  *,
  supplier:suppliers(id, name, code),
  warehouse:warehouses(id, name),
  original_invoice:purchase_invoices(id, number),
  items:purchase_return_items(
    *,
    product:products(
      id, name, sku,
      base_unit:units!products_base_unit_id_fkey(id, name, symbol)
    ),
    unit:units(id, name, symbol)
  )
`

// ============================================================
// CRUD
// ============================================================

export async function getPurchaseReturns(params?: {
  search?:      string
  status?:      PurchaseReturnStatus
  supplierId?:  string
  warehouseId?: string
  dateFrom?:    string
  dateTo?:      string
  page?:        number
  pageSize?:    number
}) {
  const page     = params?.page     || 1
  const pageSize = params?.pageSize || 25
  const from     = (page - 1) * pageSize
  const to       = from + pageSize - 1

  let query = supabase
    .from('purchase_returns')
    .select(`*, supplier:suppliers(id, name, code), warehouse:warehouses(id, name)`, { count: 'estimated' })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.search)      query = query.ilike('number', `%${params.search}%`)
  if (params?.status)      query = query.eq('status', params.status)
  if (params?.supplierId)  query = query.eq('supplier_id', params.supplierId)
  if (params?.warehouseId) query = query.eq('warehouse_id', params.warehouseId)
  if (params?.dateFrom)    query = query.gte('return_date', params.dateFrom)
  if (params?.dateTo)      query = query.lte('return_date', params.dateTo)

  const { data, error, count } = await query
  if (error) throw translateError(error)

  return {
    data: data as PurchaseReturn[],
    count:      count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

export async function getPurchaseReturn(id: string): Promise<PurchaseReturn> {
  const { data, error } = await supabase
    .from('purchase_returns')
    .select(RETURN_SELECT)
    .eq('id', id)
    .single()
  if (error) throw translateError(error)
  return data as PurchaseReturn
}

export async function createPurchaseReturn(
  header: PurchaseReturnInput,
  items:  PurchaseReturnItemInput[]
): Promise<PurchaseReturn> {
  const userId      = await getUserId()
  const cleanHeader = sanitize(header)

  const subtotal    = items.reduce((s, i) => s + i.quantity * i.unit_price, 0)
  const discountAmt = items.reduce(
    (s, i) => s + i.quantity * i.unit_price * ((i.discount_rate ?? 0) / 100), 0
  )
  const taxAmt = items.reduce(
    (s, i) => s + i.quantity * i.unit_price * (1 - (i.discount_rate ?? 0) / 100) * ((i.tax_rate ?? 0) / 100), 0
  )

  const { data: ret, error } = await supabase
    .from('purchase_returns')
    .insert({
      ...cleanHeader,
      return_date:     cleanHeader.return_date || new Date().toISOString().slice(0, 10),
      subtotal:        Math.round(subtotal             * 100) / 100,
      discount_amount: Math.round(discountAmt          * 100) / 100,
      tax_amount:      Math.round(taxAmt               * 100) / 100,
      total_amount:    Math.round((subtotal - discountAmt + taxAmt) * 100) / 100,
      status:          'draft',
      created_by:      userId,
    })
    .select()
    .single()
  if (error) throw translateError(error)

  if (items.length > 0) {
    const rows = items.map(item => ({
      return_id:     ret.id,
      product_id:    item.product_id,
      unit_id:       item.unit_id || null,
      quantity:      item.quantity,
      unit_price:    item.unit_price,
      discount_rate: item.discount_rate ?? 0,
      tax_rate:      item.tax_rate      ?? 0,
    }))
    const { error: itemsError } = await supabase
      .from('purchase_return_items')
      .insert(rows)
    if (itemsError) throw translateError(itemsError)
  }

  return getPurchaseReturn(ret.id)
}

export async function updatePurchaseReturn(
  id:     string,
  header: Partial<PurchaseReturnInput>,
  items?: PurchaseReturnItemInput[]
): Promise<PurchaseReturn> {
  const cleanHeader = sanitize(header)

  const { error: hdrError } = await supabase
    .from('purchase_returns')
    .update(cleanHeader)
    .eq('id', id)
    .eq('status', 'draft')
  if (hdrError) throw translateError(hdrError)

  if (items !== undefined) {
    const { error: delError } = await supabase
      .from('purchase_return_items')
      .delete()
      .eq('return_id', id)
    if (delError) throw translateError(delError)

    if (items.length > 0) {
      const rows = items.map(item => ({
        return_id:     id,
        product_id:    item.product_id,
        unit_id:       item.unit_id || null,
        quantity:      item.quantity,
        unit_price:    item.unit_price,
        discount_rate: item.discount_rate ?? 0,
        tax_rate:      item.tax_rate      ?? 0,
      }))
      const { error: insError } = await supabase
        .from('purchase_return_items')
        .insert(rows)
      if (insError) throw translateError(insError)
    }

    const subtotal    = items.reduce((s, i) => s + i.quantity * i.unit_price, 0)
    const discountAmt = items.reduce((s, i) => s + i.quantity * i.unit_price * ((i.discount_rate ?? 0) / 100), 0)
    const taxAmt      = items.reduce(
      (s, i) => s + i.quantity * i.unit_price * (1 - (i.discount_rate ?? 0) / 100) * ((i.tax_rate ?? 0) / 100), 0
    )
    const { error: totError } = await supabase
      .from('purchase_returns')
      .update({
        subtotal:        Math.round(subtotal    * 100) / 100,
        discount_amount: Math.round(discountAmt * 100) / 100,
        tax_amount:      Math.round(taxAmt      * 100) / 100,
        total_amount:    Math.round((subtotal - discountAmt + taxAmt) * 100) / 100,
      })
      .eq('id', id)
    if (totError) throw translateError(totError)
  }

  return getPurchaseReturn(id)
}

// ============================================================
// RPC Wrappers
// ============================================================

/**
 * إلغاء فاتورة مشتريات — يعكس المخزون والقيود ذرياً
 * حراسة صارمة: لا يتجاهل allow_negative_stock
 */
export async function cancelPurchaseInvoice(invoiceId: string): Promise<void> {
  const userId = await getUserId()
  const { error } = await supabase.rpc('cancel_purchase_invoice', {
    p_invoice_id: invoiceId,
    p_user_id:    userId,
  })
  if (error) throw translateError(error)
}

/**
 * تأكيد مرتجع المشتريات — ذري | WAC Variance → ±5300 | IAS 2
 */
export async function confirmPurchaseReturn(returnId: string): Promise<void> {
  const userId = await getUserId()
  const { error } = await supabase.rpc('confirm_purchase_return', {
    p_return_id: returnId,
    p_user_id:   userId,
  })
  if (error) throw translateError(error)
}
