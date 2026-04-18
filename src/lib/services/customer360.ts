import { supabase } from '@/lib/supabase/client'
import { getCustomerProfitability } from './profitabilityClient'
import type { CustomerProfitabilityFilterParams, GrossProfitGrainResult } from '@/lib/types/profitability'

export class Customer360UnauthorizedError extends Error {
  constructor(public domain: string) {
    super(`Unauthorized to access Customer 360 data (${domain})`)
    this.name = 'Customer360UnauthorizedError'
  }
}

export class Customer360NotDeployedError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'Customer360NotDeployedError'
  }
}

function mapRpcError(error: { message?: string; code?: string } | null, domain: string): never {
  const msg = error?.message ?? ''
  if (msg.includes('analytics_not_deployed') || msg.includes('undefined_table') || msg.includes('NOT_DEPLOYED')) {
    throw new Customer360NotDeployedError(msg)
  }
  if (msg.includes('analytics_unauthorized') || msg.includes('Access denied') || msg.includes('permission denied')) {
    throw new Customer360UnauthorizedError(domain)
  }
  throw new Error(`Customer 360 service error [${domain}]: ${msg || error?.code || 'Unknown failure'}`)
}

// ----------------------------------------------------------------------------
// Types
// ----------------------------------------------------------------------------

export interface Customer360Kpis {
  net_revenue: number | null
  total_collected: number | null
  outstanding_balance: number | null
  order_count: number | null
  monthly_avg_orders: number | null
  return_rate_pct: number | null
  latest_order_date: string | null
  customer_since_days: number | null
  credit_limit: number | null
  credit_utilization_pct: number | null
}

export interface CustomerSalesByMonth {
  month: string
  net_revenue: number
  returns_value: number
  order_count: number
}

export interface CustomerTopProduct {
  product_id: string
  product_sku: string
  product_name: string
  category_name: string | null
  total_qty: number
  total_value: number
  value_l90d: number
  order_count: number          // عدد مرات الشراء — يُحسب بالـ RPC لكن كان غائبًا عن الـ type
  return_rate_pct: number
  status: 'جديد' | 'خامد' | 'مستمر' | string
  last_purchase_date: string | null
  avg_price: number
}

export interface CustomerCategoryMix {
  category_id: string
  category_name: string
  all_time_value: number
  all_time_pct: number
  recent_90d_value: number
  recent_90d_pct: number
}

export interface CustomerArAgingBucket {
  bucket: string
  amount: number
  invoice_count: number
  oldest_invoice_date: string | null
}

export interface RecentReceipt {
  number: string
  amount: number
  payment_method: string
  date: string
}

export interface CustomerPaymentBehavior {
  avg_payment_delay_days: number | null
  min_delay_days: number | null
  max_delay_days: number | null
  payment_samples: number
  payment_methods_breakdown: Record<string, number> | null
  recent_receipts: RecentReceipt[] | null
}

export interface CustomerTimelineEvent {
  event_id: string
  event_ts: string
  event_type: 'order' | 'return' | 'payment' | 'activity' | 'credit_change' | string
  title: string
  amount: number
  status: string
  actor: string | null
  source_id: string
  extra: {
    order_number?: string
    return_number?: string
    number?: string
    total_amount?: number
    amount?: number
    status?: string
    reason?: string
    payment_method?: string
    type_name?: string
    outcome_type?: string
    outcome_notes?: string
    limit_before?: number
    limit_after?: number
  } | null
}

export interface CustomerLedgerEntry {
  id: string
  type: 'debit' | 'credit'
  amount: number
  source_type: string
  source_id: string | null
  description: string | null
  created_at: string
  running_balance: number
}

export interface CustomerHealthSnapshot {
  health_status: 'نشط' | 'خامد' | string
  /** risk_label from snapshot_customer_risk: 'VIP' | 'LOYAL' | 'ENGAGED' | 'AT_RISK' | 'DORMANT' */
  risk_label: string | null
  recency_days: number | null
  frequency_l90d: number | null
  monetary_l90d: number | null
  last_snapshot_date: string | null
}

export interface CustomerRiskSnapshot {
  risk_label: string | null
  rfm_score: number | null
  recency_days: number | null
  frequency_l90d: number | null
  monetary_l90d: number | null
}

// ----------------------------------------------------------------------------
// Services
// ----------------------------------------------------------------------------

