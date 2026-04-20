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
// Shipping Companies â€” Ø´Ø±ÙƒØ§Øª Ø§Ù„Ø´Ø­Ù†
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
// Sales Settings â€” Ø¥Ø¹Ø¯Ø§Ø¯Ø§Øª Ø§Ù„Ù…Ø¨ÙŠØ¹Ø§Øª
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
// Sales Orders â€” Ø£ÙˆØ§Ù…Ø± Ø§Ù„Ø¨ÙŠØ¹
// ============================================================

const SALES_ORDER_SELECT = `
  *,
  customer:customers(id, name, code, phone, mobile, latitude, longitude, payment_terms, credit_limit, credit_days),
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
 * Ø¬Ù„Ø¨ Ù‚Ø§Ø¦Ù…Ø© Ø£ÙˆØ§Ù…Ø± Ø§Ù„Ø¨ÙŠØ¹ Ù…Ø¹ ÙÙ„ØªØ±Ø© ÙˆØªØ±Ù‚ÙŠÙ…
 *  - search:         Ø¨Ø­Ø« ÙÙŠ Ø±Ù‚Ù… Ø§Ù„Ø·Ù„Ø¨ + Ø§Ø³Ù…/ÙƒÙˆØ¯/Ù‡Ø§ØªÙ Ø§Ù„Ø¹Ù…ÙŠÙ„
 *  - status:         Ø­Ø§Ù„Ø© Ø§Ù„Ø·Ù„Ø¨
 *  - repId:          Ø§Ù„Ù…Ù†Ø¯ÙˆØ¨
 *  - paymentTerms:   Ø·Ø±ÙŠÙ‚Ø© Ø§Ù„Ø¯ÙØ¹ (cash / credit / mixed)
 *  - governorateId:  Ù…Ø­Ø§ÙØ¸Ø© Ø§Ù„Ø¹Ù…ÙŠÙ„
 *  - cityId:         Ù…Ø¯ÙŠÙ†Ø© Ø§Ù„Ø¹Ù…ÙŠÙ„
 *  - dateFrom/To:    Ù†Ø·Ø§Ù‚ ØªØ§Ø±ÙŠØ® Ø§Ù„Ø·Ù„Ø¨
 */
export async function getSalesOrders(params?: {
  search?: string
  status?: SalesOrderStatus
  customerId?: string
  repId?: string
  paymentTerms?: string
  governorateId?: string
  cityId?: string
  dateFrom?: string
  dateTo?: string
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 25
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  // â”€â”€ Ù…Ø³Ø§Ø± Ø§Ù„Ø¨Ø­Ø« Ø§Ù„Ù†ØµÙŠ: RPC ÙŠØ¨Ø­Ø« ÙÙŠ Ø§Ø³Ù…/ÙƒÙˆØ¯/Ù‡Ø§ØªÙ Ø§Ù„Ø¹Ù…ÙŠÙ„ Ù…Ù† SQL â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  if (params?.search?.trim()) {
    const trimmed = params.search.trim()
    const fetchAll = from + pageSize

    const { data, error } = await supabase.rpc('search_sales_orders', {
      p_search: trimmed,
      p_status: params?.status || null,
      p_rep_id: params?.repId || null,
      p_payment_terms: params?.paymentTerms || null,
      p_governorate_id: params?.governorateId || null,
      p_city_id: params?.cityId || null,
      p_date_from: params?.dateFrom || null,
      p_date_to: params?.dateTo || null,
      p_cursor_ts: null,
      p_cursor_id: null,
      p_limit: fetchAll + 1,
    })
    if (error) throw error

    const rows = (data || []) as any[]
    const hasMore = rows.length > fetchAll
    const sliced = rows.slice(from, from + pageSize)
    const estimated = hasMore ? (page + 1) * pageSize : from + sliced.length

    const mapped = sliced.map((r: any) => ({
      ...r,
      customer: r.customer_id ? {
        id: r.customer_id, name: r.customer_name,
        code: r.customer_code, phone: r.customer_phone ?? null,
      } : null,
      rep: r.rep_id ? { id: r.rep_id, full_name: r.rep_name } : null,
      branch: r.branch_id ? { id: r.branch_id, name: r.branch_name } : null,
    })) as SalesOrder[]

    return { data: mapped, count: estimated, page, pageSize, totalPages: hasMore ? page + 1 : page }
  }

  // â”€â”€ Ø§Ù„Ù…Ø³Ø§Ø± Ø§Ù„Ø¹Ø§Ø¯ÙŠ (Ù„Ø§ ÙŠÙˆØ¬Ø¯ Ø¨Ø­Ø« Ù†ØµÙŠ): PostgREST â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  let query = supabase
    .from('sales_orders')
    .select(`
      *,
      customer:customers(id, name, code, phone, mobile, latitude, longitude, payment_terms, credit_limit, credit_days),
      rep:profiles!sales_orders_rep_id_fkey(id, full_name),
      branch:branches(id, name),
      warehouse:warehouses(id, name)
    `, { count: 'exact' })
    .order('order_date', { ascending: false })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.status) query = query.eq('status', params.status)
  if (params?.customerId) query = query.eq('customer_id', params.customerId)
  if (params?.repId) query = query.eq('rep_id', params.repId)
  if (params?.paymentTerms) query = query.eq('payment_terms', params.paymentTerms)
  if (params?.dateFrom) query = query.gte('order_date', params.dateFrom)
  if (params?.dateTo) query = query.lte('order_date', params.dateTo)

  // â”€â”€ Ø§Ù„ÙÙ„ØªØ±Ø© Ø§Ù„Ø¬ØºØ±Ø§ÙÙŠØ© â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //
  // Ø§Ù„Ù…Ø´ÙƒÙ„Ø©: Ø§Ù„Ø¹Ù…Ù„Ø§Ø¡ ÙŠÙØ®Ø²ÙŽÙ‘Ù†ÙˆÙ† Ø¨Ù€ city_id ÙÙŠ Ù…Ø¹Ø¸Ù… Ø§Ù„Ø­Ø§Ù„Ø§ØªØŒ Ø¨Ø¯ÙˆÙ† governorate_id Ù…Ø¨Ø§Ø´Ø±.
  // Ù„Ø°Ø§ ÙÙ„ØªØ± eq('governorate_id', govId) ÙŠÙØ¹ÙŠØ¯ ØµÙØ±Ù‹Ø§.
  //
  // Ø§Ù„Ø­Ù„:
  //   - Ù…Ø¯ÙŠÙ†Ø© ÙÙ‚Ø·         â†’ eq('city_id', cityId)
  //   - Ù…Ø­Ø§ÙØ¸Ø© ÙÙ‚Ø·        â†’ Ø­Ø¶Ø± Ù…Ø¯Ù† Ø§Ù„Ù…Ø­Ø§ÙØ¸Ø© â†’ in('city_id', cityIds)
  //                          + OR eq('governorate_id', govId) Ù„Ù„Ø¹Ù…Ù„Ø§Ø¡ Ø§Ù„Ù‚Ø¯Ø§Ù…Ù‰
  //   - Ù…Ø­Ø§ÙØ¸Ø© + Ù…Ø¯ÙŠÙ†Ø©    â†’ eq('city_id', cityId) [Ø§Ù„Ù…Ø¯ÙŠÙ†Ø© Ø£Ø¯Ù‚]
  if (params?.cityId || params?.governorateId) {
    let customerIds: string[] = []

    if (params.cityId) {
      // Ø£Ø¯Ù‚: ÙÙ„ØªØ± Ù…Ø¨Ø§Ø´Ø± Ø¨Ø§Ù„Ù…Ø¯ÙŠÙ†Ø©
      const { data: gc, error: ge } = await supabase
        .from('customers').select('id')
        .eq('city_id', params.cityId)
      if (ge) throw ge
      customerIds = (gc || []).map((c: any) => c.id)

    } else if (params.governorateId) {
      // Ù…Ø­Ø§ÙØ¸Ø© ÙÙ‚Ø·: Ù†Ø­Ø¶Ø± Ù…Ø¯Ù†Ù‡Ø§ Ø«Ù… Ù†Ø¬Ù…Ø¹ Ø§Ù„Ø¹Ù…Ù„Ø§Ø¡
      // Ø§Ù„Ø®Ø·ÙˆØ© 1: Ù…Ø¯Ù† Ø§Ù„Ù…Ø­Ø§ÙØ¸Ø©
      const { data: govCities } = await supabase
        .from('cities').select('id')
        .eq('governorate_id', params.governorateId)
      const cityIds = (govCities || []).map((c: any) => c.id)

      // Ø§Ù„Ø®Ø·ÙˆØ© 2: Ø¹Ù…Ù„Ø§Ø¡ Ø¨Ù€ city_id Ù…Ù†Ù‡Ø§ Ø£Ùˆ Ø¨Ù€ governorate_id Ù…Ø¨Ø§Ø´Ø±Ø©
      let geoQ = supabase.from('customers').select('id')
      if (cityIds.length > 0) {
        // Ù†ØºØ·ÙŠ ÙƒÙ„Ø§ Ø§Ù„Ø­Ø§Ù„ØªÙŠÙ†: Ø¨ÙŠØ§Ù†Ø§Øª Ù‚Ø¯ÙŠÙ…Ø© (governorate_id) ÙˆØ¬Ø¯ÙŠØ¯Ø© (city_id)
        geoQ = geoQ.or(
          `governorate_id.eq.${params.governorateId},city_id.in.(${cityIds.join(',')})`
        )
      } else {
        // Ù„Ø§ ØªÙˆØ¬Ø¯ Ù…Ø¯Ù† â†’ Ù†ÙƒØªÙÙŠ Ø¨Ù€ governorate_id
        geoQ = geoQ.eq('governorate_id', params.governorateId)
      }
      const { data: gc, error: ge } = await geoQ
      if (ge) throw ge
      customerIds = (gc || []).map((c: any) => c.id)
    }

    if (customerIds.length === 0) {
      return { data: [], count: 0, page, pageSize, totalPages: 0 }
    }

    query = query.in('customer_id', customerIds)
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
// searchSalesOrders â€” Keyset Pagination via RPC (O(log N))
// ÙŠØ­Ù„ Ù…Ø´ÙƒÙ„ØªÙŠÙ† Ù…Ø¹Ø§Ù‹:
//   1. Ø§Ù„Ø¨Ø­Ø« ÙÙŠ Ø§Ø³Ù… Ø§Ù„Ø¹Ù…ÙŠÙ„ (ÙƒØ§Ù† Ù…Ø¹Ø·ÙˆØ¨Ø§Ù‹ Ø³Ø§Ø¨Ù‚Ø§Ù‹)
//   2. Ø£Ø¯Ø§Ø¡ OFFSET Ø§Ù„ØªÙ†Ø§Ø²Ù„ÙŠ Ù…Ø¹ ÙƒØ¨Ø± Ø§Ù„Ø¬Ø¯ÙˆÙ„
// ============================================================

export interface SalesOrderSearchPage {
  data: SalesOrder[]
  hasMore: boolean
  nextCursor: string | null
  nextCursorId: string | null
}

/**
 * searchSalesOrders â€” ÙŠØ³ØªØ®Ø¯Ù… RPC search_sales_orders Ù…Ø¹ Keyset cursor
 * Ù…Ø«Ø§Ù„ÙŠ Ù„Ù„Ø¨Ø­Ø« ÙˆInfinite Scroll ÙÙŠ Ø§Ù„Ù…ÙˆØ¨Ø§ÙŠÙ„ ÙˆØ¹Ù†Ø¯ Ø§Ù„Ø­Ø§Ø¬Ø© Ù„Ø£Ø¯Ø§Ø¡ Ø£Ù‚ØµÙ‰
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
    p_search: params?.search || null,
    p_status: params?.status || null,
    p_rep_id: params?.repId || null,
    p_date_from: params?.dateFrom || null,
    p_date_to: params?.dateTo || null,
    p_cursor_ts: params?.cursor || null,
    p_cursor_id: params?.cursorId || null,
    p_limit: pageSize,
  })

  if (error) throw error

  const rows = (data || []) as any[]
  const hasMore = rows.length > 0 && rows[rows.length - 1]?.has_more === true
  const lastRow = rows[rows.length - 1]

  // ØªØ­ÙˆÙŠÙ„ Ù†ØªØ§Ø¦Ø¬ RPC Ø¥Ù„Ù‰ Ù†ÙˆØ¹ SalesOrder Ø§Ù„Ù…ØªÙˆØ§ÙÙ‚
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
 * Ø¬Ù„Ø¨ Ø£Ù…Ø± Ø¨ÙŠØ¹ ÙˆØ§Ø­Ø¯ Ø¨ÙƒØ§Ù…Ù„ ØªÙØ§ØµÙŠÙ„Ù‡
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
 * ØªÙ†Ø¸ÙŠÙ Ø§Ù„Ù…Ø¯Ø®Ù„Ø§Øª: ØªØ­ÙˆÙŠÙ„ Ø§Ù„Ø³Ù„Ø§Ø³Ù„ Ø§Ù„ÙØ§Ø±ØºØ© '' Ø¥Ù„Ù‰ null
 * Ù„Ø£Ù† Postgres ÙŠØ±ÙØ¶ '' ÙÙŠ Ø­Ù‚ÙˆÙ„ UUID
 */
function sanitize(input: Record<string, any>): Record<string, any> {
  const cleaned = { ...input }
  for (const key of Object.keys(cleaned)) {
    if (cleaned[key] === '') cleaned[key] = null
  }
  return cleaned
}

/**
 * Ø¥Ù†Ø´Ø§Ø¡ Ø£Ù…Ø± Ø¨ÙŠØ¹ (Ù…Ø³ÙˆØ¯Ø©)
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
      order_number: '', // Trigger ÙŠÙˆÙ„Ù‘Ø¯Ù‡
    })
    .select(SALES_ORDER_SELECT)
    .single()
  if (error) throw error
  return data as SalesOrder
}

/**
 * ØªØ­Ø¯ÙŠØ« Ø£Ù…Ø± Ø¨ÙŠØ¹ (Ø§Ù„Ù…Ø³ÙˆØ¯Ø© ÙÙ‚Ø·)
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
// Sales Order Items â€” Ø¨Ù†ÙˆØ¯ Ø£Ù…Ø± Ø§Ù„Ø¨ÙŠØ¹
// ============================================================

/**
 * Ø­ÙØ¸ Ø¨Ù†ÙˆØ¯ Ø§Ù„Ø·Ù„Ø¨ (Ø­Ø°Ù Ø§Ù„Ø­Ø§Ù„ÙŠ + Ø¥Ø¯Ø±Ø§Ø¬ Ø§Ù„Ø¬Ø¯ÙŠØ¯)
 * ÙŠØ¹Ù…Ù„ ÙÙ‚Ø· Ø¹Ù„Ù‰ Ø§Ù„Ù…Ø³ÙˆØ¯Ø§Øª (ON DELETE CASCADE ÙŠØ­Ø°Ù ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹)
 */
export async function saveSalesOrderItems(orderId: string, items: SalesOrderItemInput[]) {
  // Ø­Ø°Ù Ø§Ù„Ø¨Ù†ÙˆØ¯ Ø§Ù„Ø­Ø§Ù„ÙŠØ©
  const { error: delError } = await supabase
    .from('sales_order_items')
    .delete()
    .eq('order_id', orderId)
  if (delError) throw delError

  if (items.length === 0) return []

  // Ø¥Ø¯Ø±Ø§Ø¬ Ø§Ù„Ø¨Ù†ÙˆØ¯ Ø§Ù„Ø¬Ø¯ÙŠØ¯Ø©
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
 * ØªØ­Ø¯ÙŠØ« Ø¥Ø¬Ù…Ø§Ù„ÙŠØ§Øª Ø§Ù„Ø±Ø£Ø³ÙŠØ© Ø¨Ù†Ø§Ø¡Ù‹ Ø¹Ù„Ù‰ Ø§Ù„Ø¨Ù†ÙˆØ¯ Ø§Ù„Ù…Ø­Ø³ÙˆØ¨Ø© (Ø¨Ø¹Ø¯ Ø§Ù„Ø­ÙØ¸)
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

  // Ø¬Ù„Ø¨ Ø§Ù„Ø´Ø­Ù† Ù„Ø¥Ø¶Ø§ÙØªÙ‡
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
// Sales Order RPC Actions â€” Ø§Ù„Ø¥Ø¬Ø±Ø§Ø¡Ø§Øª Ø§Ù„Ø°Ø±ÙŠØ©
// ============================================================

/**
 * ØªØ£ÙƒÙŠØ¯ Ø£Ù…Ø± Ø§Ù„Ø¨ÙŠØ¹ â†’ Ø­Ø¬Ø² Ø§Ù„Ù…Ø®Ø²ÙˆÙ†
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
 * ØªØ³Ù„ÙŠÙ… Ø£Ù…Ø± Ø§Ù„Ø¨ÙŠØ¹ â†’ Ø®ØµÙ… Ø§Ù„Ù…Ø®Ø²ÙˆÙ† + Ù‚ÙŠØ¯ Ù…Ø­Ø§Ø³Ø¨ÙŠ
 */
export async function deliverSalesOrder(orderId: string, params: {
  paymentTerms: PaymentTerms
  cashAmount?: number
  paymentMethod?: PaymentMethod | null
  vaultId?: string | null
  custodyId?: string | null
  overrideCredit?: boolean
  bankReference?: string | null   // Ù…Ø±Ø¬Ø¹ Ø§Ù„ØªØ­ÙˆÙŠÙ„ Ø§Ù„Ø¨Ù†ÙƒÙŠ/Ø¥Ù†Ø³ØªØ§Ø¨Ø§ÙŠ
  checkNumber?: string | null     // Ø±Ù‚Ù… Ø§Ù„Ø´ÙŠÙƒ
  checkDate?: string | null       // ØªØ§Ø±ÙŠØ® Ø§Ø³ØªØ­Ù‚Ø§Ù‚ Ø§Ù„Ø´ÙŠÙƒ (YYYY-MM-DD)
  proofUrl?: string | null        // Ø±Ø§Ø¨Ø· Ø¥Ø«Ø¨Ø§Øª Ø§Ù„Ø¯ÙØ¹ (ØµÙˆØ±Ø©/PDF)
}) {
  const userId = await getAuthUserId()
  // Ù†ÙØ­Ø¯Ù‘Ø« proof_url ÙÙŠ Ø¥ÙŠØµØ§Ù„ Ø§Ù„Ø¯ÙØ¹ Ø§Ù„Ù…ÙÙ†Ø´Ø£ ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹ Ø¨Ø¹Ø¯ Ø§Ù„ØªØ³Ù„ÙŠÙ…
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

  // Ø¥Ø°Ø§ ÙƒØ§Ù† Ù‡Ù†Ø§Ùƒ Ø¥Ø«Ø¨Ø§Øª Ø¯ÙØ¹ØŒ Ù†ÙØ­Ø¯Ù‘Ø« Ø§Ù„Ø¥ÙŠØµØ§Ù„ Ø§Ù„Ù…ÙÙ†Ø´Ø£ ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹
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
 * Ø¥Ù„ØºØ§Ø¡ Ø£Ù…Ø± Ø§Ù„Ø¨ÙŠØ¹ â†’ Ø¥Ù„ØºØ§Ø¡ Ø­Ø¬Ø² Ø§Ù„Ù…Ø®Ø²ÙˆÙ†
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
// Smart Delivery RPCs â€” Ø¯ÙˆØ§Ù„ Ø§Ù„ØªØ³Ù„ÙŠÙ… Ø§Ù„Ø°ÙƒÙŠ (04b_delivery_rpcs)
// ============================================================

/** Ù†ØªÙŠØ¬Ø© ÙØ­Øµ Ø§Ù„Ø§Ø¦ØªÙ…Ø§Ù† */
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

/** ÙØ­Øµ Ø§Ø¦ØªÙ…Ø§Ù† Ø§Ù„Ø¹Ù…ÙŠÙ„ Ù‚Ø¨Ù„ Ø§Ù„ØªØ³Ù„ÙŠÙ… */
export async function checkCustomerCredit(customerId: string, amount: number): Promise<CustomerCreditInfo> {
  const { data, error } = await supabase.rpc('check_customer_credit', {
    p_customer_id: customerId,
    p_amount: amount,
  })
  if (error) throw error
  return data as CustomerCreditInfo
}

/** Ù†ØªÙŠØ¬Ø© Ø®ÙŠØ§Ø±Ø§Øª Ø§Ù„Ø¯ÙØ¹ */
export interface UserPaymentOptions {
  has_custody: boolean
  custody_id: string | null
  custody_balance: number
  custody_max: number
  can_manage_vaults: boolean
  available_vaults: Array<{ id: string; name: string; type: string; balance: number }>
  cash_destination: 'custody' | 'vault' | null
}

/** Ø®ÙŠØ§Ø±Ø§Øª Ø§Ù„Ø¯ÙØ¹ Ø§Ù„Ù…ØªØ§Ø­Ø© Ù„Ù„Ù…Ø³ØªØ®Ø¯Ù… Ø§Ù„Ø­Ø§Ù„ÙŠ */
export async function getUserPaymentOptions(branchId?: string | null): Promise<UserPaymentOptions> {
  const userId = await getAuthUserId()
  const { data, error } = await supabase.rpc('get_user_payment_options', {
    p_user_id: userId,
    p_branch_id: branchId || null,
  })
  if (error) throw error
  return data as UserPaymentOptions
}

/** ØªØ£ÙƒÙŠØ¯ Ø§Ù„Ø·Ù„Ø¨ Ù…Ø¹ ØªØ­Ø¯ÙŠØ¯ Ø§Ù„Ù…Ø®Ø²Ù† (ÙŠÙØ­Ø¯ÙŽÙ‘Ø¯ Ø¹Ù†Ø¯ Ø§Ù„ØªØ£ÙƒÙŠØ¯ Ù„Ø§ ÙÙŠ Ø§Ù„Ù…Ø³ÙˆØ¯Ø©) */
export async function confirmSalesOrderWithWarehouse(orderId: string, warehouseId: string) {
  // Ø£ÙˆÙ„Ø§Ù‹: ØªØ­Ø¯ÙŠØ« warehouse_id Ø¹Ù„Ù‰ Ø§Ù„Ø·Ù„Ø¨
  const { error: updError } = await supabase
    .from('sales_orders')
    .update({ warehouse_id: warehouseId })
    .eq('id', orderId)
    .eq('status', 'draft')
  if (updError) throw updError
  // Ø«Ø§Ù†ÙŠØ§Ù‹: ØªØ£ÙƒÙŠØ¯ Ø§Ù„Ø·Ù„Ø¨ (Ø­Ø¬Ø² Ø§Ù„Ù…Ø®Ø²ÙˆÙ† Ø°Ø±ÙŠØ§Ù‹ ÙÙŠ Ø§Ù„Ù€ backend)
  await confirmSalesOrder(orderId)
}


// ============================================================
// Sales Returns â€” Ø§Ù„Ù…Ø±ØªØ¬Ø¹Ø§Øª
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
 * Ø¬Ù„Ø¨ Ù‚Ø§Ø¦Ù…Ø© Ø§Ù„Ù…Ø±ØªØ¬Ø¹Ø§Øª
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
 * Ø¬Ù„Ø¨ Ù…Ø±ØªØ¬Ø¹ ÙˆØ§Ø­Ø¯ Ø¨Ø§Ù„ØªÙØ§ØµÙŠÙ„
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
 * Ø¥Ù†Ø´Ø§Ø¡ Ù…Ø±ØªØ¬Ø¹ (Ù…Ø³ÙˆØ¯Ø©) + Ø¨Ù†ÙˆØ¯Ù‡
 */
export async function createSalesReturn(
  input: SalesReturnInput,
  items: SalesReturnItemInput[]
) {
  const userId = await getAuthUserId()

  // Ø¥Ù†Ø´Ø§Ø¡ Ø§Ù„Ø±Ø£Ø³ÙŠØ©
  const { data: ret, error } = await supabase
    .from('sales_returns')
    .insert({
      ...input,
      created_by: userId,
      return_number: '', // Trigger ÙŠÙˆÙ„Ù‘Ø¯Ù‡
    })
    .select()
    .single()
  if (error) throw error

  // Ø¥Ù†Ø´Ø§Ø¡ Ø§Ù„Ø¨Ù†ÙˆØ¯
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

  // Ø­Ø³Ø§Ø¨ Ø§Ù„Ø¥Ø¬Ù…Ø§Ù„ÙŠ
  const total = items.reduce((s, i) => s + (i.line_total || 0), 0)
  await supabase.from('sales_returns').update({ total_amount: total }).eq('id', ret.id)

  return ret as SalesReturn
}

/**
 * ØªØ£ÙƒÙŠØ¯ Ø§Ù„Ù…Ø±ØªØ¬Ø¹ â†’ Ø¥Ø¹Ø§Ø¯Ø© Ø§Ù„Ù…Ø®Ø²ÙˆÙ† + Ù‚ÙŠØ¯ Ø¹ÙƒØ³ÙŠ
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
// Payment Allocation â€” Ø§Ù„ØªÙˆØ²ÙŠØ¹ Ø§Ù„Ø°ÙƒÙŠ
// ============================================================

/**
 * ØªÙˆØ²ÙŠØ¹ Ø¯ÙØ¹Ø© Ø¹Ù„Ù‰ ÙÙˆØ§ØªÙŠØ± Ø§Ù„Ø¹Ù…ÙŠÙ„ (FIFO)
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
// Sales Stats â€” Ø¥Ø­ØµØ§Ø¦ÙŠØ§Øª Ø§Ù„Ù…Ø¨ÙŠØ¹Ø§Øª
// ============================================================

/**
 * Ø¬Ù„Ø¨ Ø¥Ø­ØµØ§Ø¦ÙŠØ§Øª Ø¹Ø¯Ø¯ Ø§Ù„Ø·Ù„Ø¨Ø§Øª Ø­Ø³Ø¨ Ø§Ù„Ø­Ø§Ù„Ø©
 */
export async function getSalesStats() {
  // Ø§Ø³ØªØ¹Ù„Ø§Ù… ÙˆØ§Ø­Ø¯ Ù…ÙØ¬Ù…ÙŽÙ‘Ø¹ ÙÙŠ PostgreSQL Ø¨Ø¯Ù„Ø§Ù‹ Ù…Ù† 6 Ø§Ø³ØªØ¹Ù„Ø§Ù…Ø§Øª Ù…Ù†ÙØµÙ„Ø©
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
 * Ø¬Ù„Ø¨ Ø§Ù„Ø¨Ù†ÙˆØ¯ Ø§Ù„Ù‚Ø§Ø¨Ù„Ø© Ù„Ù„Ø¥Ø±Ø¬Ø§Ø¹ Ù…Ù† ÙØ§ØªÙˆØ±Ø©
 * (Ø§Ù„Ù…Ø³Ù„Ù‘Ù… - Ø§Ù„Ù…Ø±ØªØ¬Ø¹ > 0)
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

  // ØªØµÙÙŠØ©: ÙÙ‚Ø· Ø§Ù„Ø¨Ù†ÙˆØ¯ Ø§Ù„ØªÙŠ Ù„Ø§ ØªØ²Ø§Ù„ Ù‚Ø§Ø¨Ù„Ø© Ù„Ù„Ø¥Ø±Ø¬Ø§Ø¹
  return (data as SalesOrderItem[]).filter(
    item => (item.delivered_quantity - item.returned_quantity) > 0
  )
}

