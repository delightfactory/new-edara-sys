import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817007400_ai_operations_inventory_reviewed_work_bridge.sql',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations Inventory reviewed Work bridge contract', () => {
  it('supports the real stock-transfer entity in the shared Work link contract', () => {
    expect(migration).toContain("WHEN 'stock_transfer' THEN 'public.stock_transfers'")
    expect(migration).toContain("private.work_link_entity_exists('stock_transfer',v_transfer_id)")
    expect(migration).toContain("'stock_transfer',v_transfer_id,'primary'")
  })

  it('requires kill-switch clearance, human approval, immutable fingerprint and validated decision', () => {
    expect(migration).toContain('v_settings.planner_enabled')
    expect(migration).toContain('v_settings.shadow_mode')
    expect(migration).toContain("v_review.review_state<>'approved'")
    expect(migration).toContain("v_decision.validation_state<>'validated'")
    expect(migration).toContain('v_review.decision_fingerprint IS DISTINCT FROM v_fingerprint')
  })

  it('revalidates current state in the same transaction immediately before Work mutation', () => {
    const revalidation = migration.indexOf('v_issues:=ai_ops.current_decision_issues(p_decision_id)')
    const workInsert = migration.indexOf('INSERT INTO public.work_items')
    expect(revalidation).toBeGreaterThan(-1)
    expect(workInsert).toBeGreaterThan(revalidation)
    expect(migration).toContain("'current_state_changed'")
  })

  it('creates system-origin idempotent Work with employee-safe Inventory links', () => {
    expect(migration).toContain("v_source_key:='ai_ops:decision:'||p_decision_id::TEXT")
    expect(migration).toContain("'system'::public.work_source_kind")
    expect(migration).toContain("'product',v_product_id,'primary'")
    expect(migration).toContain("'warehouse',v_warehouse_id,'affected_at'")
    expect(migration).toContain("'warehouse',v_warehouse_id,'destination'")
    expect(migration).toContain("'management_rationale_exposed',false")
  })

  it('never mutates Inventory, product, warehouse, batch or purchasing records', () => {
    expect(executableSql).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:stock|stock_movements|stock_transfers|stock_transfer_items|warehouses|warehouse_managers|products|stock_batches|purchase_invoices|purchase_invoice_items)/i)
    expect(migration).toContain("'inventory_mutation_performed',false")
    expect(migration).toContain("'operational_mutation','work_create_only'")
  })

  it('extends the canonical reviewed Work dispatcher without replacing older domain logic', () => {
    expect(migration).toContain('RENAME TO work_create_ai_reviewed_task_three_domain_v1')
    expect(migration).toContain("IF v_domain='inventory' THEN")
    expect(migration).toContain('private.work_create_ai_reviewed_inventory_task')
    expect(migration).toContain('private.work_create_ai_reviewed_task_three_domain_v1')
  })

  it('keeps bridge primitives closed to generic API roles', () => {
    expect(migration).toContain('REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_inventory_task(UUID,UUID)')
    expect(migration).toContain('REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_task(UUID,UUID)')
    expect(migration).not.toMatch(/GRANT\s+EXECUTE/i)
  })
})
