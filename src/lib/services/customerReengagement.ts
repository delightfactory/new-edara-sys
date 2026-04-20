/**
 * customerReengagement.ts
 *
 * Service مستقل للوصول إلى بيانات إعادة الاستهداف.
 *
 * هذا الملف مفصول عمداً عن analyticsClient.ts لأن:
 *   1. analyticsClient مخصص لطبقة analytics engine فقط.
 *   2. يُحوّل أخطاءه إلى AnalyticsNotDeployedError — مناقض لاحتياجنا.
 *   3. صفحة إعادة الاستهداف تقرأ من public.sales_orders مباشرة
 *      ويجب أن تعمل بغض النظر عن حالة analytics engine.
 *
 * RPCs المستخدمة:
 *   public.customer_reengagement_list(...)
 *   public.customer_reengagement_summary(...)
 *
 * لا يوجد `AnalyticsNotDeployedError` هنا — أخطاء RPC تُرمى كـ Error عادية.
 */

import { supabase } from '@/lib/supabase/client'

// ─── Types ────────────────────────────────────────────────────

export type PriorityLabel =
  | 'CHAMPION_LOST'
  | 'DECLINING_HIGH'
  | 'MID_LOST'
  | 'MID_AT_RISK'
  | 'OTHER'

export type ValueTier = 'HIGH' | 'MED' | 'LOW'
export type StatusLabel = 'LOST' | 'AT_RISK' | 'ACTIVE' | 'NO_ORDERS'

export interface ReengagementRow {
  customer_id:          string
  customer_name:        string
  customer_code:        string | null
  customer_type:        string
  governorate_name:     string
  city_name:            string
  rep_name:             string
  rep_id:               string | null
  priority_label:       PriorityLabel
  priority_rank:        number
  value_tier:           ValueTier
  status_label:         StatusLabel
  historical_revenue:   number
  revenue_last_90d:     number
  revenue_prev_90d:     number
  recency_days:         number | null
  last_order_date:      string | null
  outstanding_balance:  number
  order_count:          number
  is_active:            boolean
}

export interface ReengagementSummary {
  total_customers:        number
  champion_lost_count:    number
  declining_high_count:   number
  mid_lost_count:         number
  mid_at_risk_count:      number
  other_count:            number
  total_outstanding:      number
  avg_historical_revenue: number | null
  avg_recency_days:       number | null
}

export interface ReengagementFilters {
  dateFrom?:      string
  dateTo?:        string
  repId?:         string
  governorateId?: string
  cityId?:        string
  priority?:      PriorityLabel
  customerType?:  string
  activeOnly?:    boolean
  limit?:         number
}

// ─── Service Functions ─────────────────────────────────────────

/**
 * جلب قائمة العملاء مرتبة بالأولوية
 */
export async function getReengagementList(
  filters: ReengagementFilters = {}
): Promise<ReengagementRow[]> {
  const { data, error } = await supabase.rpc('customer_reengagement_list', {
    p_date_from:      filters.dateFrom      ?? null,
    p_date_to:        filters.dateTo        ?? null,
    p_rep_id:         filters.repId         ?? null,
    p_governorate_id: filters.governorateId ?? null,
    p_city_id:        filters.cityId        ?? null,
    p_priority:       filters.priority      ?? null,
    p_customer_type:  filters.customerType  ?? null,
    p_active_only:    filters.activeOnly    ?? true,
    p_limit:          filters.limit         ?? 100,
  })
  if (error) throw new Error(error.message)
  return (data as ReengagementRow[]) ?? []
}

/**
 * جلب ملخص KPIs
 * نفس dataset الـ list — مضمون تطابق الأرقام
 */
export async function getReengagementSummary(
  filters: Omit<ReengagementFilters, 'limit'> = {}
): Promise<ReengagementSummary> {
  const { data, error } = await supabase.rpc('customer_reengagement_summary', {
    p_date_from:      filters.dateFrom      ?? null,
    p_date_to:        filters.dateTo        ?? null,
    p_rep_id:         filters.repId         ?? null,
    p_governorate_id: filters.governorateId ?? null,
    p_city_id:        filters.cityId        ?? null,
    p_priority:       filters.priority      ?? null,
    p_customer_type:  filters.customerType  ?? null,
    p_active_only:    filters.activeOnly    ?? true,
  })
  if (error) throw new Error(error.message)
  // RPC يُرجع صف واحد — نأخذ أول عنصر
  const row = Array.isArray(data) ? data[0] : data
  return (row as ReengagementSummary) ?? {
    total_customers: 0,
    champion_lost_count: 0,
    declining_high_count: 0,
    mid_lost_count: 0,
    mid_at_risk_count: 0,
    other_count: 0,
    total_outstanding: 0,
    avg_historical_revenue: null,
    avg_recency_days: null,
  }
}
