import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817010900_ai_operations_full_review_fingerprint.sql',
), 'utf8')
const service = readFileSync(resolve(process.cwd(), 'src/features/ai-operations/service.ts'), 'utf8')
const controls = readFileSync(resolve(process.cwd(), 'src/pages/work/management/AiOperationsGovernanceControls.tsx'), 'utf8')

describe('AI Operations complete human review fingerprint', () => {
  it('binds all execution and quality attributes to an immutable review fingerprint', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION ai_ops.decision_full_fingerprint')
    for (const field of [
      'business_impact', 'urgency', 'evidence_completeness', 'reversibility',
      'estimated_effort', 'success_signal', 'employee_safe_reason',
    ]) {
      expect(migration).toContain(`'${field}',d.${field}`)
    }
    expect(migration).toContain('CREATE TABLE ai_ops.decision_review_bindings')
    expect(migration).toContain('CREATE TRIGGER trg_ai_ops_decision_review_bindings_immutable')
  })

  it('requires v2 action quality before review and verifies the same full envelope before commit', () => {
    expect(migration).toContain("v_run.prompt_version='v2'")
    expect(migration).toContain('structured decision quality is incomplete; decision cannot be reviewed')
    expect(migration).toContain("'full_review_fingerprint_missing'")
    expect(migration).toContain("'full_review_fingerprint_mismatch'")
    expect(migration).toContain('ai_ops.decision_full_fingerprint(p_decision_id)')
    expect(migration).toContain('ai_ops_commit_reviewed_decision_pre_full_fingerprint_v1')
  })

  it('revokes the old public revision signature and exposes the quality-aligned revision path', () => {
    expect(migration).toContain('ai_ops_revise_decision_pre_quality_alignment_v1')
    expect(migration).toContain('p_success_signal TEXT')
    expect(migration).toContain('p_employee_safe_reason TEXT')
    expect(migration).toContain("success_signal=jsonb_build_object('summary',v_success)")
    expect(migration).toContain('employee_safe_reason=v_employee_reason')
    expect(service).toContain('p_success_signal: input.successSignal.trim()')
    expect(service).toContain('p_employee_safe_reason: input.employeeSafeReason.trim()')
    expect(controls).toContain('إشارة النجاح التي سنراجعها')
    expect(controls).toContain('السبب الآمن الذي يصل للموظف')
  })
})
