import { useQuery } from '@tanstack/react-query'
import {
  analyticsARSummary,
  analyticsARDaily,
  AnalyticsNotDeployedError,
  AnalyticsUnauthorizedError,
  type ARSummary,
  type ARDailyRow,
} from '@/lib/services/analyticsClient'

export type { ARSummary, ARDailyRow }

export interface ARFilters {
  dateFrom: string
  dateTo: string
  repId?: string
}

const noRetry = (count: number, err: unknown) => {
  if (err instanceof AnalyticsNotDeployedError) return false
  if (err instanceof AnalyticsUnauthorizedError) return false
  return count < 1
}

/** Server-aggregated AR summary — single RPC call */
export function useARSummary(filters: ARFilters, enabled = true) {
  return useQuery<ARSummary>({
    queryKey: ['analytics', 'ar-summary', filters],
    queryFn: () => analyticsARSummary(filters.dateFrom, filters.dateTo, filters.repId),
    staleTime: 5 * 60_000,
    gcTime: 15 * 60_000,
    retry: noRetry,
    enabled: enabled && !!filters.dateFrom && !!filters.dateTo,
    refetchOnWindowFocus: false,
  })
}

/** AR daily series for chart rendering, aggregated in SQL */
export function useARDailyTotals(filters: ARFilters, enabled = true) {
  return useQuery<ARDailyRow[]>({
    queryKey: ['analytics', 'ar-daily', filters],
    queryFn: () => analyticsARDaily(filters.dateFrom, filters.dateTo, filters.repId),
    staleTime: 5 * 60_000,
    gcTime: 15 * 60_000,
    retry: noRetry,
    enabled: enabled && !!filters.dateFrom && !!filters.dateTo,
    refetchOnWindowFocus: false,
  })
}
