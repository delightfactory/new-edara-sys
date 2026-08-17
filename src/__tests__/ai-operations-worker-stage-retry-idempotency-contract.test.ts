import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817009500_ai_operations_worker_stage_retry_idempotency.sql',
), 'utf8')

const prior = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817008000_ai_operations_cross_domain_runtime_hardening.sql',
), 'utf8')

describe('AI Operations worker staging retry idempotency', () => {
  it('preserves the seven-domain required-capture staging wrapper for first submission', () => {
    expect(prior).toContain('CREATE OR REPLACE FUNCTION ai_ops.worker_stage_decisions(')
    expect(prior).toContain('snapshot_has_required_domain_captures')
    expect(migration).toContain('worker_stage_decisions_pre_retry_idempotency_v1')
    expect(migration).toContain('RETURN ai_ops.worker_stage_decisions_pre_retry_idempotency_v1(')
  })

  it('admits only the staged state as the lease-free exact retry path', () => {
    expect(migration).toContain("IF v_run.status<>'staged' THEN")
    expect(migration).toContain('v_run.claimed_by IS DISTINCT FROM p_worker_id')
    expect(migration).toContain("v_run.result_summary->>'worker_context_hash' IS DISTINCT FROM p_context_hash")
  })

  it('binds retry identity to the exact persisted submission and frozen case cardinality', () => {
    expect(migration).toContain('v_submission_hash:=md5(p_decisions::TEXT)')
    expect(migration).toContain("v_run.result_summary->>'worker_submission_hash'")
    expect(migration).toContain('v_decision_count<>v_snapshot_case_count')
    expect(migration).toContain('v_existing_count<>v_decision_count')
    expect(migration).toContain('v_existing_hashes<>1')
  })

  it('still requires all seven immutable domain capture markers', () => {
    expect(migration).toContain('ai_ops.snapshot_has_required_domain_captures(v_snapshot_id)')
  })

  it('returns an explicit idempotent acknowledgement without mutating decisions', () => {
    const retryBranch = migration.slice(
      migration.indexOf("IF v_run.status<>'staged' THEN"),
      migration.indexOf('END;\n$$;'),
    )
    expect(retryBranch).toContain("'idempotent_reuse',true")
    expect(retryBranch).toContain("'retry_after_committed_stage',true")
    expect(retryBranch).not.toContain('INSERT INTO ai_ops.decisions')
    expect(retryBranch).not.toContain('UPDATE ai_ops.decisions')
  })

  it('keeps the staging surface private', () => {
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB)')
    expect(migration).toContain('FROM PUBLIC,anon,authenticated,service_role')
  })
})
