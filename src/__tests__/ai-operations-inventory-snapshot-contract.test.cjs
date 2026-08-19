import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817007100_ai_operations_inventory_snapshot_capture.sql',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations Inventory snapshot contract', () => {
  it('freezes Inventory cases into the shared immutable snapshot', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION ai_ops.refresh_inventory_cases')
    expect(migration).toContain("'inventory','inventory-v1'")
    expect(migration).toContain('INSERT INTO ai_ops.snapshot_cases')
    expect(migration).toContain('INSERT INTO ai_ops.snapshot_domain_captures')
    expect(migration).toContain("dc.domain='inventory'")
  })

  it('records bounded-selection metadata required by shared actionability', () => {
    expect(migration).toContain("'case_limit',v_effective_limit")
    expect(migration).toContain("'has_more',v_has_more")
    expect(migration).toContain("v_snapshot.snapshot_status='partial' OR v_has_more")
    expect(migration).toContain("v_snapshot.snapshot_status='blocked'")
  })

  it('bounds governed operational context per selected case', () => {
    expect(migration).toContain('LIMIT 5')
    expect(migration).toContain("'max_per_case',5")
    expect(migration).toContain("oc.subject_type='warehouse'")
    expect(migration).toContain("oc.subject_type='product'")
  })

  it('does not mutate Inventory operational sources during capture', () => {
    expect(executableSql).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:stock|stock_movements|stock_transfers|stock_transfer_items|warehouses|warehouse_managers|products|stock_batches|purchase_invoices|purchase_invoice_items)/i)
    expect(migration).toContain("'operational_mutation_performed',false")
  })

  it('keeps capture execution private', () => {
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.refresh_inventory_cases(UUID,DATE,INTEGER)')
    expect(migration).toContain('FROM PUBLIC,anon,authenticated,service_role')
  })
})
