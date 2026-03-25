/**
 * React Query Hooks — EDARA v2
 * ─────────────────────────────────────────────
 * Centralized data-fetching hooks that replace useState+useEffect
 * with automatic caching, background refresh, and deduplication.
 *
 * Architecture:
 * - Reference data (governorates, categories, branches) → staleTime: 10min
 * - List pages (customers, products, stock) → staleTime: 30s (default)
 * - Detail pages → staleTime: 30s (default)
 *
 * Usage in pages:
 *   const { data, isLoading } = useCustomers({ search, page })
 *   // No useState, no useEffect, no loadData() — it just works!
 */

import { useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase/client'

// ─── Services ───
import { getCustomers } from '@/lib/services/customers'
import { getProducts, getCategories, getBrands } from '@/lib/services/products'
import { getGovernorates, getCities, getBranches } from '@/lib/services/geography'
import {
  getWarehouses, getMyWarehouses, getStock, getStockMovements,
  getTransfers, getAdjustments
} from '@/lib/services/inventory'
import { getVaults, getVaultTransactions } from '@/lib/services/vaults'
import { getCustodyAccounts, getCustodyTransactions } from '@/lib/services/custody'
import { getExpenses, getPaymentReceipts, getExpenseCategories } from '@/lib/services/payments'
import { getUsers, getRoles } from '@/lib/services/users'
import { getAuditLogs } from '@/lib/services/settings'
import { getChartOfAccounts, getJournalEntries } from '@/lib/services/finance'
import { getSuppliers } from '@/lib/services/suppliers'

// ════════════════════════════════════════════
// 1. REFERENCE DATA — بيانات مرجعية (staleTime: 10 min)
//    تُطلب مرة واحدة وتُشارك بين كل الصفحات
// ════════════════════════════════════════════

const REF_STALE = 10 * 60 * 1000 // 10 minutes

export function useGovernorates() {
  return useQuery({
    queryKey: ['governorates'],
    queryFn: getGovernorates,
    staleTime: REF_STALE,
  })
}

export function useCities(governorateId?: string) {
  return useQuery({
    queryKey: ['cities', governorateId],
    queryFn: () => getCities(governorateId),
    staleTime: REF_STALE,
    enabled: !!governorateId,
  })
}

export function useBranches() {
  return useQuery({
    queryKey: ['branches'],
    queryFn: getBranches,
    staleTime: REF_STALE,
  })
}

export function useCategories() {
  return useQuery({
    queryKey: ['product-categories'],
    queryFn: getCategories,
    staleTime: REF_STALE,
  })
}

export function useBrands() {
  return useQuery({
    queryKey: ['brands'],
    queryFn: getBrands,
    staleTime: REF_STALE,
  })
}

export function useExpenseCategories() {
  return useQuery({
    queryKey: ['expense-categories'],
    queryFn: getExpenseCategories,
    staleTime: REF_STALE,
  })
}

export function useProfiles() {
  return useQuery({
    queryKey: ['profiles-active'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('profiles')
        .select('id, full_name')
        .eq('status', 'active')
        .order('full_name')
      if (error) throw error
      return data as { id: string; full_name: string }[]
    },
    staleTime: REF_STALE,
  })
}

// ════════════════════════════════════════════
// 2. INVENTORY — المخزون
// ════════════════════════════════════════════

export function useWarehouses(params?: { isActive?: boolean }) {
  return useQuery({
    queryKey: ['warehouses', params],
    queryFn: () => getWarehouses(params),
    staleTime: 5 * 60 * 1000, // 5 min
  })
}

export function useMyWarehouses() {
  return useQuery({
    queryKey: ['my-warehouses'],
    queryFn: getMyWarehouses,
    staleTime: 5 * 60 * 1000,
  })
}

export function useStock(params?: Parameters<typeof getStock>[0]) {
  return useQuery({
    queryKey: ['stock', params],
    queryFn: () => getStock(params),
  })
}

export function useStockMovements(params?: Parameters<typeof getStockMovements>[0]) {
  return useQuery({
    queryKey: ['stock-movements', params],
    queryFn: () => getStockMovements(params),
  })
}

export function useTransfers(params?: Parameters<typeof getTransfers>[0]) {
  return useQuery({
    queryKey: ['transfers', params],
    queryFn: () => getTransfers(params),
  })
}

export function useAdjustments(params?: Parameters<typeof getAdjustments>[0]) {
  return useQuery({
    queryKey: ['adjustments', params],
    queryFn: () => getAdjustments(params),
  })
}

// ════════════════════════════════════════════
// 3. CUSTOMERS — العملاء
// ════════════════════════════════════════════

export function useCustomers(params?: Parameters<typeof getCustomers>[0]) {
  return useQuery({
    queryKey: ['customers', params],
    queryFn: () => getCustomers(params),
  })
}

// ════════════════════════════════════════════
// 4. PRODUCTS — المنتجات
// ════════════════════════════════════════════

export function useProducts(params?: Parameters<typeof getProducts>[0]) {
  return useQuery({
    queryKey: ['products', params],
    queryFn: () => getProducts(params),
  })
}

// ════════════════════════════════════════════
// 5. FINANCE — المالية
// ════════════════════════════════════════════

export function useVaults(params?: Parameters<typeof getVaults>[0]) {
  return useQuery({
    queryKey: ['vaults', params],
    queryFn: () => getVaults(params),
    staleTime: 5 * 60 * 1000,
  })
}

export function useVaultTransactions(vaultId: string, params?: Omit<Parameters<typeof getVaultTransactions>[1], never>) {
  return useQuery({
    queryKey: ['vault-transactions', vaultId, params],
    queryFn: () => getVaultTransactions(vaultId, params),
    enabled: !!vaultId,
  })
}

export function useCustodyAccounts(params?: Parameters<typeof getCustodyAccounts>[0]) {
  return useQuery({
    queryKey: ['custody-accounts', params],
    queryFn: () => getCustodyAccounts(params),
    staleTime: 5 * 60 * 1000,
  })
}

export function useCustodyTransactions(custodyId: string, params?: Omit<Parameters<typeof getCustodyTransactions>[1], never>) {
  return useQuery({
    queryKey: ['custody-transactions', custodyId, params],
    queryFn: () => getCustodyTransactions(custodyId, params),
    enabled: !!custodyId,
  })
}

export function useExpenses(params?: Parameters<typeof getExpenses>[0]) {
  return useQuery({
    queryKey: ['expenses', params],
    queryFn: () => getExpenses(params),
  })
}

export function usePaymentReceipts(params?: Parameters<typeof getPaymentReceipts>[0]) {
  return useQuery({
    queryKey: ['payment-receipts', params],
    queryFn: () => getPaymentReceipts(params),
  })
}

// ════════════════════════════════════════════
// 6. SETTINGS & AUTH — الإعدادات والمستخدمين
// ════════════════════════════════════════════

export function useUsers(params?: Parameters<typeof getUsers>[0]) {
  return useQuery({
    queryKey: ['users', params],
    queryFn: () => getUsers(params),
  })
}

export function useRoles() {
  return useQuery({
    queryKey: ['roles'],
    queryFn: getRoles,
    staleTime: REF_STALE,
  })
}

export function useAuditLogs(params?: Parameters<typeof getAuditLogs>[0]) {
  return useQuery({
    queryKey: ['audit-logs', params],
    queryFn: () => getAuditLogs(params),
  })
}

// ════════════════════════════════════════════
// 7. FINANCE EXTENDED — المالية الممتدة
// ════════════════════════════════════════════

export function useChartOfAccounts() {
  return useQuery({
    queryKey: ['chart-of-accounts'],
    queryFn: getChartOfAccounts,
    staleTime: REF_STALE, // شجرة الحسابات لا تتغير كثيراً
  })
}

export function useJournalEntries(params?: Parameters<typeof getJournalEntries>[0]) {
  return useQuery({
    queryKey: ['journal-entries', params],
    queryFn: () => getJournalEntries(params),
  })
}

export function useSuppliers(params?: Parameters<typeof getSuppliers>[0]) {
  return useQuery({
    queryKey: ['suppliers', params],
    queryFn: () => getSuppliers(params),
  })
}

// ════════════════════════════════════════════
// 6. MUTATION HELPERS — مساعدات الكتابة
//    لإبطال الـ cache بعد عمليات الإضافة/التعديل/الحذف
//
// ملاحظة: Realtime invalidation تتم عبر GlobalRealtimeManager
//         بدلاً من hook لكل صفحة على حدة
// ════════════════════════════════════════════

/**
 * Returns a function to invalidate specific query keys
 * Usage: const invalidate = useInvalidate(); invalidate('customers');
 */
export function useInvalidate() {
  const queryClient = useQueryClient()
  return (...keys: string[]) => {
    keys.forEach(key => queryClient.invalidateQueries({ queryKey: [key] }))
  }
}
