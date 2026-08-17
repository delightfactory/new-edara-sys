import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817007900_ai_operations_field_execution_reviewed_work_bridge.sql',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations Field Execution reviewed Work bridge contract', () => {
  it('makes visit_plan a first-class Work link entity without removing prior entities', () => {
    expect(migration).toContain("WHEN 'visit_plan' THEN 'public.visit_plans'")
    expect(migration).toContain("WHEN 'stock_transfer' THEN 'public.stock_transfers'")
    expect(migration).toContain("WHEN 'employee' THEN 'public.hr_employees'")
  })

  it('requires kill-switch clearance, human approval, reviewed fingerprint and validated decision', () => {
    expect(migration).toContain('planner_enabled')
    expect(migration).toContain('shadow_mode')
    expect(migration).toContain("v_review.review_state<>'approved'")
    expect(migration).toContain('decision_fingerprint IS DISTINCT FROM v_fingerprint')
    expect(migration).toContain("v_decision.validation_state<>'validated'")
  })

  it('revalidates current state in the same transaction immediately before Work mutation', () => {
    expect(migration).toContain('PERFORM pg_advisory_xact_lock')
    expect(migration).toContain('v_issues:=ai_ops.current_decision_issues(p_decision_id)')
    expect(migration).toContain("'current_state_changed'")
    expect(migration.indexOf('v_issues:=ai_ops.current_decision_issues')).toBeLessThan(migration.indexOf('INSERT INTO public.work_items'))
  })

  it('creates employee-safe system Work with exact visit-plan and employee links', () => {
    expect(migration).toContain("v_source_key:='ai_ops:decision:'||p_decision_id::TEXT")
    expect(migration).toContain("'system'::public.work_source_kind")
    expect(migration).toContain("'management_rationale_exposed',false")
    expect(migration).toContain("v_work.id,'visit_plan',v_visit_plan_id,'primary'")
    expect(migration).toContain("v_work.id,'employee',v_rep_employee_id,'assigned_field_rep'")
  })

  it('does not mutate visit, activity, call or customer records', () => {
    expect(executableSql).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:visit_plans|visit_plan_items|activities|call_plans|call_plan_items|customers)/i)
    expect(migration).toContain("'visit_mutation_performed',false")
    expect(migration).toContain("'operational_mutation','work_create_only'")
  })

  it('keeps Work idempotent and updates normal AI/Work provenance', () => {
    expect(migration).toContain("'unexpected_source_key_collision'")
    expect(migration).toContain('private.ai_ops_append_work_system_event')
    expect(migration).toContain("checkpoint='reviewed_work_committed'")
    expect(migration).toContain("'last_commit_domain','field_execution'")
  })

  it('extends the canonical reviewed Work dispatcher and keeps bridge functions private', () => {
    expect(migration).toContain('work_create_ai_reviewed_task_four_domain_v1')
    expect(migration).toContain("IF v_domain='field_execution' THEN")
    expect(migration).toContain('private.work_create_ai_reviewed_field_execution_task')
    expect(migration).toContain('REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_field_execution_task(UUID,UUID)')
    expect(migration).toContain('FROM PUBLIC,anon,authenticated,service_role')
  })
})
