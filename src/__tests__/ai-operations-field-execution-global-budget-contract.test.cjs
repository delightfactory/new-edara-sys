import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817007700_ai_operations_field_execution_global_budget_actionability.sql',
), 'utf8')

describe('AI Operations Field Execution global budget/actionability contract', () => {
  it('adds Field Execution as a fifth domain under the same hard allocator', () => {
    expect(migration).toContain("ARRAY['receivables','sales','customer_health','inventory','field_execution']::TEXT[]")
    expect(migration).toContain("'field_execution',v_field_demand")
    expect(migration).toContain('v_existing_domain_budget:=v_credit_alloc+v_sales_alloc+v_customer_alloc+v_inventory_alloc')
    expect(migration).toContain('build_operational_snapshot_four_domain_v1')
  })

  it('records a zero-capacity immutable partial marker instead of pretending no demand', () => {
    expect(migration).toContain("'global_budget_exhausted',v_field_has_candidate")
    expect(migration).toContain("'allocated_case_limit',0")
    expect(migration).toContain("'case_limit',0")
    expect(migration).toContain("'has_more',v_field_has_candidate")
  })

  it('will not append a new domain after worker context identity is bound', () => {
    expect(migration).toContain("result_summary->>'worker_context_hash'")
    expect(migration).toContain('cannot add Field Execution')
  })

  it('extends bounded-partial actionability only for field-execution-v1 and delegates every older domain', () => {
    expect(migration).toContain('selected_case_capture_allows_action_four_domain_v1')
    expect(migration).toContain("IF v_domain<>'field_execution' THEN")
    expect(migration).toContain('RETURN ai_ops.selected_case_capture_allows_action_four_domain_v1(p_decision_id)')
    expect(migration).toContain("v_capture_version<>'field-execution-v1'")
  })

  it('keeps zero-budget, blocked, mismatched and structurally incomplete evidence fail closed', () => {
    expect(migration).toContain("v_snapshot_status<>'ready'")
    expect(migration).toContain('v_capture_source_as_of IS DISTINCT FROM v_snapshot_data_as_of')
    expect(migration).toContain('v_frozen_domain_case_count IS DISTINCT FROM v_capture_case_count')
    expect(migration).toContain("v_metadata->'global_budget_exhausted'")
    expect(migration).toContain("COALESCE(NULLIF(v_metadata->>'case_limit','')::INTEGER,0)>0")
  })

  it('keeps new primitives closed to generic API roles', () => {
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.build_operational_snapshot(UUID,INTEGER)')
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.selected_case_capture_allows_action(UUID)')
    expect(migration).toContain('FROM PUBLIC,anon,authenticated,service_role')
    expect(migration).not.toMatch(/GRANT\s+EXECUTE/i)
  })
})
