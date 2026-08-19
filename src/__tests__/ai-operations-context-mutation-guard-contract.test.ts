import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const guard = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817012200_ai_operations_context_mutation_guard_fix.sql',
), 'utf8')

describe('AI Operations governed operational-context drift guard', () => {
  it('invalidates a decision when frozen human context is revoked, expires or changes', () => {
    expect(guard).toContain("oc.status<>'active'")
    expect(guard).toContain('oc.valid_until<=v_now')
    expect(guard).toContain("oc.context_type IS DISTINCT FROM frozen->>'context_type'")
    expect(guard).toContain("'frozen_operational_context_changed'")
  })

  it('invalidates a decision when relevant new approved context appears after snapshot', () => {
    expect(guard).toContain('oc.created_at>v_snapshot.data_as_of')
    expect(guard).toContain("oc.subject_type='customer'")
    expect(guard).toContain("oc.subject_type='product'")
    expect(guard).toContain("oc.subject_type='employee'")
    expect(guard).toContain("oc.subject_type='work_item'")
    expect(guard).toContain("'new_relevant_operational_context_after_snapshot'")
  })

  it('preserves all previous domain/current-state issues and only adds deterministic unique codes', () => {
    expect(guard).toContain('current_decision_issues_pre_context_mutation_guard_v1')
    expect(guard).toContain("SELECT DISTINCT value #>> '{}' AS code")
    expect(guard).toContain('jsonb_agg(to_jsonb(code) ORDER BY code)')
    expect(guard).toContain('REVOKE ALL ON FUNCTION ai_ops.current_decision_issues(UUID)')
  })
})
