import { supabase } from '@/lib/supabase/client'
import type {
  ChartOfAccount, CustomerLedgerEntry, CustomerBalance,
  SupplierLedgerEntry, SupplierBalance,
  JournalEntry, JournalEntryLine, JournalEntryInput, JournalEntryLineInput,
  ApprovalRule
} from '@/lib/types/master-data'

// ============================================================
// Chart of Accounts — شجرة الحسابات
// ============================================================

/**
 * جلب شجرة الحسابات كاملة
 */
export async function getChartOfAccounts() {
  const { data, error } = await supabase
    .from('chart_of_accounts')
    .select('*')
    .eq('is_active', true)
    .order('sort_order')
    .order('code')
  if (error) throw error
  return data as ChartOfAccount[]
}

/**
 * بناء الشجرة الهرمية من القائمة المسطحة
 */
export function buildAccountTree(accounts: ChartOfAccount[]): ChartOfAccount[] {
  const map = new Map<string, ChartOfAccount>()
  const roots: ChartOfAccount[] = []

  accounts.forEach(a => map.set(a.id, { ...a, children: [] }))
  accounts.forEach(a => {
    const node = map.get(a.id)!
    if (a.parent_id && map.has(a.parent_id)) {
      map.get(a.parent_id)!.children!.push(node)
    } else {
      roots.push(node)
    }
  })
  return roots
}

// ============================================================
// Customer Ledger — دفتر حسابات العملاء
// ============================================================

/**
 * جلب حركات دفتر العميل
 */
