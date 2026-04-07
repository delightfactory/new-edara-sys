/**
 * analyticsClient.ts
 *
 * Central access layer for analytics data.
 *
 * WHY THIS EXISTS:
 *   Supabase PostgREST only exposes schemas listed in the db.schemas
 *   config (default: public only). The analytics schema contains our
 *   fact tables but is NOT listed there. Attempting
 *   supabase.from('fact_sales_daily_grain') returns a 404 because
 *   PostgREST cannot route it.
 *
 * THE SOLUTION:
 *   All analytics read access goes through public-schema SECURITY DEFINER
 *   RPC functions defined in 77_analytics_public_rpc_layer.sql.
 *   These functions run internally as service_role against analytics.*
 *   while enforcing check_permission() at the application boundary.
 *
 * DEPLOYMENT REQUIREMENT:
 *   Migration 77_analytics_public_rpc_layer.sql must be applied AFTER
 *   75_analytics_schema_wave1.sql and 76_analytics_incremental_jobs.sql.
 */

import { supabase } from '@/lib/supabase/client'

// ─── Type: the error class we use to distinguish setup failures ───────────────

export class AnalyticsNotDeployedError extends Error {
  constructor(reason?: string) {
    super(reason ?? 'Analytics engine not yet deployed')
    this.name = 'AnalyticsNotDeployedError'
  }
}

export class AnalyticsUnauthorizedError extends Error {
  /** domain identifies which report page triggered the failure */
  constructor(public readonly domain?: string) {
    super(`Insufficient permissions for analytics${domain ? ` (domain: ${domain})` : ''}`)
    this.name = 'AnalyticsUnauthorizedError'
  }
}

// ─── Helper: convert supabase RPC errors into typed errors ───────────────────

function mapRpcError(error: { message?: string; code?: string } | null, domain?: string): never {
  const msg = error?.message ?? ''
  if (msg.includes('analytics_not_deployed') || msg.includes('undefined_table') || msg.includes('NOT_DEPLOYED')) {
    throw new AnalyticsNotDeployedError(msg)
  }
  // Catch our custom RAISE EXCEPTION 'analytics_unauthorized:domain=...' pattern
  if (msg.startsWith('analytics_unauthorized') || msg.includes('Unauthorized') || error?.code === '42501') {
    const d = domain ?? msg.match(/domain=([^,)]+)/)?.[1]
    throw new AnalyticsUnauthorizedError(d)
  }
  throw new Error(msg || 'Analytics RPC failed')
}

// ─── 1. Availability Ping (lightweight probe) ─────────────────────────────────

export interface AnalyticsPingResult {
  available: boolean
  reason?: string
  schema?: string
  etl_rows?: number
  checked_at?: string
}

export async function analyticsping(): Promise<AnalyticsPingResult> {
  const { data, error } = await supabase.rpc('analytics_ping')
  if (error) {
    // If the function itself doesn't exist, analytics RPC layer isn't deployed
    if (error.code === '42883' || error.message?.includes('function') || error.message?.includes('does not exist')) {
      return { available: false, reason: 'rpc_layer_not_deployed' }
    }
    return { available: false, reason: error.message }
  }
  return (data as AnalyticsPingResult) ?? { available: false, reason: 'empty_response' }
}

// ─── 2. Trust State ──────────────────────────────────────────────────────────

export interface TrustStateRow {
  component_name: string
  status: string
  drift_value: number | null
  last_completed_at: string | null
  is_stale: boolean
}

/**
 * domain controls which components are returned and which permission is checked:
 *   undefined / 'all' → full list, requires reports.sales
 *   'treasury'         → treasury components only, accepts reports.financial
 *   'sales'            → sales components only, requires reports.sales
 *   'ar'               → AR components only, accepts reports.targets
 *   'customers'        → customer_health components only, requires reports.sales
 */
export async function analyticsGetTrustState(
  domain?: 'all' | 'treasury' | 'sales' | 'ar' | 'customers'
): Promise<TrustStateRow[]> {
  const { data, error } = await supabase.rpc('analytics_get_trust_state', {
    p_domain: domain ?? null,
  })
  if (error) mapRpcError(error, domain)
  return (data as TrustStateRow[]) ?? []
}

// ─── 3. Sales ────────────────────────────────────────────────────────────────

export interface SalesSummary {
  total_revenue: number
  total_tax: number
  total_ar_credit: number
  total_gross_revenue: number
  total_returns_value: number
  total_gross_qty: number
  total_return_qty: number
  total_net_qty: number
  row_count: number
}

