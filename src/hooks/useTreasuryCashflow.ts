import { useQuery } from '@tanstack/react-query'
import {
  analyticsTreasurySummary,
  analyticsTreasuryDaily,
  AnalyticsNotDeployedError,
  AnalyticsUnauthorizedError,
  type TreasurySummary,
  type TreasuryDailyRow,
} from '@/lib/services/analyticsClient'

export type { TreasurySummary, TreasuryDailyRow }

export interface TreasuryFilters {
  dateFrom: string
  dateTo: string
  repId?: string
}

const noRetry = (count: number, err: unknown) => {
  if (err instanceof AnalyticsNotDeployedError) return false
  if (err instanceof AnalyticsUnauthorizedError) return false
  return count < 1
}

/** Pre-aggregated treasury summary — single server-side SUM per column */
export function useTreasurySummary(filters: TreasuryFilters, enabled = true) {
  return useQuery<TreasurySummary>({
    queryKey: ['analytics', 'treasury-summary', filters],
    queryFn: () => analyticsTreasurySummary(filters.dateFrom, filters.dateTo, filters.repId),
    staleTime: 5 * 60_000,
    gcTime: 15 * 60_000,
    retry: noRetry,
    enabled: enabled && !!filters.dateFrom && !!filters.dateTo,
    refetchOnWindowFocus: false,
  })
}

/** Date-level series for chart — 4 columns × N days, aggregated in SQL */
export function useTreasuryDailyTotals(filters: TreasuryFilters, enabled = true) {
  return useQuery<TreasuryDailyRow[]>({
    queryKey: ['analytics', 'treasury-daily', filters],
    queryFn: () => analyticsTreasuryDaily(filters.dateFrom, filters.dateTo, filters.repId),
    staleTime: 5 * 60_000,
    gcTime: 15 * 60_000,
    retry: noRetry,
    enabled: enabled && !!filters.dateFrom && !!filters.dateTo,
    refetchOnWindowFocus: false,
  })
}
