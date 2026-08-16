import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816172600_ai_operations_current_state_guard.sql',
), 'utf8')

describe('AI Operations shared current-state guard contract', () => {
  it('is internal, read-only at the guard layer and unavailable to API roles', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION ai_ops.current_decision_issues')
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.current_decision_issues(UUID) FROM PUBLIC, anon, authenticated, service_role;')
    expect(migration).not.toMatch(/GRANT\s+EXECUTE/i)
  })

  it('centralizes the full receivables/credit/work/context drift vocabulary', () => {
    for (const code of [
      'invoice_no_longer_overdue_candidate',
      'due_date_changed_after_snapshot',
      'remaining_balance_changed_after_snapshot',
      'customer_assignment_changed_after_snapshot',
      'order_rep_changed_after_snapshot',
      'credit_override_changed_after_snapshot',
      'due_date_history_changed_after_snapshot',
      'customer_credit_policy_changed_after_snapshot',
      'new_governed_context_after_snapshot',
      'recommended_owner_unavailable',
      'recommended_assignee_unavailable',
      'active_work_collision_now',
      'escalation_has_no_linked_work',
      'linked_work_no_longer_active',
      'snapshot_not_complete_for_action',
    ]) {
      expect(migration).toContain(`'${code}'`)
    }
  })

  it('uses Cairo current reality for commit-time due-state checks', () => {
    expect(migration).toContain("AT TIME ZONE 'Africa/Cairo'")
    expect(migration).toContain('v_current_order.due_date >= v_business_date')
  })

  it('is reused by staged validation instead of duplicating the safety rules there', () => {
    const overrideIndex = migration.indexOf('CREATE OR REPLACE FUNCTION ai_ops.validate_staged_run')
    expect(overrideIndex).toBeGreaterThan(-1)
    const validationBody = migration.slice(overrideIndex)
    expect(validationBody).toContain('v_reasons := ai_ops.current_decision_issues(v_decision.id)')
    expect(validationBody).not.toContain('FROM public.sales_orders')
    expect(validationBody).not.toContain('FROM public.work_links')
  })

  it('keeps validation stage-only and performs no operational execution', () => {
    expect(migration).toContain("validation_state = 'validated'")
    expect(migration).toContain("validation_state = 'rejected'")
    expect(migration).toContain("'execution_performed', false")
    expect(migration).not.toMatch(/work_create_task|work_delegate|work_transfer_ownership|work_escalate\(/i)
    expect(migration).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:sales_orders|customers|work_items|work_links)/i)
  })
})
