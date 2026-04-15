import { supabase } from '@/lib/supabase/client'
import type { FinancialSummary, TrialBalanceEntry } from '@/lib/types/financialBalanceSheet'

/**
 * جلب الملخص المالي: Balance Sheet + Income Statement + Health KPIs
 */
export async function fetchFinancialSummary(
  asOfDate: string,
  periodStart?: string
): Promise<FinancialSummary> {
  const { data, error } = await supabase.rpc('get_financial_summary', {
    p_as_of_date: asOfDate,
    p_period_start: periodStart || null,
  })
  if (error) throw error
  return data as FinancialSummary
}

/**
 * جلب ميزان المراجعة التفصيلي
 */
export async function fetchTrialBalanceDetail(
  asOfDate: string,
  showParents: boolean
): Promise<TrialBalanceEntry[]> {
  const { data, error } = await supabase.rpc('get_trial_balance_detail', {
    p_as_of_date: asOfDate,
    p_show_parents: showParents,
  })
  if (error) throw error
  return (data || []) as TrialBalanceEntry[]
}
