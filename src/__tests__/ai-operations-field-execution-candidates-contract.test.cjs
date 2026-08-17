import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817007500_ai_operations_field_execution_case_engine.sql',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations Field Execution candidate contract', () => {
  it('uses the native operational visit lifecycle and past-date pending commitments', () => {
    expect(migration).toContain("vp.status IN ('confirmed','in_progress')")
    expect(migration).toContain('vp.plan_date<p_business_date')
    expect(migration).toContain("FILTER (WHERE vpi.status='pending')")
    expect(migration).toContain("'legacy_submitted_state_authoritative',false")
  })

  it('emits one visit-day Case instead of one Case per pending customer', () => {
    expect(migration).toContain("'field_execution:overdue_visit_day:'||e.visit_plan_id::TEXT")
    expect(migration).toContain("'overdue_visit_day'::TEXT")
    expect(migration).toContain("'visit_plan'::TEXT AS entity_type")
    expect(migration).toContain("'pending_items',e.pending_items")
    expect(migration).toContain('LIMIT 10')
    expect(migration).not.toMatch(/field_execution:overdue_visit[^']*customer/i)
  })

  it('freezes execution rep and direct-manager accountability without guessing alternates', () => {
    expect(migration).toContain('rep.direct_manager_id')
    expect(migration).toContain("'routing_rule','plan_rep_executes_direct_manager_accountable'")
    expect(migration).toContain("'rep_user_id'")
    expect(migration).toContain("'manager_user_id'")
    expect(migration).toContain('responsibility_unambiguous')
  })

  it('keeps exact location coordinates out of worker facts and makes no causal inference', () => {
    expect(migration).toContain("'gps_coordinates_excluded',true")
    expect(migration).toContain("'miss_reason_inferred',false")
    expect(executableSql).not.toMatch(/\b(?:gps_lat|gps_lng|expected_lat|expected_lng|start_lat|start_lng|end_lat|end_lng)\b/i)
  })

  it('is read-only against field execution and customer sources', () => {
    expect(executableSql).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:visit_plans|visit_plan_items|activities|call_plans|call_plan_items|customers|hr_employees)/i)
    expect(migration).toContain("'visit_mutation_performed',false")
  })

  it('keeps the deterministic kernel private from generic API roles', () => {
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.field_execution_candidates(DATE,INTEGER)')
    expect(migration).toContain('FROM PUBLIC,anon,authenticated,service_role')
  })
})
