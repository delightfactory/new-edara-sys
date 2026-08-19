import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817006400_ai_operations_customer_health_case_engine.sql',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations Customer Health case engine contract', () => {
  it('uses governed reactivation and category-spread target definitions instead of hard-coded campaign rules', () => {
    expect(migration).toContain("t.type_code='reactivation'")
    expect(migration).toContain("t.type_code='category_spread'")
    expect(migration).toContain("t.filter_criteria->>'min_reactivation_value'")
    expect(migration).toContain("t.filter_criteria->>'required_category_count'")
    expect(migration).toContain('t.dormancy_days')
    expect(migration).toContain('tc.baseline_period_end')
    expect(migration).toContain('tc.baseline_category_ids')
  })

  it('uses the deployed commercial-date contract and both legacy/current completed-sale statuses', () => {
    expect(migration).toContain('analytics.effective_sale_date(so.delivered_at,so.order_date)')
    expect(migration).toContain("so.status::TEXT IN ('delivered','completed')")
    expect(migration).toContain("'commercial_date_contract','analytics.effective_sale_date'")
  })

  it('creates a governed reactivation exception and a distinct top-value opportunity outside the plan', () => {
    expect(migration).toContain("'reactivation_gap'::TEXT")
    expect(migration).toContain("'exception'::TEXT AS attention_class")
    expect(migration).toContain("'high_value_reactivation_opportunity'::TEXT")
    expect(migration).toContain("'opportunity'::TEXT AS attention_class")
    expect(migration).toContain('rr.value_percentile>=0.90')
    expect(migration).toContain('NOT EXISTS (\n      SELECT 1 FROM reactivation_selected rs WHERE rs.customer_id=h.customer_id')
  })

  it('reuses Customer 360 semantics but explicitly rejects legacy fixed 45/90 labels as policy authority', () => {
    expect(migration).toContain("'customer_360_semantics_reused',true")
    expect(migration).toContain("'legacy_fixed_45_90_status_not_authoritative',true")
    expect(migration).toContain("'credit_interpretation','feasibility_evidence_not_customer_health_cause'")
  })

  it('includes structured interaction, category, credit and existing Work evidence without making them causal rules', () => {
    expect(migration).toContain('public.activities')
    expect(migration).toContain('public.visit_plan_items')
    expect(migration).toContain('public.call_plan_items')
    expect(migration).toContain("wl.entity_type='customer'")
    expect(migration).toContain("'category_spread'")
    expect(migration).toContain("'field_execution_interpretation','supporting_only_no_causal_inference'")
  })

  it('freezes accountability evidence without silently hard-routing Work', () => {
    expect(migration).toContain("'customer_assigned_rep'")
    expect(migration).toContain("'employee_direct_manager_context'")
    expect(migration).toContain("'reactivation_target_scope_accountability'")
    expect(migration).toContain("'routing_rule',false")
  })

  it('keeps customer contact PII out of worker facts', () => {
    expect(migration).toContain("'pii_excluded_from_worker_facts',true")
    expect(executableSql).not.toMatch(/\bc\.(?:phone|mobile|email|tax_number)\b/i)
  })

  it('is read-only against customer, sales, target, field execution, credit and Work sources', () => {
    expect(executableSql).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:customers|sales_orders|sales_order_items|targets|target_customers|target_progress|activities|visit_plans|visit_plan_items|call_plans|call_plan_items|customer_ledger|work_items|work_links)/i)
    expect(executableSql).not.toMatch(/recalculate_target_progress\s*\(/i)
  })

  it('keeps the deterministic candidate kernel private from browser/API roles', () => {
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.customer_health_candidates(DATE, INTEGER)')
    expect(migration).toContain('FROM PUBLIC, anon, authenticated, service_role')
  })
})