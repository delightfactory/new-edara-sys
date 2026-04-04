import { supabase } from '@/lib/supabase/client'
import { getAuthUserId } from '@/lib/services/_get-user-id'
import type {
  PaymentReceipt, PaymentReceiptInput,
  ExpenseCategory, Expense, ExpenseInput,
} from '@/lib/types/master-data'

// ============================================================
// Payment Receipts — إيصالات الدفع / التحصيل
// ============================================================

/**
 * جلب إيصالات الدفع مع التصفية والترقيم
 */
export async function getPaymentReceipts(params?: {
  status?: string
  customerId?: string
  branchId?: string
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
    .from('payment_receipts')
    .select(`
      *,
      customer:customers(id, name, code),
      vault:vaults(id, name, type),
      branch:branches(id, name),
      sales_order:sales_orders(id, order_number),
      collected_by_profile:profiles!payment_receipts_collected_by_fkey(id, full_name),
      reviewed_by_profile:profiles!payment_receipts_reviewed_by_fkey(id, full_name),
      created_by_profile:profiles!payment_receipts_created_by_fkey(id, full_name)
    `, { count: 'estimated' })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.status) {
    query = query.eq('status', params.status)
  }
  if (params?.customerId) {
    query = query.eq('customer_id', params.customerId)
  }
  if (params?.branchId) {
    query = query.eq('branch_id', params.branchId)
  }
  if (params?.dateFrom) {
    query = query.gte('created_at', params.dateFrom)
  }
  if (params?.dateTo) {
    query = query.lte('created_at', params.dateTo + 'T23:59:59')
  }

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as PaymentReceipt[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

/**
 * جلب إيصال دفع واحد
 */
export async function getPaymentReceipt(id: string) {
  const { data, error } = await supabase
    .from('payment_receipts')
    .select(`
      *,
      customer:customers(id, name, code),
      vault:vaults(id, name, type),
      branch:branches(id, name),
      sales_order:sales_orders(id, order_number),
      collected_by_profile:profiles!payment_receipts_collected_by_fkey(id, full_name),
      reviewed_by_profile:profiles!payment_receipts_reviewed_by_fkey(id, full_name),
      created_by_profile:profiles!payment_receipts_created_by_fkey(id, full_name)
    `)
    .eq('id', id)
    .single()
  if (error) throw error
  return data as PaymentReceipt
}

/**
 * إنشاء إيصال دفع (حالة: pending)
 */
export async function createPaymentReceipt(input: PaymentReceiptInput) {
  const userId = await getAuthUserId()
  const { data, error } = await supabase
    .from('payment_receipts')
    .insert({
      ...input,
      status: 'pending',
      created_by: userId,
      collected_by: input.collected_by || userId,
    })
    .select()
    .single()
  if (error) throw error
  return data as PaymentReceipt
}

/**
 * تأكيد إيصال دفع
 * RPC: confirm_payment_receipt(action='confirm')
 * vaultId: مطلوب للنقد/البنك/المحفظة — null للشيكات
 */
export async function confirmPaymentReceipt(receiptId: string, vaultId: string | null) {
  const userId = await getAuthUserId()
  const { error } = await supabase.rpc('confirm_payment_receipt', {
    p_receipt_id: receiptId,
    p_action: 'confirm',
    p_vault_id: vaultId,
    p_reason: null,
    p_user_id: userId,
  })
  if (error) throw error
}

/**
 * جلب الطلبات المفتوحة (غير مسددة بالكامل) لعميل محدد
 * تُستخدم في نموذج إنشاء الإيصال لربطه بفاتورة
 */
export async function getOpenOrdersForCustomer(customerId: string) {
  const { data, error } = await supabase
    .from('sales_orders')
    .select('id, order_number, total_amount, paid_amount, status, order_date')
    .eq('customer_id', customerId)
    .eq('status', 'delivered')   // completed = paid in full by definition
    .order('order_date', { ascending: true })
    .limit(50)
  if (error) throw error
  // فلترة إضافية: فقط ما لم يُسدد بالكامل (احتياطي)
  return (data || []).filter(o => (o.paid_amount ?? 0) < o.total_amount)
}

/**
 * رفض إيصال دفع
 * RPC: confirm_payment_receipt(action='reject')
 */
export async function rejectPaymentReceipt(receiptId: string, reason: string) {
  const userId = await getAuthUserId()
  const { error } = await supabase.rpc('confirm_payment_receipt', {
    p_receipt_id: receiptId,
    p_action: 'reject',
    p_vault_id: null,
    p_reason: reason,
    p_user_id: userId,
  })
  if (error) throw error
}

/**
 * رفع إثبات دفع إلى storage bucket
 */
export async function uploadPaymentProof(file: File): Promise<string> {
  const ext = file.name.split('.').pop()
  const fileName = `${Date.now()}-${Math.random().toString(36).substring(2)}.${ext}`
  const filePath = `receipts/${fileName}`

  const { error } = await supabase.storage
    .from('payment-proofs')
    .upload(filePath, file, { upsert: false })
  if (error) throw error

  const { data } = supabase.storage
    .from('payment-proofs')
    .getPublicUrl(filePath)
  return data.publicUrl
}

// ============================================================
// Expense Categories — تصنيفات المصروفات
// ============================================================

/**
 * جلب تصنيفات المصروفات
 */
export async function getExpenseCategories() {
  const { data, error } = await supabase
    .from('expense_categories')
    .select('*')
    .eq('is_active', true)
    .order('name')
  if (error) throw error
  return data as ExpenseCategory[]
}

/**
 * إنشاء تصنيف مصروف جديد
 */
export async function createExpenseCategory(input: {
  name: string
  parent_id?: string | null
}) {
  const { data, error } = await supabase
    .from('expense_categories')
    .insert(input)
    .select()
    .single()
  if (error) throw error
  return data as ExpenseCategory
}

/**
 * تعديل تصنيف مصروف
 */
export async function updateExpenseCategory(id: string, input: {
  name?: string
  parent_id?: string | null
  is_active?: boolean
}) {
  const { data, error } = await supabase
    .from('expense_categories')
    .update(input)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as ExpenseCategory
}

// ============================================================
// Expenses — المصروفات
// ============================================================

/**
 * جلب المصروفات مع التصفية والترقيم
 */
export async function getExpenses(params?: {
  status?: string
  categoryId?: string
  branchId?: string
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
    .from('expenses')
    .select(`
      *,
      category:expense_categories(id, name),
      vault:vaults(id, name, type),
      branch:branches(id, name),
      approved_by_profile:profiles!expenses_approved_by_fkey(id, full_name),
      created_by_profile:profiles!expenses_created_by_fkey(id, full_name)
    `, { count: 'estimated' })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.status) {
    query = query.eq('status', params.status)
  }
  if (params?.categoryId) {
    query = query.eq('category_id', params.categoryId)
  }
  if (params?.branchId) {
    query = query.eq('branch_id', params.branchId)
  }
  if (params?.dateFrom) {
    query = query.gte('expense_date', params.dateFrom)
  }
  if (params?.dateTo) {
    query = query.lte('expense_date', params.dateTo)
  }

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as Expense[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

/**
 * جلب مصروف واحد
 */
export async function getExpense(id: string) {
  const { data, error } = await supabase
    .from('expenses')
    .select(`
      *,
      category:expense_categories(id, name),
      vault:vaults(id, name, type),
      branch:branches(id, name),
      approved_by_profile:profiles!expenses_approved_by_fkey(id, full_name),
      created_by_profile:profiles!expenses_created_by_fkey(id, full_name)
    `)
    .eq('id', id)
    .single()
  if (error) throw error
  return data as Expense
}

/**
 * إنشاء مصروف (حالة: draft)
 */
export async function createExpense(input: ExpenseInput) {
  const userId = await getAuthUserId()
  const { data, error } = await supabase
    .from('expenses')
    .insert({
      ...input,
      status: 'draft',
      expense_date: input.expense_date || new Date().toISOString().split('T')[0],
      created_by: userId,
    })
    .select()
    .single()
  if (error) throw error
  return data as Expense
}

/**
 * تحديث مصروف (فقط في حالة draft)
 */
export async function updateExpense(id: string, input: Partial<ExpenseInput>) {
  const { data, error } = await supabase
    .from('expenses')
    .update(input)
    .eq('id', id)
    .eq('status', 'draft')  // لا يمكن تعديل مصروف تم تقديمه
    .select()
    .single()
  if (error) throw error
  return data as Expense
}

/**
 * تقديم مصروف للموافقة (draft → pending_approval)
 */
export async function submitExpenseForApproval(id: string) {
  const { data, error } = await supabase
    .from('expenses')
    .update({ status: 'pending_approval' })
    .eq('id', id)
    .eq('status', 'draft')
    .select()
    .single()
  if (error) throw error
  return data as Expense
}

/**
 * الموافقة على مصروف
 * RPC: approve_expense(action='approve')
 */
export async function approveExpense(expenseId: string) {
  const userId = await getAuthUserId()
  const { error } = await supabase.rpc('approve_expense', {
    p_expense_id: expenseId,
    p_action: 'approve',
    p_reason: null,
    p_user_id: userId,
  })
  if (error) throw error
}

/**
 * رفض مصروف
 * RPC: approve_expense(action='reject')
 */
export async function rejectExpense(expenseId: string, reason: string) {
  const userId = await getAuthUserId()
  const { error } = await supabase.rpc('approve_expense', {
    p_expense_id: expenseId,
    p_action: 'reject',
    p_reason: reason,
    p_user_id: userId,
  })
  if (error) throw error
}

/**
 * رفع إيصال مصروف إلى storage bucket
 */
export async function uploadExpenseReceipt(file: File): Promise<string> {
  const ext = file.name.split('.').pop()
  const fileName = `${Date.now()}-${Math.random().toString(36).substring(2)}.${ext}`
  const filePath = `receipts/${fileName}`

  const { error } = await supabase.storage
    .from('expense-receipts')
    .upload(filePath, file, { upsert: false })
  if (error) throw error

  const { data } = supabase.storage
    .from('expense-receipts')
    .getPublicUrl(filePath)
  return data.publicUrl
}

/**
 * فحص الائتمان قبل إنشاء طلب بيع
 * RPC: check_credit_available
 */
export async function checkCreditAvailable(
  customerId: string,
  amount: number,
): Promise<boolean> {
  const { data, error } = await supabase.rpc('check_credit_available', {
    p_customer_id: customerId,
    p_amount: amount,
  })
  if (error) throw error
  return data as boolean
}
