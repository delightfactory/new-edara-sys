import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(process.cwd(),'supabase/migrations/20260817009900_ai_operations_cross_domain_feasibility_gate.sql'),'utf8')

describe('AI Operations cross-domain feasibility', () => {
  it('adds provable availability conflicts to the canonical current-state gate', () => {
    expect(migration).toContain('current_decision_issues_pre_cross_domain_feasibility_v1')
    expect(migration).toContain("sc.domain='hr_availability'")
    expect(migration).toContain('assignee_has_frozen_hr_unavailability_conflict')
    expect(migration).toContain('private.work_actor_is_active')
    expect(migration).not.toContain('productivity_score')
  })
})
