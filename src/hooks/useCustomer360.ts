import { useQuery, useInfiniteQuery } from '@tanstack/react-query'
import { useAuthStore } from '@/stores/auth-store'
import {
  getCustomer360Kpis,
  getCustomer360SalesByMonth,
  getCustomer360TopProducts,
  getCustomer360CategoryMix,
  getCustomer360ArAging,
  getCustomer360PaymentBehavior,
  getCustomer360Timeline,
  getCustomer360Ledger,
  getCustomer360HealthSnapshot,
  getCustomer360RiskSnapshot,
  getCustomer360Profitability,
  Customer360NotDeployedError
} from '@/lib/services/customer360'

const STALE_TIME = 5 * 60 * 1000 // 5 minutes

export const customer360Keys = {
  all: ['customer360'] as const,
  customer: (id: string) => [...customer360Keys.all, id] as const,
  kpis: (id: string) => [...customer360Keys.customer(id), 'kpis'] as const,
  health: (id: string) => [...customer360Keys.customer(id), 'health'] as const,
  risk: (id: string) => [...customer360Keys.customer(id), 'risk'] as const,
  salesByMonth: (id: string, months: number) => [...customer360Keys.customer(id), 'salesByMonth', months] as const,
  topProducts: (id: string, limit: number) => [...customer360Keys.customer(id), 'topProducts', limit] as const,
  categoryMix: (id: string) => [...customer360Keys.customer(id), 'categoryMix'] as const,
  arAging: (id: string) => [...customer360Keys.customer(id), 'arAging'] as const,
  paymentBehavior: (id: string) => [...customer360Keys.customer(id), 'paymentBehavior'] as const,
  timeline: (id: string, limit: number) => [...customer360Keys.customer(id), 'timeline', limit] as const,
  ledger: (id: string, limit: number) => [...customer360Keys.customer(id), 'ledger', limit] as const,
  profitability: (id: string) => [...customer360Keys.customer(id), 'profitability'] as const,
}

// ----------------------------------------------------------------------------
// Phase 1: Core Summary Load
// ----------------------------------------------------------------------------

export function useCustomer360Kpis(customerId: string) {
  return useQuery({
    queryKey: customer360Keys.kpis(customerId),
    queryFn: () => getCustomer360Kpis(customerId),
    staleTime: STALE_TIME,
    enabled: !!customerId,
  })
}

export function useCustomer360HealthSnapshot(customerId: string) {
  return useQuery({
    queryKey: customer360Keys.health(customerId),
    // When analytics tables are not deployed, resolve to null (graceful) rather than error state.
    queryFn: () => getCustomer360HealthSnapshot(customerId).catch((e) => {
      if (e instanceof Customer360NotDeployedError) return null
      throw e
    }),
    staleTime: STALE_TIME,
    enabled: !!customerId,
    retry: (failureCount, error) => {
      // Do not retry on not-deployed or unauthorized — these are deterministic failures.
      if (error instanceof Customer360NotDeployedError) return false
      return failureCount < 2
    },
  })
}

export function useCustomer360RiskSnapshot(customerId: string) {
  return useQuery({
    queryKey: customer360Keys.risk(customerId),
    queryFn: () => getCustomer360RiskSnapshot(customerId).catch((e) => {
      if (e instanceof Customer360NotDeployedError) return null
      throw e
    }),
    staleTime: STALE_TIME,
    enabled: !!customerId,
    retry: (failureCount, error) => {
      if (error instanceof Customer360NotDeployedError) return false
      return failureCount < 2
    },
  })
}

// Phase 1 Orchestration Hook
export function useCustomer360Summary(customerId: string) {
  const kpisQuery = useCustomer360Kpis(customerId)
  const healthQuery = useCustomer360HealthSnapshot(customerId)
  const riskQuery = useCustomer360RiskSnapshot(customerId)

  const isPending = kpisQuery.isPending || healthQuery.isPending || riskQuery.isPending
  const isError = kpisQuery.isError || healthQuery.isError || riskQuery.isError
  
  return {
    kpis: kpisQuery.data,
    health: healthQuery.data,
    risk: riskQuery.data,
    isPending,
    isError,
    // Provide a convenient aggregated refresh
    refetch: () => {
      kpisQuery.refetch()
      healthQuery.refetch()
      riskQuery.refetch()
    }
  }
}

// ----------------------------------------------------------------------------
// Phase 2: Secondary Visual Load
// ----------------------------------------------------------------------------

