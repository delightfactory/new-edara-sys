import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const reconciliationFreeze = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817011400_ai_operations_reconciliation_replay_freeze.sql',
), 'utf8')
const attemptFreeze = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817011600_ai_operations_context_attempt_freeze.sql',
), 'utf8')

describe('AI Operations exact recovery replay evidence', () => {
  it('freezes the first reconciliation result once per snapshot/run', () => {
    expect(reconciliationFreeze).toContain('CREATE TABLE ai_ops.snapshot_reconciliation')
    expect(reconciliationFreeze).toContain('snapshot_id UUID PRIMARY KEY')
    expect(reconciliationFreeze).toContain('CREATE TRIGGER trg_ai_ops_snapshot_reconciliation_immutable')
    expect(reconciliationFreeze).toContain('ai_ops.capture_snapshot_reconciliation')
    expect(reconciliationFreeze).toContain("'reconciliation_frozen',true")
    expect(reconciliationFreeze).toContain("'{reconciliation}'")
  })

  it('freezes first-context attempt metadata while leaving runtime retry telemetry in planner_runs', () => {
    expect(attemptFreeze).toContain('CREATE TABLE ai_ops.snapshot_context_runtime_metadata')
    expect(attemptFreeze).toContain('first_context_attempt_no INTEGER NOT NULL')
    expect(attemptFreeze).toContain('CREATE TRIGGER trg_ai_ops_snapshot_context_runtime_metadata_immutable')
    expect(attemptFreeze).toContain('ai_ops.capture_first_context_attempt')
    expect(attemptFreeze).toContain("'{run,attempt_no}'")
    expect(attemptFreeze).toContain('attempt_no_is_first_context_attempt_and_is_frozen_for_replay')
  })

  it('recomputes final context identity only after frozen replay metadata is restored', () => {
    expect(reconciliationFreeze).toContain('v_hash:=md5(v_context::TEXT)')
    expect(attemptFreeze).toContain('v_hash:=md5(v_context::TEXT)')
    expect(attemptFreeze).toContain("'attempt_metadata_frozen_for_replay',true")
  })
})
