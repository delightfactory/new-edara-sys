import { supabase } from '@/lib/supabase/client'
import { getAuthUserId } from '@/lib/services/_get-user-id'
import type {
  Customer, CustomerInput, CustomerBranch, CustomerContact, CustomerCreditHistory
} from '@/lib/types/master-data'

function buildCustomerPatch(input: Partial<CustomerInput>) {
  const patch: Record<string, unknown> = {}

  const setText = (key: string, value: string | null | undefined, nullable = true) => {
    if (value === undefined) return
    patch[key] = value === '' ? (nullable ? null : '') : value
  }

  const setNumber = (key: string, value: number | null | undefined) => {
    if (value === undefined) return
    patch[key] = value
  }

  const setBoolean = (key: string, value: boolean | undefined) => {
    if (value === undefined) return
    patch[key] = value
  }

  setText('name', input.name, false)
  setText('type', input.type, false)
  setText('governorate_id', input.governorate_id)
  setText('city_id', input.city_id)
  setText('area_id', input.area_id)
  setText('address', input.address)
  setText('phone', input.phone)
  setText('mobile', input.mobile)
  setText('email', input.email)
  setText('tax_number', input.tax_number)
  setText('payment_terms', input.payment_terms, false)
  setNumber('credit_limit', input.credit_limit)
  setNumber('credit_days', input.credit_days)
  setText('price_list_id', input.price_list_id)
  setText('assigned_rep_id', input.assigned_rep_id)
  setBoolean('is_active', input.is_active)
  setText('notes', input.notes)

  return patch
}

// ============================================================
// Customers — العملاء
// ============================================================

/**
 * جلب العملاء مع التصفية والترقيم
 * RLS يتحكم تلقائياً: customers.read = عملاءه فقط، customers.read_all = الكل
 */
