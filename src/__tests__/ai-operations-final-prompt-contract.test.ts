import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817011200_ai_operations_prompt_contract_precedence.sql',
), 'utf8')
const v3Review = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817011300_ai_operations_v3_review_enforcement.sql',
), 'utf8')

describe('AI Operations final prompt v3 contract', () => {
  it('removes ambiguity between the old narrow field list and structured quality output', () => {
    expect(migration).toContain('FINAL OUTPUT CONTRACT PRECEDENCE — PROMPT v3')
    expect(migration).toContain('supersedes any earlier narrower allowed-field list')
    expect(migration).toContain("'v3',true")
    expect(migration).toContain("SET prompt_version='v3'")
    expect(migration).toContain("'structured_quality_required_for_actions',true")
  })

  it('publishes the same final output and action-quality contract in worker context', () => {
    expect(migration).toContain("'final_output_contract_version','v3'")
    expect(migration).toContain("'allowed_fields',jsonb_build_array")
    expect(migration).toContain("'action_quality_requires',jsonb_build_array")
    expect(migration).toContain("'structured_quality_labels_are_planning_not_employee_scores',true")
    expect(migration).toContain("'quality_contract_is_additive_to_deterministic_validation',true")
    expect(migration).toContain('v_hash:=md5(v_context::TEXT)')
  })

  it('keeps v3 review and commit fail-closed on complete quality and full fingerprint', () => {
    expect(v3Review).toContain("v_run.prompt_version='v3'")
    expect(v3Review).toContain('structured decision quality is incomplete; v3 decision cannot be reviewed')
    expect(v3Review).toContain("'full_review_fingerprint_missing'")
    expect(v3Review).toContain("'full_review_fingerprint_mismatch'")
    expect(v3Review).toContain('ai_ops.decision_full_fingerprint(p_decision_id)')
  })
})
