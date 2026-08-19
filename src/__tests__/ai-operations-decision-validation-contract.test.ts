import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816172500_ai_operations_decision_validation.sql',
), 'utf8')

describe('AI Operations staged decision validation contract', () => {
  it('is internal, design-only and unavailable to normal API roles', () => {
    expect(migration).toContain('DESIGN-TIME MIGRATION ONLY')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION ai_ops.validate_staged_run')
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.validate_staged_run(UUID) FROM PUBLIC, anon, authenticated, service_role;')
    expect(migration).not.toMatch(/GRANT\s+EXECUTE/i)
  })

  it('accepts staged runs only and validates against the same immutable run snapshot', () => {
    expect(migration).toContain("v_run.status <> 'staged'")
    expect(migration).toContain('FROM ai_ops.snapshots')
    expect(migration).toContain('WHERE run_id = p_run_id')
    expect(migration).toContain('WHERE sc.snapshot_id = v_snapshot.id')
    expect(migration).toContain('AND sc.case_id = v_decision.case_id')
  })

  it('rechecks the current overdue reality with Cairo business-date semantics', () => {
    expect(migration).toContain("AT TIME ZONE 'Africa/Cairo'")
    expect(migration).toContain("v_current_order.status NOT IN ('delivered','partially_delivered')")
    expect(migration).toContain("v_current_order.payment_terms NOT IN ('credit','mixed')")
    expect(migration).toContain('v_current_order.due_date >= v_business_date')
    expect(migration).toContain('v_current_order.remaining_amount <= 0')
    expect(migration).toContain("'invoice_no_longer_overdue_candidate'")
  })

  it('rejects factual drift instead of executing a stale recommendation', () => {
    expect(migration).toContain("'due_date_changed_after_snapshot'")
    expect(migration).toContain("'remaining_balance_changed_after_snapshot'")
    expect(migration).toContain("'customer_assignment_changed_after_snapshot'")
    expect(migration).toContain("'order_rep_changed_after_snapshot'")
    expect(migration).toContain("'credit_override_changed_after_snapshot'")
    expect(migration).toContain("'due_date_history_changed_after_snapshot'")
    expect(migration).toContain("'customer_credit_policy_changed_after_snapshot'")
  })

  it('detects newer governed human context after the frozen snapshot', () => {
    expect(migration).toContain('FROM ai_ops.operational_context oc')
    expect(migration).toContain('oc.updated_at > v_sc.created_at')
    expect(migration).toContain("oc.visibility IN ('management','standard')")
    expect(migration).toContain("oc.confidence_class <> 'ai_inference' OR oc.approved_by_user_id IS NOT NULL")
    expect(migration).toContain("'new_governed_context_after_snapshot'")
  })

  it('revalidates Work actors and exact active Work collision before CREATE_WORK', () => {
    expect(migration).toContain("v_decision.decision_type = 'CREATE_WORK'")
    expect(migration).toContain('private.work_actor_is_active(v_decision.recommended_owner_user_id)')
    expect(migration).toContain('private.work_actor_is_active(v_decision.recommended_assignee_user_id)')
    expect(migration).toContain('FROM public.work_links wl')
    expect(migration).toContain("wl.entity_type = 'sales_order'")
    expect(migration).toContain("'active_work_collision_now'")
  })

  it('requires the frozen linked Work to remain active before ESCALATE', () => {
    expect(migration).toContain("v_decision.decision_type = 'ESCALATE'")
    expect(migration).toContain("'escalation_has_no_linked_work'")
    expect(migration).toContain("'linked_work_no_longer_active'")
    expect(migration).toContain("wi.status NOT IN ('done'::public.work_item_status, 'cancelled'::public.work_item_status)")
  })

  it('blocks action decisions from partial snapshots while preserving passive review semantics', () => {
    expect(migration).toContain("v_decision.decision_type IN ('CREATE_WORK','ESCALATE')")
    expect(migration).toContain("v_snapshot.snapshot_status <> 'ready'")
    expect(migration).toContain("v_domain_capture.capture_status <> 'completed'")
    expect(migration).toContain("'snapshot_not_complete_for_action'")
  })

  it('changes only ai_ops validation state and never performs operational execution', () => {
    expect(migration).toContain("validation_state = 'validated'")
    expect(migration).toContain("validation_state = 'rejected'")
    expect(migration).toContain("'execution_performed', false")
    expect(migration).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:sales_orders|customers|work_items|work_links|customer_credit_history|sales_order_due_date_history)/i)
    expect(migration).not.toMatch(/work_create_task|work_delegate|work_transfer_ownership|work_escalate\(/i)
  })
})
