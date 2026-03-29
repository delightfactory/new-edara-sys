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
// 8. SALES — المبيعات
// ════════════════════════════════════════════

import {
  getSalesOrders, getSalesReturns, getShippingCompanies, getSalesStats, getSalesSettings
} from '@/lib/services/sales'

export function useSalesOrders(params?: Parameters<typeof getSalesOrders>[0]) {
  return useQuery({
    queryKey: ['sales-orders', params],
    queryFn: () => getSalesOrders(params),
  })
}

export function useSalesReturns(params?: Parameters<typeof getSalesReturns>[0]) {
  return useQuery({
    queryKey: ['sales-returns', params],
    queryFn: () => getSalesReturns(params),
  })
}

export function useShippingCompanies(onlyActive = false) {
  return useQuery({
    queryKey: ['shipping-companies', onlyActive],
    queryFn: () => getShippingCompanies(onlyActive),
    staleTime: 5 * 60 * 1000,
  })
}

export function useSalesStats() {
  return useQuery({
    queryKey: ['sales-stats'],
    queryFn: getSalesStats,
    staleTime: 60 * 1000, // 1 min
  })
}

export function useSalesSettings() {
  return useQuery({
    queryKey: ['sales-settings'],
    queryFn: getSalesSettings,
    staleTime: REF_STALE,
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

// ════════════════════════════════════════════
// 9. HR MODULE — الموارد البشرية
// ════════════════════════════════════════════

import {
  getEmployees, getEmployee, getCurrentEmployeeRecord,
  getDepartments, getPositions,
  getWorkLocations,
  getLeaveTypes, getLeaveBalances, getLeaveRequests,
  createLeaveRequest, updateLeaveRequestStatus,
  getAdvances, requestAdvance, disburseAdvance, updateAdvanceStatus,
  getPayrollRuns, getPayrollLines, getPayrollPeriods,
  createPayrollPeriod, createPayrollRun, calculateEmployeePayroll, approvePayrollRun,
  getPenaltyInstances, getPenaltyRules, overridePenalty,
  getCommissionRecords, getCommissionTargets, createCommissionTarget,
  getPublicHolidays,
  getAttendanceDays, upsertAttendanceDay,
  getMonthlyAttendanceSummary,
  createEmployee, updateEmployee,
  createDepartment, createPosition,
  getPermissionRequests, createPermissionRequest, approvePermissionRequest, rejectPermissionRequest,
  getEmployeeSalaryHistory, createContract, getContracts,
  getPayrollAdjustments, createPayrollAdjustment, approvePayrollAdjustment,
} from '@/lib/services/hr'
import type {
  HREmployeeInput, HRDepartmentInput, HRPositionInput,
  HRLeaveRequestInput,
  HRAdvanceInput, HRAdvanceStatus,
  HRPayrollPeriodInput, HRPayrollRunInput,
  HRPermissionRequestInput,
  HRContractInput,
  HRCommissionTargetInput,
  HRAttendanceDayInput,
  HRPayrollAdjustmentInput,
} from '@/lib/types/hr'
import { useMutation } from '@tanstack/react-query'

// ── Reference data (staleTime: 10 min) ───────────────────────

export function useHRDepartments(onlyActive = true) {
  return useQuery({
    queryKey: ['hr-departments', onlyActive],
    queryFn: () => getDepartments(onlyActive),
    staleTime: REF_STALE,
  })
}

export function useHRPositions(departmentId?: string) {
  return useQuery({
    queryKey: ['hr-positions', departmentId],
    queryFn: () => getPositions(departmentId),
    staleTime: REF_STALE,
  })
}

export function useHRWorkLocations() {
  return useQuery({
    queryKey: ['hr-work-locations'],
    queryFn: getWorkLocations,
    staleTime: REF_STALE,
  })
}

export function useHRLeaveTypes() {
  return useQuery({
    queryKey: ['hr-leave-types'],
    queryFn: () => getLeaveTypes(true),
    staleTime: REF_STALE,
  })
}

export function useHRPublicHolidays(year?: number) {
  return useQuery({
    queryKey: ['hr-public-holidays', year],
    queryFn: () => getPublicHolidays(year),
    staleTime: REF_STALE,
  })
}

/**
 * الموظف المرتبط بالمستخدم الحالي — لشاشات الخدمة الذاتية
 * يُعيد null إذا لم يكن المستخدم الحالي موظفاً مسجلاً في HR
 * staleTime عالٍ: سجل الموظف نادراً ما يتغير
 */
export function useCurrentEmployee() {
  return useQuery({
    queryKey: ['hr-current-employee'],
    queryFn: getCurrentEmployeeRecord,
    staleTime: 5 * 60 * 1000, // 5 دقائق
    retry: 1,
  })
}

// ── List pages (staleTime: 30s default) ──────────────────────

export function useHREmployees(params?: Parameters<typeof getEmployees>[0]) {
  return useQuery({
    queryKey: ['hr-employees', params],
    queryFn: () => getEmployees(params),
  })
}

export function useHREmployee(id: string | null | undefined) {
  return useQuery({
    queryKey: ['hr-employee', id],
    queryFn: () => getEmployee(id!),
    enabled: !!id,
  })
}

export function useHRLeaveRequests(params?: Parameters<typeof getLeaveRequests>[0]) {
  return useQuery({
    queryKey: ['hr-leave-requests', params],
    queryFn: () => getLeaveRequests(params),
  })
}

export function useHRLeaveBalances(employeeId: string | null | undefined, year?: number) {
  return useQuery({
    queryKey: ['hr-leave-balances', employeeId, year],
    queryFn: () => getLeaveBalances(employeeId!, year),
    enabled: !!employeeId,
  })
}

export function useHRAdvances(params?: Parameters<typeof getAdvances>[0]) {
  return useQuery({
    queryKey: ['hr-advances', params],
    queryFn: () => getAdvances(params),
  })
}

export function useHRPayrollPeriods() {
  return useQuery({
    queryKey: ['hr-payroll-periods'],
    queryFn: getPayrollPeriods,
  })
}

export function useHRPayrollRuns(params?: Parameters<typeof getPayrollRuns>[0]) {
  return useQuery({
    queryKey: ['hr-payroll-runs', params],
    queryFn: () => getPayrollRuns(params),
    refetchInterval: 15_000,
    refetchOnWindowFocus: true,
  })
}

export function useHRPayrollLines(runId: string | null | undefined) {
  return useQuery({
    queryKey: ['hr-payroll-lines', runId],
    queryFn: () => getPayrollLines(runId!),
    enabled: !!runId,
    refetchInterval: 15_000,
    refetchOnWindowFocus: true,
  })
}

export function useHRAttendanceDays(params: Parameters<typeof getAttendanceDays>[0]) {
  return useQuery({
    queryKey: ['hr-attendance-days', params],
    queryFn: () => getAttendanceDays(params),
    enabled: !!(params.dateFrom && params.dateTo),
  })
}

export function useHRMonthlyAttendanceSummary(
  employeeId: string | null | undefined,
  year: number,
  month: number
) {
  return useQuery({
    queryKey: ['hr-attendance-summary', employeeId, year, month],
    queryFn: () => getMonthlyAttendanceSummary(employeeId!, year, month),
    enabled: !!employeeId,
  })
}

export function useHRPenaltyInstances(params?: Parameters<typeof getPenaltyInstances>[0]) {
  return useQuery({
    queryKey: ['hr-penalty-instances', params],
    queryFn: () => getPenaltyInstances(params ?? {}),
    enabled: !!(params?.employeeId || params?.payrollRunId),
  })
}

export function useHRCommissionRecords(params?: Parameters<typeof getCommissionRecords>[0]) {
  return useQuery({
    queryKey: ['hr-commission-records', params],
    queryFn: () => getCommissionRecords(params),
  })
}

// ── Mutations ─────────────────────────────────────────────────

/**
 * إنشاء موظف جديد
 * الـ invalidate يُعيد تحميل القائمة تلقائياً
 */
export function useCreateEmployee() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (input: HREmployeeInput) => createEmployee(input),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['hr-employees'] })
    },
  })
}

