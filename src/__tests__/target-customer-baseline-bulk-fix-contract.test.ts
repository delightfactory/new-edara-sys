import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(
  'supabase/migrations/20260802100600_fix_target_customer_baselines_and_bulk_candidates.sql',
  'utf8',
)
const service = readFileSync('src/lib/services/targets.ts', 'utf8')
const form = readFileSync('src/pages/activities/TargetForm.tsx', 'utf8')

function functionBody(name: string) {
  const start = migration.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`)
  expect(start).toBeGreaterThanOrEqual(0)
  const end = migration.indexOf('\n$$;', start)
  expect(end).toBeGreaterThan(start)
  return migration.slice(start, end)
}

describe('customer target baseline and bulk candidate correction', () => {
  it('keeps customer state global while target achievement remains scope-attributed', () => {
    const createBody = functionBody('create_target_with_rewards')
    const progressBody = functionBody('target_customer_progress_rows')

    const baselineSection = createBody.slice(createBody.indexOf("IF v_type_code = 'upgrade_value'"))
    expect(baselineSection).toContain('analytics.effective_sale_date')
    expect(baselineSection).not.toContain('he.id = ANY(v_employee_ids)')
    expect(progressBody).toContain('he.id = ANY(v_employee_ids)')
  })

  it('freezes baseline category ids and counts only genuinely new categories', () => {
    expect(migration).toContain('ADD COLUMN IF NOT EXISTS baseline_category_ids UUID[]')
    expect(migration).toContain('ARRAY_AGG(DISTINCT p.category_id ORDER BY p.category_id)')
    expect(migration).toContain('p.category_id = ANY(COALESCE(selected.baseline_category_ids')
    expect(migration).toContain('تصنيفات جديدة')
  })

  it('uses the Cairo-aware canonical sale date for all corrected calculations', () => {
    expect(migration).toContain('analytics.effective_sale_date(so.delivered_at, so.order_date)')
    expect(functionBody('get_target_customer_candidates')).not.toContain('so.delivered_at::DATE')
  })

  it('provides one permission-checked, filterable server candidate endpoint', () => {
    const body = functionBody('get_target_customer_candidates')
    expect(body).toContain("check_permission(auth.uid(), 'targets.read_all')")
    expect(body).toContain("check_permission(auth.uid(), 'targets.create')")
    expect(body).toContain('p_employee_id')
    expect(body).toContain('p_governorate_id')
    expect(body).toContain('p_baseline_min')
    expect(body).toContain('regexp_split_to_table')
    expect(body).toContain('COUNT(*) OVER() AS total_count')
  })

  it('keeps function execution least-privileged and confirms authenticated target creation', () => {
    expect(migration).toMatch(/REVOKE ALL ON FUNCTION public\.get_target_customer_candidates[\s\S]*FROM PUBLIC, anon;/)
    expect(migration).toMatch(/GRANT EXECUTE ON FUNCTION public\.get_target_customer_candidates[\s\S]*TO authenticated;/)
    expect(migration).toMatch(/REVOKE ALL ON FUNCTION public\.create_target_with_rewards[\s\S]*FROM PUBLIC, anon;/)
    expect(migration).toMatch(/GRANT EXECUTE ON FUNCTION public\.create_target_with_rewards[\s\S]*TO authenticated;/)
    expect(functionBody('create_target_with_rewards')).toContain('v_caller_id := auth.uid()')
    expect(functionBody('create_target_with_rewards')).toContain("check_permission(v_caller_id, 'targets.create')")
    expect(functionBody('create_target_with_rewards')).toContain('العميل [%] لا ينتمي إلى نطاق الهدف المحدد')
  })

  it('does not mutate or constrain operational sales and return tables', () => {
    expect(migration).not.toMatch(/(?:ALTER|UPDATE|DELETE FROM|INSERT INTO)\s+public\.sales_orders/i)
    expect(migration).not.toMatch(/(?:ALTER|UPDATE|DELETE FROM|INSERT INTO)\s+public\.sales_order_items/i)
    expect(migration).not.toMatch(/(?:ALTER|UPDATE|DELETE FROM|INSERT INTO)\s+public\.sales_returns/i)
  })

  it('wires all filters and bulk selection through the service and responsive form', () => {
    expect(service).toContain("supabase.rpc('get_target_customer_candidates'")
    expect(service).toContain('p_employee_id: params.employeeId || null')
    expect(service).toContain('p_page_size: pageSize')
    expect(form).toContain('اختيار النتائج المعروضة')
    expect(form).toContain('tf-candidate-filters')
    expect(form).toContain("@media (max-width: 600px)")
    expect(form).toContain(".tf-candidate-row { grid-template-columns: auto minmax(0, 1fr);")
  })
})
