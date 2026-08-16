import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817003000_ai_operations_sales_target_case_engine.sql',
), 'utf8')

const sourceMap = readFileSync(resolve(
  process.cwd(),
  'docs/work-management/16_AI_OPERATIONS_SALES_TARGETS_SOURCE_MAP.md',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations Sales & Targets case engine contract', () => {
  it('is additive and keeps all new routines inside ai_ops', () => {
    expect(migration).toContain('DESIGN-TIME MIGRATION ONLY')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION ai_ops.sales_target_contribution_evidence')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION ai_ops.sales_target_candidates')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION ai_ops.refresh_sales_target_cases')
    expect(migration).not.toMatch(/CREATE\s+TABLE/i)
    expect(migration).not.toMatch(/ALTER\s+TABLE/i)
    expect(migration).not.toMatch(/CREATE\s+(?:UNIQUE\s+)?INDEX/i)
    expect(migration).not.toMatch(/CREATE\s+TRIGGER/i)
    expect(migration).not.toMatch(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(?:public|private)\./i)
  })

  it('consumes canonical target_progress without recalculating operational targets', () => {
    expect(migration).toContain('FROM public.target_progress tp')
    expect(migration).toContain('tp.snapshot_date = p_business_date')
    expect(migration).toContain("t.type_code IN ('sales_value', 'product_qty')")
    expect(migration).toContain("tp.trend::TEXT IN ('behind', 'at_risk')")
    expect(executableSql).not.toMatch(/recalculate_target_progress\s*\(/i)
    expect(sourceMap).toContain('AI Operations **must not recalculate or replace that authority**')
  })

  it('preserves delivery-date and return semantics from the deployed target engine', () => {
    expect(migration).toContain("so.status::TEXT IN ('delivered', 'completed')")
    expect(migration).toContain('so.delivered_at::DATE BETWEEN t.period_start AND p_business_date')
    expect(migration).toContain('GREATEST(so.total_amount - COALESCE(so.returned_amount, 0), 0)')
    expect(migration).toContain('soi.delivered_quantity - COALESCE(soi.returned_quantity, 0)')
    expect(migration).toContain("sr.status::TEXT = 'confirmed'")
    expect(migration).toContain('sri.order_item_id = soi.id')
    expect(sourceMap).toContain('It must never use order creation date as the official sales date')
  })

  it('requires contribution parity with the official target progress', () => {
    expect(migration).toContain("'official_achieved_value'")
    expect(migration).toContain("'parity_delta'")
    expect(migration).toContain("'parity_ok'")
    expect(migration).toContain('<= 0.01')
    expect(migration).toContain("'contribution_parity_ok'")
    expect(migration).toContain("'deterministic_target_contribution'")
  })

  it('keeps accountability, target assignment and contribution as separate evidence', () => {
    expect(migration).toContain("'target_individual_scope'")
    expect(migration).toContain("'department_manager_accountability'")
    expect(migration).toContain("'branch_manager_accountability'")
    expect(migration).toContain("'target_assigner_context_only'")
    expect(migration).toContain("'routing_rule', false")
    expect(migration).toContain("'top_contributors'")
    expect(sourceMap).toContain('Contribution is **driver evidence**, not blame')
  })

  it('does not claim activity causality when the activity baseline is incomplete', () => {
    expect(migration).toContain('FROM public.activities a')
    expect(migration).toContain('FROM public.visit_plans vp')
    expect(migration).toContain("'supporting_only_no_uniform_activity_baseline'")
    expect(migration).toContain("'causal_label', NULL")
    expect(migration).toContain("'causal_inference_allowed_without_reasoning', false")
    expect(sourceMap).toContain('must not deterministically label a department target gap as "low activity" or "poor conversion"')
  })

  it('detects exact active Work linked to the target instead of creating a parallel link model', () => {
    expect(migration).toContain('FROM public.work_links wl')
    expect(migration).toContain("wl.entity_type = 'target'")
    expect(migration).toContain('wl.entity_id = b.id')
    expect(migration).toContain("wi.status::TEXT NOT IN ('done', 'cancelled')")
    expect(migration).toContain("'existing_work_continuity'")
    expect(migration).not.toMatch(/CREATE\s+TABLE\s+(?:public\.)?work_(?:entity_)?links/i)
  })

  it('uses a stable target case key and bounded target types without mixing future domains', () => {
    expect(migration).toContain("'sales:target_trajectory_gap:' || b.id::TEXT")
    expect(migration).toContain("'sales'")
    expect(migration).toContain("'target_trajectory_gap'")
    expect(executableSql).not.toMatch(/type_code\s+IN\s*\([^)]*reactivation/i)
    expect(executableSql).not.toMatch(/type_code\s+IN\s*\([^)]*category_spread/i)
    expect(sourceMap).toContain('`reactivation` → Customer Health / Re-engagement')
  })

  it('never mutates Target, Sales, Activity, Visit, HR or Work sources', () => {
    const sourceTables = '(?:targets|target_progress|sales_orders|sales_order_items|activities|visit_plans|hr_employees|work_items|work_links)'
    expect(executableSql).not.toMatch(new RegExp(`UPDATE\\s+public\\.${sourceTables}`, 'i'))
    expect(executableSql).not.toMatch(new RegExp(`INSERT\\s+INTO\\s+public\\.${sourceTables}`, 'i'))
    expect(executableSql).not.toMatch(new RegExp(`DELETE\\s+FROM\\s+public\\.${sourceTables}`, 'i'))
    expect(migration).toContain('INSERT INTO ai_ops.cases')
    expect(migration).toContain("'target_recalculation_performed', false")
  })

  it('keeps all domain routines closed to browser and generic service roles', () => {
    const signatures = [
      'ai_ops.sales_target_contribution_evidence(UUID, DATE, INTEGER)',
      'ai_ops.sales_target_candidates(DATE, INTEGER)',
      'ai_ops.refresh_sales_target_cases(UUID, DATE, INTEGER)',
    ]

    for (const signature of signatures) {
      expect(migration).toContain(`REVOKE ALL ON FUNCTION ${signature} FROM PUBLIC;`)
      expect(migration).toContain(`REVOKE ALL ON FUNCTION ${signature} FROM anon;`)
      expect(migration).toContain(`REVOKE ALL ON FUNCTION ${signature} FROM authenticated;`)
      expect(migration).toContain(`REVOKE ALL ON FUNCTION ${signature} FROM service_role;`)
    }
  })
})
