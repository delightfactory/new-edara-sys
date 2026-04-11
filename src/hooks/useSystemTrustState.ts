import { useQuery } from '@tanstack/react-query'
import {
  analyticsGetTrustState,
  AnalyticsNotDeployedError,
  AnalyticsUnauthorizedError,
  type TrustStateRow,
} from '@/lib/services/analyticsClient'

export type { TrustStateRow }

export type TrustDomain = 'all' | 'treasury' | 'sales' | 'ar' | 'customers' | 'targets' | 'profit_overview' | 'branch_profitability' | 'allocation_quality'

export type TrustStatus =
  | 'VERIFIED'
  | 'POSTING_CONSISTENCY_ONLY'
  | 'RECONCILED_WITH_WARNING'
  | 'BLOCKED'
  | 'RUNNING'
  | 'FAILED'
  | 'PARTIAL_FAILURE'
  | 'NOT_DEPLOYED'
  | null

const noRetryOnSetupError = (count: number, err: unknown) => {
  if (err instanceof AnalyticsNotDeployedError) return false
  if (err instanceof AnalyticsUnauthorizedError) return false
  return count < 1
}

/**
 * domain — passed to the RPC to:
 *   1. Filter which trust components are returned (treasury|sales|ar|customers)
 *   2. Gate permission at the SQL level (treasury accepts reports.financial)
 *
 * Always pass the domain that matches the report page. This ensures
 * a finance-only user fetching treasury trust state doesn't get an
 * auth error even though they can't access /reports/sales.
 */
export function useSystemTrustState(domain?: TrustDomain) {
  return useQuery<TrustStateRow[]>({
    queryKey: ['analytics', 'system-trust-state', domain ?? 'all'],
    queryFn:  () => analyticsGetTrustState(domain),
    staleTime: 5 * 60_000,
    gcTime: 15 * 60_000,
    retry: noRetryOnSetupError,
    refetchInterval: 10 * 60_000,
    refetchOnWindowFocus: false,
    refetchOnReconnect: false,
  })
}

export function useTrustForComponent(
  trustRows: TrustStateRow[] | undefined,
  componentName: string
): TrustStateRow | undefined {
  return trustRows?.find(r => r.component_name === componentName)
}

export function getWorstTrustStatus(rows: TrustStateRow[]): TrustStatus {
  const priority: TrustStatus[] = [
    'FAILED', 'BLOCKED', 'PARTIAL_FAILURE', 'RUNNING',
    'RECONCILED_WITH_WARNING', 'POSTING_CONSISTENCY_ONLY', 'VERIFIED', 'NOT_DEPLOYED', null,
  ]
  for (const s of priority) {
    if (rows.some(r => r.status === s)) return s
  }
  return null
}