export async function getCustomerLedger(customerId: string, params?: {
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 50
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  const { data, error, count } = await supabase
    .from('customer_ledger')
    .select(`
      *,
      created_by_profile:profiles!customer_ledger_created_by_fkey(id, full_name)
    `, { count: 'exact' })
    .eq('customer_id', customerId)
    .order('created_at', { ascending: false })
    .range(from, to)
  if (error) throw error

  return {
    data: data as CustomerLedgerEntry[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

/**
 * جلب رصيد عميل واحد من الـ View
 */
export async function getCustomerBalance(customerId: string) {
  const { data, error } = await supabase
    .from('v_customer_balances')
    .select('*')
    .eq('customer_id', customerId)
    .maybeSingle()
  if (error) throw error
  return (data as CustomerBalance) || {
    customer_id: customerId,
    balance: 0,
    transaction_count: 0,
    last_transaction_at: null,
  }
}

/**
 * جلب أرصدة كل العملاء
 */
export async function getAllCustomerBalances() {
  const { data, error } = await supabase
    .from('v_customer_balances')
    .select('*')
  if (error) throw error
  return data as CustomerBalance[]
}

// ============================================================
// Supplier Ledger — دفتر حسابات الموردين
// ============================================================

/**
 * جلب حركات دفتر المورد
 */
export async function getSupplierLedger(supplierId: string, params?: {
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 50
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  const { data, error, count } = await supabase
    .from('supplier_ledger')
    .select(`
      *,
      created_by_profile:profiles!supplier_ledger_created_by_fkey(id, full_name)
    `, { count: 'exact' })
    .eq('supplier_id', supplierId)
    .order('created_at', { ascending: false })
    .range(from, to)
  if (error) throw error

  return {
    data: data as SupplierLedgerEntry[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

/**
 * جلب رصيد مورد واحد من الـ View
 */
export async function getSupplierBalance(supplierId: string) {
  const { data, error } = await supabase
    .from('v_supplier_balances')
    .select('*')
    .eq('supplier_id', supplierId)
    .maybeSingle()
  if (error) throw error
  return (data as SupplierBalance) || {
    supplier_id: supplierId,
    balance: 0,
    transaction_count: 0,
    last_transaction_at: null,
  }
}

// ============================================================
// Journal Entries — القيود المحاسبية
// ============================================================

/**
 * جلب القيود المحاسبية مع التصفية والترقيم
 */
export async function getJournalEntries(params?: {
  sourceType?: string
  status?: string
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
    .from('journal_entries')
    .select(`
      *,
      created_by_profile:profiles!journal_entries_created_by_fkey(id, full_name)
    `, { count: 'exact' })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.sourceType) {
    query = query.eq('source_type', params.sourceType)
  }
  if (params?.status) {
    query = query.eq('status', params.status)
  }
  if (params?.dateFrom) {
    query = query.gte('entry_date', params.dateFrom)
  }
  if (params?.dateTo) {
    query = query.lte('entry_date', params.dateTo)
  }

  const { data, error, count } = await query
  if (error) throw error

  return {
    data: data as JournalEntry[],
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

/**
 * جلب قيد واحد مع سطوره
 */
export async function getJournalEntry(id: string) {
  const { data, error } = await supabase
    .from('journal_entries')
    .select(`
      *,
      created_by_profile:profiles!journal_entries_created_by_fkey(id, full_name),
      lines:journal_entry_lines(
        *,
        account:chart_of_accounts(id, code, name)
      )
    `)
    .eq('id', id)
    .single()
  if (error) throw error
  return data as JournalEntry & { lines: JournalEntryLine[] }
}

/**
 * إنشاء قيد محاسبي يدوي
 * يجب أن total_debit = total_credit وإلا ستفشل الـ CHECK constraint
 */
export async function createManualJournalEntry(
  entry: JournalEntryInput,
  lines: JournalEntryLineInput[]
) {
  const userId = (await supabase.auth.getUser()).data.user?.id

  // 1. حساب المجاميع
  const totalDebit = lines.reduce((sum, l) => sum + l.debit, 0)
  const totalCredit = lines.reduce((sum, l) => sum + l.credit, 0)

  if (totalDebit !== totalCredit) {
    throw new Error(`القيد غير متوازن: مدين ${totalDebit} ≠ دائن ${totalCredit}`)
  }

  // 2. جلب معرّفات الحسابات من الأكواد
  const codes = [...new Set(lines.map(l => l.account_code))]
  const { data: accounts, error: accError } = await supabase
    .from('chart_of_accounts')
    .select('id, code')
    .in('code', codes)
  if (accError) throw accError

  const codeToId = new Map(accounts.map(a => [a.code, a.id]))
  for (const code of codes) {
    if (!codeToId.has(code)) {
      throw new Error(`حساب غير موجود: ${code}`)
    }
  }

  // 3. إنشاء القيد
  const { data: je, error: jeError } = await supabase
    .from('journal_entries')
    .insert({
      source_type: entry.source_type || 'manual',
      source_id: entry.source_id || null,
      description: entry.description,
      entry_date: entry.entry_date || new Date().toISOString().split('T')[0],
      is_auto: false,
      status: 'posted',
      total_debit: totalDebit,
      total_credit: totalCredit,
      created_by: userId,
    })
    .select()
    .single()
  if (jeError) throw jeError

  // 4. إنشاء السطور
  const lineInserts = lines.map(l => ({
    entry_id: je.id,
    account_id: codeToId.get(l.account_code)!,
    debit: l.debit,
    credit: l.credit,
    description: l.description || null,
  }))

  const { error: linesError } = await supabase
    .from('journal_entry_lines')
    .insert(lineInserts)
  if (linesError) throw linesError

  return je as JournalEntry
}

// ============================================================
// Approval Rules — قواعد الموافقات
// ============================================================

/**
 * جلب قواعد الموافقات — مع كل الحالات (نشط + غير نشط)
 */
export async function getApprovalRules(type?: string) {
  let query = supabase
    .from('approval_rules')
    .select(`
      *,
      role:roles(id, name, name_ar, color)
    `)
    .order('type')
    .order('sort_order')

  if (type) {
    query = query.eq('type', type)
  }

  const { data, error } = await query
  if (error) throw error
  return data as ApprovalRule[]
}

/**
 * إنشاء قاعدة موافقة
 */
export async function createApprovalRule(input: {
  type: string; role_id: string; max_amount: number; sort_order?: number
}) {
  const { data, error } = await supabase
    .from('approval_rules')
    .insert({ ...input, sort_order: input.sort_order ?? 0 })
    .select(`*, role:roles(id, name, name_ar, color)`)
    .single()
  if (error) throw error
  return data as ApprovalRule
}

/**
 * تعديل قاعدة موافقة
 */
export async function updateApprovalRule(id: string, input: {
  max_amount?: number; sort_order?: number; is_active?: boolean
}) {
  const { data, error } = await supabase
    .from('approval_rules')
    .update(input)
    .eq('id', id)
    .select(`*, role:roles(id, name, name_ar, color)`)
    .single()
  if (error) throw error
  return data as ApprovalRule
}

/**
 * حذف قاعدة موافقة
 */
export async function deleteApprovalRule(id: string) {
  const { error } = await supabase
    .from('approval_rules')
    .delete()
    .eq('id', id)
  if (error) throw error
}

/**
 * جلب الأدوار المتاحة لإضافة قاعدة موافقة
 */
export async function getRolesForApproval() {
  const { data, error } = await supabase
    .from('roles')
    .select('id, name, name_ar, color')
    .order('name_ar')
  if (error) throw error
  return data as { id: string; name: string; name_ar: string; color: string }[]
}
