import { useQuery } from '@tanstack/react-query'
import {
  analyticsGeographySummary,
  analyticsGeographyTable,
  AnalyticsNotDeployedError,
  AnalyticsUnauthorizedError,
  type GeographySummary,
  type GeographyRow,
  type GeoLevel,
} from '@/lib/services/analyticsClient'

export type { GeographySummary, GeographyRow, GeoLevel }

export interface GeographyFilters {
  dateFrom: string
  dateTo:   string
  level:    GeoLevel
}

const noRetry = (count: number, err: unknown) => {
  if (err instanceof AnalyticsNotDeployedError) return false
  if (err instanceof AnalyticsUnauthorizedError) return false
  return count < 1
}

export function useGeographySummary(filters: GeographyFilters, enabled = true) {
  return useQuery<GeographySummary>({
    queryKey: ['analytics', 'geography', 'summary', filters],
    queryFn:  () => analyticsGeographySummary(filters.dateFrom, filters.dateTo, filters.level),
    staleTime: 5 * 60_000,
    gcTime:    15 * 60_000,
    retry:     noRetry,
    enabled:   enabled && !!filters.dateFrom && !!filters.dateTo,
    refetchOnWindowFocus: false,
  })
}

export function useGeographyTable(filters: GeographyFilters, enabled = true) {
  return useQuery<GeographyRow[]>({
    queryKey: ['analytics', 'geography', 'table', filters],
    queryFn:  () => analyticsGeographyTable(filters.dateFrom, filters.dateTo, filters.level),
    staleTime: 5 * 60_000,
    gcTime:    15 * 60_000,
    retry:     noRetry,
    enabled:   enabled && !!filters.dateFrom && !!filters.dateTo,
    refetchOnWindowFocus: false,
  })
}