/**
 * تعديل بيانات موظف
 */
export function useUpdateEmployee() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, input }: { id: string; input: Partial<HREmployeeInput> }) =>
      updateEmployee(id, input),
    onSuccess: (_data, vars) => {
      queryClient.invalidateQueries({ queryKey: ['hr-employees'] })
      queryClient.invalidateQueries({ queryKey: ['hr-employee', vars.id] })
    },
  })
}

/**
 * إنشاء قسم جديد
 */
export function useCreateDepartment() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (input: HRDepartmentInput) => createDepartment(input),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['hr-departments'] })
    },
  })
}

/**
 * إنشاء مسمى وظيفي جديد
 */
export function useCreatePosition() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (input: HRPositionInput) => createPosition(input),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['hr-positions'] })
    },
  })
}

/**
 * تقديم طلب إجازة
 * على الـ Trigger في DB أن يُفشل العملية إذا كان الرصيد غير كافٍ
 */
export function useCreateLeaveRequest() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (input: HRLeaveRequestInput) => createLeaveRequest(input),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['hr-leave-requests'] })
      queryClient.invalidateQueries({ queryKey: ['hr-leave-balances'] })
    },
  })
}

/**
 * تحديث حالة طلب إجازة (قبول / رفض)
 * يُستخدم من مدير الموارد البشرية أو المشرف المباشر
 */
