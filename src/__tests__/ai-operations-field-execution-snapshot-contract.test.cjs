import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817007600_ai_operations_field_execution_snapshot_capture.sql',
), 'utf8')

describe('AI Operations Field Execution snapshot contract', () => {
  it('freezes cases into the shared immutable snapshot with a domain capture marker', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION ai_ops.refresh_field_execution_cases')
    expect(migration).toContain("'field_execution'")
    expect(migration).toContain("'field-execution-v1'")
    expect(migration).toContain('ai_ops.snapshot_cases')
    expect(migration).toContain('ai_ops.snapshot_domain_captures')
  })

  it('refuses duplicate domain capture or orphan frozen evidence', () => {
    expect(migration).toContain("dc.domain='field_execution'")
    expect(migration).toContain("sc.domain='field_execution'")
    expect(migration).toContain('field_execution domain already captured')
    expect(migration).toContain('field_execution evidence exists without capture marker')
  })

  it('bounds governed employee/branch context to five items per Case', () => {
    expect(migration).toContain("oc.subject_type='employee'")
    expect(migration).toContain("oc.subject_type='branch'")
    expect(migration).toContain('LIMIT 5')
    expect(migration).toContain("'max_per_case',5")
  })

  it('distinguishes bounded coverage from source/snapshot incompleteness', () => {
    expect(migration).toContain("v_snapshot.snapshot_status='blocked'")
    expect(migration).toContain("v_snapshot.snapshot_status='partial' OR v_has_more")
    expect(migration).toContain("'case_limit',v_effective_limit")
    expect(migration).toContain("'has_more',v_has_more")
  })

  it('records no exact GPS or field mutation in the frozen contract', () => {
    expect(migration).toContain("'exact_gps_captured',false")
    expect(migration).toContain("'visit_mutation_performed',false")
    expect(migration).toContain("'resolution_performed',false")
  })

  it('keeps snapshot capture private from generic API roles', () => {
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.refresh_field_execution_cases(UUID,DATE,INTEGER)')
    expect(migration).toContain('FROM PUBLIC,anon,authenticated,service_role')
  })
})
