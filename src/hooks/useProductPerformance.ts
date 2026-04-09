import { useQuery } from '@tanstack/react-query'
import {
  analyticsProductPerformanceSummary,
  analyticsProductPerformanceTable,
  AnalyticsNotDeployedError,
  AnalyticsUnauthorizedError,
  type ProductPerformanceSummary,
  type ProductPerformanceRow,
} from '@/lib/services/analyticsClient'

export type { ProductPerformanceSummary, ProductPerformanceRow }

export interface ProductPerformanceFilters {
  dateFrom:   string
  dateTo:     string
  categoryId?: string
  limit?:     number
}

const noRetry = (count: number, err: unknown) => {
  if (err instanceof AnalyticsNotDeployedError) return false
  if (err instanceof AnalyticsUnauthorizedError) return false
  return count < 1
}

export function useProductPerformanceSummary(filters: ProductPerformanceFilters, enabled = true) {
  return useQuery<ProductPerformanceSummary>({
    queryKey: ['analytics', 'product-performance', 'summary', filters],
    queryFn:  () => analyticsProductPerformanceSummary(
      filters.dateFrom, filters.dateTo, filters.categoryId
    ),
    staleTime: 5 * 60_000,
    gcTime:    15 * 60_000,
    retry:     noRetry,
    enabled:   enabled && !!filters.dateFrom && !!filters.dateTo,
    refetchOnWindowFocus: false,
  })
}

export function useProductPerformanceTable(filters: ProductPerformanceFilters, enabled = true) {
  return useQuery<ProductPerformanceRow[]>({
    queryKey: ['analytics', 'product-performance', 'table', filters],
    queryFn:  () => analyticsProductPerformanceTable(
      filters.dateFrom, filters.dateTo, filters.categoryId, filters.limit ?? 50
    ),
    staleTime: 5 * 60_000,
    gcTime:    15 * 60_000,
    retry:     noRetry,
    enabled:   enabled && !!filters.dateFrom && !!filters.dateTo,
    refetchOnWindowFocus: false,
  })
}
