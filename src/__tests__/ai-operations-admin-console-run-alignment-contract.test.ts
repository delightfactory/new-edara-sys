import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816171200_ai_operations_admin_console_run_alignment.sql',
), 'utf8')

describe('AI Operations management console run-alignment contract', () => {
  it('is a design-time read-only console override', () => {
    expect(migration).toContain('DESIGN-TIME MIGRATION ONLY')
    expect(migration.match(/CREATE OR REPLACE FUNCTION public\.ai_ops_/g)).toHaveLength(1)
    expect(migration).toContain('public.ai_ops_get_console_snapshot()')
    expect(migration).not.toMatch(/\bINSERT\s+INTO\b|\bUPDATE\s+(?:ai_ops|public|private)\.|\bDELETE\s+FROM\b/i)
  })

  it('lists facts exclusively from the latest immutable snapshot evidence', () => {
    expect(migration).toContain('FROM ai_ops.snapshot_cases sc')
    expect(migration).toContain('WHERE sc.snapshot_id = v_snapshot.id')
    expect(migration).toContain('ORDER BY sc.snapshot_rank ASC')
    expect(migration).toContain("sc.facts->>'remaining_amount'")
  })

  it('attaches a decision only when it belongs to the same run as the displayed snapshot', () => {
    expect(migration).toContain('AND d.run_id = v_snapshot.run_id')
    expect(migration).toContain('same_run_decision.decision_type')
    expect(migration).toContain('same_run_decision.review_after')
    expect(migration).toContain("same_run_decision.responsibility_basis->>'summary'")
    expect(migration).not.toContain('latest_decision.decision_type')
  })

  it('retains the management permission boundary and no-anon execution', () => {
    expect(migration).toContain('private.work_actor_is_active(v_actor)')
    expect(migration).toContain("public.check_permission(v_actor, 'work.policies.manage')")
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.ai_ops_get_console_snapshot() FROM anon;')
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.ai_ops_get_console_snapshot() TO authenticated;')
  })
})
