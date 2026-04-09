import { useQuery } from '@tanstack/react-query'
import {
  analyticsRepPerformanceSummary,
  analyticsRepPerformanceTable,
  AnalyticsNotDeployedError,
  AnalyticsUnauthorizedError,
  type RepPerformanceSummary,
  type RepPerformanceRow,
} from '@/lib/services/analyticsClient'

export type { RepPerformanceSummary, RepPerformanceRow }

export interface RepPerformanceFilters {
  dateFrom: string
  dateTo:   string
}

const noRetry = (count: number, err: unknown) => {
  if (err instanceof AnalyticsNotDeployedError) return false
  if (err instanceof AnalyticsUnauthorizedError) return false
  return count < 1
}

export function useRepPerformanceSummary(filters: RepPerformanceFilters, enabled = true) {
  return useQuery<RepPerformanceSummary>({
    queryKey: ['analytics', 'rep-performance', 'summary', filters],
    queryFn:  () => analyticsRepPerformanceSummary(filters.dateFrom, filters.dateTo),
    staleTime: 5 * 60_000,
    gcTime:    15 * 60_000,
    retry:     noRetry,
    enabled:   enabled && !!filters.dateFrom && !!filters.dateTo,
    refetchOnWindowFocus: false,
  })
}

export function useRepPerformanceTable(filters: RepPerformanceFilters, enabled = true) {
  return useQuery<RepPerformanceRow[]>({
    queryKey: ['analytics', 'rep-performance', 'table', filters],
    queryFn:  () => analyticsRepPerformanceTable(filters.dateFrom, filters.dateTo),
    staleTime: 5 * 60_000,
    gcTime:    15 * 60_000,
    retry:     noRetry,
    enabled:   enabled && !!filters.dateFrom && !!filters.dateTo,
    refetchOnWindowFocus: false,
  })
}
