import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817009000_ai_operations_hr_availability_global_budget_actionability.sql',
), 'utf8')

describe('AI Operations HR Availability global-budget integrity hardening', () => {
  it('fails closed if an idempotent seven-domain snapshot has lost a required capture marker', () => {
    expect(migration).toContain('existing seven-domain snapshot is missing a required immutable domain capture marker')
    expect(migration).toContain("COUNT(*)=7 FROM ai_ops.snapshot_domain_captures")
  })

  it('rebinds HR demand and allocation to the exact frozen snapshot and real residual capacity', () => {
    expect(migration).toContain('ai_ops.hr_availability_candidates(v_run.business_date,v_snapshot.data_as_of,2000)')
    expect(migration).toContain('v_hr_alloc:=LEAST(v_hr_demand,v_remaining)')
    expect(migration).not.toContain('v_hr_alloc:=LEAST(v_hr_alloc,v_hr_demand,v_remaining)')
  })

  it('only emits a zero-capacity partial marker when exact frozen demand remains', () => {
    expect(migration).toContain('v_hr_has_candidate:=v_hr_demand>0')
    expect(migration).toContain("CASE WHEN v_hr_has_candidate THEN 'partial' ELSE 'completed' END")
    expect(migration).toContain("'global_budget_exhausted',v_hr_has_candidate")
  })
})
