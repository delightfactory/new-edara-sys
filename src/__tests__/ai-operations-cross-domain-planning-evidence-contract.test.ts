import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817010700_ai_operations_cross_domain_planning_evidence.sql',
), 'utf8')

describe('AI Operations cross-domain planning evidence', () => {
  it('keeps explicit unavailability hard without inventing a workload score', () => {
    expect(migration).toContain("'hard_unavailability_cases'")
    expect(migration).toContain("'hard_block_from_this_summary'")
    expect(migration).toContain("'work_field_counts_are_pressure_evidence_only',true")
    expect(migration).toContain("'capacity_score',NULL")
    expect(migration).toContain("'capacity_score_prohibited_without_effort_model',true")
    expect(migration).toContain("'arbitrary_tasks_per_day_threshold',false")
  })

  it('freezes Work, Field and responsibility pressure as model evidence', () => {
    expect(migration).toContain("'unhealthy_owned_work_cases'")
    expect(migration).toContain("'unhealthy_assigned_work_cases'")
    expect(migration).toContain("'overdue_field_plan_cases'")
    expect(migration).toContain("'customer_relationship_cases'")
    expect(migration).toContain("'sales_accountability_cases'")
    expect(migration).toContain("'inventory_responsibility_cases'")
  })

  it('links exact shared customer/product entities across frozen domains without merging severity', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION ai_ops.build_cross_domain_entity_links')
    expect(migration).toContain("'shared_entity_evidence_not_automatic_conflict'")
    expect(migration).toContain("'sales_inventory_link_requires_case_specific_reasoning'")
    expect(migration).toContain("'automatic_priority_from_link',false")
  })

  it('adds all cross-domain evidence to the global context before it is frozen', () => {
    expect(migration).toContain("'actor_feasibility',ai_ops.build_actor_feasibility_evidence(p_snapshot_id)")
    expect(migration).toContain("'cross_domain_entity_links',ai_ops.build_cross_domain_entity_links(p_snapshot_id)")
    expect(migration).toContain("'explicit_hr_unavailability_is_hard',true")
    expect(migration).toContain("'work_health_pressure_is_not_capacity_proof',true")
  })
})
