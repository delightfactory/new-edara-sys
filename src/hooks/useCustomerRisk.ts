import { useQuery } from '@tanstack/react-query'
import {
  analyticsCustomerRiskSummary,
  analyticsCustomerRiskList,
  AnalyticsNotDeployedError,
  AnalyticsUnauthorizedError,
  type CustomerRiskStats,
  type CustomerRiskRow,
} from '@/lib/services/analyticsClient'

export type { CustomerRiskStats, CustomerRiskRow }

export interface CustomerRiskFilters {
  asOfDate:   string
  riskLabel?: string
  repId?:     string
  limit?:     number
}

const noRetry = (count: number, err: unknown) => {
  if (err instanceof AnalyticsNotDeployedError) return false
  if (err instanceof AnalyticsUnauthorizedError) return false
  return count < 1
}

export function useCustomerRiskSummary(filters: CustomerRiskFilters, enabled = true) {
  return useQuery<CustomerRiskStats>({
    queryKey: ['analytics', 'customer-risk', 'summary', filters],
    queryFn:  () => analyticsCustomerRiskSummary(filters.asOfDate, filters.riskLabel),
    staleTime: 5 * 60_000,
    gcTime:    15 * 60_000,
    retry:     noRetry,
    enabled:   enabled && !!filters.asOfDate,
    refetchOnWindowFocus: false,
  })
}

export function useCustomerRiskList(filters: CustomerRiskFilters, enabled = true) {
  return useQuery<CustomerRiskRow[]>({
    queryKey: ['analytics', 'customer-risk', 'list', filters],
    queryFn:  () => analyticsCustomerRiskList(
      filters.asOfDate, filters.riskLabel, filters.repId, filters.limit ?? 50
    ),
    staleTime: 5 * 60_000,
    gcTime:    15 * 60_000,
    retry:     noRetry,
    enabled:   enabled && !!filters.asOfDate,
    refetchOnWindowFocus: false,
  })
}
