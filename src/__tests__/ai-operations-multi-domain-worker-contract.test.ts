import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { aiOpsWorkerContextResponseSchema } from '@/features/ai-operations/worker-contracts'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817006000_ai_operations_multi_domain_worker.sql',
), 'utf8')

const closure = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817010400_ai_operations_snapshot_global_context_freeze.sql',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations multi-domain worker contract', () => {
  it('adds one operational snapshot orchestrator without creating parallel planner state', () => {
    expect(migration).toContain('DESIGN-TIME MIGRATION ONLY')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION ai_ops.build_operational_snapshot')
    expect(migration).toContain('ai_ops.build_credit_snapshot')
    expect(migration).toContain('ai_ops.refresh_sales_target_cases')
    expect(migration).not.toMatch(/CREATE\s+TABLE/i)
    expect(migration).not.toMatch(/ALTER\s+TABLE/i)
    expect(migration).not.toMatch(/CREATE\s+TRIGGER/i)
  })

  it('shares one hard case budget between receivables and sales without cross-domain severity ranking', () => {
    expect(migration).toContain('v_credit_quota := (v_limit + 1) / 2')
    expect(migration).toContain('v_sales_quota := v_limit / 2')
    expect(migration).toContain('v_total_cases > v_limit')
    expect(migration).toContain("dc.domain = 'receivables'")
    expect(migration).toContain("dc.domain = 'sales'")
    expect(migration).not.toMatch(/ORDER BY[\s\S]{0,300}(?:sc\.)?severity/i)
    expect(executableSql).not.toMatch(/recalculate_target_progress\s*\(/i)
  })

  it('records a zero-capacity sales capture instead of forcing one sales case past the global budget', () => {
    expect(migration).toContain("'global_budget_exhausted'")
    expect(migration).toContain("'remaining_case_budget', 0")
    expect(migration).toContain("CASE WHEN v_sales_has_candidate THEN 'partial' ELSE 'completed' END")
    expect(migration).toContain("'capture_marker_written', true")
  })

  it('never mutates an already context-bound credit-only snapshot to add sales evidence', () => {
    expect(migration).toContain("NULLIF(v_run.result_summary->>'worker_context_hash', '') IS NOT NULL")
    expect(migration).toContain('existing snapshot is already bound to a worker context and cannot add a new domain')
  })

  it('builds worker context from every frozen case and exposes immutable domain captures', () => {
    expect(migration).toContain('ALTER FUNCTION ai_ops.worker_get_context(UUID, TEXT)')
    expect(migration).toContain('RENAME TO worker_get_context_credit_v2')
    expect(migration).toContain("'{snapshot,domain_captures}'")
    expect(migration).toContain('FROM ai_ops.snapshot_cases sc')
    expect(migration).toContain('WHERE sc.snapshot_id = v_snapshot.id')
    expect(migration).not.toMatch(/WHERE sc\.snapshot_id = v_snapshot\.id\s+AND sc\.domain = 'receivables'/)
    expect(migration).toContain("'all_domain_captures_complete'")
    expect(migration).toContain("'multi_domain_context', true")
    expect(closure).toContain("'{planner_policy}'")
    expect(closure).toContain("'{global_operational_context}'")
  })

  it('recomputes byte budget and context identity after sales evidence is included', () => {
    expect(migration).toContain("octet_length(convert_to(v_body::TEXT, 'UTF8'))")
    expect(migration).toContain('v_context_bytes > v_settings.max_worker_context_bytes')
    expect(migration).toContain('v_hash := md5(v_body::TEXT)')
    expect(migration).toContain("'worker_context_hash', v_hash")
  })

  it('requires one decision for every frozen case across all domains', () => {
    expect(migration).toContain('SELECT count(*)::INTEGER INTO v_expected_case_count')
    expect(migration).toContain('FROM ai_ops.snapshot_cases sc')
    expect(migration).toContain('v_decision_count <> v_expected_case_count')
    expect(migration).toContain('decision payload omitted a frozen case')
    expect(migration).toContain('decision payload references a case outside the frozen run snapshot')
    expect(migration).toContain("'multi_domain_staging',true")
  })

  it('keeps strict action requirements and staging-only semantics', () => {
    expect(migration).toContain("length(COALESCE(item->>'next_action_text','')) > 500")
    expect(migration).toContain('MONITOR decisions require a future review_after')
    expect(migration).toContain('CREATE_WORK requires explicit owner, assignee, expected_outcome, next_action_text and future due_at')
    expect(migration).toContain("item->>'decision_type' IN ('CREATE_WORK','ESCALATE')")
    expect(migration).not.toMatch(/INSERT\s+INTO\s+public\.work_items/i)
    expect(migration).not.toMatch(/UPDATE\s+public\.(?:targets|target_progress|sales_orders|work_items)/i)
    expect(migration).not.toMatch(/DELETE\s+FROM\s+public\.(?:targets|target_progress|sales_orders|work_items)/i)
  })

  it('keeps every new or renamed worker function private from generic API roles', () => {
    for (const signature of [
      'ai_ops.build_operational_snapshot(UUID, INTEGER)',
      'ai_ops.worker_get_context_credit_v2(UUID, TEXT)',
      'ai_ops.worker_get_context(UUID, TEXT)',
      'ai_ops.worker_stage_decisions(UUID, TEXT, TEXT, JSONB)',
    ]) {
      expect(migration).toContain(`REVOKE ALL ON FUNCTION ${signature}`)
    }
  })

  it('types the final multi-domain context including policy and frozen global planning frame', () => {
    const now = new Date().toISOString()
    const parsed = aiOpsWorkerContextResponseSchema.safeParse({
      blocked: false,
      context_hash: 'a'.repeat(32),
      context_hash_algorithm: 'md5-jsonb-identity',
      context_bytes: 2048,
      context_limit_bytes: 65536,
      prompt_hash: 'b'.repeat(32),
      planner_policy_version: 'v1',
      prompt_version: 'v2',
      context: {
        contract_version: 'v1',
        run: {
          run_id: '11111111-1111-4111-8111-111111111111',
          run_key: 'morning:2026-08-17',
          run_type: 'morning',
          business_date: '2026-08-17',
          scheduled_for: now,
          attempt_no: 1,
          planner_policy_version: 'v1',
          prompt_version: 'v2',
        },
        snapshot: {
          snapshot_id: '22222222-2222-4222-8222-222222222222',
          payload_version: 'credit-overdue-v1',
          generated_at: now,
          data_as_of: now,
          snapshot_status: 'ready',
          trust: {},
          company_pulse: {},
          coverage: {},
          domain_capture: {
            domain: 'receivables',
            capture_status: 'completed',
            case_count: 0,
            evidence_bytes: 0,
            metadata: {},
          },
          domain_captures: [
            {
              domain: 'receivables',
              capture_status: 'completed',
              case_count: 0,
              evidence_bytes: 0,
              capture_version: 'credit-overdue-v1',
              business_date: '2026-08-17',
              source_as_of: now,
              metadata: {},
            },
            {
              domain: 'sales',
              capture_status: 'completed',
              case_count: 0,
              evidence_bytes: 0,
              capture_version: 'sales-target-gap-v1',
              business_date: '2026-08-17',
              source_as_of: now,
              metadata: {},
            },
          ],
        },
        cases: [],
        decision_contract: {
          required_decision_for_each_case: true,
          zero_cases_allows_zero_decisions: true,
          allowed_decisions: ['IGNORE','MONITOR','INVESTIGATE','INFORM','CREATE_WORK','ESCALATE'],
          action_decisions: ['CREATE_WORK','ESCALATE'],
          max_actions_per_run: 5,
          monitor_requires_review_after: true,
          monitor_review_after_must_be_future: true,
          create_work_requires: ['recommended_owner_user_id','recommended_assignee_user_id','expected_outcome','next_action_text','due_at'],
          create_work_due_at_must_be_future: true,
          rationale_is_concise_not_chain_of_thought: true,
        },
        planner_policy: {
          policy_version: 'v1',
          prompt_version: 'v2',
          prompt_hash: 'b'.repeat(32),
          system_prompt: 'Versioned bounded management policy',
          methodology: { zero_actions_valid: true },
        },
        global_operational_context: {
          source: 'same_frozen_snapshot',
          actor_feasibility: [],
          cross_domain_entity_links: { customers: [], products: [] },
        },
        reconciliation: {
          complete_domains_reconciled: 7,
          domains_skipped_as_partial: 0,
          cases_resolved: 0,
          cases_reopened_after_terminal_work: 0,
        },
      },
    })

    expect(parsed.success).toBe(true)
  })
})
