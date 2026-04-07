import { useQuery } from '@tanstack/react-query'
import {
  analyticsCustomerHealthSummary,
  AnalyticsNotDeployedError,
  AnalyticsUnauthorizedError,
  type CustomerHealthResult,
  type CustomerHealthRow,
  type CustomerHealthStats,
} from '@/lib/services/analyticsClient'

export type { CustomerHealthResult, CustomerHealthRow, CustomerHealthStats }

export interface CustomerHealthFilters {
  asOfDate: string
  customerId?: string
  limit?: number
}

const noRetry = (count: number, err: unknown) => {
  if (err instanceof AnalyticsNotDeployedError) return false
  if (err instanceof AnalyticsUnauthorizedError) return false
  return count < 1
}

/**
 * Returns both aggregate stats AND top-N rows in a single RPC call.
 * All aggregation is server-side. No raw row scan sent to browser.
 * recency_days is NULL for customers with no sales history (not 0).
 */
export function useCustomerHealthSummary(filters: CustomerHealthFilters, enabled = true) {
  return useQuery<CustomerHealthResult>({
    queryKey: ['analytics', 'customer-health', filters],
    queryFn: () => analyticsCustomerHealthSummary(
      filters.asOfDate,
      filters.customerId,
      filters.limit ?? 50
    ),
    staleTime: 5 * 60_000,
    gcTime: 15 * 60_000,
    retry: noRetry,
    enabled: enabled && !!filters.asOfDate,
    refetchOnWindowFocus: false,
  })
}
