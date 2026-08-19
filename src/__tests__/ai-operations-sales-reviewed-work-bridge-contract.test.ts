import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817006200_ai_operations_sales_reviewed_work_bridge.sql',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations Sales reviewed Work bridge contract', () => {
  it('preserves the existing credit safety wrapper and dispatches by frozen domain', () => {
    expect(migration).toContain('ALTER FUNCTION private.work_create_ai_reviewed_task(UUID, UUID)')
    expect(migration).toContain('RENAME TO work_create_ai_reviewed_credit_task_v2')
    expect(migration).toContain("WHEN 'receivables' THEN")
    expect(migration).toContain('private.work_create_ai_reviewed_credit_task_v2(p_decision_id,p_approved_execution_by)')
    expect(migration).toContain("WHEN 'sales' THEN")
    expect(migration).toContain('private.work_create_ai_reviewed_sales_task(p_decision_id,p_approved_execution_by)')
    expect(migration).toContain("'unsupported_work_bridge_domain'")
  })

  it('keeps kill switches and unexplained source-key collisions fail closed for new sales Work', () => {
    expect(migration).toContain("'planner_disabled_kill_switch'")
    expect(migration).toContain("'shadow_mode_blocks_operational_commit'")
    expect(migration).toContain("v_source_key := 'ai_ops:decision:' || p_decision_id::TEXT")
    expect(migration).toContain("'unexpected_source_key_collision'")
    expect(migration).toContain('v_decision.committed_work_item_id IS NOT NULL')
    expect(migration).toContain("'idempotent_reuse',true")
  })

  it('requires immutable human approval, exact fingerprint and current validation', () => {
    expect(migration).toContain('FROM ai_ops.decision_reviews')
    expect(migration).toContain("v_review.review_state <> 'approved'")
    expect(migration).toContain("'human_approval_required'")
    expect(migration).toContain("v_decision.validation_state <> 'validated'")
    expect(migration).toContain("'decision_not_validated'")
    expect(migration).toContain('v_review.decision_fingerprint IS DISTINCT FROM v_fingerprint')
    expect(migration).toContain("'review_fingerprint_mismatch'")
  })

  it('re-runs the canonical current-state guard before the first Work mutation', () => {
    const guardIndex = migration.indexOf('v_issues := ai_ops.current_decision_issues(p_decision_id)')
    const workInsertIndex = migration.indexOf('INSERT INTO public.work_items(')
    expect(guardIndex).toBeGreaterThan(-1)
    expect(workInsertIndex).toBeGreaterThan(guardIndex)
    expect(migration).toContain("'commit_revalidation_failed',true")
    expect(migration).toContain("'reason','current_state_changed'")
  })

  it('requires explicit active owner, assignee and future due date without routing defaults', () => {
    expect(migration).toContain('v_decision.recommended_owner_user_id IS NULL')
    expect(migration).toContain('v_decision.recommended_assignee_user_id IS NULL')
    expect(migration).toContain('v_decision.due_at IS NULL')
    expect(migration).toContain("'explicit_owner_assignee_and_due_required'")
    expect(migration).toContain('v_decision.due_at <= v_now')
    expect(migration).toContain("'proposed_due_at_not_future'")
    expect(migration).toContain('private.work_actor_is_active(v_decision.recommended_owner_user_id)')
    expect(migration).toContain('private.work_actor_is_active(v_decision.recommended_assignee_user_id)')
  })

  it('uses the canonical Work target allowlist and creates only a target link for the sales condition', () => {
    expect(migration).toContain("private.work_link_entity_exists('target',v_target_id)")
    expect(migration).toContain("'target',")
    expect(migration).toContain("'primary',")
    expect(migration).not.toMatch(/CREATE\s+TABLE\s+(?:public\.)?work_(?:entity_)?links/i)
  })

  it('creates system-origin employee-safe Work without exposing management rationale', () => {
    expect(migration).toContain("'system'::public.work_source_kind")
    expect(migration).toContain("'draft'::public.work_item_status")
    expect(migration).toContain("status='open'::public.work_item_status")
    expect(migration).toContain('إجراء تشغيلي ناتج عن مراجعة مسار هدف مبيعات معتمد.')
    expect(migration).toContain("'management_rationale_exposed',false")
    expect(migration).toContain('creator_user_id,requester_user_id')
    expect(migration).toContain("'work.created'")
    expect(migration).toContain("'work.activated'")
    expect(migration).not.toMatch(/description[\s\S]{0,400}v_decision\.concise_rationale/)
    expect(migration).not.toMatch(/description[\s\S]{0,400}v_decision\.responsibility_basis/)
  })

  it('mutates only Work and AI provenance, never targets or sales operational data', () => {
    expect(migration).toContain('INSERT INTO public.work_items(')
    expect(migration).toContain('INSERT INTO public.work_links(')
    expect(migration).toContain('UPDATE ai_ops.decisions')
    expect(migration).toContain('UPDATE ai_ops.cases')
    expect(executableSql).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:targets|target_progress|sales_orders|sales_order_items|activities|visit_plans)/i)
    expect(executableSql).not.toMatch(/recalculate_target_progress\s*\(/i)
  })

  it('keeps the public management commit surface unchanged and all private bridge primitives revoked', () => {
    expect(migration).not.toMatch(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.ai_ops_commit_reviewed_decision/i)
    for (const signature of [
      'private.work_create_ai_reviewed_credit_task_v2(UUID, UUID)',
      'private.work_create_ai_reviewed_sales_task(UUID, UUID)',
      'private.work_create_ai_reviewed_task(UUID, UUID)',
    ]) {
      expect(migration).toContain(`REVOKE ALL ON FUNCTION ${signature}`)
    }
  })
})