export async function analyticsSalesSummary(
  dateFrom: string,
  dateTo: string,
  repId?: string,
  customerId?: string
): Promise<SalesSummary> {
  const { data, error } = await supabase.rpc('analytics_sales_summary', {
    p_date_from:   dateFrom,
    p_date_to:     dateTo,
    p_rep_id:      repId ?? null,
    p_customer_id: customerId ?? null,
  })
  if (error) mapRpcError(error)
  return (data as SalesSummary) ?? {} as SalesSummary
}

export interface SalesDailyRow {
  sale_date:     string
  net_revenue:   number
  tax_amount:    number
  returns_value: number
  gross_qty:     number
  net_qty:       number
}

export async function analyticsSalesDaily(
  dateFrom: string,
  dateTo: string,
  repId?: string
): Promise<SalesDailyRow[]> {
  const { data, error } = await supabase.rpc('analytics_sales_daily', {
    p_date_from: dateFrom,
    p_date_to:   dateTo,
    p_rep_id:    repId ?? null,
  })
  if (error) mapRpcError(error)
  return (data as SalesDailyRow[]) ?? []
}

// ─── 4. Treasury ─────────────────────────────────────────────────────────────

export interface TreasurySummary {
  total_inflow:  number
  total_outflow: number
  net_cashflow:  number
}

export async function analyticsTreasurySummary(
  dateFrom: string,
  dateTo: string,
  repId?: string
): Promise<TreasurySummary> {
  const { data, error } = await supabase.rpc('analytics_treasury_summary', {
    p_date_from: dateFrom,
    p_date_to:   dateTo,
    p_rep_id:    repId ?? null,
  })
  if (error) mapRpcError(error)
  return (data as TreasurySummary) ?? {} as TreasurySummary
}

export interface TreasuryDailyRow {
  treasury_date: string
  gross_inflow:  number
  gross_outflow: number
  net_cashflow:  number
}

export async function analyticsTreasuryDaily(
  dateFrom: string,
  dateTo: string,
  repId?: string
): Promise<TreasuryDailyRow[]> {
  const { data, error } = await supabase.rpc('analytics_treasury_daily', {
    p_date_from: dateFrom,
    p_date_to:   dateTo,
    p_rep_id:    repId ?? null,
  })
  if (error) mapRpcError(error)
  return (data as TreasuryDailyRow[]) ?? []
}

// ─── 5. AR Collections ──────────────────────────────────────────────────────

export interface ARSummary {
  total_receipt_amount: number
  total_refunds:        number
  total_net_cohort:     number
}

export async function analyticsARSummary(
  dateFrom: string,
  dateTo: string,
  repId?: string
): Promise<ARSummary> {
  const { data, error } = await supabase.rpc('analytics_ar_summary', {
    p_date_from: dateFrom,
    p_date_to:   dateTo,
    p_rep_id:    repId ?? null,
  })
  if (error) mapRpcError(error)
  return (data as ARSummary) ?? {} as ARSummary
}

export interface ARDailyRow {
  sale_date:      string
  receipt_amount: number
  refund_amount:  number
  net_cohort:     number
}

export async function analyticsARDaily(
  dateFrom: string,
  dateTo: string,
  repId?: string
): Promise<ARDailyRow[]> {
  const { data, error } = await supabase.rpc('analytics_ar_daily', {
    p_date_from: dateFrom,
    p_date_to:   dateTo,
    p_rep_id:    repId ?? null,
  })
  if (error) mapRpcError(error)
  return (data as ARDailyRow[]) ?? []
}

// ─── 6. Customer Health ──────────────────────────────────────────────────────

export interface CustomerHealthStats {
  total:        number
  dormant:      number
  active:       number
  avg_monetary: number
  avg_recency:  number | null
}

export interface CustomerHealthRow {
  customer_id:    string
  customer_name?: string
  as_of_date:     string
  recency_days:   number | null
  frequency_l90d: number
  monetary_l90d:  number
  is_dormant:     boolean
}

export interface CustomerHealthResult {
  stats: CustomerHealthStats
  rows:  CustomerHealthRow[]
}

export async function analyticsCustomerHealthSummary(
  asOfDate: string,
  customerId?: string,
  limit = 50
): Promise<CustomerHealthResult> {
  const { data, error } = await supabase.rpc('analytics_customer_health_summary', {
    p_as_of_date:  asOfDate,
    p_customer_id: customerId ?? null,
    p_limit:       limit,
  })
  if (error) mapRpcError(error)
  const d = data as { stats: CustomerHealthStats; rows: CustomerHealthRow[] }
  return { stats: d?.stats ?? {} as CustomerHealthStats, rows: d?.rows ?? [] }
}
