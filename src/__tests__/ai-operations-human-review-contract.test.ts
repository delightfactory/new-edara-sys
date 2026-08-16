import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const foundation = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816173000_ai_operations_human_review.sql',
), 'utf8')
const correction = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816173100_ai_operations_human_review_revalidation_fix.sql',
), 'utf8')

describe('AI Operations human decision review contract', () => {
  it('separates immutable human review from system validation state', () => {
    expect(foundation).toContain('CREATE TABLE ai_ops.decision_reviews')
    expect(foundation).toContain('review_state TEXT NOT NULL')
    expect(foundation).toContain('validation_state_at_review TEXT NOT NULL')
    expect(foundation).toContain('decision_fingerprint TEXT NOT NULL')
    expect(foundation).toContain('decision_id UUID NOT NULL UNIQUE')
  })

  it('keeps review history immutable and closed to direct browser table access', () => {
    expect(foundation).toContain('CREATE TRIGGER trg_ai_ops_decision_reviews_immutable')
    expect(foundation).toContain('BEFORE UPDATE OR DELETE ON ai_ops.decision_reviews')
    expect(foundation).toContain('ALTER TABLE ai_ops.decision_reviews ENABLE ROW LEVEL SECURITY;')
    expect(foundation).toContain('REVOKE ALL ON TABLE ai_ops.decision_reviews FROM authenticated;')
  })

  it('exposes only a permission-gated management review RPC', () => {
    expect(correction).toContain('CREATE OR REPLACE FUNCTION public.ai_ops_review_decision')
    expect(correction).toContain('private.work_actor_is_active(v_actor)')
    expect(correction).toContain("public.check_permission(v_actor, 'work.policies.manage')")
    expect(correction).toContain('REVOKE ALL ON FUNCTION public.ai_ops_review_decision(UUID, TEXT, TEXT) FROM anon;')
    expect(correction).toContain('GRANT EXECUTE ON FUNCTION public.ai_ops_review_decision(UUID, TEXT, TEXT) TO authenticated;')
  })

  it('revalidates current reality at approval time instead of trusting older validation', () => {
    expect(correction).toContain('v_issues := ai_ops.current_decision_issues(p_decision_id)')
    expect(correction).toContain("'approval_revalidated_against_current_state', true")
    expect(correction).toContain("'approval_revalidation_at', v_now")
  })

  it('persists stale rejection and returns a blocked result instead of raising after the update', () => {
    const failedBranch = correction.slice(
      correction.indexOf('IF jsonb_array_length(v_issues) > 0 THEN'),
      correction.indexOf("UPDATE ai_ops.decisions\n    SET\n      validation_state = 'validated'"),
    )
    expect(failedBranch).toContain("validation_state = 'rejected'")
    expect(failedBranch).toContain("'approval_blocked', true")
    expect(failedBranch).toContain("'reason', 'current_state_changed'")
    expect(failedBranch).not.toContain('RAISE EXCEPTION')
  })

  it('is idempotent only for the same reviewer, decision fingerprint, state and note', () => {
    expect(correction).toContain('v_existing.review_state = p_review_state')
    expect(correction).toContain('v_existing.reviewed_by_user_id = v_actor')
    expect(correction).toContain('v_existing.decision_fingerprint = v_fingerprint')
    expect(correction).toContain("'idempotent_reuse', true")
    expect(correction).toContain('القرار تمت مراجعته بالفعل ولا يمكن استبدال سجل المراجعة')
  })

  it('never performs operational execution', () => {
    for (const sql of [foundation, correction]) {
      expect(sql).not.toMatch(/work_create_task|work_delegate|work_transfer_ownership|work_escalate\(/i)
      expect(sql).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:sales_orders|customers|work_items|work_links)/i)
    }
    expect(correction).toContain("'execution_performed', false")
  })
})
