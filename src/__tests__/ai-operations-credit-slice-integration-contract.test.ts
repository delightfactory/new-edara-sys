import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

function migration(name: string) {
  return readFileSync(resolve(process.cwd(), 'supabase/migrations', name), 'utf8')
}

const files = {
  foundation: '20260816163504_ai_operations_foundation.sql',
  alignment: '20260816171900_ai_operations_runtime_contract_alignment.sql',
  worker: '20260816172000_ai_operations_worker_protocol.sql',
  inputGuard: '20260816172100_ai_operations_decision_input_guard.sql',
  contextAlignment: '20260816172110_ai_operations_worker_context_contract_alignment.sql',
  validation: '20260816172500_ai_operations_decision_validation.sql',
  currentGuard: '20260816172600_ai_operations_current_state_guard.sql',
  review: '20260816173000_ai_operations_human_review.sql',
  reviewFix: '20260816173100_ai_operations_human_review_revalidation_fix.sql',
  bridge: '20260816173500_ai_operations_reviewed_work_bridge.sql',
} as const

const sql = Object.fromEntries(
  Object.entries(files).map(([key, filename]) => [key, migration(filename)]),
) as Record<keyof typeof files, string>

describe('AI Operations Credit slice cross-migration integration contract', () => {
  it('orders schema alignment before every function that consumes the final runtime columns', () => {
    const ordered = Object.values(files)
    expect([...ordered].sort()).toEqual(ordered)
    expect(files.alignment < files.worker).toBe(true)
    expect(files.worker < files.validation).toBe(true)
    expect(files.validation < files.currentGuard).toBe(true)
    expect(files.currentGuard < files.review).toBe(true)
    expect(files.reviewFix < files.bridge).toBe(true)
  })

  it('aligns foundation drift before worker references claimed/prompt and final decision fields', () => {
    expect(sql.foundation).toContain("validation_status TEXT NOT NULL DEFAULT 'pending'")
    expect(sql.foundation).toContain('work_item_id UUID')

    expect(sql.alignment).toContain('ADD COLUMN claimed_at TIMESTAMPTZ')
    expect(sql.alignment).toContain("ADD COLUMN prompt_version TEXT NOT NULL DEFAULT 'v1'")
    expect(sql.alignment).toContain('RENAME COLUMN validation_status TO validation_state')
    expect(sql.alignment).toContain('RENAME COLUMN work_item_id TO committed_work_item_id')
    expect(sql.alignment).toContain('ADD COLUMN next_action_text TEXT')
    expect(sql.alignment).toContain('ADD COLUMN due_at TIMESTAMPTZ')
    expect(sql.alignment).toContain('ADD COLUMN linked_work_item_id UUID')
    expect(sql.alignment).toContain('ADD COLUMN validated_at TIMESTAMPTZ')
    expect(sql.alignment).toContain('ADD COLUMN validated_by_user_id UUID')
    expect(sql.alignment).toContain('ADD COLUMN committed_at TIMESTAMPTZ')
    expect(sql.alignment).toContain("validation_state IN ('pending','validated','rejected')")

    expect(sql.worker).toContain('claimed_at = v_now')
    expect(sql.worker).toContain("'prompt_version', v_run.prompt_version")
    expect(sql.worker).toContain('linked_work_item_id, validation_state, validation_detail')
    expect(sql.currentGuard).toContain("validation_state = 'validated'")
    expect(sql.reviewFix).toContain("validation_state = 'rejected'")
    expect(sql.bridge).toContain('committed_work_item_id')
    expect(sql.bridge).toContain('committed_at')
  })

  it('keeps staged CREATE_WORK executable without hidden routing/deadline defaults', () => {
    expect(sql.inputGuard).toContain('NEW.recommended_owner_user_id IS NULL')
    expect(sql.inputGuard).toContain('NEW.recommended_assignee_user_id IS NULL')
    expect(sql.inputGuard).toContain('NEW.due_at IS NULL')
    expect(sql.inputGuard).toContain('NEW.due_at <= v_now')
    expect(sql.inputGuard).toContain('MONITOR decisions require a future review_after')

    expect(sql.contextAlignment).toContain("'recommended_owner_user_id'")
    expect(sql.contextAlignment).toContain("'recommended_assignee_user_id'")
    expect(sql.contextAlignment).toContain("'expected_outcome'")
    expect(sql.contextAlignment).toContain("'next_action_text'")
    expect(sql.contextAlignment).toContain("'due_at'")
    expect(sql.contextAlignment).toContain('create_work_due_at_must_be_future')
    expect(sql.contextAlignment).toContain('monitor_review_after_must_be_future')

    expect(sql.bridge).toContain("'explicit_owner_assignee_and_due_required'")
    expect(sql.bridge).not.toMatch(/COALESCE\(v_decision\.recommended_assignee_user_id\s*,/)
    expect(sql.bridge).not.toMatch(/COALESCE\(v_decision\.due_at\s*,/)
  })

  it('uses one current-state safety source for final validation, approval revalidation and commit', () => {
    expect(sql.currentGuard).toContain('CREATE OR REPLACE FUNCTION ai_ops.current_decision_issues')
    expect(sql.currentGuard).toContain('CREATE OR REPLACE FUNCTION ai_ops.validate_staged_run')
    expect(sql.currentGuard).toContain('v_reasons := ai_ops.current_decision_issues(v_decision.id)')
    expect(sql.reviewFix).toContain('ai_ops.current_decision_issues(p_decision_id)')
    expect(sql.bridge).toContain('ai_ops.current_decision_issues(p_decision_id)')

    const commitGuard = sql.bridge.indexOf('v_issues := ai_ops.current_decision_issues(p_decision_id)')
    const firstWorkWrite = sql.bridge.indexOf('INSERT INTO public.work_items(')
    expect(commitGuard).toBeGreaterThan(-1)
    expect(firstWorkWrite).toBeGreaterThan(commitGuard)
  })

  it('keeps technical validation distinct from immutable human review', () => {
    expect(sql.currentGuard).toContain("validation_state = 'validated'")
    expect(sql.review).toContain('CREATE TABLE ai_ops.decision_reviews')
    expect(sql.review).toContain("CHECK (review_state IN ('approved','rejected'))")
    expect(sql.bridge).toContain("v_review.review_state <> 'approved'")
    expect(sql.bridge).toContain("v_decision.validation_state <> 'validated'")
  })

  it('matches deployed Work Engine fields/events and preserves system provenance', () => {
    expect(sql.bridge).toContain('accountable_owner_user_id,')
    expect(sql.bridge).toContain('current_assignee_user_id,')
    expect(sql.bridge).toContain('creator_user_id,')
    expect(sql.bridge).toContain('requester_user_id,')
    expect(sql.bridge).toContain('state_version,')
    expect(sql.bridge).toContain("'system'::public.work_source_kind")
    expect(sql.bridge).toContain('private.work_append_system_event(uuid,text,public.work_item_status,public.work_item_status,jsonb)')
    expect(sql.bridge).toContain("'work.created'")
    expect(sql.bridge).toContain("'work.activated'")
    expect(sql.bridge).not.toContain('private.work_append_system_event(uuid,text,jsonb)')
  })

  it('keeps first operational bridge human-approved CREATE_WORK-only and idempotent', () => {
    expect(sql.bridge).toContain("v_decision.decision_type <> 'CREATE_WORK'")
    expect(sql.bridge).toContain("v_source_key := 'ai_ops:decision:' || p_decision_id::TEXT")
    expect(sql.bridge).toContain("wi.source_kind = 'system'::public.work_source_kind")
    expect(sql.bridge).toContain('AND wi.source_key = v_source_key')
    expect(sql.bridge).toContain("commit_status = 'committed'")
    expect(sql.bridge).not.toMatch(/work_escalate\(/i)
    expect(sql.bridge).not.toMatch(/auto_commit_enabled\s*=\s*true/i)
  })

  it('has no autonomous worker execution grant and no Sales/Credit mutation path', () => {
    expect(sql.worker).toContain('REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions(UUID, TEXT, TEXT, JSONB) FROM PUBLIC, anon, authenticated, service_role;')
    expect(sql.contextAlignment).toContain('REVOKE ALL ON FUNCTION ai_ops.worker_get_context(UUID, TEXT)')
    expect(sql.worker).not.toMatch(/GRANT\s+EXECUTE/i)
    expect(sql.contextAlignment).not.toMatch(/GRANT\s+EXECUTE/i)

    const operationalMutation = /(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:sales_orders|customers|customer_credit_history|sales_order_due_date_history)/i
    expect(sql.currentGuard).not.toMatch(operationalMutation)
    expect(sql.review).not.toMatch(operationalMutation)
    expect(sql.reviewFix).not.toMatch(operationalMutation)
    expect(sql.bridge).not.toMatch(operationalMutation)
  })
})
