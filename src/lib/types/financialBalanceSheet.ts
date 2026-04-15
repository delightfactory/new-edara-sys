// ============================================================
// Financial Balance Sheet — TypeScript Types
// ============================================================

export interface BalanceSheetSection {
  codes: string[]
  total: number
  label: string
}

export interface BalanceSheetData {
  total_assets: number
  total_liabilities: number
  total_equity_gl: number
  unclosed_pnl_to_date: number
  net_profit_current_period: number
  balance_check: boolean
  balance_diff: number
  sections: {
    cash: BalanceSheetSection
    receivables: BalanceSheetSection
    inventory: BalanceSheetSection
    custody: BalanceSheetSection
    other_assets: BalanceSheetSection
    payables: BalanceSheetSection
    tax_payable: BalanceSheetSection
    employee_liabilities: BalanceSheetSection
    capital: BalanceSheetSection
    retained_earnings: BalanceSheetSection
  }
}

export interface IncomeStatementData {
  gross_revenue: number
  sales_returns: number
  sales_discounts: number
  net_revenue: number
  cogs: number
  gross_profit: number
  gross_margin_pct: number
  operating_expenses: number
  payroll_expenses: number
  inventory_adjustments: number
  rounding_diffs: number
  total_expenses: number
  net_profit: number
  net_margin_pct: number
}

export type RatioStatus = 'excellent' | 'good' | 'warning' | 'critical'

export interface HealthIndicators {
  current_assets: number
  current_liabilities: number
  current_ratio: number | null
  current_ratio_status: RatioStatus
  quick_assets: number
  quick_ratio: number | null
  quick_ratio_status: RatioStatus
  working_capital: number
  debt_to_equity: number | null
  debt_to_equity_status: RatioStatus
  cash_position: number
  ar_total: number
  ap_total: number
  inventory_value: number
}

export interface FinancialSummary {
  as_of_date: string
  period_start: string
  balance_sheet: BalanceSheetData
  income_statement: IncomeStatementData
  health_indicators: HealthIndicators
}

export interface TrialBalanceEntry {
  account_id: string
  account_code: string
  account_name: string
  account_name_en: string | null
  account_type: string
  parent_code: string | null
  depth: number
  total_debit: number
  total_credit: number
  net_balance: number
  is_leaf: boolean
}
