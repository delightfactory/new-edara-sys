import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const finalization = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816174000_ai_operations_run_finalization.sql',
), 'utf8')

const multiDomain = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817006000_ai_operations_multi_domain_worker.sql',
), 'utf8')

const restore = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817009600_ai_operations_stage_lifecycle_restore.sql',
), 'utf8')

describe('AI Operations staging lifecycle restoration', () => {
  it('documents the original terminal-state resolver and the later multi-domain replacement surface', () => {
    expect(finalization).toContain('ai_ops.refresh_run_terminal_state(p_run_id)')
    expect(finalization).toContain("'completed_zero_cases'")
    expect(finalization).toContain("'completed_shadow_analysis'")
    expect(multiDomain).toContain('CREATE OR REPLACE FUNCTION ai_ops.worker_stage_decisions(')
  })

  it('rebinds the current staging entrypoint to lifecycle refresh after first submission', () => {
    expect(restore).toContain('worker_stage_decisions_pre_lifecycle_restore_v1')
    expect(restore).toContain('v_result:=ai_ops.worker_stage_decisions_pre_lifecycle_restore_v1(')
    expect(restore).toContain('v_lifecycle:=ai_ops.refresh_run_terminal_state(p_run_id)')
    expect(restore).toContain("'run_lifecycle',v_lifecycle")
  })

  it('allows exact response-loss replay even after lifecycle terminalizes the run', () => {
    expect(restore).toContain("v_run.status NOT IN ('staged','completed','partial')")
    expect(restore).toContain("v_run.result_summary->>'worker_submission_hash'")
    expect(restore).toContain("v_run.result_summary->>'worker_context_hash'")
    expect(restore).toContain('v_run.claimed_by IS DISTINCT FROM p_worker_id')
    expect(restore).toContain("'retry_after_durable_stage',true")
  })

  it('handles the zero-case exact replay without requiring a non-existent decision hash row', () => {
    expect(restore).toContain('(v_decision_count>0 AND v_existing_hashes<>1)')
    expect(restore).toContain('(v_decision_count=0 AND v_existing_hashes<>0)')
  })

  it('keeps replay read-only and fail-closed for any changed durable identity', () => {
    const retryBranch = restore.slice(
      restore.indexOf('-- Once a submission is durable'),
      restore.indexOf('-- Re-run the deterministic lifecycle resolver'),
    )
    expect(retryBranch).toContain('worker_submission_hash')
    expect(retryBranch).toContain('worker_context_hash')
    expect(retryBranch).toContain('worker_id')
    expect(retryBranch).toContain("RAISE EXCEPTION 'staging retry does not exactly match the persisted decision set'")
    expect(retryBranch).not.toContain('INSERT INTO ai_ops.decisions')
    expect(retryBranch).not.toContain('UPDATE ai_ops.decisions')
  })

  it('keeps the worker staging surface private', () => {
    expect(restore).toContain('REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB)')
    expect(restore).toContain('FROM PUBLIC,anon,authenticated,service_role')
  })
})
