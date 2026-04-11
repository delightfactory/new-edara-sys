import { supabase } from '@/lib/supabase/client'
import { AnalyticsNotDeployedError, AnalyticsUnauthorizedError } from './analyticsClient'
import type { 
  ProfitSummaryResult, 
  ProfitTrendResult, 
  GrossProfitGrainResult, 
  BranchDirectProfitResult, 
  BranchProfitTrendResult, 
  BranchFinalNetProfitResult,
  AllocationQualityReportResult,
  ProfitabilityFilterParams,
  GranularProfitabilityFilterParams
} from '@/lib/types/profitability'

// Helper to map errors precisely matching the analytics client logic
function mapRpcError(error: { message?: string; code?: string } | null, domain?: string): never {
  const msg = error?.message ?? ''
  if (msg.includes('analytics_not_deployed') || msg.includes('undefined_table') || msg.includes('NOT_DEPLOYED')) {
    throw new AnalyticsNotDeployedError(msg)
  }
  if (msg.includes('analytics_unauthorized') || msg.includes('Access denied')) {
    throw new AnalyticsUnauthorizedError(domain)
  }
  throw new Error(`Analytics service error: ${msg || error?.code || 'Unknown RPC failure'}`)
}

// --------------------------------------------------------------------------------
// Phase 1: Summary & Trends
// --------------------------------------------------------------------------------

export async function getProfitSummary({ date_from, date_to }: ProfitabilityFilterParams): Promise<ProfitSummaryResult | null> {
  const { data, error } = await supabase.rpc('analytics_profit_summary', { date_from, date_to })
  if (error) mapRpcError(error, 'profit_summary')
  return data ? (data as ProfitSummaryResult) : null
}

export async function getProfitTrend({ date_from, date_to, granularity = 'daily' }: GranularProfitabilityFilterParams): Promise<ProfitTrendResult[]> {
  const { data, error } = await supabase.rpc('analytics_profit_trend', { date_from, date_to, granularity })
  if (error) mapRpcError(error, 'profit_trend')
  return (data as ProfitTrendResult[]) || []
}

// --------------------------------------------------------------------------------
// Phase 2: Gross Profit Granular & Branch Direct Net Profit
// --------------------------------------------------------------------------------

export async function getGrossProfitByProduct({ date_from, date_to, branch_id, granularity = 'daily', limit_count = 100 }: GranularProfitabilityFilterParams): Promise<GrossProfitGrainResult[]> {
  const { data, error } = await supabase.rpc('analytics_gross_profit_by_product', {
    date_from,
    date_to,
    p_branch_id: branch_id || null,
    p_granularity: granularity,
    p_limit_count: limit_count,
  })
  if (error) mapRpcError(error, 'gross_profit_product')
  
  const results = (data as GrossProfitGrainResult[]) || []
  if (results.length > 0) {
    const ids = Array.from(new Set(results.map(r => r.product_id).filter(Boolean))) as string[]
    if (ids.length > 0) {
      const { data: dict } = await supabase.from('products').select('id, name').in('id', ids)
      if (dict) {
        results.forEach(r => {
          r.product_name = dict.find(d => d.id === r.product_id)?.name
        })
      }
    }
  }
  return results
}

export async function getGrossProfitByCustomer({ date_from, date_to, branch_id, granularity = 'daily', limit_count = 100 }: GranularProfitabilityFilterParams): Promise<GrossProfitGrainResult[]> {
  const { data, error } = await supabase.rpc('analytics_gross_profit_by_customer', {
    date_from,
    date_to,
    p_branch_id: branch_id || null,
    p_granularity: granularity,
    p_limit_count: limit_count,
  })
  if (error) mapRpcError(error, 'gross_profit_customer')

  const results = (data as GrossProfitGrainResult[]) || []
  if (results.length > 0) {
    const ids = Array.from(new Set(results.map(r => r.customer_id).filter(Boolean))) as string[]
    if (ids.length > 0) {
      const { data: dict } = await supabase.from('customers').select('id, name').in('id', ids)
      if (dict) {
        results.forEach(r => {
          r.customer_name = dict.find(d => d.id === r.customer_id)?.name
        })
      }
    }
  }
  return results
}

