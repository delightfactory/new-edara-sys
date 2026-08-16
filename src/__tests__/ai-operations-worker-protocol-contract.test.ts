import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { aiOpsWorkerDecisionBatchSchema } from '@/features/ai-operations/worker-contracts'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816172000_ai_operations_worker_protocol.sql',
), 'utf8')

const limitsMigration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816164000_ai_operations_worker_limits.sql',
), 'utf8')

const inputGuardMigration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816172100_ai_operations_decision_input_guard.sql',
), 'utf8')

const contextAlignmentMigration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816172110_ai_operations_worker_context_contract_alignment.sql',
), 'utf8')

describe('AI Operations internal worker protocol contract', () => {
  it('is design-only, internal and unavailable to normal Supabase API roles', () => {
    expect(migration).toContain('DESIGN-TIME MIGRATION ONLY')
    expect(migration).not.toMatch(/CREATE OR REPLACE FUNCTION\s+public\.ai_ops_worker/i)
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.worker_claim_next_run(TEXT, INTEGER) FROM PUBLIC, anon, authenticated, service_role;')
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions(UUID, TEXT, TEXT, JSONB) FROM PUBLIC, anon, authenticated, service_role;')
    expect(migration).not.toMatch(/GRANT\s+EXECUTE/i)
    expect(contextAlignmentMigration).toContain('REVOKE ALL ON FUNCTION ai_ops.worker_get_context(UUID, TEXT)')
    expect(contextAlignmentMigration).not.toMatch(/GRANT\s+EXECUTE/i)
  })

  it('claims due/recoverable runs with row locking and bounded leases', () => {
    expect(migration).toContain("r.status = 'pending'")
    expect(migration).toContain("r.status IN ('claimed','reasoning')")
    expect(migration).toContain('r.lease_expires_at <= v_now')
    expect(migration).toContain('FOR UPDATE SKIP LOCKED')
    expect(migration).toContain('LEAST(GREATEST(COALESCE(p_lease_seconds, 1200), 300), 1800)')
    expect(migration).toContain("checkpoint = 'claimed'")
  })

  it('builds context from frozen snapshot evidence and never mutable live case evidence', () => {
    expect(migration).toContain('ai_ops.build_credit_snapshot(p_run_id, v_settings.max_cases_per_snapshot)')
    expect(migration).toContain('FROM ai_ops.snapshot_cases sc')
    expect(migration).toContain("'responsibility_evidence', sc.responsibility_evidence")
    expect(migration).toContain("'operational_context', sc.operational_context")
    expect(migration).toContain("'case_status_at_snapshot', sc.case_status")
  })

  it('enforces a hard serialized context budget instead of silently dropping evidence', () => {
    expect(limitsMigration).toContain('max_worker_context_bytes INTEGER NOT NULL DEFAULT 65536')
    expect(migration).toContain('v_context_bytes := octet_length(convert_to(v_body::TEXT, \'UTF8\'))')
    expect(migration).toContain('v_context_bytes > v_settings.max_worker_context_bytes')
    expect(migration).toContain("checkpoint = 'context_budget_blocked'")
    expect(migration).toContain("'reason', 'context_budget_exceeded'")
  })

  it('binds staged decisions to an exact deterministic context identity', () => {
    expect(migration).toContain('v_hash := md5(v_body::TEXT)')
    expect(migration).toContain("'worker_context_hash', v_hash")
    expect(migration).toContain("v_run.result_summary->>'worker_context_hash' IS DISTINCT FROM p_context_hash")
    expect(migration).toContain("'worker_submission_hash', v_submission_hash")
  })

  it('requires one decision per frozen case while allowing a legitimate zero-case/zero-action run', () => {
    expect(migration).toContain('v_decision_count <> v_domain_capture.case_count')
    expect(migration).toContain('one decision is required for every frozen case')
    expect(migration).toContain("'zero_cases_allows_zero_decisions', true")
    expect(migration).toContain("'zero_action_run', v_action_count = 0")
  })

  it('rejects chain-of-thought-like extra fields and bounds rationale/action text', () => {
    expect(migration).toContain('decision payload contains unsupported fields')
    expect(migration).toContain("'case_id','decision_type','concise_rationale','confidence'")
    expect(migration).toContain('NOT BETWEEN 1 AND 1200')
    expect(migration).toContain("length(COALESCE(item->>'expected_outcome','')) > 1000")
    expect(inputGuardMigration).toContain('length(NEW.next_action_text) > 500')
    expect(migration).toContain("'chain_of_thought_stored', false")
  })

  it('keeps action recommendations bounded and stage-only', () => {
    expect(migration).toContain("item->>'decision_type' IN ('CREATE_WORK','ESCALATE')")
    expect(migration).toContain('v_action_count > v_settings.max_actions_per_run')
    expect(migration).toContain('linked_work_item_id, validation_state, validation_detail')
    expect(migration).toContain("'stage_only', true")
    expect(migration).not.toMatch(/work_create_task|work_delegate|work_transfer_ownership|work_escalate\(/i)
    expect(migration).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:sales_orders|customers|work_items|work_links)/i)
  })

  it('acknowledges an exact post-commit staging retry by persisted submission identity', () => {
    expect(migration).toContain('v_existing_count = v_decision_count')
    expect(migration).toContain('v_existing_hashes = 1')
    expect(migration).toContain("d.management_only_metadata->>'worker_submission_hash' = v_submission_hash")
    expect(migration).toContain("'idempotent_reuse', true")
    expect(migration).toContain('run already contains a different staged decision submission')
  })

  it('keeps MONITOR and CREATE_WORK compatible with the first reviewed Work bridge', () => {
    expect(inputGuardMigration).toContain('MONITOR decisions require a future review_after')
    expect(inputGuardMigration).toContain('CREATE_WORK requires explicit owner, assignee, expected_outcome, next_action_text <= 500 chars and due_at')
    expect(inputGuardMigration).toContain('CREATE_WORK due_at must be in the future')
    expect(contextAlignmentMigration).toContain("'recommended_assignee_user_id'")
    expect(contextAlignmentMigration).toContain("'due_at'")
    expect(contextAlignmentMigration).toContain('create_work_due_at_must_be_future')

    const monitor = aiOpsWorkerDecisionBatchSchema.safeParse([{
      case_id: '11111111-1111-4111-8111-111111111111',
      decision_type: 'MONITOR',
      concise_rationale: 'حالة تستحق المراقبة فقط.',
      confidence: 0.9,
    }])
    expect(monitor.success).toBe(false)

    const createWork = aiOpsWorkerDecisionBatchSchema.safeParse([{
      case_id: '11111111-1111-4111-8111-111111111111',
      decision_type: 'CREATE_WORK',
      concise_rationale: 'الإجراء له قيمة تشغيلية واضحة.',
      confidence: 0.9,
      recommended_owner_user_id: '22222222-2222-4222-8222-222222222222',
      expected_outcome: 'تحصيل أو حسم موقف الفاتورة.',
      next_action_text: 'راجع العميل وسجل نتيجة التحصيل.',
    }])
    expect(createWork.success).toBe(false)

    const oversizedNextAction = aiOpsWorkerDecisionBatchSchema.safeParse([{
      case_id: '11111111-1111-4111-8111-111111111111',
      decision_type: 'CREATE_WORK',
      concise_rationale: 'الإجراء له قيمة تشغيلية واضحة.',
      confidence: 0.9,
      recommended_owner_user_id: '22222222-2222-4222-8222-222222222222',
      recommended_assignee_user_id: '33333333-3333-4333-8333-333333333333',
      expected_outcome: 'تحصيل أو حسم موقف الفاتورة.',
      next_action_text: 'أ'.repeat(501),
      due_at: new Date(Date.now() + 60_000).toISOString(),
    }])
    expect(oversizedNextAction.success).toBe(false)
  })
})
