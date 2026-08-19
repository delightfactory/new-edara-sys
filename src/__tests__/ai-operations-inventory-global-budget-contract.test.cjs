import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817007200_ai_operations_inventory_global_budget_actionability.sql',
), 'utf8')

describe('AI Operations Inventory global budget/actionability contract', () => {
  it('preserves the three-domain builder and allocates four domains under one hard budget', () => {
    expect(migration).toContain('RENAME TO build_operational_snapshot_three_domain_v1')
    expect(migration).toContain("ARRAY['receivables','sales','customer_health','inventory']::TEXT[]")
    expect(migration).toContain("'inventory',v_inventory_demand")
    expect(migration).toContain('v_existing_domain_budget:=v_credit_alloc+v_sales_alloc+v_customer_alloc')
    expect(migration).toContain('v_total_cases>v_limit')
  })

  it('does not compare domain-specific severity to distribute global capacity', () => {
    const start = migration.indexOf('CREATE OR REPLACE FUNCTION ai_ops.build_operational_snapshot')
    const end = migration.indexOf('REVOKE ALL ON FUNCTION ai_ops.build_operational_snapshot')
    const builder = migration.slice(start, end)
    expect(builder).toContain('ai_ops.allocate_domain_case_budget')
    expect(builder).not.toMatch(/ORDER BY[^;]*severity/is)
    expect(builder).toContain('v_remaining:=GREATEST(v_limit-v_existing_cases,0)')
  })

  it('writes an explicit zero-capacity marker instead of pretending Inventory had no demand', () => {
    expect(migration).toContain("'global_budget_exhausted',v_inventory_has_candidate")
    expect(migration).toContain("'allocated_case_limit',0")
    expect(migration).toContain("'has_more',v_inventory_has_candidate")
    expect(migration).toContain("'inventory','inventory-v1'")
  })

  it('extends bounded-partial actionability only to the trusted inventory-v1 capture contract', () => {
    expect(migration).toContain('RENAME TO selected_case_capture_allows_action_three_domain_v1')
    expect(migration).toContain("IF v_domain<>'inventory' THEN")
    expect(migration).toContain("v_capture_version<>'inventory-v1'")
    expect(migration).toContain("v_snapshot_status<>'ready'")
    expect(migration).toContain("v_capture_status NOT IN ('completed','partial')")
    expect(migration).toContain("v_metadata->'global_budget_exhausted'")
    expect(migration).toContain("AND (v_metadata ? 'case_limit')")
  })

  it('keeps frozen evidence accounting fail closed', () => {
    expect(migration).toContain('v_capture_source_as_of IS DISTINCT FROM v_snapshot_data_as_of')
    expect(migration).toContain('v_case_source_as_of IS DISTINCT FROM v_snapshot_data_as_of')
    expect(migration).toContain('v_frozen_domain_case_count IS DISTINCT FROM v_capture_case_count')
    expect(migration).toContain('v_frozen_domain_evidence_bytes IS DISTINCT FROM v_capture_evidence_bytes')
  })

  it('does not expose new orchestration primitives to generic API roles', () => {
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.build_operational_snapshot(UUID,INTEGER)')
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.selected_case_capture_allows_action(UUID)')
    expect(migration).not.toMatch(/GRANT\s+EXECUTE/i)
  })
})
