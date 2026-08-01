import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260801140911_improve_customer_target_axes_safely.sql',
), 'utf8')

describe('customer target axes migration contract', () => {
  it('does not mutate operational schemas or install operational triggers', () => {
    expect(migration).not.toMatch(/(?:ALTER|UPDATE|INSERT INTO|DELETE FROM)\s+public\.(?:sales_|purchase_|payment_|stock_)/i)
    expect(migration).not.toMatch(/CREATE\s+(?:CONSTRAINT\s+)?TRIGGER/i)
    expect(migration).not.toMatch(/CREATE OR REPLACE FUNCTION public\.(?:confirm_|deliver_|create_sales|approve_purchase)/i)
  })

  it('keeps the three axes customer-count based and server-calculated', () => {
    expect(migration).toContain("WHEN 'upgrade_value' THEN")
    expect(migration).toContain("WHEN 'reactivation' THEN")
    expect(migration).toContain("WHEN 'category_spread' THEN")
    expect(migration).not.toMatch(/WHEN\s+'[^']+'\s*,\s*'[^']+'/)
    expect(migration).toContain('FROM public.target_customer_progress_rows(p_target_id, v_calc_date)')
    expect(migration).toContain("p_target_value > v_customer_count")
    expect(migration).toContain("p_period <> 'monthly'")
  })

  it('attributes delivered net sales through the order representative and target scope', () => {
    const helperStart = migration.indexOf('CREATE OR REPLACE FUNCTION public.target_customer_progress_rows(')
    const helperEnd = migration.indexOf('REVOKE ALL ON FUNCTION public.target_customer_progress_rows', helperStart)
    const helper = migration.slice(helperStart, helperEnd)
    expect(helper).toContain("so.status IN ('delivered', 'completed')")
    expect(helper).toContain('GREATEST(so.total_amount - COALESCE(so.returned_amount, 0), 0)')
    expect(helper).toContain('JOIN public.hr_employees he ON he.user_id = so.rep_id')
    expect(helper).toContain('he.id = ANY(v_employee_ids)')
    expect(helper).toContain('WITH sales AS (')
    expect(helper).toContain('WITH category_sales AS (')
    expect(helper).not.toContain('LEFT JOIN LATERAL')
    expect(helper).not.toContain('assigned_rep_id')
  })

  it('freezes the intended baseline definitions during atomic creation', () => {
    expect(migration).toContain("date_trunc('month', v_start) - INTERVAL '3 months'")
    expect(migration).toContain("/ 3.0")
    expect(migration).toContain('v_last_purchase > v_start - p_dormancy_days')
    expect(migration).toContain("p_filter_criteria->>'required_category_count'")
    expect(migration).toContain("p_filter_criteria->>'min_reactivation_value'")
    expect(migration).toContain("محاور العملاء تتطلب شهراً تقويمياً كاملاً")
    expect(migration).toContain('IF CURRENT_DATE >= v_start THEN')
  })

  it('exposes only read-only customer detail and candidate endpoints', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.get_target_customer_progress(')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.get_reactivation_target_candidates(')
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.get_target_customer_progress(UUID, DATE) TO authenticated')
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.get_reactivation_target_candidates(TEXT, UUID, DATE, INTEGER, TEXT, INTEGER) TO authenticated')
  })

  it('keeps department target reads inside the caller branch', () => {
    expect(migration).toContain('CREATE POLICY tgt_read_department_team ON public.targets')
    expect(migration).toContain('CREATE POLICY tp_read_department_team ON public.target_progress')
    expect(migration).toContain("v_target.scope = 'department' AND EXISTS")
    expect(migration).toContain('WHERE id = v_target.scope_id AND branch_id = v_caller_branch')
  })
})
