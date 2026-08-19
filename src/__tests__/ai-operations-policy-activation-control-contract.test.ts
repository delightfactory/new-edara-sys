import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817011000_ai_operations_policy_activation_control.sql',
), 'utf8')

describe('AI Operations planner policy activation control', () => {
  it('keeps replay-critical policy content immutable', () => {
    expect(migration).toContain('NEW.system_prompt IS DISTINCT FROM OLD.system_prompt')
    expect(migration).toContain('NEW.methodology IS DISTINCT FROM OLD.methodology')
    expect(migration).toContain('NEW.prompt_hash IS DISTINCT FROM OLD.prompt_hash')
    expect(migration).toContain('AI planner policy content is immutable; create a new prompt version')
    expect(migration).toContain('AI planner policy versions cannot be deleted')
  })

  it('allows only activation state to change in place', () => {
    expect(migration).toContain('Only activation state and its audit timestamp may change in-place')
    expect(migration).toContain('NEW.updated_at:=clock_timestamp()')
    expect(migration).toContain('CREATE TRIGGER trg_ai_ops_planner_policies_guarded')
  })
})
