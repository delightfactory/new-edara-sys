import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const closure = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817010200_ai_operations_policy_global_outcome_closure.sql',
), 'utf8')
const freeze = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817010400_ai_operations_snapshot_global_context_freeze.sql',
), 'utf8')

describe('AI Operations global planning context and closed outcome loop', () => {
  it('builds one cross-domain planning frame instead of domain-isolated severity lists', () => {
    expect(closure).toContain('CREATE OR REPLACE FUNCTION ai_ops.build_global_operational_context')
    expect(closure).toContain("'commercial_cases'")
    expect(closure).toContain("'constraint_cases'")
    expect(closure).toContain("'global_action_budget'")
    expect(closure).toContain("'severity_is_not_automatic_priority', true")
    expect(closure).toContain("'recent_human_feedback'")
    expect(closure).toContain("'recent_outcome_observations'")
  })

  it('freezes the enriched global frame once per snapshot for replay', () => {
    expect(freeze).toContain('CREATE TABLE ai_ops.snapshot_global_context')
    expect(freeze).toContain('snapshot_id UUID PRIMARY KEY')
    expect(freeze).toContain('CREATE TRIGGER trg_ai_ops_snapshot_global_context_immutable')
    expect(freeze).toContain('ai_ops.capture_global_operational_context')
    expect(freeze).toContain('global_context_frozen')
  })

  it('resolves only complete domains and never treats Work completion as business success', () => {
    expect(closure).toContain("v_domain.capture_status <> 'completed'")
    expect(closure).toContain("global_budget_exhausted")
    expect(closure).toContain("'source_resolved'")
    expect(closure).toContain("'work_completed_condition_persists'")
    expect(closure).toContain("'work_cancelled_condition_persists'")
    expect(closure).toContain("'completion_is_not_success', true")
    expect(closure).toContain("status = 'open'")
    expect(closure).toContain("'source_mutation_performed', false")
  })

  it('keeps outcome observations immutable and explicitly non-punitive', () => {
    expect(closure).toContain('CREATE TABLE ai_ops.case_outcomes')
    expect(closure).toContain('CREATE TRIGGER trg_ai_ops_case_outcomes_immutable')
    expect(closure).toContain("'employee_performance_signal', false")
  })
})
