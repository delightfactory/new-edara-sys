import { supabase } from '@/lib/supabase/client'

// ============================================================
// Types
// ============================================================

export type SupplierPaymentMethod = 'cash' | 'bank_transfer' | 'cheque' | 'mobile_wallet'

export interface SupplierPaymentVoucher {
  id: string
  number: string
  supplier_id: string
  amount: number
  payment_date: string
  payment_method: SupplierPaymentMethod
  vault_id: string | null
  vault_txn_id: string | null
  notes: string | null
  status: 'posted' | 'reversed'
  created_by: string | null
  created_at: string
  updated_at: string
  // Joined
  supplier?: { id: string; name: string; code: string }
  vault?: { id: string; name: string; type: string }
  created_by_profile?: { id: string; full_name: string }
}

export interface CreateSupplierPaymentInput {
  supplierId: string
  amount: number
  paymentMethod: SupplierPaymentMethod
  vaultId?: string | null
  notes?: string | null
  paymentDate?: string | null
}

// ============================================================
// Helpers
// ============================================================

async function getUserId(): Promise<string> {
  const { data } = await supabase.auth.getUser()
  if (!data.user?.id) throw new Error('يجب تسجيل الدخول')
  return data.user.id
}

const SELECT_VOUCHER = `
  *,
  supplier:suppliers(id, name, code),
  vault:vaults(id, name, type),
  created_by_profile:profiles!supplier_payment_vouchers_created_by_fkey(id, full_name)
`

// ============================================================
// API
// ============================================================

/**
 * جلب سندات صرف مورد محدد مع ترقيم الصفحات
 */
export async function getSupplierPayments(params: {
  supplierId: string
  page?: number
  pageSize?: number
}) {
  const page     = params.page     || 1
  const pageSize = params.pageSize || 25
  const from     = (page - 1) * pageSize
  const to       = from + pageSize - 1

  const { data, error, count } = await supabase
    .from('supplier_payment_vouchers')
    .select(SELECT_VOUCHER, { count: 'estimated' })
    .eq('supplier_id', params.supplierId)
    .eq('status', 'posted')
    .order('payment_date', { ascending: false })
    .range(from, to)

  if (error) throw error
  return {
    data: data as SupplierPaymentVoucher[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

/**
 * جلب كل سندات الصرف (لصفحة القائمة العامة)
 */
export async function getAllSupplierPayments(params?: {
  supplierId?: string
  dateFrom?: string
  dateTo?: string
  page?: number
  pageSize?: number
}) {
  const page     = params?.page     || 1
  const pageSize = params?.pageSize || 25
  const from     = (page - 1) * pageSize
  const to       = from + pageSize - 1

  let query = supabase
    .from('supplier_payment_vouchers')
    .select(SELECT_VOUCHER, { count: 'estimated' })
    .eq('status', 'posted')
    .order('payment_date', { ascending: false })
    .range(from, to)

  if (params?.supplierId) query = query.eq('supplier_id', params.supplierId)
  if (params?.dateFrom)   query = query.gte('payment_date', params.dateFrom)
  if (params?.dateTo)     query = query.lte('payment_date', params.dateTo)

  const { data, error, count } = await query
  if (error) throw error
  return {
    data: data as SupplierPaymentVoucher[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

/**
 * RPC: إنشاء سند صرف مورد مستقل
 * يُنشئ أتوماتيكياً:
 *   - حركة خزينة (vendor_payment) — إذا لم يكن شيكاً
 *   - قيد محاسبي: DR:2100 / CR:خزينة أو CR:2110
 *   - سجل في دفتر الموردين (supplier_ledger)
 */
export async function createSupplierPayment(
  input: CreateSupplierPaymentInput
): Promise<string> {
  const userId = await getUserId()

  const { data, error } = await supabase.rpc('pay_supplier_account', {
    p_supplier_id:    input.supplierId,
    p_user_id:        userId,
    p_amount:         input.amount,
    p_payment_method: input.paymentMethod,
    p_vault_id:       input.vaultId   ?? null,
    p_notes:          input.notes     ?? null,
    p_payment_date:   input.paymentDate ?? null,
  })
  if (error) throw error
  return data as string   // UUID السند المُنشأ
}
