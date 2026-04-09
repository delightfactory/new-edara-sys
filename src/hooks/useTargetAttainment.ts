import { useQuery } from '@tanstack/react-query'
import {
  analyticsTargetAttainmentSummary,
  analyticsTargetAttainmentTable,
  AnalyticsNotDeployedError,
  AnalyticsUnauthorizedError,
  type TargetAttainmentStats,
  type TargetAttainmentRow,
} from '@/lib/services/analyticsClient'

export type { TargetAttainmentStats, TargetAttainmentRow }

export interface TargetAttainmentFilters {
  asOfDate: string
  scope?:   string
}

const noRetry = (count: number, err: unknown) => {
  if (err instanceof AnalyticsNotDeployedError) return false
  if (err instanceof AnalyticsUnauthorizedError) return false
  return count < 1
}

export function useTargetAttainmentSummary(filters: TargetAttainmentFilters, enabled = true) {
  return useQuery<TargetAttainmentStats>({
    queryKey: ['analytics', 'target-attainment', 'summary', filters],
    queryFn:  () => analyticsTargetAttainmentSummary(filters.asOfDate),
    staleTime: 5 * 60_000,
    gcTime:    15 * 60_000,
    retry:     noRetry,
    enabled:   enabled && !!filters.asOfDate,
    refetchOnWindowFocus: false,
  })
}

export function useTargetAttainmentTable(filters: TargetAttainmentFilters, enabled = true) {
  return useQuery<TargetAttainmentRow[]>({
    queryKey: ['analytics', 'target-attainment', 'table', filters],
    queryFn:  () => analyticsTargetAttainmentTable(filters.asOfDate, filters.scope),
    staleTime: 5 * 60_000,
    gcTime:    15 * 60_000,
    retry:     noRetry,
    enabled:   enabled && !!filters.asOfDate,
    refetchOnWindowFocus: false,
  })
}
