import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const initialMigration = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260817009900_ai_operations_cross_domain_feasibility_gate.sql'),
  'utf8',
)

const hardeningMigration = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260817010200_ai_operations_cross_domain_feasibility_hardening.sql'),
  'utf8',
)

describe('AI Operations cross-domain feasibility', () => {
  it('keeps the original canonical wrapper and frozen HR conflict contract', () => {
    expect(initialMigration).toContain('current_decision_issues_pre_cross_domain_feasibility_v1')
    expect(initialMigration).toContain("sc.domain='hr_availability'")
    expect(initialMigration).toContain('assignee_has_frozen_hr_unavailability_conflict')
    expect(initialMigration).toContain('private.work_actor_is_active')
  })

  it('hardens feasibility with explicit current availability and deterministic duplicate blocking', () => {
    expect(hardeningMigration).toContain('current_cross_domain_feasibility_evidence')
    expect(hardeningMigration).toContain('assignee_on_approved_leave_for_immediate_action')
    expect(hardeningMigration).toContain('assignee_explicitly_unavailable_for_immediate_action')
    expect(hardeningMigration).toContain('duplicate_same_entity_create_work_in_run')
    expect(hardeningMigration).toContain('duplicate_linked_work_escalation_in_run')
    expect(hardeningMigration).toContain("d2.validation_state IN ('pending','validated')")
    expect(hardeningMigration).toContain('assignee_has_frozen_hr_unavailability_conflict')
    expect(hardeningMigration).toContain("ad.status::TEXT IN (\n          'on_leave','absent_authorized','absent_unauthorized','weekly_off','public_holiday'")
  })

  it('surfaces workload, visits and dependency/approval evidence without inventing a productivity threshold', () => {
    expect(hardeningMigration).toContain('active_standard_work_count')
    expect(hardeningMigration).toContain('urgent_or_critical_overdue_work_count')
    expect(hardeningMigration).toContain('today_active_visit_plan_count')
    expect(hardeningMigration).toContain('unresolved_hard_dependency_count')
    expect(hardeningMigration).toContain('source_work_pending_approval')
    expect(hardeningMigration).toContain('related_frozen_cases')
    expect(hardeningMigration).toContain("'arbitrary_capacity_threshold_applied', false")
    expect(hardeningMigration).toContain("'missing_attendance_never_implies_absence', true")
    expect(hardeningMigration).not.toContain('productivity_score NUMERIC')
  })

  it('is forward-only AI-boundary hardening and never mutates production source structures', () => {
    expect(hardeningMigration).not.toMatch(/ALTER\s+TABLE\s+public\./i)
    expect(hardeningMigration).not.toMatch(/CREATE\s+(?:OR\s+REPLACE\s+)?TRIGGER/i)
    expect(hardeningMigration).not.toMatch(/CREATE\s+(?:UNIQUE\s+)?INDEX/i)
    expect(hardeningMigration).not.toMatch(/UPDATE\s+public\./i)
    expect(hardeningMigration).not.toMatch(/DELETE\s+FROM\s+public\./i)
    expect(hardeningMigration).not.toMatch(/INSERT\s+INTO\s+public\./i)
  })
})
