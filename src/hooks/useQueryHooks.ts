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

import { useQuery, useQueryClient, useMutation } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase/client'

// ─── Services ───
import { getCustomers, getCustomer } from '@/lib/services/customers'
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
import {
  getActivityTypes, getTargetTypes,
  getVisitPlanTemplates, getCallPlanTemplates,
  getActivities, getActivity, createActivity, updateActivity, softDeleteActivity,
  saveCallDetail,
  getVisitPlans, getVisitPlan, getVisitPlanItems,
  createVisitPlan, updateVisitPlan, confirmVisitPlan, cancelVisitPlan,
  addVisitPlanItem, updateVisitPlanItem,
  getCallPlans, getCallPlan, getCallPlanItems,
  createCallPlan, updateCallPlan, confirmCallPlan, cancelCallPlan,
  addCallPlanItem, updateCallPlanItem,
  getTarget, getTargetChildren,
  createTarget, updateTarget, adjustTarget,
  getRepPerformance, getPlanDailySummary, getTargetStatus,
  getChecklistTemplates, getChecklistQuestions, getChecklistResponses,
  saveChecklistResponses,
  deleteVisitPlanItem, deleteCallPlanItem,
  reorderVisitPlanItems, reorderCallPlanItems,
} from '@/lib/services/activities'
import type {
  ActivityInput, CallDetailInput,
  VisitPlanInput, VisitPlanItemInput,
  CallPlanInput, CallPlanItemInput,
  TargetInput, AdjustTargetInput, TargetScope, TargetPeriod, TargetFilters, PayoutFilters,
  CreateTargetWithRewardsInput, TierInput, TargetCustomerInput,
  ChecklistResponseInput,
} from '@/lib/types/activities'

import {
  getTargets, getTargetDetail, getTargetRewardSummary, getTargetPayouts, prepareTargetRewardPayouts,
  adjustTargetBatch, getTargetProgressHistory, createTargetWithRewards,
} from '@/lib/services/targets'

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