export async function getGrossProfitByRep({ date_from, date_to, branch_id, granularity = 'daily', limit_count = 100 }: GranularProfitabilityFilterParams): Promise<GrossProfitGrainResult[]> {
  const { data, error } = await supabase.rpc('analytics_gross_profit_by_rep', {
    date_from,
    date_to,
    p_branch_id: branch_id || null,
    p_granularity: granularity,
    p_limit_count: limit_count,
  })
  if (error) mapRpcError(error, 'gross_profit_rep')

  const results = (data as GrossProfitGrainResult[]) || []
  if (results.length > 0) {
    const ids = Array.from(new Set(results.map(r => r.rep_id).filter(Boolean))) as string[]
    if (ids.length > 0) {
      const { data: dict } = await supabase.from('profiles').select('id, full_name').in('id', ids)
      if (dict) {
        results.forEach(r => {
          r.rep_name = dict.find(d => d.id === r.rep_id)?.full_name
        })
      }
    }
  }
  return results
}

export async function getBranchDirectNetProfit({ date_from, date_to, branch_id }: ProfitabilityFilterParams): Promise<BranchDirectProfitResult[]> {
  const { data, error } = await supabase.rpc('analytics_branch_direct_net_profit', {
    date_from,
    date_to,
    p_branch_id: branch_id || null,
  })
  if (error) mapRpcError(error, 'branch_direct_net_profit')

  const results = (data as BranchDirectProfitResult[]) || []
  if (results.length > 0) {
    const ids = Array.from(new Set(results.map(r => r.branch_id).filter(Boolean))) as string[]
    if (ids.length > 0) {
      const { data: dict } = await supabase.from('branches').select('id, name').in('id', ids)
      if (dict) {
        results.forEach(r => {
          r.branch_name = dict.find(d => d.id === r.branch_id)?.name
        })
      }
    }
  }
  return results
}

// NOTE: getBranchDirectProfitTrend is not consumed by any UI page in this release.
// Retained as pre-built service coverage for a future branch trend chart.
export async function getBranchDirectProfitTrend({ date_from, date_to, branch_id, granularity = 'daily' }: GranularProfitabilityFilterParams): Promise<BranchProfitTrendResult[]> {
  const { data, error } = await supabase.rpc('analytics_branch_profit_trend', {
    date_from,
    date_to,
    p_branch_id: branch_id || null,
    p_granularity: granularity,
  })
  if (error) mapRpcError(error, 'branch_profit_trend')
  return (data as BranchProfitTrendResult[]) || []
}

// --------------------------------------------------------------------------------
// Phase 3: Branch Final Allocation & Quality
// --------------------------------------------------------------------------------

export async function getBranchFinalNetProfitMonthly({ date_from, date_to, branch_id }: ProfitabilityFilterParams): Promise<BranchFinalNetProfitResult[]> {
  const { data, error } = await supabase.rpc('analytics_branch_final_net_profit_monthly', {
    date_from, date_to, p_branch_id: branch_id || null
  })
  if (error) mapRpcError(error, 'branch_final_net_profit')

  const results = (data as BranchFinalNetProfitResult[]) || []
  if (results.length > 0) {
    const ids = Array.from(new Set(results.map(r => r.branch_id).filter(Boolean))) as string[]
    if (ids.length > 0) {
      const { data: dict } = await supabase.from('branches').select('id, name').in('id', ids)
      if (dict) {
        results.forEach(r => {
          r.branch_name = dict.find(d => d.id === r.branch_id)?.name
        })
      }
    }
  }
  return results
}

export async function getAllocationQualityReport({ date_from, date_to }: ProfitabilityFilterParams): Promise<AllocationQualityReportResult[]> {
  const { data, error } = await supabase.rpc('analytics_allocation_quality_report', {
    date_from, date_to
  })
  if (error) mapRpcError(error, 'allocation_quality')
  return (data as AllocationQualityReportResult[]) || []
}
