import { supabase } from '@/lib/supabase/client'
import type { PriceList, PriceListItem, PriceListAssignment } from '@/lib/types/master-data'

// ============================================================
// Price Lists — قوائم الأسعار
// ============================================================

/**
 * جلب كل قوائم الأسعار
 */
export async function getPriceLists() {
  const { data, error } = await supabase
    .from('price_lists')
    .select('*')
    .order('is_default', { ascending: false })
    .order('name')
  if (error) throw error
  return data as PriceList[]
}

/**
 * جلب قائمة أسعار واحدة
 */
export async function getPriceList(id: string) {
  const { data, error } = await supabase
    .from('price_lists')
    .select('*')
    .eq('id', id)
    .single()
  if (error) throw error
  return data as PriceList
}

/**
 * إنشاء قائمة أسعار
 */
export async function createPriceList(input: {
  name: string
  description?: string
  is_active?: boolean
  valid_from?: string | null
  valid_to?: string | null
}) {
  const { data, error } = await supabase
    .from('price_lists')
    .insert(input)
    .select()
    .single()
  if (error) throw error
  return data as PriceList
}

/**
 * تحديث قائمة أسعار
 */
export async function updatePriceList(id: string, input: Partial<{
  name: string
  description: string
  is_active: boolean
  is_default: boolean
  valid_from: string | null
  valid_to: string | null
}>) {
  const { data, error } = await supabase
    .from('price_lists')
    .update(input)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as PriceList
}

// ============================================================
// Price List Items — بنود قائمة الأسعار
// ============================================================

/**
 * جلب بنود قائمة أسعار مع أسماء المنتجات والوحدات
 */
export async function getPriceListItems(priceListId: string, params?: {
  search?: string
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 50
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('price_list_items')
    .select(`
      *,
      product:products(id, name, sku),
      unit:units(id, name, symbol)
    `, { count: 'estimated' })
    .eq('price_list_id', priceListId)
    .order('created_at', { ascending: false })
    .range(from, to)

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as PriceListItem[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

/**
 * حفظ بنود قائمة أسعار (ذري — delete + insert في transaction واحد)
 */
export async function savePriceListItems(
  priceListId: string,
  items: { product_id: string; unit_id: string; price: number; min_qty?: number; max_qty?: number | null }[]
) {
  const { error } = await supabase.rpc('save_price_list_items_atomic', {
    p_price_list_id: priceListId,
    p_items: items,
  })
  if (error) throw error
}

/**
 * إضافة بند سعر واحد
 */
export async function addPriceListItem(priceListId: string, item: {
  product_id: string
  unit_id: string
  price: number
  min_qty?: number
  max_qty?: number | null
}) {
  const { data, error } = await supabase
    .from('price_list_items')
    .insert({ ...item, price_list_id: priceListId })
    .select()
    .single()
  if (error) throw error
  return data as PriceListItem
}

/**
 * حذف بند سعر
 */
export async function deletePriceListItem(id: string) {
  const { error } = await supabase
    .from('price_list_items')
    .delete()
    .eq('id', id)
  if (error) throw error
}

// ============================================================
// Price List Assignments — ربط قوائم الأسعار
// ============================================================

/**
 * جلب ربط قائمة أسعار (عملاء / مدن / محافظات)
 */
export async function getPriceListAssignments(priceListId: string) {
  const { data, error } = await supabase
    .from('price_list_assignments')
    .select('*')
    .eq('price_list_id', priceListId)
    .order('entity_type')
  if (error) throw error
  return data as PriceListAssignment[]
}

/**
 * ربط قائمة أسعار بكيان (عميل / مدينة / محافظة)
 */
export async function assignPriceList(priceListId: string, entityType: 'customer' | 'city' | 'governorate', entityId: string) {
  const { data, error } = await supabase
    .from('price_list_assignments')
    .insert({ price_list_id: priceListId, entity_type: entityType, entity_id: entityId })
    .select()
    .single()
  if (error) throw error
  return data as PriceListAssignment
}

/**
 * إلغاء ربط
 */
export async function unassignPriceList(id: string) {
  const { error } = await supabase
    .from('price_list_assignments')
    .delete()
    .eq('id', id)
  if (error) throw error
}

// ============================================================
// Pricing Function — دالة التسعير (RPC)
// ============================================================

/**
 * جلب السعر بالأولوية عبر دالة SQL
 * الأولوية: قائمة العميل → مدينة → محافظة → افتراضية → سعر المنتج
 */
export async function getProductPrice(
  productId: string,
  customerId: string,
  unitId: string,
  qty: number = 1
): Promise<number> {
  const { data, error } = await supabase.rpc('get_product_price', {
    p_product_id: productId,
    p_customer_id: customerId,
    p_unit_id: unitId,
    p_qty: qty,
  })
  if (error) throw error
  return data as number
}