export function useCustomer(id: string | null | undefined) {
  return useQuery({
    queryKey: ['customer', id],
    queryFn: () => getCustomer(id!),
    enabled: !!id,
    staleTime: 5 * 60 * 1000,
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
      const { data: emps } = await supabase
        .from('hr_employees')
        .select('id')
        .eq('status', 'active')
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

// ════════════════════════════════════════════
// 10. ACTIVITIES MODULE — موديول الأنشطة الميدانية
// ════════════════════════════════════════════

// ── Reference Data (staleTime: 10min) ────────────────────────

export function useActivityTypes() {
  return useQuery({ queryKey: ['activity-types'], queryFn: getActivityTypes, staleTime: REF_STALE })
}

export function useTargetTypes() {
  return useQuery({ queryKey: ['target-types'], queryFn: getTargetTypes, staleTime: REF_STALE })
}

export function useVisitPlanTemplates() {
  return useQuery({ queryKey: ['visit-plan-templates'], queryFn: getVisitPlanTemplates, staleTime: REF_STALE })
}

export function useCallPlanTemplates() {
  return useQuery({ queryKey: ['call-plan-templates'], queryFn: getCallPlanTemplates, staleTime: REF_STALE })
}

// ── Activities Queries ────────────────────────────────────────

export function useActivities(params?: Parameters<typeof getActivities>[0]) {
  return useQuery({
    queryKey: ['activities', params],
    queryFn: () => getActivities(params),
  })
}

export function useActivity(id: string | null | undefined) {
  return useQuery({
    queryKey: ['activity', id],
    queryFn: () => getActivity(id!),
    enabled: !!id,
  })
}

// ── Visit Plans Queries ───────────────────────────────────────

export function useVisitPlans(params?: Parameters<typeof getVisitPlans>[0]) {
  return useQuery({
    queryKey: ['visit-plans', params],
    queryFn: () => getVisitPlans(params),
  })
}

export function useVisitPlan(id: string | null | undefined) {
  return useQuery({
    queryKey: ['visit-plan', id],
    queryFn: () => getVisitPlan(id!),
    enabled: !!id,
  })
}

export function useVisitPlanItems(planId: string | null | undefined) {
  return useQuery({
    queryKey: ['visit-plan-items', planId],
    queryFn: () => getVisitPlanItems(planId!),
    enabled: !!planId,
  })
}

// ── Call Plans Queries ────────────────────────────────────────

export function useCallPlans(params?: Parameters<typeof getCallPlans>[0]) {
  return useQuery({
    queryKey: ['call-plans', params],
    queryFn: () => getCallPlans(params),
  })
}

export function useCallPlan(id: string | null | undefined) {
  return useQuery({
    queryKey: ['call-plan', id],
    queryFn: () => getCallPlan(id!),
    enabled: !!id,
  })
}

export function useCallPlanItems(planId: string | null | undefined) {
  return useQuery({
    queryKey: ['call-plan-items', planId],
    queryFn: () => getCallPlanItems(planId!),
    enabled: !!planId,
  })
}

// ── Targets Queries ───────────────────────────────────────────

export function useTargets(filters?: TargetFilters, pagination?: { page?: number; pageSize?: number }) {
  return useQuery({
    queryKey: ['targets', filters, pagination],
    queryFn: () => getTargets(filters, pagination),
  })
}

export function useTarget(id: string | null | undefined) {
  return useQuery({
    queryKey: ['target', id],
    queryFn: () => getTarget(id!),
    enabled: !!id,
  })
}

// ── Targets Phase 22 Queries ───────────────────────────────

export function useTargetDetail(id: string | null | undefined) {
  return useQuery({
    queryKey: ['target-detail', id],
    queryFn: () => getTargetDetail(id!),
    enabled: !!id,
  })
}

export function useTargetRewardSummary(id: string | null | undefined) {
  return useQuery({
    queryKey: ['target-reward-summary', id],
    queryFn: () => getTargetRewardSummary(id!),
    enabled: !!id,
  })
}
export function useTargetProgressHistory(id: string | null | undefined, limit: number = 90) {
  return useQuery({
    queryKey: ['target-progress-history', id, limit],
    queryFn: () => getTargetProgressHistory(id!, limit),
    enabled: !!id,
  })
}
export function useTargetPayouts(filters?: PayoutFilters) {
  return useQuery({
    queryKey: ['target-payouts', filters],
    queryFn: () => getTargetPayouts(filters),
  })
}

export function usePrepareTargetPayouts() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (periodId: string) => prepareTargetRewardPayouts(periodId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['target-payouts'] })
      qc.invalidateQueries({ queryKey: ['target-reward-summary'] })
      qc.invalidateQueries({ queryKey: ['target-detail'] })
      qc.invalidateQueries({ queryKey: ['targets'] })
    },
  })
}

// ── Views Queries ─────────────────────────────────────────────

export function useRepPerformance(params?: Parameters<typeof getRepPerformance>[0]) {
  return useQuery({
    queryKey: ['rep-performance', params],
    queryFn: () => getRepPerformance(params),
    // فلتر الشهر/السنة موصى به دائماً — لا نُعطِّل القيود
    staleTime: 60 * 1000, // 1 دقيقة
  })
}

export function usePlanDailySummary(params?: Parameters<typeof getPlanDailySummary>[0]) {
  return useQuery({
    queryKey: ['plan-daily-summary', params],
    queryFn: () => getPlanDailySummary(params),
    staleTime: 60 * 1000,
  })
}

export function useTargetStatus(params?: Parameters<typeof getTargetStatus>[0]) {
  return useQuery({
    queryKey: ['target-status', params],
    queryFn: () => getTargetStatus(params),
    staleTime: 5 * 60 * 1000,
  })
}

// ── Activity Mutations ────────────────────────────────────────

export function useCreateActivity() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: ActivityInput) => createActivity(input),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['activities'] })
      qc.invalidateQueries({ queryKey: ['rep-performance'] })
      qc.invalidateQueries({ queryKey: ['plan-daily-summary'] })
    },
  })
}

export function useUpdateActivity() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, input }: { id: string; input: Partial<ActivityInput> }) =>
      updateActivity(id, input),
    onSuccess: (_data, vars) => {
      qc.invalidateQueries({ queryKey: ['activities'] })
      qc.invalidateQueries({ queryKey: ['activity', vars.id] })
    },
  })
}

export function useSoftDeleteActivity() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (activityId: string) => softDeleteActivity(activityId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['activities'] })
      qc.invalidateQueries({ queryKey: ['plan-daily-summary'] })
    },
  })
}

