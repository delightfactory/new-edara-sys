import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const blockedFix = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817011900_ai_operations_blocked_review_fingerprint_fix.sql',
), 'utf8')
const finalReview = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817012000_ai_operations_review_quality_scope_fix.sql',
), 'utf8')

describe('AI Operations final human review semantics', () => {
  it('preserves current-state approval blocks as valid fail-closed results without requiring a review row', () => {
    expect(blockedFix).toContain("v_result->>'approval_blocked'")
    expect(blockedFix).toContain("'full_review_fingerprint_bound',false")
    expect(blockedFix).toContain('ai_ops_review_decision_pre_full_fingerprint_v1')
  })

  it('requires complete structured quality for approval only', () => {
    expect(finalReview).toContain("IF p_review_state='approved'")
    expect(finalReview).toContain("v_run.prompt_version='v3'")
    expect(finalReview).toContain('v3 decision cannot be approved')
    expect(finalReview).not.toContain('v3 decision cannot be rejected')
  })

  it('allows successful approve/reject rows to receive the immutable full fingerprint', () => {
    expect(finalReview).toContain('SELECT * INTO v_review')
    expect(finalReview).toContain('ai_ops.decision_full_fingerprint(p_decision_id)')
    expect(finalReview).toContain('INSERT INTO ai_ops.decision_review_bindings')
    expect(finalReview).toContain("'full_review_fingerprint_bound',true")
  })
})
