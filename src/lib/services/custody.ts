import { supabase } from '@/lib/supabase/client'
import type {
  CustodyAccount, CustodyAccountInput, CustodyTransaction
} from '@/lib/types/master-data'

// ============================================================
// Custody Accounts — العُهد
// ============================================================

/**
 * جلب كل حسابات العُهد
 */
export async function getCustodyAccounts(params?: {
  isActive?: boolean
}) {
  let query = supabase
    .from('custody_accounts')
    .select(`
      *,
      employee:profiles!custody_accounts_employee_id_fkey(id, full_name)
    `)
    .order('created_at', { ascending: false })

  if (params?.isActive !== undefined) {
    query = query.eq('is_active', params.isActive)
  }

  const { data, error } = await query
  if (error) throw error
  return data as CustodyAccount[]
}

/**
 * جلب عهدة واحدة مع بيانات الموظف
 */
export async function getCustodyAccount(id: string) {
  const { data, error } = await supabase
    .from('custody_accounts')
    .select(`
      *,
      employee:profiles!custody_accounts_employee_id_fkey(id, full_name)
    `)
    .eq('id', id)
    .single()
  if (error) throw error
  return data as CustodyAccount
}

/**
 * جلب عهدة الموظف الحالي
 */
export async function getMyCustodyAccount() {
  const userId = (await supabase.auth.getUser()).data.user?.id
  if (!userId) throw new Error('غير مصادق')

  const { data, error } = await supabase
    .from('custody_accounts')
    .select(`
      *,
      employee:profiles!custody_accounts_employee_id_fkey(id, full_name)
    `)
    .eq('employee_id', userId)
    .maybeSingle()
  if (error) throw error
  return data as CustodyAccount | null
}

/**
 * إنشاء حساب عهدة لموظف
 */
export async function createCustodyAccount(input: CustodyAccountInput) {
  const { data, error } = await supabase
    .from('custody_accounts')
    .insert(input)
    .select()
    .single()
  if (error) throw error
  return data as CustodyAccount
}

/**
 * تعديل حساب عهدة (الحد الأقصى / الحالة)
 */
export async function updateCustodyAccount(
  id: string,
  input: Partial<Pick<CustodyAccountInput, 'max_balance' | 'is_active'>>
) {
  const { data, error } = await supabase
    .from('custody_accounts')
    .update(input)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as CustodyAccount
}

// ============================================================
// Custody Transactions — حركات العُهد
// ============================================================

/**
 * جلب حركات عهدة — كشف حساب
 */
export async function getCustodyTransactions(custodyId: string, params?: {
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 50
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  const { data, error, count } = await supabase
    .from('custody_transactions')
    .select(`
      *,
      vault:vaults(id, name, type),
      created_by_profile:profiles!custody_transactions_created_by_fkey(id, full_name)
    `, { count: 'exact' })
    .eq('custody_id', custodyId)
    .order('created_at', { ascending: false })
    .range(from, to)
  if (error) throw error

  return {
    data: data as CustodyTransaction[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

/**
 * تحميل عهدة من خزنة
 * RPC: load_custody_from_vault
 */
export async function loadCustodyFromVault(
  custodyId: string,
  vaultId: string,
  amount: number,
) {
  const userId = (await supabase.auth.getUser()).data.user?.id
  const { error } = await supabase.rpc('load_custody_from_vault', {
    p_custody_id: custodyId,
    p_vault_id: vaultId,
    p_amount: amount,
    p_user_id: userId,
  })
  if (error) throw error
}

/**
 * تسوية عهدة إلى خزنة
 * RPC: settle_custody_to_vault
 */
export async function settleCustodyToVault(
  custodyId: string,
  vaultId: string,
  amount: number,
  type: 'settlement' | 'return' = 'settlement',
) {
  const userId = (await supabase.auth.getUser()).data.user?.id
  const { error } = await supabase.rpc('settle_custody_to_vault', {
    p_custody_id: custodyId,
    p_vault_id: vaultId,
    p_amount: amount,
    p_type: type,
    p_user_id: userId,
  })
  if (error) throw error
}
