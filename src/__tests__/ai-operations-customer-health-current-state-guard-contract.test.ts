import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817006700_ai_operations_customer_health_current_state_guard.sql',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations Customer Health current-state guard contract', () => {
  it('re-runs the exact deterministic Customer Health candidate kernel', () => {
    expect(migration).toContain('FROM ai_ops.customer_health_candidates(v_business_date,2000) c')
    expect(migration).toContain('c.case_key=v_sc.case_key')
    expect(migration).toContain("'customer_health_case_no_longer_current'")
  })

  it('detects customer routing and governed target-rule drift', () => {
    expect(migration).toContain("'customer_assigned_rep_changed_after_snapshot'")
    expect(migration).toContain("'reactivation_target_identity_changed_after_snapshot'")
    expect(migration).toContain("'reactivation_dormancy_rule_changed_after_snapshot'")
    expect(migration).toContain("'reactivation_minimum_value_changed_after_snapshot'")
    expect(migration).toContain("'reactivation_scope_accountability_changed_after_snapshot'")
  })

  it('rechecks sales, progress, credit feasibility and newer interaction commitments before consequential action', () => {
    expect(migration).toContain("v_decision.decision_type IN ('CREATE_WORK','ESCALATE')")
    expect(migration).toContain("'customer_sales_changed_after_snapshot'")
    expect(migration).toContain("'reactivation_progress_changed_after_snapshot'")
    expect(migration).toContain("'customer_credit_feasibility_changed_after_snapshot'")
    expect(migration).toContain("'new_customer_interaction_after_snapshot'")
    expect(migration).toContain("'new_customer_contact_commitment_after_snapshot'")
  })

  it('prevents duplicate customer Work and validates escalation continuity', () => {
    expect(migration).toContain("wl.entity_type='customer'")
    expect(migration).toContain("'active_customer_work_collision_now'")
    expect(migration).toContain("'linked_customer_work_no_longer_active'")
  })

  it('requires active explicit Work actors and complete Customer Health capture for action', () => {
    expect(migration).toContain("'recommended_owner_unavailable'")
    expect(migration).toContain("'recommended_assignee_unavailable'")
    expect(migration).toContain("dc.domain='customer_health'")
    expect(migration).toContain("v_capture.capture_status<>'completed'")
    expect(migration).toContain("'snapshot_not_complete_for_action'")
  })

  it('blocks action if newer governed customer, employee or target context appeared', () => {
    expect(migration).toContain("oc.subject_type='customer'")
    expect(migration).toContain("oc.subject_type='employee'")
    expect(migration).toContain("oc.subject_type='target'")
    expect(migration).toContain("'new_customer_governed_context_after_snapshot'")
  })

  it('preserves the audited Receivables/Sales guard and adds Customer Health as a dispatcher extension', () => {
    expect(migration).toContain('RENAME TO current_decision_issues_receivables_sales_v4')
    expect(migration).toContain("IF v_domain='customer_health' THEN")
    expect(migration).toContain('ai_ops.current_customer_health_decision_issues(p_decision_id)')
    expect(migration).toContain('ai_ops.current_decision_issues_receivables_sales_v4(p_decision_id)')
  })

  it('is read-only against operational customer, sales, target, activity, visit, call, credit and Work tables', () => {
    expect(executableSql).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:customers|sales_orders|sales_order_items|targets|target_customers|target_progress|activities|visit_plans|visit_plan_items|call_plans|call_plan_items|customer_ledger|work_items|work_links)/i)
    expect(executableSql).not.toMatch(/recalculate_target_progress\s*\(/i)
  })
})