export function useSaveCallDetail() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ activityId, input }: { activityId: string; input: CallDetailInput }) =>
      saveCallDetail(activityId, input),
    onSuccess: (_data, vars) => {
      qc.invalidateQueries({ queryKey: ['activity', vars.activityId] })
    },
  })
}

// ── Visit Plan Mutations ──────────────────────────────────────

export function useCreateVisitPlan() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: VisitPlanInput) => createVisitPlan(input),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['visit-plans'] }),
  })
}

export function useUpdateVisitPlan() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, input }: { id: string; input: Partial<VisitPlanInput> }) =>
      updateVisitPlan(id, input),
    onSuccess: (_data, vars) => {
      qc.invalidateQueries({ queryKey: ['visit-plans'] })
      qc.invalidateQueries({ queryKey: ['visit-plan', vars.id] })
    },
  })
}

export function useConfirmVisitPlan() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => confirmVisitPlan(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['visit-plans'] }),
  })
}

export function useCancelVisitPlan() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, reason }: { id: string; reason?: string }) => cancelVisitPlan(id, reason),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['visit-plans'] }),
  })
}

export function useAddVisitPlanItem() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ planId, item }: { planId: string; item: VisitPlanItemInput }) =>
      addVisitPlanItem(planId, item),
    onSuccess: (_data, vars) => {
      qc.invalidateQueries({ queryKey: ['visit-plan',       vars.planId] })
      qc.invalidateQueries({ queryKey: ['visit-plan-items', vars.planId] }) // ✅ مضاف
    },
  })
}

export function useUpdateVisitPlanItem() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ itemId, input, planId }: { itemId: string; input: any; planId: string }) =>
      updateVisitPlanItem(itemId, input),
    onSuccess: (_data, vars) => {
      qc.invalidateQueries({ queryKey: ['visit-plan', vars.planId] })
      qc.invalidateQueries({ queryKey: ['visit-plan-items', vars.planId] })
    },
  })
}

// ── Call Plan Mutations ───────────────────────────────────────

export function useCreateCallPlan() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: CallPlanInput) => createCallPlan(input),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['call-plans'] }),
  })
}

export function useUpdateCallPlan() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, input }: { id: string; input: Partial<CallPlanInput> }) =>
      updateCallPlan(id, input),
    onSuccess: (_data, vars) => {
      qc.invalidateQueries({ queryKey: ['call-plans'] })
      qc.invalidateQueries({ queryKey: ['call-plan', vars.id] })
    },
  })
}

export function useConfirmCallPlan() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => confirmCallPlan(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['call-plans'] }),
  })
}

export function useCancelCallPlan() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, reason }: { id: string; reason?: string }) => cancelCallPlan(id, reason),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['call-plans'] }),
  })
}

export function useAddCallPlanItem() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ planId, item }: { planId: string; item: CallPlanItemInput }) =>
      addCallPlanItem(planId, item),
    onSuccess: (_data, vars) => {
      qc.invalidateQueries({ queryKey: ['call-plan',       vars.planId] })
      qc.invalidateQueries({ queryKey: ['call-plan-items', vars.planId] }) // ✅ مضاف
    },
  })
}

export function useUpdateCallPlanItem() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ itemId, input, planId }: { itemId: string; input: any; planId: string }) =>
      updateCallPlanItem(itemId, input),
    onSuccess: (_data, vars) => {
      qc.invalidateQueries({ queryKey: ['call-plan', vars.planId] })
      qc.invalidateQueries({ queryKey: ['call-plan-items', vars.planId] })
    },
  })
}

// ── Target Mutations ──────────────────────────────────────────

export function useCreateTarget() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: TargetInput) => createTarget(input),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['targets'] })
      qc.invalidateQueries({ queryKey: ['target-status'] })
    },
  })
}

export function useCreateTargetWithRewards() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: CreateTargetWithRewardsInput) => createTargetWithRewards(input),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['targets'] })
      qc.invalidateQueries({ queryKey: ['target-status'] })
    },
  })
}

