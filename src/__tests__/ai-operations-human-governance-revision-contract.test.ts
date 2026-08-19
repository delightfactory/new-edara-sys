import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817010300_ai_operations_human_context_decision_revision.sql',
), 'utf8')
const lifecycle = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817010500_ai_operations_revision_aware_run_lifecycle.sql',
), 'utf8')

describe('AI Operations human context and decision revision governance', () => {
  it('keeps context writes management-only, temporary and non-executable', () => {
    expect(migration).toContain("public.check_permission(v_actor,'work.policies.manage')")
    expect(migration).toContain("p_valid_until > v_now + interval '180 days'")
    expect(migration).toContain("'approved_human'")
    expect(migration).toContain("'execution_authority', false")
    expect(migration).toContain('CREATE TABLE ai_ops.operational_context_events')
    expect(migration).toContain('CREATE TRIGGER trg_ai_ops_context_events_immutable')
    expect(migration).toContain('FROM PUBLIC, anon')
    expect(migration).toContain('TO authenticated, service_role')
  })

  it('creates a new audited decision revision instead of mutating reviewed history', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.ai_ops_revise_decision')
    expect(migration).toContain("reviewed decisions cannot be revised")
    expect(migration).toContain("'superseded_by_human_revision',true")
    expect(migration).toContain('v_old.revision+1')
    expect(migration).toContain("'human-revision:'||v_new_id::TEXT")
    expect(migration).toContain('v_issues := ai_ops.current_decision_issues(v_new.id)')
    expect(migration).toContain("'execution_performed',false")
  })

  it('makes run lifecycle evaluate only the latest revision for each Case', () => {
    expect(lifecycle).toContain('SELECT DISTINCT ON (d.case_id) d.*')
    expect(lifecycle).toContain('ORDER BY d.case_id,d.revision DESC')
    expect(lifecycle).toContain("'superseded_decision_rows'")
    expect(lifecycle).toContain("'revision_aware_lifecycle',true")
  })
})
