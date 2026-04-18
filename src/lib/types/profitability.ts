// ============================================================================
// Profitability Analytics Types (Phase 1, 2, 3)
// ============================================================================

export interface ProfitabilityFilterParams {
  date_from: string;
  date_to: string;
  branch_id?: string | null;
}

export interface GranularProfitabilityFilterParams extends ProfitabilityFilterParams {
  granularity?: 'daily' | 'weekly' | 'monthly' | 'quarterly' | 'yearly' | 'aggregate';
  limit_count?: number;
  customer_id?: string | null;
}

/**
 * Granularity values accepted by analytics_gross_profit_by_customer (migration 100).
 * Narrower than the full GranularProfitabilityFilterParams.granularity union.
 */
export type CustomerProfitabilityGranularity = 'aggregate' | 'daily' | 'monthly'

/**
 * Filter params for the customer-specific profitability path.
 * Uses CustomerProfitabilityGranularity to prevent passing granularity values
 * ('weekly', 'quarterly', 'yearly') that analytics_gross_profit_by_customer rejects at runtime.
 * Other profitability functions (getProfitTrend, getGrossProfitByProduct, etc.) keep
 * using the broader GranularProfitabilityFilterParams.
 */
export interface CustomerProfitabilityFilterParams extends ProfitabilityFilterParams {
  customer_id: string;                          // required (not optional) for customer path
  granularity?: CustomerProfitabilityGranularity;
  limit_count?: number;
}


// ----------------------------------------------------------------------------
// Phase 1 Results
// ----------------------------------------------------------------------------

export interface ProfitSummaryResult {
  net_revenue: number;
  cogs: number;
  gross_profit: number;
  operating_expenses: number;
  payroll_expenses: number;
  net_profit: number;
}

export interface ProfitTrendResult {
  period: string; // The RPC returns 'period' not 'date'
  gross_profit: number;
  net_profit: number;
}

// ----------------------------------------------------------------------------
// Phase 2 Results
// ----------------------------------------------------------------------------

// product_id, customer_id, rep_id depend on the RPC called
export interface GrossProfitGrainResult {
  period: string;
  product_id?: string | null;
  customer_id?: string | null;
  rep_id?: string | null;
  product_name?: string;
  customer_name?: string;
  rep_name?: string;
  gross_revenue: number;
  net_cogs: number;
  gross_profit: number;
  net_quantity: number;
}

export interface BranchDirectProfitResult {
  branch_id: string;
  branch_name?: string;
  gross_revenue: number;
  gross_cogs: number;
  gross_profit: number;
  operating_expense: number;
  payroll_expense: number;
  net_profit: number;
}

export interface BranchProfitTrendResult {
  period: string; // The backend uses column 'period' or 'period_start' (typically period)
  branch_id: string;
  gross_profit: number;
  net_profit: number;
}

// ----------------------------------------------------------------------------
// Phase 3 Results
// ----------------------------------------------------------------------------

export interface BranchFinalNetProfitResult {
  month_start: string;
  branch_id: string | null;
  branch_name?: string;
  direct_gross_revenue: number;
  direct_gross_cogs: number;
  direct_gross_profit: number;
  direct_operating_exp: number;
  direct_payroll_exp: number;
  allocated_shared_op: number;
  allocated_shared_pay: number;
  unallocated_shared_op: number;
  unallocated_shared_pay: number;
  final_net_profit: number;
  is_estimated: boolean;
  allocation_status: string;
}

export interface AllocationQualityReportResult {
  check_date: string;
  check_month: string;
  applies_to: string;
  check_type: string;
  severity: 'INFO' | 'WARNING' | 'ERROR';
  record_count: number;
  detail: Record<string, any>;
  created_at: string;
}
