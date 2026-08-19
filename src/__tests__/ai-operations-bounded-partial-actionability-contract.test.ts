import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const gateMigration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817006900_ai_operations_bounded_partial_actionability.sql',
), 'utf8')

const budgetMigration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817006600_ai_operations_generic_domain_budget_customer_health.sql',
), 'utf8')

const executableBudgetSql = budgetMigration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations bounded partial capture actionability contract', () => {
  it('uses one shared fail-closed gate for Sales and Customer Health', () => {
    expect(gateMigration).toContain('CREATE OR REPLACE FUNCTION ai_ops.selected_case_capture_allows_action')
    expect(gateMigration).toContain('CREATE OR REPLACE FUNCTION ai_ops.apply_selected_case_capture_actionability')
    expect(gateMigration).toContain('ai_ops.current_sales_target_decision_issues_pre_bounded_v1(p_decision_id)')
    expect(gateMigration).toContain('ai_ops.current_customer_health_decision_issues_pre_bounded_v1(p_decision_id)')

    const sharedGateCalls = gateMigration.match(/ai_ops\.apply_selected_case_capture_actionability\(/g) ?? []
    expect(sharedGateCalls.length).toBeGreaterThanOrEqual(3)
  })

  it('trusts bounded partial semantics only for the explicitly known capture versions', () => {
    expect(gateMigration).toContain("(v_domain = 'sales' AND v_capture_version = 'sales-target-gap-v1')")
    expect(gateMigration).toContain("(v_domain = 'customer_health' AND v_capture_version = 'customer-health-v1')")
    expect(gateMigration).toContain("IF v_snapshot_status <> 'ready' THEN")
    expect(gateMigration).toContain("IF v_capture_status NOT IN ('completed','partial') THEN")
  })

  it('allows a selected case through a partial capture only when truncation is bounded-selection-only', () => {
    expect(gateMigration).toContain("v_capture_status = 'partial'")
    expect(gateMigration).toContain("COALESCE(v_metadata->'has_more', 'false'::JSONB) = 'true'::JSONB")
    expect(gateMigration).toContain("(v_metadata ? 'case_limit')")
    expect(gateMigration).toContain("COALESCE(v_metadata->'global_budget_exhausted', 'false'::JSONB) = 'true'::JSONB")
    expect(gateMigration).toContain("e.value <> to_jsonb('snapshot_not_complete_for_action'::TEXT)")
  })

  it('keeps source, blocked, malformed and structurally incomplete evidence fail closed', () => {
    expect(gateMigration).toContain('v_capture_source_as_of IS DISTINCT FROM v_snapshot_data_as_of')
    expect(gateMigration).toContain('v_case_source_as_of IS DISTINCT FROM v_snapshot_data_as_of')
    expect(gateMigration).toContain('v_capture_business_date IS DISTINCT FROM v_run_business_date')
    expect(gateMigration).toContain('v_frozen_domain_case_count IS DISTINCT FROM v_capture_case_count')
    expect(gateMigration).toContain('v_frozen_domain_evidence_bytes IS DISTINCT FROM v_capture_evidence_bytes')
    expect(gateMigration).toContain("v_reasons := v_reasons || jsonb_build_array('snapshot_not_complete_for_action')")
  })

  it('cannot make a zero-capacity budget-exhausted domain actionable', () => {
    expect(budgetMigration).toContain("'global_budget_exhausted',v_customer_has_candidate")
    expect(budgetMigration).toContain("'allocated_case_limit',0")
    expect(budgetMigration).toContain("'has_more',v_customer_has_candidate")
    expect(gateMigration).toContain('COALESCE(v_capture_case_count, 0) <= 0')
    expect(gateMigration).toContain("v_metadata->'global_budget_exhausted'")
  })

  it('preserves every non-coverage current-state issue while filtering only the coverage issue', () => {
    expect(gateMigration).toContain('Remove only the coverage-level issue')
    expect(gateMigration).toContain("e.value <> to_jsonb('snapshot_not_complete_for_action'::TEXT)")
    expect(gateMigration).not.toContain("e.value <> to_jsonb('sales_progress_stale_for_action'::TEXT)")
    expect(gateMigration).not.toContain("e.value <> to_jsonb('sales_contribution_parity_failed'::TEXT)")
    expect(gateMigration).not.toContain("e.value <> to_jsonb('active_work_collision_now'::TEXT)")
  })

  it('rebuilds the canonical dispatcher with Receivables unchanged and both new domains gated', () => {
    expect(gateMigration).toContain("WHEN 'receivables' THEN")
    expect(gateMigration).toContain('ai_ops.current_decision_issues_credit_v1(p_decision_id)')
    expect(gateMigration).toContain("WHEN 'sales' THEN")
    expect(gateMigration).toContain('ai_ops.current_sales_target_decision_issues(p_decision_id)')
    expect(gateMigration).toContain("WHEN 'customer_health' THEN")
    expect(gateMigration).toContain('ai_ops.current_customer_health_decision_issues(p_decision_id)')
    expect(gateMigration).toContain("'unsupported_validation_domain'")
  })

  it('keeps the allocator domain-neutral with no cross-domain severity comparison', () => {
    const allocatorStart = executableBudgetSql.indexOf(
      'CREATE OR REPLACE FUNCTION ai_ops.allocate_domain_case_budget',
    )
    const allocatorEnd = executableBudgetSql.indexOf(
      'REVOKE ALL ON FUNCTION ai_ops.allocate_domain_case_budget',
    )
    expect(allocatorStart).toBeGreaterThan(-1)
    expect(allocatorEnd).toBeGreaterThan(allocatorStart)

    const allocatorSql = executableBudgetSql.slice(allocatorStart, allocatorEnd)
    expect(allocatorSql).not.toMatch(/\bseverity\b/i)
    expect(allocatorSql).toContain('FOREACH v_domain IN ARRAY p_domain_order LOOP')
    expect(allocatorSql).toContain('v_allocated<v_demand')
  })

  it('keeps all new guard primitives closed to generic API roles', () => {
    for (const signature of [
      'ai_ops.current_sales_target_decision_issues_pre_bounded_v1(UUID)',
      'ai_ops.current_customer_health_decision_issues_pre_bounded_v1(UUID)',
      'ai_ops.selected_case_capture_allows_action(UUID)',
      'ai_ops.apply_selected_case_capture_actionability(UUID, JSONB)',
      'ai_ops.current_sales_target_decision_issues(UUID)',
      'ai_ops.current_customer_health_decision_issues(UUID)',
      'ai_ops.current_decision_issues(UUID)',
    ]) {
      expect(gateMigration).toContain(`REVOKE ALL ON FUNCTION ${signature}`)
    }
    expect(gateMigration).not.toMatch(/GRANT\s+EXECUTE/i)
  })
})
