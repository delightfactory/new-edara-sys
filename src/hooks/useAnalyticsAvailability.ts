/**
 * useAnalyticsAvailability
 *
 * P0 Gate — this is the ONLY hook that query pages should use
 * before mounting any data-fetching hooks.
 *
 * States:
 *  - 'checking'      : initial probe in flight
 *  - 'available'     : analytics engine accessible, data hooks may fire
 *  - 'not_deployed'  : migration 77 / analytics schema not applied yet
 *  - 'unauthorized'  : user lacks reports.sales permission
 *  - 'error'         : unexpected technical error (transient network, etc.)
 */

import { useQuery } from '@tanstack/react-query'
import { analyticsping, AnalyticsUnauthorizedError, AnalyticsNotDeployedError } from '@/lib/services/analyticsClient'

export type AnalyticsAvailabilityStatus =
  | 'checking'
  | 'available'
  | 'not_deployed'
  | 'unauthorized'
  | 'error'

export interface AnalyticsAvailability {
  status: AnalyticsAvailabilityStatus
  errorReason?: string
  isReady: boolean  // true only when 'available'
}

export function useAnalyticsAvailability(): AnalyticsAvailability {
  const { data, isLoading, error } = useQuery({
    queryKey: ['analytics', 'availability'],
    queryFn: analyticsping,
    staleTime: 5 * 60_000,
    gcTime: 10 * 60_000,
    // Never retry on setup failures — they won't heal by themselves
    retry: (failureCount, err) => {
      if (err instanceof AnalyticsNotDeployedError) return false
      if (err instanceof AnalyticsUnauthorizedError) return false
      return failureCount < 1
    },
    refetchOnWindowFocus: false,
    refetchOnReconnect: false,
  })

  if (isLoading) return { status: 'checking', isReady: false }

  if (error) {
    if (error instanceof AnalyticsUnauthorizedError) return { status: 'unauthorized', isReady: false }
    if (error instanceof AnalyticsNotDeployedError)  return { status: 'not_deployed', isReady: false }
    return { status: 'error', errorReason: (error as Error).message, isReady: false }
  }

  if (!data?.available) {
    const reason = data?.reason ?? 'unknown'
    if (reason.includes('unauthorized'))          return { status: 'unauthorized', isReady: false }
    if (reason.includes('not_deployed') || reason.includes('schema_not_deployed'))
                                                  return { status: 'not_deployed', isReady: false }
    return { status: 'not_deployed', errorReason: reason, isReady: false }
  }

  return { status: 'available', isReady: true }
}
