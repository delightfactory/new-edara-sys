import { useQuery } from '@tanstack/react-query'
import {
  analyticsSalesSummary,
  analyticsSalesDaily,
  AnalyticsNotDeployedError,
  AnalyticsUnauthorizedError,
  type SalesSummary,
  type SalesDailyRow,
} from '@/lib/services/analyticsClient'

export type { SalesSummary, SalesDailyRow }

export interface SalesFilters {
  dateFrom: string
  dateTo: string
  repId?: string
  customerId?: string
}

const noRetry = (count: number, err: unknown) => {
  if (err instanceof AnalyticsNotDeployedError) return false
  if (err instanceof AnalyticsUnauthorizedError) return false
  return count < 1
}

/**
 * Pre-aggregated summary — returns a single jsonb from server-side SUM().
 * Zero overfetch: no raw rows ever sent to browser.
 */
export function useSalesSummary(filters: SalesFilters, enabled = true) {
  return useQuery<SalesSummary>({
    queryKey: ['analytics', 'sales-summary', filters],
    queryFn: () => analyticsSalesSummary(filters.dateFrom, filters.dateTo, filters.repId, filters.customerId),
    staleTime: 5 * 60_000,
    gcTime: 15 * 60_000,
    retry: noRetry,
    enabled: enabled && !!filters.dateFrom && !!filters.dateTo,
    refetchOnWindowFocus: false,
  })
}

/**
 * Daily series for chart rendering — aggregated by date in SQL.
 * Payload is date-level granularity only (6 columns × N days).
 */
export function useSalesDailyTotals(filters: SalesFilters, enabled = true) {
  return useQuery<SalesDailyRow[]>({
    queryKey: ['analytics', 'sales-daily', filters],
    queryFn: () => analyticsSalesDaily(filters.dateFrom, filters.dateTo, filters.repId),
    staleTime: 5 * 60_000,
    gcTime: 15 * 60_000,
    retry: noRetry,
    enabled: enabled && !!filters.dateFrom && !!filters.dateTo,
    refetchOnWindowFocus: false,
  })
}
