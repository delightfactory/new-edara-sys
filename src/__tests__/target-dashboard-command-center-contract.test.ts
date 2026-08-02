import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(
  'supabase/migrations/20260802122140_dashboard_goal_command_center.sql',
  'utf8',
)
const service = readFileSync('src/lib/services/targets.ts', 'utf8')

describe('dashboard goal command center migration contract', () => {
  it('links only missing HR hierarchy records to the single active branch', () => {
    expect(migration).toContain("WHERE is_active = true")
    expect(migration).toContain('Expected exactly one active branch')
    expect(migration).toMatch(/UPDATE public\.hr_departments[\s\S]*WHERE branch_id IS NULL;/)
    expect(migration).toMatch(/UPDATE public\.hr_employees[\s\S]*WHERE branch_id IS NULL;/)
  })

  it('never mutates operational transactions or role assignments', () => {
    for (const table of [
      'sales_orders', 'sales_order_items', 'sales_returns', 'sales_return_items',
      'purchase_invoices', 'payment_receipts', 'user_roles', 'visit_plans',
    ]) {
      expect(migration).not.toMatch(new RegExp(`(?:UPDATE|DELETE FROM|INSERT INTO|ALTER TABLE) public\\.${table}`, 'i'))
    }
  })

  it('adds read-only scope membership without granting target writes', () => {
    expect(migration).toContain('CREATE POLICY tgt_read_scope_members')
    expect(migration).toContain('CREATE POLICY tp_read_scope_members')
    expect(migration).toContain('target_scope_matches_employee')
    expect(migration).not.toMatch(/CREATE POLICY tgt_[\s\S]*FOR (?:INSERT|UPDATE|DELETE)/)
  })

  it('keeps contribution arithmetic aligned with the canonical calculators', () => {
    expect(migration).toContain("v_target.type_code NOT IN")
    expect(migration).toContain("so.status IN ('delivered', 'completed')")
    expect(migration).toContain('so.total_amount - COALESCE(so.returned_amount, 0)')
    expect(migration).toContain('soi.delivered_quantity - COALESCE(soi.returned_quantity, 0)')
    expect(migration).toContain('employee_receipts_by_order')
    expect(migration).toContain('all_receipts_by_order')
    expect(migration).toContain("v_target.type_code = 'collection'")
    expect(migration).toContain('SUM(cv.achieved) OVER () <= 0')
    expect(migration).not.toContain('ARRAY[m.id]::UUID[]')
    expect(migration).toContain("at_.category = 'visit'")
    expect(migration).toContain("at_.category = 'call'")
  })

  it('exposes the read-only RPC only to authenticated users and wires active-date filtering', () => {
    expect(migration).toMatch(/REVOKE ALL ON FUNCTION public\.get_target_employee_contributions\(UUID, DATE\)[\s\S]*FROM PUBLIC, anon;/)
    expect(migration).toMatch(/GRANT EXECUTE ON FUNCTION public\.get_target_employee_contributions\(UUID, DATE\)[\s\S]*TO authenticated;/)
    expect(service).toContain("supabase.rpc('get_target_employee_contributions'")
    expect(service).toContain("q.lte('period_start', filters.active_on).gte('period_end', filters.active_on)")
  })
})
