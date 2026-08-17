import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817007800_ai_operations_field_execution_current_state_guard.sql',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations Field Execution current-state guard contract', () => {
  it('re-runs the exact deterministic Field Execution candidate kernel', () => {
    expect(migration).toContain('FROM ai_ops.field_execution_candidates(v_business_date,2000) c')
    expect(migration).toContain('c.case_key=v_sc.case_key')
    expect(migration).toContain("'field_execution_case_no_longer_current'")
  })

  it('detects plan, pending commitment and activity drift before consequential action', () => {
    expect(migration).toContain("'visit_plan_state_changed_after_snapshot'")
    expect(migration).toContain("'visit_day_commitment_counts_changed_after_snapshot'")
    expect(migration).toContain("'visit_day_pending_commitments_changed_after_snapshot'")
    expect(migration).toContain("'new_visit_day_activity_after_snapshot'")
  })

  it('requires the actual plan rep as assignee and direct manager as accountable owner', () => {
    expect(migration).toContain("'recommended_field_assignee_not_plan_rep'")
    expect(migration).toContain("'recommended_field_owner_not_direct_manager'")
    expect(migration).toContain("'field_execution_responsibility_ambiguous_or_unavailable'")
    expect(migration).toContain('private.work_actor_is_active')
  })

  it('prevents duplicate Work and validates escalation continuity on the exact visit plan', () => {
    expect(migration).toContain("wl.entity_type='visit_plan'")
    expect(migration).toContain("'active_visit_plan_work_collision_now'")
    expect(migration).toContain("'linked_visit_plan_work_no_longer_active'")
  })

  it('routes coverage through the shared bounded-partial gate and checks newer governed context', () => {
    expect(migration).toContain("dc.domain='field_execution'")
    expect(migration).toContain("'snapshot_not_complete_for_action'")
    expect(migration).toContain('ai_ops.apply_selected_case_capture_actionability')
    expect(migration).toContain("'new_field_execution_governed_context_after_snapshot'")
  })

  it('does not mutate visit, activity or customer sources', () => {
    expect(executableSql).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:visit_plans|visit_plan_items|activities|call_plans|call_plan_items|customers)/i)
  })

  it('extends the canonical decision guard without changing older domain primitives', () => {
    expect(migration).toContain("WHEN 'receivables' THEN")
    expect(migration).toContain("WHEN 'sales' THEN")
    expect(migration).toContain("WHEN 'customer_health' THEN")
    expect(migration).toContain("WHEN 'inventory' THEN")
    expect(migration).toContain("WHEN 'field_execution' THEN")
    expect(migration).toContain('ai_ops.current_field_execution_decision_issues(p_decision_id)')
  })
})