export function useUpdateTarget() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, input }: { id: string; input: Partial<TargetInput> }) =>
      updateTarget(id, input),
    onSuccess: (_data, vars) => {
      qc.invalidateQueries({ queryKey: ['targets'] })
      qc.invalidateQueries({ queryKey: ['target', vars.id] })
      qc.invalidateQueries({ queryKey: ['target-status'] })
    },
  })
}

export function useTargetChildren(parentId: string | null | undefined) {
  return useQuery({
    queryKey: ['target-children', parentId],
    queryFn: () => getTargetChildren(parentId!),
    enabled: !!parentId,
  })
}

/**
 * تعديل قيمة الهدف — يستدعي adjust_target() RPC حصراً
 * التوقيع الحقيقي: p_target_id + p_field + p_new_value (TEXT) + p_reason + p_user_id
 */
export function useAdjustTarget() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: AdjustTargetInput) => adjustTarget(input),
    onSuccess: (_data, vars) => {
      qc.invalidateQueries({ queryKey: ['targets'] })
      qc.invalidateQueries({ queryKey: ['target', vars.p_target_id] })
      qc.invalidateQueries({ queryKey: ['target-detail', vars.p_target_id] })
      qc.invalidateQueries({ queryKey: ['target-children'] })
      qc.invalidateQueries({ queryKey: ['target-status'] })
    },
  })
}

export function useAdjustTargetBatch() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ targetId, fields, reason, userId }: { targetId: string; fields: any; reason: string; userId: string }) => 
      adjustTargetBatch(targetId, fields, reason, userId),
    onSuccess: (_data, vars) => {
      qc.invalidateQueries({ queryKey: ['targets'] })
      qc.invalidateQueries({ queryKey: ['target', vars.targetId] })
      qc.invalidateQueries({ queryKey: ['target-detail', vars.targetId] })
      qc.invalidateQueries({ queryKey: ['target-reward-summary', vars.targetId] })
      qc.invalidateQueries({ queryKey: ['target-children'] })
      qc.invalidateQueries({ queryKey: ['target-status'] })
    },
  })
}

// ════════════════════════════════════════════
// CHECKLISTS — استبيانات الزيارات والمكالمات
// ════════════════════════════════════════════

export function useChecklistTemplates(params?: {
  category?: string
  purposeType?: string | null
}) {
  return useQuery({
    queryKey: ['checklist-templates', params],
    queryFn: () => getChecklistTemplates(params),
    staleTime: REF_STALE,
  })
}

export function useChecklistQuestions(templateId: string | null | undefined) {
  return useQuery({
    queryKey: ['checklist-questions', templateId],
    queryFn: () => getChecklistQuestions(templateId!),
    enabled: !!templateId,
    staleTime: REF_STALE,
  })
}

export function useChecklistResponses(activityId: string | null | undefined) {
  return useQuery({
    queryKey: ['checklist-responses', activityId],
    queryFn: () => getChecklistResponses(activityId!),
    enabled: !!activityId,
  })
}

export function useSaveChecklistResponses() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (responses: ChecklistResponseInput[]) =>
      saveChecklistResponses(responses),
    onSuccess: (_data, vars) => {
      if (vars.length > 0) {
        qc.invalidateQueries({ queryKey: ['checklist-responses', vars[0].activity_id] })
      }
    },
  })
}

// ════════════════════════════════════════════
// PLAN ITEM MANAGEMENT — حذف وإعادة ترتيب بنود الخطط
// ════════════════════════════════════════════

export function useDeleteVisitPlanItem() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (itemId: string) => deleteVisitPlanItem(itemId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['visit-plan-items'] })
      qc.invalidateQueries({ queryKey: ['visit-plans'] })
    },
  })
}

export function useDeleteCallPlanItem() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (itemId: string) => deleteCallPlanItem(itemId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['call-plan-items'] })
      qc.invalidateQueries({ queryKey: ['call-plans'] })
    },
  })
}

export function useReorderVisitPlanItems() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ planId, orderedItemIds }: { planId: string; orderedItemIds: string[] }) =>
      reorderVisitPlanItems(planId, orderedItemIds),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['visit-plan-items'] })
    },
  })
}

export function useReorderCallPlanItems() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ planId, orderedItemIds }: { planId: string; orderedItemIds: string[] }) =>
      reorderCallPlanItems(planId, orderedItemIds),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['call-plan-items'] })
    },
  })
}
