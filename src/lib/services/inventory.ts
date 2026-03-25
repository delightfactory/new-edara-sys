import { supabase } from '@/lib/supabase/client'
import type {
  Warehouse, WarehouseManager, Stock, StockBatch, StockMovement,
  StockTransfer, StockTransferItem,
  StockAdjustment, StockAdjustmentItem,
  TransferStatus
} from '@/lib/types/master-data'

// ============================================================
// Warehouses — المخازن
// ============================================================

/**
 * جلب كل المخازن مع الفرع والمدير
 */
export async function getWarehouses(params?: { isActive?: boolean }) {
  let query = supabase
    .from('warehouses')
    .select(`
      *,
      branch:branches(id, name),
      manager:profiles!warehouses_manager_id_fkey(id, full_name)
    `)
    .order('name')

  if (params?.isActive !== undefined) {
    query = query.eq('is_active', params.isActive)
  }

  const { data, error } = await query
  if (error) throw error
  return data as Warehouse[]
}

/**
 * جلب مخزن واحد
 */
export async function getWarehouse(id: string) {
  const { data, error } = await supabase
    .from('warehouses')
    .select(`
      *,
      branch:branches(id, name),
      manager:profiles!warehouses_manager_id_fkey(id, full_name)
    `)
    .eq('id', id)
    .single()
  if (error) throw error
  return data as Warehouse
}

/**
 * إنشاء مخزن
 */
export async function createWarehouse(input: {
  name: string
  type: 'fixed' | 'vehicle' | 'retail'
  branch_id?: string | null
  address?: string | null
  manager_id?: string | null
}) {
  const { data, error } = await supabase
    .from('warehouses')
    .insert(input)
    .select()
    .single()
  if (error) throw error
  return data as Warehouse
}

/**
 * تحديث مخزن
 */
export async function updateWarehouse(id: string, input: Partial<{
  name: string
  type: 'fixed' | 'vehicle' | 'retail'
  branch_id: string | null
  address: string | null
  manager_id: string | null
  is_active: boolean
}>) {
  const { data, error } = await supabase
    .from('warehouses')
    .update(input)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as Warehouse
}

// ============================================================
// Warehouse Managers — مديرو المخازن
// ============================================================

export async function getWarehouseManagers(warehouseId: string) {
  const { data, error } = await supabase
    .from('warehouse_managers')
    .select('*, profile:profiles(id, full_name)')
    .eq('warehouse_id', warehouseId)
    .order('is_primary', { ascending: false })
  if (error) throw error
  return data as WarehouseManager[]
}

export async function addWarehouseManager(warehouseId: string, profileId: string, options?: {
  is_primary?: boolean
  can_approve_receipts?: boolean
}) {
  const { data, error } = await supabase
    .from('warehouse_managers')
    .insert({
      warehouse_id: warehouseId,
      profile_id: profileId,
      is_primary: options?.is_primary || false,
      can_approve_receipts: options?.can_approve_receipts || false,
    })
    .select()
    .single()
  if (error) throw error
  return data as WarehouseManager
}

export async function removeWarehouseManager(id: string) {
  const { error } = await supabase
    .from('warehouse_managers')
    .delete()
    .eq('id', id)
  if (error) throw error
}

/**
 * جلب المخازن المرتبطة بالمستخدم الحالي
 * (عبر warehouse_managers أو warehouses.manager_id)
 */
export async function getMyWarehouses(): Promise<Warehouse[]> {
  const userId = (await supabase.auth.getUser()).data.user?.id
  if (!userId) return []

  // 1. المخازن عبر warehouse_managers
  const { data: assignments } = await supabase
    .from('warehouse_managers')
    .select('warehouse_id')
    .eq('profile_id', userId)

  const assignedIds = (assignments || []).map(a => a.warehouse_id)

  // 2. المخازن عبر warehouses.manager_id
  const { data: ownedWhs } = await supabase
    .from('warehouses')
    .select('id')
    .eq('manager_id', userId)

  const ownedIds = (ownedWhs || []).map(w => w.id)

  // 3. جمع كل المعرفات الفريدة
  const allIds = [...new Set([...assignedIds, ...ownedIds])]
  if (!allIds.length) return []

  // 4. جلب البيانات الكاملة
  const { data, error } = await supabase
    .from('warehouses')
    .select('*, branch:branches(id, name), manager:profiles!warehouses_manager_id_fkey(id, full_name)')
    .in('id', allIds)
    .eq('is_active', true)
    .order('name')

  if (error) throw error
  return data as Warehouse[]
}

