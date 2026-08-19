import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817008000_ai_operations_cross_domain_runtime_hardening.sql',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations cross-domain runtime hardening contract', () => {
  it('uses the production activity type relation instead of the nonexistent activities.type column', () => {
    expect(migration).toContain('LEFT JOIN public.activity_types at ON at.id=a.type_id')
    expect(migration).toContain("COALESCE(at.code::TEXT,a.subject_type::TEXT,'activity')")
    expect(executableSql).not.toMatch(/\ba\.type\b/i)
  })

  it('freezes a full pending-set fingerprint while retaining bounded item detail', () => {
    expect(migration).toContain("'pending_set_fingerprint',e.pending_set_fingerprint")
    expect(migration).toContain("'pending_set_fingerprint_algorithm','md5-stable-identity'")
    expect(migration).toContain('LIMIT 10')
    expect(migration).toContain("'visit_day_pending_set_changed_after_snapshot'")
    expect(migration).toContain("'visit_day_pending_set_fingerprint_missing'")
  })

  it('normalizes existing active Work evidence for Field Execution and Inventory', () => {
    expect(migration).toContain("'existing_active_work'")
    expect(migration).toContain("'work_item_id',e.active_work_item_id")
    expect(migration).toContain('inventory_candidates_pre_active_work_v1')
    expect(migration).toContain("'work_item_id',aw.work_item_id")
    expect(migration).toContain("b.case_type='local_shortage'")
    expect(migration).toContain("b.case_type='stalled_transfer'")
    expect(migration).toContain("wp.entity_type='product'")
    expect(migration).toContain("ww.entity_type='warehouse'")
    expect(migration).toContain("wt.entity_type='stock_transfer'")
  })

  it('centralizes the required domain set and gates both worker context and staging', () => {
    for (const domain of ['receivables', 'sales', 'customer_health', 'inventory', 'field_execution']) {
      expect(migration).toContain(`'${domain}'`)
    }
    expect(migration).toContain('CREATE OR REPLACE FUNCTION ai_ops.required_operational_domains()')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION ai_ops.snapshot_has_required_domain_captures')
    expect(migration).toContain('worker_get_context_pre_required_domains_v1')
    expect(migration).toContain('worker_stage_decisions_pre_required_domains_v1')
    expect(migration).toContain('NOT ai_ops.snapshot_has_required_domain_captures(v_snapshot_id)')
  })

  it('keeps operational source domains read-only', () => {
    expect(executableSql).not.toMatch(
      /(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:visit_plans|visit_plan_items|activities|activity_types|stock|stock_movements|stock_transfers|stock_transfer_items|products|warehouses)/i,
    )
  })

  it('keeps internal planner helpers private from generic API roles', () => {
    expect(migration).toContain('FROM PUBLIC,anon,authenticated,service_role')
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.field_execution_candidates(DATE,INTEGER)')
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.inventory_candidates(DATE,INTEGER)')
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.worker_get_context(UUID,TEXT)')
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB)')
  })
})
