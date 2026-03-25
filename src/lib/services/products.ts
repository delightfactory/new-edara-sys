import { supabase } from '@/lib/supabase/client'
import type {
  Product, ProductInput, ProductUnit, ProductUnitInput,
  ProductCategory, Brand, Unit,
  ProductBundle, ProductBundleItem
} from '@/lib/types/master-data'

// ============================================================
// Products — المنتجات
// ============================================================

/**
 * جلب المنتجات مع التصفية والترقيم
 */
export async function getProducts(params?: {
  search?: string
  categoryId?: string
  brandId?: string
  isActive?: boolean
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 25
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('products')
    .select(`
      *,
      category:product_categories(id, name),
      brand:brands(id, name),
      base_unit:units!products_base_unit_id_fkey(id, name, symbol)
    `, { count: 'estimated' })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.search) {
    query = query.or(`name.ilike.%${params.search}%,sku.ilike.%${params.search}%,barcode.ilike.%${params.search}%`)
  }
  if (params?.categoryId) {
    query = query.eq('category_id', params.categoryId)
  }
  if (params?.brandId) {
    query = query.eq('brand_id', params.brandId)
  }
  if (params?.isActive !== undefined) {
    query = query.eq('is_active', params.isActive)
  }

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as Product[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

/**
 * جلب منتج واحد مع وحداته
 */
export async function getProduct(id: string) {
  const { data, error } = await supabase
    .from('products')
    .select(`
      *,
      category:product_categories(id, name),
      brand:brands(id, name),
      base_unit:units!products_base_unit_id_fkey(id, name, symbol),
      product_units(*, unit:units(id, name, symbol))
    `)
    .eq('id', id)
    .single()
  if (error) throw error
  return data as Product
}

/**
 * إنشاء منتج
 */
export async function createProduct(input: ProductInput) {
  const { data, error } = await supabase
    .from('products')
    .insert(input)
    .select()
    .single()
  if (error) throw error
  return data as Product
}

/**
 * تحديث منتج
 */
export async function updateProduct(id: string, input: Partial<ProductInput>) {
  const { data, error } = await supabase
    .from('products')
    .update(input)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as Product
}

/**
 * تبديل حالة المنتج (تفعيل/تعطيل)
 */
export async function toggleProductActive(id: string, isActive: boolean) {
  const { error } = await supabase
    .from('products')
    .update({ is_active: isActive })
    .eq('id', id)
  if (error) throw error
}

// ============================================================
// Product Units — وحدات المنتج
// ============================================================

/**
 * جلب وحدات منتج معين
 */
export async function getProductUnits(productId: string) {
  const { data, error } = await supabase
    .from('product_units')
    .select('*, unit:units(id, name, symbol)')
    .eq('product_id', productId)
  if (error) throw error
  return data as ProductUnit[]
}

/**
 * حفظ وحدات المنتج (حذف القديمة + إضافة الجديدة)
 */
export async function saveProductUnits(productId: string, units: ProductUnitInput[]) {
  const userId = (await supabase.auth.getUser()).data.user?.id
  const { error } = await supabase.rpc('save_product_units_atomic', {
    p_product_id: productId,
    p_units: units,
    p_user_id: userId,
  })
  if (error) throw error
}

// ============================================================
// Categories — التصنيفات
// ============================================================

/**
 * جلب كل التصنيفات (مسطحة — يتم بناء الشجرة في الواجهة)
 */
export async function getCategories() {
  const { data, error } = await supabase
    .from('product_categories')
    .select('*')
    .order('sort_order')
    .order('name')
  if (error) throw error
  return data as ProductCategory[]
}

/**
 * بناء شجرة التصنيفات من القائمة المسطحة
 */
export function buildCategoryTree(categories: ProductCategory[]): ProductCategory[] {
  const map = new Map<string, ProductCategory>()
  const roots: ProductCategory[] = []

  for (const cat of categories) {
    map.set(cat.id, { ...cat, children: [] })
  }

  for (const cat of categories) {
    const node = map.get(cat.id)!
    if (cat.parent_id && map.has(cat.parent_id)) {
      map.get(cat.parent_id)!.children!.push(node)
    } else {
      roots.push(node)
    }
  }

  return roots
}

/**
 * إنشاء تصنيف
 */
export async function createCategory(input: { name: string; parent_id?: string | null; icon?: string; sort_order?: number }) {
  const { data, error } = await supabase
    .from('product_categories')
    .insert(input)
    .select()
    .single()
  if (error) throw error
  return data as ProductCategory
}

/**
 * تحديث تصنيف
 */
export async function updateCategory(id: string, input: { name?: string; parent_id?: string | null; icon?: string; sort_order?: number; is_active?: boolean }) {
  const { data, error } = await supabase
    .from('product_categories')
    .update(input)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as ProductCategory
}

// ============================================================
// Brands — العلامات التجارية
// ============================================================

export async function getBrands() {
  const { data, error } = await supabase
    .from('brands')
    .select('*')
    .order('name')
  if (error) throw error
  return data as Brand[]
}

export async function createBrand(input: { name: string; logo_url?: string }) {
  const { data, error } = await supabase
    .from('brands')
    .insert(input)
    .select()
    .single()
  if (error) throw error
  return data as Brand
}

export async function updateBrand(id: string, input: { name?: string; logo_url?: string; is_active?: boolean }) {
  const { data, error } = await supabase
    .from('brands')
    .update(input)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as Brand
}

// ============================================================
// Units — وحدات القياس
// ============================================================

export async function getUnits() {
  const { data, error } = await supabase
    .from('units')
    .select('*')
    .order('name')
  if (error) throw error
  return data as Unit[]
}

// ============================================================
// Bundles — الباقات
// ============================================================

export async function getBundles() {
  const { data, error } = await supabase
    .from('product_bundles')
    .select(`
      *,
      items:product_bundle_items(
        *,
        product:products(id, name, sku),
        unit:units(id, name, symbol)
      )
    `)
    .order('created_at', { ascending: false })
    .limit(100)
  if (error) throw error
  return data as ProductBundle[]
}

export async function createBundle(
  bundle: { name: string; sku?: string; price: number },
  items: { product_id: string; unit_id: string; quantity: number }[]
) {
  const { data, error } = await supabase
    .from('product_bundles')
    .insert(bundle)
    .select()
    .single()
  if (error) throw error

  if (items.length > 0) {
    const { error: itemErr } = await supabase
      .from('product_bundle_items')
      .insert(items.map(i => ({ ...i, bundle_id: data.id })))
    if (itemErr) throw itemErr
  }

  return data as ProductBundle
}

export async function updateBundle(
  id: string,
  bundle: { name?: string; sku?: string; price?: number; is_active?: boolean },
  items?: { product_id: string; unit_id: string; quantity: number }[]
) {
  const userId = (await supabase.auth.getUser()).data.user?.id
  const { error } = await supabase.rpc('update_bundle_atomic', {
    p_bundle_id: id,
    p_name: bundle.name ?? null,
    p_sku: bundle.sku ?? null,
    p_price: bundle.price ?? null,
    p_is_active: bundle.is_active ?? null,
    p_items: items ?? null,
    p_user_id: userId,
  })
  if (error) throw error
}
