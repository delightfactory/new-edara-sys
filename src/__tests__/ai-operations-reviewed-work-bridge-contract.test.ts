import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816173500_ai_operations_reviewed_work_bridge.sql',
), 'utf8')

describe('AI Operations human-approved Work bridge contract', () => {
  it('is design-time and limits first operational bridge scope to CREATE_WORK', () => {
    expect(migration).toContain('DESIGN-TIME MIGRATION ONLY')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION private.work_create_ai_reviewed_task')
    expect(migration).toContain("v_decision.decision_type <> 'CREATE_WORK'")
    expect(migration).toContain("'bridge_supports_create_work_only'")
    expect(migration).not.toMatch(/work_escalate\(/i)
  })

  it('accepts only decision id from management and never impersonates the approving manager as Work creator/requester', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.ai_ops_commit_reviewed_decision(p_decision_id UUID)')
    expect(migration).toContain('v_actor UUID := auth.uid()')
    expect(migration).toContain('private.work_actor_is_active(v_actor)')
    expect(migration).toContain("public.check_permission(v_actor, 'work.policies.manage')")
    expect(migration).toContain('private.work_create_ai_reviewed_task(p_decision_id, v_actor)')
    expect(migration).toContain('creator_user_id,')
    expect(migration).toContain('requester_user_id,')
    expect(migration).toMatch(/creator_user_id,[\s\S]*requester_user_id,[\s\S]*accountable_owner_user_id/)
    expect(migration).not.toMatch(/creator_user_id[\s\S]{0,400}p_approved_execution_by/)
  })

  it('requires immutable human approval and a currently validated decision', () => {
    expect(migration).toContain('FROM ai_ops.decision_reviews')
    expect(migration).toContain("v_review.review_state <> 'approved'")
    expect(migration).toContain("'human_approval_required'")
    expect(migration).toContain("v_decision.validation_state <> 'validated'")
    expect(migration).toContain("'decision_not_validated'")
    expect(migration).toContain('v_review.decision_fingerprint IS DISTINCT FROM v_fingerprint')
  })

  it('re-runs the shared current-state guard inside the commit transaction before first Work mutation', () => {
    const guard = migration.indexOf('v_issues := ai_ops.current_decision_issues(p_decision_id)')
    const insert = migration.indexOf('INSERT INTO public.work_items(')
    expect(guard).toBeGreaterThan(-1)
    expect(insert).toBeGreaterThan(guard)
    expect(migration).toContain("'commit_revalidation_failed', true")
    expect(migration).toContain("'reason', 'current_state_changed'")
    expect(migration).toContain("commit_status = 'rejected'")
  })

  it('never guesses owner, assignee or deadline', () => {
    expect(migration).toContain('v_decision.recommended_owner_user_id IS NULL')
    expect(migration).toContain('v_decision.recommended_assignee_user_id IS NULL')
    expect(migration).toContain('v_decision.due_at IS NULL')
    expect(migration).toContain("'explicit_owner_assignee_and_due_required'")
    expect(migration).toContain("'proposed_due_at_not_future'")
  })

  it('uses the actual deployed Work field names and canonical draft-to-open lifecycle', () => {
    expect(migration).toContain('accountable_owner_user_id,')
    expect(migration).toContain('current_assignee_user_id,')
    expect(migration).toContain('creator_user_id,')
    expect(migration).toContain('state_version,')
    expect(migration).toContain("'draft'::public.work_item_status")
    expect(migration).toContain("status = 'open'::public.work_item_status")
    expect(migration).toContain('state_version = state_version + 1')
    expect(migration).not.toMatch(/\bowner_user_id\s*,[\s\n]*\bassignee_user_id\s*,/)
    expect(migration).not.toContain('created_by_user_id,\n    version')
  })

  it('uses deterministic system-source idempotency and the existing unique source-key convention', () => {
    expect(migration).toContain("v_source_key := 'ai_ops:decision:' || p_decision_id::TEXT")
    expect(migration).toContain("wi.source_kind = 'system'::public.work_source_kind")
    expect(migration).toContain('AND wi.source_key = v_source_key')
    expect(migration).toContain("'system'::public.work_source_kind")
    expect(migration).toContain("'origin', 'ai_ops'")
    expect(migration).toContain("commit_status = 'committed'")
  })

  it('creates bounded employee-visible Work text without exposing management rationale', () => {
    expect(migration).toContain('إجراء تشغيلي ناتج عن مراجعة حالة ائتمانية متأخرة.')
    expect(migration).toContain("'management_rationale_exposed', false")
    expect(migration).toContain("'employee_safe_reason', v_decision.employee_safe_reason")
    expect(migration).not.toMatch(/description[\s\S]{0,300}v_decision\.concise_rationale/)
    expect(migration).not.toMatch(/description[\s\S]{0,300}v_decision\.responsibility_basis/)
  })

  it('links created Work to exact sales order and customer using existing work_links', () => {
    expect(migration).toContain('INSERT INTO public.work_links(')
    expect(migration).toContain("'sales_order'")
    expect(migration).toContain("'customer'")
    expect(migration).toContain('ON CONFLICT (work_item_id, entity_type, entity_id, relation_type) DO NOTHING')
    expect(migration).not.toMatch(/CREATE\s+TABLE\s+(?:public\.)?work_(?:entity_)?links/i)
  })

  it('uses exact five-argument Work system-event helper and canonical assignment notification event', () => {
    expect(migration).toContain("private.work_append_system_event(uuid,text,public.work_item_status,public.work_item_status,jsonb)")
    expect(migration).toContain("'work.created'")
    expect(migration).toContain("'work.activated'")
    expect(migration).toContain('private.ai_ops_append_work_system_event')
    expect(migration).not.toContain("private.work_append_system_event(uuid,text,jsonb)")
  })

  it('updates only AI provenance/state after Work mutation and performs no Sales/Credit mutation', () => {
    expect(migration).toContain('committed_work_item_id = v_work.id')
    expect(migration).toContain("status = 'actioned'")
    expect(migration).toContain('work_created_count = work_created_count + 1')
    expect(migration).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:sales_orders|customers|customer_credit_history|sales_order_due_date_history)/i)
  })

  it('keeps private mutation primitive unavailable to normal API roles', () => {
    expect(migration).toContain('REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_task(UUID, UUID)')
    expect(migration).toContain('FROM PUBLIC, anon, authenticated, service_role;')
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) FROM anon;')
  })
})
