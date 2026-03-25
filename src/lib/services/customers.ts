import { supabase } from '@/lib/supabase/client'
import type {
  Customer, CustomerInput, CustomerBranch, CustomerContact, CustomerCreditHistory
} from '@/lib/types/master-data'

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
    `, { count: 'exact' })
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
  const userId = (await supabase.auth.getUser()).data.user?.id
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
  const { data, error } = await supabase
    .from('customers')
    .update(input)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as Customer
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
      location_updated_by: (await supabase.auth.getUser()).data.user?.id,
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
  if (error) throw error
  return data as CustomerCreditHistory[]
}