export async function getCustomers(params?: {
  search?: string
  type?: string
  governorateId?: string
  cityId?: string
  repId?: string
  isActive?: boolean
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 25
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('customers')
    .select(`
      *,
      governorate:governorates(id, name),
      city:cities(id, name),
      assigned_rep:profiles!customers_assigned_rep_id_fkey(id, full_name)
    `, { count: 'estimated' })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.search) {
    query = query.or(`name.ilike.%${params.search}%,code.ilike.%${params.search}%,phone.ilike.%${params.search}%,mobile.ilike.%${params.search}%`)
  }
  if (params?.type) {
    query = query.eq('type', params.type)
  }
  if (params?.governorateId) {
    query = query.eq('governorate_id', params.governorateId)
  }
  if (params?.cityId) {
    query = query.eq('city_id', params.cityId)
  }
  if (params?.repId) {
    query = query.eq('assigned_rep_id', params.repId)
  }
  if (params?.isActive !== undefined) {
    query = query.eq('is_active', params.isActive)
  }

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as Customer[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

// ============================================================
// searchCustomers — Keyset Pagination (O(log N) ثابت الأداء)
// يستخدم RPC search_customers لأفضل أداء مع البحث
// ============================================================

export interface CustomerSearchPage {
  data: Customer[]
  hasMore: boolean
  nextCursor: string | null    // ISO timestamp
  nextCursorId: string | null  // UUID
}

/**
 * searchCustomers — يستخدم RPC مع Keyset cursor
 * - لا COUNT(*) — أسرع بكثير من OFFSET
 * - أداء O(log N) ثابت بغض النظر عن عمق الصفحة
 * - يدعم البحث النصي الكامل (اسم + كود + هاتف + موبايل)
 */
export async function searchCustomers(params?: {
  search?: string
  type?: string
  governorateId?: string
  cityId?: string
  repId?: string
  isActive?: boolean
  cursor?: string | null      // created_at من آخر عنصر
  cursorId?: string | null    // id من آخر عنصر
  pageSize?: number
}): Promise<CustomerSearchPage> {
  const pageSize = params?.pageSize ?? 30

  const { data, error } = await supabase.rpc('search_customers', {
    p_search:      params?.search      || null,
    p_type:        params?.type        || null,
    p_governorate: params?.governorateId || null,
    p_city:        params?.cityId      || null,
    p_rep_id:      params?.repId       || null,
    p_is_active:   params?.isActive    ?? null,
    p_cursor_ts:   params?.cursor      || null,
    p_cursor_id:   params?.cursorId    || null,
    p_limit:       pageSize,
  })

  if (error) throw error

  const rows = (data || []) as any[]
  const hasMore = rows.length > 0 && rows[rows.length - 1]?.has_more === true
  const lastRow = rows[rows.length - 1]

  // تحويل نتائج RPC إلى نوع Customer المتوافق
  const mapped = rows.map(r => ({
    id: r.id,
    name: r.name,
    code: r.code,
    phone: r.phone,
    mobile: r.mobile,
    type: r.type,
    payment_terms: r.payment_terms,
    credit_limit: r.credit_limit,
    current_balance: r.current_balance,
    is_active: r.is_active,
    assigned_rep_id: r.assigned_rep_id,
    latitude: r.latitude,
    longitude: r.longitude,
    address: r.address,
    created_at: r.created_at,
    governorate: r.governorate_id ? { id: r.governorate_id, name: r.governorate_name } : null,
    city: r.city_id ? { id: r.city_id, name: r.city_name } : null,
    assigned_rep: r.assigned_rep_id ? { id: r.assigned_rep_id, full_name: r.rep_name } : null,
  })) as Customer[]

  return {
    data: mapped,
    hasMore,
    nextCursor: hasMore ? lastRow?.created_at ?? null : null,
    nextCursorId: hasMore ? lastRow?.id ?? null : null,
  }
}

/**
 * جلب عميل واحد مع بياناته الكاملة
 */
export async function getCustomer(id: string) {
  const { data, error } = await supabase
    .from('customers')
    .select(`
      *,
      governorate:governorates(id, name),
      city:cities(id, name),
      area:areas(id, name),
      assigned_rep:profiles!customers_assigned_rep_id_fkey(id, full_name),
      price_list:price_lists(id, name)
    `)
    .eq('id', id)
    .single()
  if (error) throw error
  return data as Customer
}

/**
 * إنشاء عميل — الكود يتولد تلقائياً بالـ Trigger (CUS-00001)
 */
export async function createCustomer(input: CustomerInput) {
  const userId = await getAuthUserId()
  const { data, error } = await supabase
    .from('customers')
    .insert({ ...input, created_by: userId })
    .select()
    .single()
  if (error) throw error
  return data as Customer
}

/**
 * تحديث عميل
 */
export async function updateCustomer(id: string, input: Partial<CustomerInput>) {
  const userId = await getAuthUserId()
  const { opening_balance, ...nonFinancialFields } = input
  const { error } = await supabase.rpc('update_customer_with_opening_balance', {
    p_customer_id: id,
    p_non_financial_patch: buildCustomerPatch(nonFinancialFields),
    p_new_opening_balance: opening_balance ?? null,
    p_reason: null,
    p_user_id: userId,
  })
  if (error) throw error
  return await getCustomer(id)
}

/**
 * تبديل حالة العميل (Soft Delete)
 */
export async function toggleCustomerActive(id: string, isActive: boolean) {
  const { error } = await supabase
    .from('customers')
    .update({ is_active: isActive })
    .eq('id', id)
  if (error) throw error
}

/**
 * تحديث موقع العميل GPS
 */
export async function updateCustomerLocation(id: string, location: {
  latitude: number
  longitude: number
  location_accuracy?: number
}) {
  const { error } = await supabase
    .from('customers')
    .update({
      ...location,
      location_updated_at: new Date().toISOString(),
      location_updated_by: await getAuthUserId(),
    })
    .eq('id', id)
  if (error) throw error
}

// ============================================================
// Customer Branches — فروع العميل
// ============================================================

export async function getCustomerBranches(customerId: string) {
  const { data, error } = await supabase
    .from('customer_branches')
    .select('*')
    .eq('customer_id', customerId)
    .order('is_primary', { ascending: false })
    .order('name')
  if (error) throw error
  return data as CustomerBranch[]
}

export async function saveCustomerBranch(
  customerId: string,
  branch: Omit<Partial<CustomerBranch>, 'id' | 'customer_id' | 'created_at' | 'updated_at'> & { name: string },
  branchId?: string
) {
  if (branchId) {
    const { data, error } = await supabase
      .from('customer_branches')
      .update(branch)
      .eq('id', branchId)
      .select()
      .single()
    if (error) throw error
    return data as CustomerBranch
  } else {
    const { data, error } = await supabase
      .from('customer_branches')
      .insert({ ...branch, customer_id: customerId })
      .select()
      .single()
    if (error) throw error
    return data as CustomerBranch
  }
}

export async function deleteCustomerBranch(id: string) {
  const { error } = await supabase
    .from('customer_branches')
    .delete()
    .eq('id', id)
  if (error) throw error
}

// ============================================================
// Customer Contacts — جهات اتصال العميل
// ============================================================

export async function getCustomerContacts(customerId: string) {
  const { data, error } = await supabase
    .from('customer_contacts')
    .select('*')
    .eq('customer_id', customerId)
    .order('is_primary', { ascending: false })
    .order('name')
  if (error) throw error
  return data as CustomerContact[]
}

export async function saveCustomerContact(
  customerId: string,
  contact: Omit<Partial<CustomerContact>, 'id' | 'customer_id' | 'created_at'> & { name: string },
  contactId?: string
) {
  if (contactId) {
    const { data, error } = await supabase
      .from('customer_contacts')
      .update(contact)
      .eq('id', contactId)
      .select()
      .single()
    if (error) throw error
    return data as CustomerContact
  } else {
    const { data, error } = await supabase
      .from('customer_contacts')
      .insert({ ...contact, customer_id: customerId })
      .select()
      .single()
    if (error) throw error
    return data as CustomerContact
  }
}

export async function deleteCustomerContact(id: string) {
  const { error } = await supabase
    .from('customer_contacts')
    .delete()
    .eq('id', id)
  if (error) throw error
}

// ============================================================
// Credit History — سجل تغييرات الائتمان (قراءة فقط — يملأه Trigger)
// ============================================================

export async function getCreditHistory(customerId: string) {
  const { data, error } = await supabase
    .from('customer_credit_history')
    .select('*, changed_by_profile:profiles!customer_credit_history_changed_by_fkey(id, full_name)')
    .eq('customer_id', customerId)
    .order('created_at', { ascending: false })
    .limit(50)
  if (error) throw error
  return data as CustomerCreditHistory[]
}
