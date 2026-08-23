import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817011100_ai_operations_reconciliation_concurrency_guard.sql',
), 'utf8')

describe('AI Operations reconciliation stale-snapshot protection', () => {
  it('prevents an older recovery snapshot from resolving newer Case reality', () => {
    expect(migration).toContain('c.last_seen_at<=v_snapshot.generated_at')
    expect(migration).toContain('c.last_seen_at>v_snapshot.generated_at')
    expect(migration).toContain("'stale_case_updates_skipped'")
    expect(migration).toContain("'stale_snapshot_guard',true")
  })

  it('reopens persistent actioned Cases only when the current snapshot is still the latest Case capture', () => {
    expect(migration).toContain('c.last_snapshot_id=p_snapshot_id')
    expect(migration).toContain("v_decision.work_status IN ('done','cancelled')")
    expect(migration).toContain("'completion_is_not_success',true")
    expect(migration).toContain("'source_mutation_performed',false")
  })

  it('retains complete-domain and truncation fail-closed semantics', () => {
    expect(migration).toContain("v_domain.capture_status<>'completed'")
    expect(migration).toContain("v_domain.metadata->>'has_more'")
    expect(migration).toContain("v_domain.metadata->>'global_budget_exhausted'")
    expect(migration).toContain("v_domain.metadata->>'truncated'")
  })
})