// ============================================================
// Stock — أرصدة المخزون
// ============================================================

/**
 * جلب أرصدة المخزون مع فلاتر
 */
export async function getStock(params?: {
  warehouseId?: string
  productId?: string
  lowStockOnly?: boolean
  search?: string
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 50
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  // فلتر المخزون المنخفض — يستخدم RPC على مستوى DB لتجنب كسر الـ Pagination
  if (params?.lowStockOnly) {
    const { data, error } = await supabase.rpc('get_low_stock', {
      p_warehouse_id: params?.warehouseId || null,
      p_offset: from,
      p_limit: pageSize,
    })
    if (error) throw error
    const rows = (data || []) as any[]
    const totalCount = rows.length > 0 ? Number(rows[0].total_count) : 0
    // تحويل الهيكل ليتوافق مع Stock type
    const results = rows.map((r: any) => ({
      id: r.id,
      warehouse_id: r.warehouse_id,
      product_id: r.product_id,
      quantity: r.quantity,
      reserved_quantity: r.reserved_quantity,
      available_quantity: r.available_quantity,
      wac: r.wac,
      total_cost_value: r.total_cost_value,
      created_at: '',
      updated_at: '',
      warehouse: { id: r.warehouse_id, name: r.warehouse_name, type: 'main' as const },
      product: {
        id: r.product_id, name: r.product_name, sku: r.product_sku,
        min_stock_level: r.min_stock_level,
        base_unit: { name: r.unit_name, symbol: r.unit_symbol },
      },
    })) as unknown as Stock[]
    return {
      data: results,
      count: totalCount,
      page,
      pageSize,
      totalPages: Math.ceil(totalCount / pageSize),
    }
  }

  let query = supabase
    .from('stock')
    .select(`
      *,
      warehouse:warehouses(id, name, type),
      product:products(id, name, sku, min_stock_level, base_unit:units!products_base_unit_id_fkey(id, name, symbol))
    `, { count: 'exact' })
    .order('updated_at', { ascending: false })
    .range(from, to)

  if (params?.warehouseId) {
    query = query.eq('warehouse_id', params.warehouseId)
  }
  if (params?.productId) {
    query = query.eq('product_id', params.productId)
  }

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as Stock[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

/**
 * جلب دفعات المخزون (batches)
 */
export async function getStockBatches(stockId: string) {
  const { data, error } = await supabase
    .from('stock_batches')
    .select('*')
    .eq('stock_id', stockId)
    .order('expiry_date', { ascending: true, nullsFirst: false })
  if (error) throw error
  return data as StockBatch[]
}

// ============================================================
// Stock Movements — حركات المخزون (قراءة فقط — INSERT-ONLY)
// ============================================================

/**
 * جلب حركات المخزون مع فلاتر
 */
export async function getStockMovements(params?: {
  warehouseId?: string
  productId?: string
  type?: string
  referenceType?: string
  referenceId?: string
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 50
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('stock_movements')
    .select(`
      *,
      warehouse:warehouses(id, name),
      product:products(id, name, sku),
      created_by_profile:profiles!stock_movements_created_by_fkey(id, full_name)
    `, { count: 'exact' })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.warehouseId) {
    query = query.eq('warehouse_id', params.warehouseId)
  }
  if (params?.productId) {
    query = query.eq('product_id', params.productId)
  }
  if (params?.type) {
    query = query.eq('type', params.type)
  }
  if (params?.referenceType) {
    query = query.eq('reference_type', params.referenceType)
  }
  if (params?.referenceId) {
    query = query.eq('reference_id', params.referenceId)
  }

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as StockMovement[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

// ============================================================
// Stock Transfers — التحويلات بين المخازن (ذري)
// ============================================================

/**
 * جلب الكمية المتاحة لمنتج في مخزن (بعد خصم المحجوز)
 */
export async function getAvailableStock(warehouseId: string, productId: string): Promise<number> {
  const { data, error } = await supabase.rpc('get_available_stock', {
    p_warehouse_id: warehouseId,
    p_product_id: productId,
  })
  if (error) throw error
  return data as number
}

/**
 * جلب التحويلات مع فلاتر
 */
export async function getTransfers(params?: {
  status?: TransferStatus
  warehouseId?: string
  direction?: 'push' | 'pull'
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 25
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('stock_transfers')
    .select(`
      *,
      from_warehouse:warehouses!stock_transfers_from_warehouse_id_fkey(id, name),
      to_warehouse:warehouses!stock_transfers_to_warehouse_id_fkey(id, name),
      requested_by_profile:profiles!stock_transfers_requested_by_fkey(id, full_name),
      items:stock_transfer_items(
        *,
        product:products(id, name, sku),
        unit:units(id, name, symbol)
      )
    `, { count: 'exact' })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.status) {
    query = query.eq('status', params.status)
  }
  if (params?.warehouseId) {
    query = query.or(`from_warehouse_id.eq.${params.warehouseId},to_warehouse_id.eq.${params.warehouseId}`)
  }
  if (params?.direction) {
    query = query.eq('direction', params.direction)
  }

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as StockTransfer[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

/**
 * جلب تحويل واحد
 */
export async function getTransfer(id: string) {
  const { data, error } = await supabase
    .from('stock_transfers')
    .select(`
      *,
      from_warehouse:warehouses!stock_transfers_from_warehouse_id_fkey(id, name),
      to_warehouse:warehouses!stock_transfers_to_warehouse_id_fkey(id, name),
      requested_by_profile:profiles!stock_transfers_requested_by_fkey(id, full_name),
      items:stock_transfer_items(
        *,
        product:products(id, name, sku),
        unit:units(id, name, symbol)
      )
    `)
    .eq('id', id)
    .single()
  if (error) throw error
  return data as StockTransfer
}

/**
 * إنشاء تحويل مع حجز (ذري)
 * Push: حجز فوري للكميات في المخزن المُرسل
 * Pull: لا حجز مسبق — ينتظر موافقة المُرسل
 */
export async function createTransfer(
  transfer: {
    from_warehouse_id: string
    to_warehouse_id: string
    direction: 'push' | 'pull'
    notes?: string
  },
  items: { product_id: string; unit_id: string; quantity: number }[]
) {
  const userId = (await supabase.auth.getUser()).data.user?.id
  if (!userId) throw new Error('يجب تسجيل الدخول')

  const { data, error } = await supabase.rpc('create_transfer_with_reservation', {
    p_from_warehouse_id: transfer.from_warehouse_id,
    p_to_warehouse_id: transfer.to_warehouse_id,
    p_direction: transfer.direction,
    p_notes: transfer.notes || '',
    p_user_id: userId,
    p_items: items,
  })
  if (error) throw error
  return data as string // returns transfer_id
}

/**
 * تأكيد شحن (Push) — خصم المخزون + إلغاء الحجز + تسجيل حركات
 */
export async function shipTransfer(transferId: string) {
  const userId = (await supabase.auth.getUser()).data.user?.id
  if (!userId) throw new Error('يجب تسجيل الدخول')

  const { error } = await supabase.rpc('confirm_transfer_shipment', {
    p_transfer_id: transferId,
    p_user_id: userId,
  })
  if (error) throw error
}

/**
 * موافقة وشحن (Pull) — فحص التوفر + خصم فوري + تسجيل حركات
 */
export async function approveAndShipTransfer(transferId: string) {
  const userId = (await supabase.auth.getUser()).data.user?.id
  if (!userId) throw new Error('يجب تسجيل الدخول')

  const { error } = await supabase.rpc('approve_and_ship_transfer', {
    p_transfer_id: transferId,
    p_user_id: userId,
  })
  if (error) throw error
}

/**
 * تأكيد الاستلام — إضافة المخزون بالـ WAC + تسجيل حركات
 */
export async function receiveTransfer(transferId: string) {
  const userId = (await supabase.auth.getUser()).data.user?.id
  if (!userId) throw new Error('يجب تسجيل الدخول')

  const { error } = await supabase.rpc('confirm_transfer_receipt', {
    p_transfer_id: transferId,
    p_user_id: userId,
  })
  if (error) throw error
}

/**
 * إلغاء التحويل — إلغاء الحجز إن وُجد
 */
export async function cancelTransfer(transferId: string) {
  const userId = (await supabase.auth.getUser()).data.user?.id
  if (!userId) throw new Error('يجب تسجيل الدخول')

  const { error } = await supabase.rpc('cancel_transfer', {
    p_transfer_id: transferId,
    p_user_id: userId,
  })
  if (error) throw error
}

// ============================================================
// Stock Adjustments — تسويات المخزون (ذري)
// ============================================================

/**
 * جلب التسويات مع فلاتر
 */
export async function getAdjustments(params?: {
  warehouseId?: string
  status?: string
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 25
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('stock_adjustments')
    .select(`
      *,
      warehouse:warehouses(id, name),
      created_by_profile:profiles!stock_adjustments_created_by_fkey(id, full_name),
      items:stock_adjustment_items(
        *,
        product:products(id, name, sku)
      )
    `, { count: 'exact' })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.warehouseId) {
    query = query.eq('warehouse_id', params.warehouseId)
  }
  if (params?.status) {
    query = query.eq('status', params.status)
  }

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as StockAdjustment[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

/**
 * جلب تسوية واحدة
 */
export async function getAdjustment(id: string) {
  const { data, error } = await supabase
    .from('stock_adjustments')
    .select(`
      *,
      warehouse:warehouses(id, name),
      created_by_profile:profiles!stock_adjustments_created_by_fkey(id, full_name),
      items:stock_adjustment_items(
        *,
        product:products(id, name, sku)
      )
    `)
    .eq('id', id)
    .single()
  if (error) throw error
  return data as StockAdjustment
}

/**
 * إنشاء تسوية ذرية — system_qty يُحسب لحظياً من المخزون
 */
export async function createAdjustment(
  adjustment: {
    warehouse_id: string
    type: 'add' | 'remove' | 'count'
    reason?: string
  },
  items: { product_id: string; actual_qty: number; unit_cost?: number; notes?: string }[]
) {
  const userId = (await supabase.auth.getUser()).data.user?.id
  if (!userId) throw new Error('يجب تسجيل الدخول')

  const { data, error } = await supabase.rpc('create_adjustment_with_items', {
    p_warehouse_id: adjustment.warehouse_id,
    p_type: adjustment.type,
    p_reason: adjustment.reason || '',
    p_user_id: userId,
    p_items: items,
  })
  if (error) throw error
  return data as string // adjustment_id
}

/**
 * اعتماد التسوية — تطبيق الفروق على المخزون (ذري)
 */
export async function approveAdjustment(adjustmentId: string) {
  const userId = (await supabase.auth.getUser()).data.user?.id
  if (!userId) throw new Error('يجب تسجيل الدخول')

  const { error } = await supabase.rpc('confirm_adjustment', {
    p_adjustment_id: adjustmentId,
    p_user_id: userId,
  })
  if (error) throw error
}

/**
 * رفض التسوية — بدون تطبيق + سبب الرفض
 */
export async function rejectAdjustment(adjustmentId: string, reason?: string) {
  const userId = (await supabase.auth.getUser()).data.user?.id
  if (!userId) throw new Error('يجب تسجيل الدخول')

  const { error } = await supabase.rpc('reject_adjustment', {
    p_adjustment_id: adjustmentId,
    p_user_id: userId,
    p_reason: reason || null,
  })
  if (error) throw error
}
