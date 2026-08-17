import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817007000_ai_operations_inventory_case_engine.sql',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations Inventory case engine contract', () => {
  it('uses actual outbound demand and available stock instead of unconfigured min-stock levels', () => {
    expect(migration).toContain("sm.type='out'")
    expect(migration).toContain("BETWEEN p_business_date-29 AND p_business_date")
    expect(migration).toContain('s.available_quantity')
    expect(migration).toContain('o.outbound_qty_30d/30.0')
    expect(migration).toContain("'coverage_threshold_days',7")
    expect(migration).toContain("'min_stock_level_authoritative',false")
    expect(executableSql).not.toMatch(/p\.min_stock_level\s*[<>=]/i)
  })

  it('detects only production-backed v1 case families', () => {
    expect(migration).toContain("'local_shortage'::TEXT")
    expect(migration).toContain("'stalled_transfer'::TEXT")
    expect(migration).toContain("st.status='in_transit'")
    expect(migration).toContain("p_business_date-8")
    expect(migration).toContain("'batch_expiry_case_enabled',false")
    expect(migration).not.toContain("'expiry_risk'::TEXT")
  })

  it('freezes alternate-warehouse and incoming-transfer feasibility without executing either', () => {
    expect(migration).toContain("'alternate_available_quantity'")
    expect(migration).toContain("'alternate_warehouses'")
    expect(migration).toContain("'incoming_transfer_count'")
    expect(migration).toContain("'incoming_transfer_remaining_qty'")
  })

  it('treats warehouse responsibility ambiguity as evidence rather than inventing a route', () => {
    expect(migration).toContain('COUNT(DISTINCT wm.profile_id) FILTER (WHERE wm.is_primary)')
    expect(migration).toContain('mr.primary_count=1')
    expect(migration).toContain("'responsibility_unambiguous'")
    expect(migration).toContain("'warehouse_primary_manager_count'")
  })

  it('is read-only against Inventory and purchasing operational sources', () => {
    expect(executableSql).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:stock|stock_movements|stock_transfers|stock_transfer_items|warehouses|warehouse_managers|products|stock_batches|purchase_invoices|purchase_invoice_items)/i)
    expect(migration).toContain("'operational_mutation_performed',false")
  })

  it('keeps the deterministic candidate kernel private from generic API roles', () => {
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.inventory_candidates(DATE,INTEGER)')
    expect(migration).toContain('FROM PUBLIC,anon,authenticated,service_role')
  })
})
