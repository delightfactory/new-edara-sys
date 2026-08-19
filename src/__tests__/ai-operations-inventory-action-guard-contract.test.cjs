import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817007300_ai_operations_inventory_current_state_guard.sql',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations Inventory current-state guard contract', () => {
  it('re-runs the exact deterministic Inventory candidate kernel', () => {
    expect(migration).toContain('FROM ai_ops.inventory_candidates(v_business_date,2000) c')
    expect(migration).toContain('c.case_key=v_sc.case_key')
    expect(migration).toContain("'inventory_case_no_longer_current'")
  })

  it('fails closed on responsibility ambiguity or routing drift', () => {
    expect(migration).toContain("'inventory_responsibility_changed_after_snapshot'")
    expect(migration).toContain("'inventory_responsibility_ambiguous_or_unavailable'")
    expect(migration).toContain("'recommended_inventory_assignee_not_responsible_manager'")
  })

  it('rechecks shortage, supply-feasibility and transfer state before action', () => {
    expect(migration).toContain("'inventory_shortage_balance_or_demand_changed_after_snapshot'")
    expect(migration).toContain("'inventory_supply_feasibility_changed_after_snapshot'")
    expect(migration).toContain("'inventory_transfer_state_changed_after_snapshot'")
  })

  it('prevents duplicate Inventory Work and validates escalation continuity', () => {
    expect(migration).toContain("'active_inventory_shortage_work_collision_now'")
    expect(migration).toContain("'active_inventory_transfer_work_collision_now'")
    expect(migration).toContain("'linked_inventory_work_no_longer_active'")
    expect(migration).toContain("wl.entity_type='stock_transfer'")
  })

  it('passes Inventory through the shared bounded-partial gate and canonical dispatcher', () => {
    expect(migration).toContain('ai_ops.apply_selected_case_capture_actionability')
    expect(migration).toContain("dc.domain='inventory'")
    expect(migration).toContain("'snapshot_not_complete_for_action'")
    expect(migration).toContain("WHEN 'inventory' THEN RETURN ai_ops.current_inventory_decision_issues")
  })

  it('remains read-only against Inventory operational sources', () => {
    expect(executableSql).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:stock|stock_movements|stock_transfers|stock_transfer_items|warehouses|warehouse_managers|products|stock_batches|purchase_invoices|purchase_invoice_items)/i)
  })

  it('keeps guard primitives private', () => {
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.current_inventory_decision_issues_pre_bounded_v1(UUID)')
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.current_inventory_decision_issues(UUID)')
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.current_decision_issues(UUID)')
  })
})
