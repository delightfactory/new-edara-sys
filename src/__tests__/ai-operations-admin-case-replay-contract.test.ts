import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816171100_ai_operations_admin_case_replay_fix.sql',
), 'utf8')

describe('AI Operations decision-time management replay contract', () => {
  it('remains a design-time, read-only override of case detail only', () => {
    expect(migration).toContain('DESIGN-TIME MIGRATION ONLY')
    expect(migration.match(/CREATE OR REPLACE FUNCTION public\.ai_ops_/g)).toHaveLength(1)
    expect(migration).toContain('public.ai_ops_get_case_detail(p_case_id UUID)')
    expect(migration).not.toMatch(/\bINSERT\s+INTO\b|\bUPDATE\s+(?:ai_ops|public|private)\.|\bDELETE\s+FROM\b/i)
  })

  it('matches a decision to immutable evidence from the same run', () => {
    expect(migration).toContain('s.run_id = v_decision.run_id')
    expect(migration).toContain('decision-time immutable evidence not found')
    expect(migration).toContain('v_snapshot_case ai_ops.snapshot_cases%ROWTYPE')
    expect(migration).toContain('v_snapshot_case.responsibility_evidence')
  })

  it('falls back to latest frozen evidence only when no decision exists', () => {
    expect(migration).toContain('IF v_decision.id IS NOT NULL THEN')
    expect(migration).toContain('ORDER BY s.generated_at DESC, sc.snapshot_rank ASC')
    expect(migration).toContain('AI Operations immutable case evidence not found')
  })

  it('reads decision context from the frozen snapshot instead of mutable current context', () => {
    expect(migration).toContain("v_snapshot_case.operational_context->'items'")
    expect(migration).toContain("'frozen_context', v_context_items")
    expect(migration).toContain("'context_coverage', v_context_coverage")
    expect(migration).not.toContain('FROM ai_ops.operational_context')
  })

  it('keeps frozen context coverage explicit and auditable', () => {
    expect(migration).toContain("v_snapshot_case.operational_context->>'total'")
    expect(migration).toContain("v_snapshot_case.operational_context->>'captured'")
    expect(migration).toContain("v_snapshot_case.operational_context->>'truncated'")
    expect(migration).toContain("'relevant_context_ids', v_context_ids")
  })

  it('preserves the management permission boundary and no-anon access', () => {
    expect(migration).toContain('private.work_actor_is_active(v_actor)')
    expect(migration).toContain("public.check_permission(v_actor, 'work.policies.manage')")
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.ai_ops_get_case_detail(UUID) FROM anon;')
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.ai_ops_get_case_detail(UUID) TO authenticated;')
  })
})