export async function getCustomer360Kpis(customerId: string): Promise<Customer360Kpis | null> {
  const { data, error } = await supabase.rpc('get_customer_360_kpis', { p_customer_id: customerId })
  if (error) mapRpcError(error, 'kpis')
  return data && data.length > 0 ? data[0] as Customer360Kpis : null
}

export async function getCustomer360SalesByMonth(customerId: string, months = 18): Promise<CustomerSalesByMonth[]> {
  const { data, error } = await supabase.rpc('get_customer_sales_by_month', {
    p_customer_id: customerId,
    p_months: months
  })
  if (error) mapRpcError(error, 'sales_by_month')
  return (data || []) as CustomerSalesByMonth[]
}

export async function getCustomer360TopProducts(customerId: string, limit = 15): Promise<CustomerTopProduct[]> {
  const { data, error } = await supabase.rpc('get_customer_top_products', {
    p_customer_id: customerId,
    p_limit: limit
  })
  if (error) mapRpcError(error, 'top_products')
  return (data || []) as CustomerTopProduct[]
}

export async function getCustomer360CategoryMix(customerId: string): Promise<CustomerCategoryMix[]> {
  const { data, error } = await supabase.rpc('get_customer_category_mix', { p_customer_id: customerId })
  if (error) mapRpcError(error, 'category_mix')
  return (data || []) as CustomerCategoryMix[]
}

export async function getCustomer360ArAging(customerId: string): Promise<CustomerArAgingBucket[]> {
  const { data, error } = await supabase.rpc('get_customer_ar_aging', { p_customer_id: customerId })
  if (error) mapRpcError(error, 'ar_aging')
  return (data || []) as CustomerArAgingBucket[]
}

export async function getCustomer360PaymentBehavior(customerId: string): Promise<CustomerPaymentBehavior | null> {
  const { data, error } = await supabase.rpc('get_customer_payment_behavior', { p_customer_id: customerId })
  if (error) mapRpcError(error, 'payment_behavior')
  return data && data.length > 0 ? data[0] as CustomerPaymentBehavior : null
}

export async function getCustomer360Timeline(
  customerId: string,
  params?: { limit?: number; before_ts?: string | null; before_id?: string | null }
): Promise<CustomerTimelineEvent[]> {
  const { data, error } = await supabase.rpc('get_customer_unified_timeline', {
    p_customer_id: customerId,
    p_limit: params?.limit || 30,
    p_before_ts: params?.before_ts || null,
    p_before_id: params?.before_id || null
  })
  if (error) mapRpcError(error, 'timeline')
  return (data || []) as CustomerTimelineEvent[]
}

export async function getCustomer360Ledger(
  customerId: string,
  params?: { limit?: number; before_ts?: string | null; before_id?: string | null }
): Promise<CustomerLedgerEntry[]> {
  const { data, error } = await supabase.rpc('get_customer_ledger_with_balance', {
    p_customer_id: customerId,
    p_limit: params?.limit || 15,
    p_before_ts: params?.before_ts || null,
    p_before_id: params?.before_id || null   // deterministic cursor: second dimension
  })
  if (error) mapRpcError(error, 'ledger')
  return (data || []) as CustomerLedgerEntry[]
}

export async function getCustomer360HealthSnapshot(customerId: string): Promise<CustomerHealthSnapshot | null> {
  const { data, error } = await supabase.rpc('get_customer_360_health_snapshot', { p_customer_id: customerId })
  if (error) mapRpcError(error, 'health_snapshot')
  return data && data.length > 0 ? data[0] as CustomerHealthSnapshot : null
}

export async function getCustomer360RiskSnapshot(customerId: string): Promise<CustomerRiskSnapshot | null> {
  const { data, error } = await supabase.rpc('get_customer_360_risk_snapshot', { p_customer_id: customerId })
  if (error) mapRpcError(error, 'risk_snapshot')
  return data && data.length > 0 ? data[0] as CustomerRiskSnapshot : null
}

export async function getCustomer360Profitability(
  params: CustomerProfitabilityFilterParams
): Promise<GrossProfitGrainResult[] | null> {
  try {
    return await getCustomerProfitability(params)
  } catch (error: unknown) {
    const err = error as Error
    if (err?.name === 'AnalyticsUnauthorizedError' || err?.message?.includes('unauthorized')) {
      return null
    }
    throw error
  }
}
