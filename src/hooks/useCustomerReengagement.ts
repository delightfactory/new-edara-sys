/**
 * useCustomerReengagement.ts
 *
 * Hooks مستقلة لصفحة إعادة الاستهداف.
 *
 * قرارات معمارية:
 *   - الفلاتر لا تُدار هنا — تُمرَّر من الصفحة (أو hook فلاتر منفصل).
 *   - لا AnalyticsNotDeployedError — هذا الـ service مستقل.
 *   - staleTime: 2 دقيقة — البيانات التشغيلية تتحدث بشكل محتمل.
 *   - retry: 1 — لا نريد إعادة محاولات كثيرة على بيانات ثقيلة.
 */

import { useQuery } from '@tanstack/react-query'
import {
  getReengagementList,
  getReengagementSummary,
  type ReengagementFilters,
  type ReengagementRow,
  type ReengagementSummary,
  type PriorityLabel,
} from '@/lib/services/customerReengagement'

export type { ReengagementRow, ReengagementSummary, ReengagementFilters, PriorityLabel }

const STALE = 2 * 60_000 // 2 دقيقة

export function useReengagementList(
  filters: ReengagementFilters,
  enabled = true
) {
  return useQuery<ReengagementRow[]>({
    queryKey:  ['reengagement', 'list', filters],
    queryFn:   () => getReengagementList(filters),
    staleTime: STALE,
    gcTime:    10 * 60_000,
    retry:     1,
    enabled,
    refetchOnWindowFocus: false,
  })
}

export function useReengagementSummary(
  filters: Omit<ReengagementFilters, 'limit'>,
  enabled = true
) {
  return useQuery<ReengagementSummary>({
    queryKey:  ['reengagement', 'summary', filters],
    queryFn:   () => getReengagementSummary(filters),
    staleTime: STALE,
    gcTime:    10 * 60_000,
    retry:     1,
    enabled,
    refetchOnWindowFocus: false,
  })
}
