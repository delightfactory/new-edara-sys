import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817006800_ai_operations_customer_health_reviewed_work_bridge.sql',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations Customer Health reviewed Work bridge contract', () => {
  it('keeps planner kill switches, deterministic source keys and retry idempotency', () => {
    expect(migration).toContain("'planner_disabled_kill_switch'")
    expect(migration).toContain("'shadow_mode_blocks_operational_commit'")
    expect(migration).toContain("v_source_key:='ai_ops:decision:'||p_decision_id::TEXT")
    expect(migration).toContain("'unexpected_source_key_collision'")
    expect(migration).toContain("'idempotent_reuse',true")
  })

  it('requires immutable human approval, exact reviewed fingerprint and validation', () => {
    expect(migration).toContain('FROM ai_ops.decision_reviews')
    expect(migration).toContain("v_review.review_state<>'approved'")
    expect(migration).toContain("'human_approval_required'")
    expect(migration).toContain("v_decision.validation_state<>'validated'")
    expect(migration).toContain("'decision_not_validated'")
    expect(migration).toContain('v_review.decision_fingerprint IS DISTINCT FROM v_fingerprint')
    expect(migration).toContain("'review_fingerprint_mismatch'")
  })

  it('re-runs the canonical current-state guard immediately before the first Work mutation', () => {
    const guardIndex = migration.indexOf('v_issues:=ai_ops.current_decision_issues(p_decision_id)')
    const workInsertIndex = migration.indexOf('INSERT INTO public.work_items(')
    expect(guardIndex).toBeGreaterThan(-1)
    expect(workInsertIndex).toBeGreaterThan(guardIndex)
    expect(migration).toContain("'commit_revalidation_failed',true")
    expect(migration).toContain("'reason','current_state_changed'")
  })

  it('requires explicit active owner, assignee and a future due date', () => {
    expect(migration).toContain('v_decision.recommended_owner_user_id IS NULL')
    expect(migration).toContain('v_decision.recommended_assignee_user_id IS NULL')
    expect(migration).toContain('v_decision.due_at IS NULL')
    expect(migration).toContain("'explicit_owner_assignee_and_due_required'")
    expect(migration).toContain("'proposed_due_at_not_future'")
    expect(migration).toContain('private.work_actor_is_active(v_decision.recommended_owner_user_id)')
    expect(migration).toContain('private.work_actor_is_active(v_decision.recommended_assignee_user_id)')
  })

  it('creates employee-safe system Work linked primarily to the customer and secondarily to a governing target', () => {
    expect(migration).toContain("'system'::public.work_source_kind")
    expect(migration).toContain("'customer',v_customer_id,'primary'")
    expect(migration).toContain("'target',v_target_id,'governed_by'")
    expect(migration).toContain("'management_rationale_exposed',false")
    expect(migration).toContain('متابعة إعادة تنشيط العميل')
    expect(migration).toContain("'work.created'")
    expect(migration).toContain("'work.activated'")
  })

  it('mutates only Work and AI provenance, never operational customer-domain sources', () => {
    expect(migration).toContain('INSERT INTO public.work_items(')
    expect(migration).toContain('INSERT INTO public.work_links(')
    expect(migration).toContain('UPDATE ai_ops.decisions')
    expect(migration).toContain('UPDATE ai_ops.cases')
    expect(executableSql).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:customers|sales_orders|sales_order_items|targets|target_customers|target_progress|activities|visit_plans|visit_plan_items|call_plans|call_plan_items|customer_ledger)/i)
    expect(executableSql).not.toMatch(/recalculate_target_progress\s*\(/i)
  })

  it('preserves the reviewed Receivables/Sales dispatcher and extends only the Customer Health branch', () => {
    expect(migration).toContain('RENAME TO work_create_ai_reviewed_task_receivables_sales_v3')
    expect(migration).toContain("IF v_domain='customer_health' THEN")
    expect(migration).toContain('private.work_create_ai_reviewed_customer_health_task(')
    expect(migration).toContain('private.work_create_ai_reviewed_task_receivables_sales_v3(')
  })

  it('keeps every new or renamed bridge primitive private', () => {
    for (const signature of [
      'private.work_create_ai_reviewed_customer_health_task(UUID,UUID)',
      'private.work_create_ai_reviewed_task_receivables_sales_v3(UUID,UUID)',
      'private.work_create_ai_reviewed_task(UUID,UUID)',
    ]) {
      expect(migration).toContain(`REVOKE ALL ON FUNCTION ${signature}`)
    }
  })
})