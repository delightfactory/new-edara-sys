import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817009700_ai_operations_reviewed_escalation_execution.sql',
), 'utf8')

const worker = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817006000_ai_operations_multi_domain_worker.sql',
), 'utf8')

describe('AI Operations reviewed ESCALATE execution bridge', () => {
  it('executes ESCALATE through the native Work overlay instead of creating replacement Work', () => {
    const helper = migration.slice(
      migration.indexOf('CREATE OR REPLACE FUNCTION private.ai_ops_execute_reviewed_escalation'),
      migration.indexOf('-- Preserve every existing domain-specific CREATE_WORK wrapper'),
    )
    expect(helper).toContain('v_work_result := public.work_escalate(')
    expect(helper).toContain("'operational_mutation', 'work_escalation_overlay'")
    expect(helper).not.toContain('INSERT INTO public.work_items')
    expect(helper).not.toContain("status = 'escalated'")
  })

  it('re-derives the Work target from frozen evidence and never accepts a caller target id', () => {
    expect(worker).toContain("sc.facts->'existing_active_work'->>'work_item_id'")
    expect(migration).toContain("v_frozen_work_id := NULLIF(v_sc.facts->'existing_active_work'->>'work_item_id','')::UUID")
    expect(migration).toContain('v_decision.linked_work_item_id IS DISTINCT FROM v_frozen_work_id')
    expect(migration).toContain("'frozen_escalation_target_mismatch'")
    expect(migration).not.toContain('p_work_item_id UUID')
  })

  it('requires exact approved decision identity and revalidates current state before mutation', () => {
    expect(migration).toContain("v_review.review_state <> 'approved'")
    expect(migration).toContain('v_review.decision_fingerprint IS DISTINCT FROM v_fingerprint')
    expect(migration).toContain('v_review.decision_revision <> v_decision.revision')
    expect(migration).toContain('v_issues := ai_ops.current_decision_issues(p_decision_id)')
    expect(migration.indexOf('v_issues := ai_ops.current_decision_issues(p_decision_id)'))
      .toBeLessThan(migration.indexOf('v_work_result := public.work_escalate('))
  })

  it('keeps Work-visible escalation reason employee-safe', () => {
    const helper = migration.slice(
      migration.indexOf('-- The reason becomes visible in Work.'),
      migration.indexOf('-- Stable per decision+actor operation id'),
    )
    expect(helper).toContain('v_decision.employee_safe_reason')
    expect(helper).not.toContain('v_decision.concise_rationale')
  })

  it('is response-loss idempotent and fails closed if durable escalation evidence disappears', () => {
    expect(migration).toContain("v_decision.commit_status = 'committed'")
    expect(migration).toContain("v_decision.validation_detail->>'work_escalation_id'")
    expect(migration).toContain("'idempotent_reuse', true")
    expect(migration).toContain("RAISE EXCEPTION 'decision references missing committed Work escalation'")
    expect(migration).toContain("'ai_ops:escalate:' || p_decision_id::TEXT || ':' || p_approved_execution_by::TEXT")
  })

  it('preserves existing CREATE_WORK domain dispatch and adds ESCALATE at the canonical dispatcher', () => {
    expect(migration).toContain('work_create_ai_reviewed_task_pre_escalation_execution_v1')
    expect(migration).toContain("IF v_decision_type = 'ESCALATE' THEN")
    expect(migration).toContain('RETURN private.ai_ops_execute_reviewed_escalation(')
    expect(migration).toContain('RETURN private.work_create_ai_reviewed_task_pre_escalation_execution_v1(')
  })

  it('treats approved CREATE_WORK and ESCALATE as pending until explicit durable execution', () => {
    expect(migration).toContain("d.decision_type IN ('CREATE_WORK','ESCALATE')")
    expect(migration).toContain('d.committed_work_item_id IS NULL')
    expect(migration).toContain('d.committed_work_item_id IS NOT NULL')
    expect(migration).toContain("'unsupported_execution_decisions', 0")
    expect(migration).toContain("v_checkpoint := 'awaiting_work_commit'")
  })

  it('does not inflate created-Work metrics for escalation', () => {
    const helper = migration.slice(
      migration.indexOf('CREATE OR REPLACE FUNCTION private.ai_ops_execute_reviewed_escalation'),
      migration.indexOf('-- Preserve every existing domain-specific CREATE_WORK wrapper'),
    )
    expect(helper).toContain("checkpoint = 'reviewed_escalation_committed'")
    expect(helper).not.toContain('work_created_count = work_created_count + 1')
  })

  it('rebinds the public commit gateway with management permission and lifecycle refresh', () => {
    expect(migration).toContain('ai_ops_commit_reviewed_decision_pre_escalation_execution_v1')
    expect(migration).toContain("public.check_permission(v_actor, 'work.policies.manage')")
    expect(migration).toContain('v_result := private.work_create_ai_reviewed_task(p_decision_id, v_actor)')
    expect(migration).toContain('v_lifecycle := ai_ops.refresh_run_terminal_state(v_run_id)')
  })

  it('keeps internal execution helpers private and public execution authenticated', () => {
    expect(migration).toContain('SECURITY DEFINER')
    expect(migration).toContain("SET search_path = ''")
    expect(migration).toContain('REVOKE ALL ON FUNCTION private.ai_ops_execute_reviewed_escalation(UUID, UUID)')
    expect(migration).toContain('FROM PUBLIC, anon, authenticated, service_role')
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.ai_ops_commit_reviewed_decision(UUID) TO authenticated')
  })
})