export function useUpdateLeaveRequestStatus() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({
      id,
      status,
      notes,
      rejectionReason,
    }: {
      id: string
      status: string
      notes?: string | null
      rejectionReason?: string | null
    }) => updateLeaveRequestStatus(id, status, notes, rejectionReason),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['hr-leave-requests'] })
      queryClient.invalidateQueries({ queryKey: ['hr-leave-balances'] })
    },
  })
}

// ────────────────────────────────────────────────────────
// ADVANCES MUTATIONS — السلف والأقساط
// ────────────────────────────────────────────────────────

/**
 * تقديم طلب سلفة عبر RPC request_advance
 * يتحقق من الحد الأقصى ومن عدم وجود سلفة نشطة
 */
export function useRequestAdvance() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (input: HRAdvanceInput) => requestAdvance(input),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['hr-advances'] })
    },
  })
}

/**
 * صرف السلفة — نقطة التقاطع المالي
 * يُرسل vault_id مع تحويل الحالة → approved
 * الـ Trigger في DB يُولِّد الأقساط تلقائياً
 */
export function useDisburseAdvance() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, vaultId, notes }: { id: string; vaultId: string; notes?: string | null }) =>
      disburseAdvance(id, vaultId, notes),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['hr-advances'] })
    },
  })
}

/**
 * تحديث حالة السلفة من قِبَل المشرف أو مدير الموارد البشرية
 */
export function useUpdateAdvanceStatus() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({
      id, status, notes, rejectionReason,
    }: {
      id: string
      status: HRAdvanceStatus
      notes?: string | null
      rejectionReason?: string | null
    }) => updateAdvanceStatus(id, status, notes, rejectionReason),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['hr-advances'] })
    },
  })
}

// ────────────────────────────────────────────────────────
// PAYROLL MUTATIONS — مسير الرواتب
// ────────────────────────────────────────────────────────

/**
 * إنشاء مسير رواتب جديد (سجل draft فقط)
 * الحساب الفعلي يتم لاحقاً عبر useCalculatePayrollRun
 */
export function useCreatePayrollRun() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (input: HRPayrollRunInput) => createPayrollRun(input),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['hr-payroll-runs'] })
    },
  })
}

/**
 * حساب مسير الرواتب — يستدعي calculate_employee_payroll لكل موظف نشط
 * الـ RPC يعمل بالموظف الواحد (p_employee_id, p_run_id)
 * نحسب الكل عبر loop — الـ DB transaction منفصل لكل موظف (تحمل جزئي)
 *
 * onProgress: callback يُستدعى بعد كل موظف (للـ progress bar)
 */
export function useCalculatePayrollRun() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({
      runId,
      onProgress,
    }: {
      runId: string
      onProgress?: (done: number, total: number) => void
    }) => {
      // جلب كل الموظفين النشطين
      const { data: emps } = await import('@/lib/supabase/client').then(m =>
        m.supabase
          .from('hr_employees')
          .select('id')
          .eq('status', 'active')
      )
      const employees = emps ?? []
      let calculated = 0
      let skipped = 0
      for (let i = 0; i < employees.length; i++) {
        try {
          await calculateEmployeePayroll(employees[i].id, runId)
          calculated++
        } catch {
          skipped++
        }
        onProgress?.(i + 1, employees.length)
      }
      return { calculated, skipped, total: employees.length }
    },
    onSuccess: (_, { runId }) => {
      queryClient.invalidateQueries({ queryKey: ['hr-payroll-runs'] })
      queryClient.invalidateQueries({ queryKey: ['hr-payroll-lines', runId] })
      queryClient.invalidateQueries({ queryKey: ['hr-adjustments'] })
    },
  })
}

/**
 * اعتماد مسير الرواتب + توليد القيد المحاسبي
 * يرفض EXCEPTION إذا القيد غير متوازن
 */
export function useApprovePayrollRun() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (runId: string) => approvePayrollRun(runId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['hr-payroll-runs'] })
    },
  })
}

// ═══════════════════════════════════════════════════════════
// PAYROLL ADJUSTMENTS
// ═══════════════════════════════════════════════════════════

export function useHRAdjustments(params?: Parameters<typeof getPayrollAdjustments>[0]) {
  return useQuery({
    queryKey: ['hr-adjustments', params],
    queryFn: () => getPayrollAdjustments(params),
  })
}

export function useCreateAdjustment() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: HRPayrollAdjustmentInput) => createPayrollAdjustment(input),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['hr-adjustments'] }),
  })
}

export function useApproveAdjustment() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, action }: { id: string; action: 'approve' | 'reject' }) =>
      approvePayrollAdjustment(id, action),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['hr-adjustments'] }),
  })
}