export function useCustomer360SalesByMonth(customerId: string, months = 18) {
  return useQuery({
    queryKey: customer360Keys.salesByMonth(customerId, months),
    queryFn: () => getCustomer360SalesByMonth(customerId, months),
    staleTime: STALE_TIME,
    enabled: !!customerId,
  })
}

export function useCustomer360TopProducts(customerId: string, limit = 15) {
  return useQuery({
    queryKey: customer360Keys.topProducts(customerId, limit),
    queryFn: () => getCustomer360TopProducts(customerId, limit),
    staleTime: STALE_TIME,
    enabled: !!customerId,
  })
}

export function useCustomer360ArAging(customerId: string) {
  return useQuery({
    queryKey: customer360Keys.arAging(customerId),
    queryFn: () => getCustomer360ArAging(customerId),
    staleTime: STALE_TIME,
    enabled: !!customerId,
  })
}

// ----------------------------------------------------------------------------
// Phase 3: Tertiary / Heavy Load
// ----------------------------------------------------------------------------

// Phase 3 hooks accept an optional enabled gate for lazy loading.
// Pass enabled=false to defer fetch until Phase 1 summary is loaded.
export function useCustomer360CategoryMix(customerId: string, enabled = true) {
  return useQuery({
    queryKey: customer360Keys.categoryMix(customerId),
    queryFn: () => getCustomer360CategoryMix(customerId),
    staleTime: STALE_TIME,
    enabled: !!customerId && enabled,
  })
}

export function useCustomer360PaymentBehavior(customerId: string, enabled = true) {
  return useQuery({
    queryKey: customer360Keys.paymentBehavior(customerId),
    queryFn: () => getCustomer360PaymentBehavior(customerId),
    staleTime: STALE_TIME,
    enabled: !!customerId && enabled,
  })
}

export function useCustomer360Timeline(customerId: string, limit = 30, enabled = true) {
  return useInfiniteQuery({
    queryKey: customer360Keys.timeline(customerId, limit),
    initialPageParam: undefined as { beforeTs?: string | null; beforeId?: string | null } | undefined,
    queryFn: ({ pageParam }) => 
      getCustomer360Timeline(customerId, {
        limit,
        before_ts: pageParam?.beforeTs,
        before_id: pageParam?.beforeId
      }),
    getNextPageParam: (lastPage) => {
      if (!lastPage || lastPage.length < limit) return undefined
      const lastEvent = lastPage[lastPage.length - 1]
      return { beforeTs: lastEvent.event_ts, beforeId: lastEvent.event_id }
    },
    staleTime: STALE_TIME,
    enabled: !!customerId && enabled,
  })
}

// Ledger Pagination using deterministic cursor (before_ts + before_id)
export function useCustomer360Ledger(customerId: string, limit = 15, enabled = true) {
  return useInfiniteQuery({
    queryKey: customer360Keys.ledger(customerId, limit),
    initialPageParam: undefined as { beforeTs?: string | null; beforeId?: string | null } | undefined,
    queryFn: ({ pageParam }) =>
      getCustomer360Ledger(customerId, {
        limit,
        before_ts: pageParam?.beforeTs,
        before_id: pageParam?.beforeId    // deterministic: pass id alongside timestamp
      }),
    getNextPageParam: (lastPage) => {
      if (!lastPage || lastPage.length < limit) return undefined
      const lastEntry = lastPage[lastPage.length - 1]
      // Pass both timestamp and id so cursor breaks ties deterministically
      return { beforeTs: lastEntry.created_at, beforeId: lastEntry.id }
    },
    staleTime: STALE_TIME,
    enabled: !!customerId && enabled,
  })
}


export function useCustomer360Profitability(customerId: string, enabled = true) {
  const can = useAuthStore(s => s.can)
  const hasAccess = can('finance.view_costs')

  const currentDate = new Date()
  const dateTo = new Date(currentDate.getFullYear(), currentDate.getMonth() + 1, 0, 23, 59, 59)
  const dateFrom = new Date(currentDate.getFullYear(), currentDate.getMonth() - 11, 1) // 12 months history
  
  return useQuery({
    queryKey: customer360Keys.profitability(customerId),
    // If the user lacks finance.view_costs, short-circuit immediately with null
    // (no RPC call made). The SQL also enforces this, but skipping the request
    // avoids a wasted round-trip and an error-state flicker.
    queryFn: () => {
      if (!hasAccess) return Promise.resolve(null)
      return getCustomer360Profitability({ 
        customer_id: customerId,
        date_from: dateFrom.toISOString(),
        date_to: dateTo.toISOString(),
        granularity: 'monthly'
      })
    },
    staleTime: STALE_TIME,
    enabled: !!customerId && enabled,
  })
}
