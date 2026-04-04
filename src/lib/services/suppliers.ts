import { supabase } from '@/lib/supabase/client'
import { getAuthUserId } from '@/lib/services/_get-user-id'
import type {
  Supplier, SupplierInput, SupplierContact, SupplierPaymentReminder
} from '@/lib/types/master-data'

function buildSupplierPatch(input: Partial<SupplierInput>) {
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
  setText('type', input.type)
  setText('governorate_id', input.governorate_id)
  setText('city_id', input.city_id)
  setText('phone', input.phone)
  setText('email', input.email)
  setText('tax_number', input.tax_number)
  setText('payment_terms', input.payment_terms)
  setNumber('credit_limit', input.credit_limit)
  setNumber('credit_days', input.credit_days)
  setText('bank_account', input.bank_account)
  setBoolean('is_active', input.is_active)

  return patch
}

// ============================================================
// Suppliers — الموردين
// ============================================================

/**
 * جلب الموردين مع التصفية والترقيم
 */
export async function getSuppliers(params?: {
  search?: string
  isActive?: boolean
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 25
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('suppliers')
    .select(`
      *,
      governorate:governorates(id, name),
      city:cities(id, name)
    `, { count: 'estimated' })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.search) {
    query = query.or(`name.ilike.%${params.search}%,code.ilike.%${params.search}%,phone.ilike.%${params.search}%`)
  }
  if (params?.isActive !== undefined) {
    query = query.eq('is_active', params.isActive)
  }

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as Supplier[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

/**
 * جلب مورد واحد
 */
export async function getSupplier(id: string) {
  const { data, error } = await supabase
    .from('suppliers')
    .select(`
      *,
      governorate:governorates(id, name),
      city:cities(id, name)
    `)
    .eq('id', id)
    .single()
  if (error) throw error
  return data as Supplier
}

/**
 * إنشاء مورد — الكود يتولد تلقائياً بالـ Trigger (SUP-00001)
 */
export async function createSupplier(input: SupplierInput) {
  // NOTE: suppliers table has NO created_by column (confirmed schema).
  // Actor resolution is handled by sync_supplier_opening_balance trigger
  // via auth.uid() fallback. Do NOT add created_by here.
  const { data, error } = await supabase
    .from('suppliers')
    .insert(input)
    .select()
    .single()
  if (error) throw error
  return data as Supplier
}

/**
 * تحديث مورد
 */
export async function updateSupplier(id: string, input: Partial<SupplierInput>) {
  const userId = await getAuthUserId()
  const { opening_balance, ...nonFinancialFields } = input
  const { error } = await supabase.rpc('update_supplier_with_opening_balance', {
    p_supplier_id: id,
    p_non_financial_patch: buildSupplierPatch(nonFinancialFields),
    p_new_opening_balance: opening_balance ?? null,
    p_reason: null,
    p_user_id: userId,
  })
  if (error) throw error
  const { data, error: fetchError } = await supabase
    .from('suppliers')
    .select(`
      *,
      governorate:governorates(id, name),
      city:cities(id, name)
    `)
    .eq('id', id)
    .single()
  if (fetchError) throw fetchError
  return data as Supplier
}

/**
 * تبديل حالة المورد (Soft Delete)
 */
export async function toggleSupplierActive(id: string, isActive: boolean) {
  const { error } = await supabase
    .from('suppliers')
    .update({ is_active: isActive })
    .eq('id', id)
  if (error) throw error
}

// ============================================================
// Supplier Contacts — جهات اتصال المورد
// ============================================================

export async function getSupplierContacts(supplierId: string) {
  const { data, error } = await supabase
    .from('supplier_contacts')
    .select('*')
    .eq('supplier_id', supplierId)
    .order('name')
  if (error) throw error
  return data as SupplierContact[]
}

export async function saveSupplierContact(
  supplierId: string,
  contact: Omit<Partial<SupplierContact>, 'id' | 'supplier_id' | 'created_at'> & { name: string },
  contactId?: string
) {
  if (contactId) {
    const { data, error } = await supabase
      .from('supplier_contacts')
      .update(contact)
      .eq('id', contactId)
      .select()
      .single()
    if (error) throw error
    return data as SupplierContact
  } else {
    const { data, error } = await supabase
      .from('supplier_contacts')
      .insert({ ...contact, supplier_id: supplierId })
      .select()
      .single()
    if (error) throw error
    return data as SupplierContact
  }
}

export async function deleteSupplierContact(id: string) {
  const { error } = await supabase
    .from('supplier_contacts')
    .delete()
    .eq('id', id)
  if (error) throw error
}

// ============================================================
// Payment Reminders — تذكيرات سداد الموردين
// ============================================================

export async function getPaymentReminders(params?: {
  supplierId?: string
  status?: string
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 25
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('supplier_payment_reminders')
    .select('*', { count: 'estimated' })
    .order('due_date', { ascending: true })
    .range(from, to)

  if (params?.supplierId) {
    query = query.eq('supplier_id', params.supplierId)
  }
  if (params?.status) {
    query = query.eq('status', params.status)
  }

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as SupplierPaymentReminder[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

export async function createPaymentReminder(input: {
  supplier_id: string
  due_date: string
  amount: number
  invoice_ref?: string
  notify_before_days?: number
}) {
  const { data, error } = await supabase
    .from('supplier_payment_reminders')
    .insert(input)
    .select()
    .single()
  if (error) throw error
  return data as SupplierPaymentReminder
}

export async function updatePaymentReminderStatus(id: string, status: 'pending' | 'paid' | 'overdue') {
  const { error } = await supabase
    .from('supplier_payment_reminders')
    .update({ status })
    .eq('id', id)
  if (error) throw error
}
