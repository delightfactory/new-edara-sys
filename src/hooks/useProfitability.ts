import { useQuery } from '@tanstack/react-query'
import * as client from '@/lib/services/profitabilityClient'
import type { ProfitabilityFilterParams, GranularProfitabilityFilterParams } from '@/lib/types/profitability'

export function useProfitSummary(params: ProfitabilityFilterParams) {
  return useQuery({
    queryKey: ['profitability', 'summary', params.date_from, params.date_to],
    queryFn: () => client.getProfitSummary(params),
    staleTime: 5 * 60 * 1000,
  })
}

export function useProfitTrend(params: GranularProfitabilityFilterParams) {
  return useQuery({
    queryKey: ['profitability', 'trend', params.date_from, params.date_to, params.granularity],
    queryFn: () => client.getProfitTrend(params),
    staleTime: 5 * 60 * 1000,
  })
}

export function useGrossProfitByProduct(params: GranularProfitabilityFilterParams) {
  return useQuery({
    queryKey: ['profitability', 'gross_profit', 'product', params.date_from, params.date_to, params.branch_id, params.granularity, params.limit_count],
    queryFn: () => client.getGrossProfitByProduct(params),
    select: (data) => data.map(item => ({
      ...item,
      // Map gross_revenue to semantic net_revenue
      net_revenue_after_returns: item.gross_revenue,
      entity_id_display: item.product_name ?? item.product_id ?? 'غير معرّف'
    })),
    staleTime: 5 * 60 * 1000,
  })
}

export function useGrossProfitByCustomer(params: GranularProfitabilityFilterParams) {
  return useQuery({
    queryKey: ['profitability', 'gross_profit', 'customer', params.date_from, params.date_to, params.branch_id, params.granularity, params.limit_count],
    queryFn: () => client.getGrossProfitByCustomer(params),
    select: (data) => data.map(item => ({
      ...item,
      net_revenue_after_returns: item.gross_revenue,
      entity_id_display: item.customer_name ?? item.customer_id ?? 'غير معرّف'
    })),
    staleTime: 5 * 60 * 1000,
  })
}

export function useGrossProfitByRep(params: GranularProfitabilityFilterParams) {
  return useQuery({
    queryKey: ['profitability', 'gross_profit', 'rep', params.date_from, params.date_to, params.branch_id, params.granularity, params.limit_count],
    queryFn: () => client.getGrossProfitByRep(params),
    select: (data) => data.map(item => ({
      ...item,
      net_revenue_after_returns: item.gross_revenue,
      entity_id_display: item.rep_id === '00000000-0000-0000-0000-000000000000' || item.rep_id === null 
        ? 'غير مسند' 
        : (item.rep_name ?? item.rep_id)
    })),
    staleTime: 5 * 60 * 1000,
  })
}

export function useBranchDirectNetProfit(params: ProfitabilityFilterParams) {
  return useQuery({
    queryKey: ['profitability', 'branch_direct', params.date_from, params.date_to, params.branch_id],
    queryFn: () => client.getBranchDirectNetProfit(params),
    select: (data) => data.map(item => ({
      ...item,
      net_revenue_after_returns: item.gross_revenue,
      entity_id_display: item.branch_name ?? item.branch_id
    })),
    staleTime: 5 * 60 * 1000,
  })
}

// NOTE: useBranchDirectProfitTrend is not consumed by any UI page in this release.
// Retained as pre-built hook for a future branch trend chart.
export function useBranchDirectProfitTrend(params: GranularProfitabilityFilterParams) {
  return useQuery({
    queryKey: ['profitability', 'branch_direct_trend', params.date_from, params.date_to, params.branch_id, params.granularity],
    queryFn: () => client.getBranchDirectProfitTrend(params),
    staleTime: 5 * 60 * 1000,
  })
}

export function useBranchFinalNetProfitMonthly(params: ProfitabilityFilterParams) {
  return useQuery({
    queryKey: ['profitability', 'branch_final', params.date_from, params.date_to, params.branch_id],
    queryFn: () => client.getBranchFinalNetProfitMonthly(params),
    select: (data) => data.map(item => ({
      ...item,
      branch_name_display: item.branch_id === null ? 'وعاء مشترك غير موزع' : (item.branch_name ?? item.branch_id),
      net_revenue_after_returns: item.direct_gross_revenue
    })),
    staleTime: 5 * 60 * 1000,
  })
}

export function useAllocationQualityReport(params: ProfitabilityFilterParams) {
  return useQuery({
    queryKey: ['profitability', 'allocation_quality', params.date_from, params.date_to],
    queryFn: () => client.getAllocationQualityReport(params),
    staleTime: 5 * 60 * 1000,
  })
}
