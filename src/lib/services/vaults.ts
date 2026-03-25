import { supabase } from '@/lib/supabase/client'
import type { Vault, VaultInput, VaultTransaction } from '@/lib/types/master-data'

// ============================================================
// Vaults — الخزائن
// ============================================================

/**
 * جلب كل الخزائن
 */
export async function getVaults(params?: {
  isActive?: boolean
  branchId?: string
  type?: string
}) {
  let query = supabase
    .from('vaults')
    .select(`
      *,
      responsible:profiles!vaults_responsible_id_fkey(id, full_name),
      branch:branches(id, name)
    `)
    .order('name')

  if (params?.isActive !== undefined) {
    query = query.eq('is_active', params.isActive)
  }
  if (params?.branchId) {
    query = query.eq('branch_id', params.branchId)
  }
  if (params?.type) {
    query = query.eq('type', params.type)
  }

  const { data, error } = await query
  if (error) throw error
  return data as Vault[]
}

/**
 * جلب خزنة واحدة
 */
export async function getVault(id: string) {
  const { data, error } = await supabase
    .from('vaults')
    .select(`
      *,
      responsible:profiles!vaults_responsible_id_fkey(id, full_name),
      branch:branches(id, name)
    `)
    .eq('id', id)
    .single()
  if (error) throw error
  return data as Vault
}

/**
 * إنشاء خزنة جديدة
 */
export async function createVault(input: VaultInput) {
  const { data, error } = await supabase
    .from('vaults')
    .insert(input)
    .select()
    .single()
  if (error) throw error
  return data as Vault
}

/**
 * تعديل خزنة
 */
export async function updateVault(id: string, input: Partial<VaultInput>) {
  const { data, error } = await supabase
    .from('vaults')
    .update(input)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as Vault
}

// ============================================================
// Vault Transactions — حركات الخزائن
// ============================================================

/**
 * جلب حركات خزنة — كشف حساب
 */
export async function getVaultTransactions(vaultId: string, params?: {
  page?: number
  pageSize?: number
  dateFrom?: string
  dateTo?: string
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 50
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('vault_transactions')
    .select(`
      *,
      created_by_profile:profiles!vault_transactions_created_by_fkey(id, full_name)
    `, { count: 'exact' })
    .eq('vault_id', vaultId)
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.dateFrom) {
    query = query.gte('created_at', params.dateFrom)
  }
  if (params?.dateTo) {
    query = query.lte('created_at', params.dateTo)
  }

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as VaultTransaction[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

/**
 * إيداع يدوي في الخزنة
 * يستدعي add_vault_transaction RPC
 */
export async function addVaultDeposit(
  vaultId: string,
  amount: number,
  description: string,
  refType?: string,
  refId?: string,
) {
  const userId = (await supabase.auth.getUser()).data.user?.id
  const { data, error } = await supabase.rpc('add_vault_transaction', {
    p_vault_id: vaultId,
    p_type: 'deposit',
    p_amount: amount,
    p_ref_type: refType || null,
    p_ref_id: refId || null,
    p_description: description,
    p_user_id: userId,
  })
  if (error) throw error
  return data as string  // returns UUID
}

/**
 * سحب يدوي من الخزنة
 * يستدعي add_vault_transaction RPC
 */
export async function addVaultWithdrawal(
  vaultId: string,
  amount: number,
  description: string,
  refType?: string,
  refId?: string,
) {
  const userId = (await supabase.auth.getUser()).data.user?.id
  const { data, error } = await supabase.rpc('add_vault_transaction', {
    p_vault_id: vaultId,
    p_type: 'withdrawal',
    p_amount: amount,
    p_ref_type: refType || null,
    p_ref_id: refId || null,
    p_description: description,
    p_user_id: userId,
  })
  if (error) throw error
  return data as string
}

/**
 * إيداع رصيد افتتاحي
 */
export async function addVaultOpeningBalance(
  vaultId: string,
  amount: number,
) {
  const userId = (await supabase.auth.getUser()).data.user?.id
  const { data, error } = await supabase.rpc('add_vault_transaction', {
    p_vault_id: vaultId,
    p_type: 'opening_balance',
    p_amount: amount,
    p_ref_type: null,
    p_ref_id: null,
    p_description: 'رصيد افتتاحي',
    p_user_id: userId,
  })
  if (error) throw error
  return data as string
}
