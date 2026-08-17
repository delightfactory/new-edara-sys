import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817006300_ai_operations_sales_routing_context_hardening.sql',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations Sales routing/context hardening contract', () => {
  it('preserves the reviewed multidomain guard behind a private wrapper', () => {
    expect(migration).toContain('ALTER FUNCTION ai_ops.current_decision_issues(UUID)')
    expect(migration).toContain('RENAME TO current_decision_issues_multidomain_v3')
    expect(migration).toContain('ai_ops.current_decision_issues_multidomain_v3(p_decision_id)')
    expect(migration).toContain('ai_ops.sales_target_routing_context_issues(p_decision_id)')
  })

  it('re-resolves the current accountable scope owner from canonical HR/org sources', () => {
    expect(migration).toContain("WHEN 'individual' THEN")
    expect(migration).toContain('FROM public.hr_employees he')
    expect(migration).toContain("WHEN 'department' THEN")
    expect(migration).toContain('FROM public.hr_departments dep')
    expect(migration).toContain("WHEN 'branch' THEN")
    expect(migration).toContain('FROM public.branches br')
    expect(migration).toContain("responsibility_evidence->'scope_accountability'->>'user_id'")
    expect(migration).toContain("'target_scope_accountability_changed_after_snapshot'")
  })

  it('watches the branch and employee governed context families frozen by Sales capture', () => {
    expect(migration).toContain("v_target.scope = 'branch'")
    expect(migration).toContain("oc.subject_type = 'branch'")
    expect(migration).toContain("v_target.scope = 'individual'")
    expect(migration).toContain("oc.subject_type = 'employee'")
    expect(migration).toContain("'new_scope_governed_context_after_snapshot'")
    expect(migration).toContain('oc.valid_from <= v_now')
  })

  it('keeps the hardening helper read-only against operational business tables', () => {
    for (const table of [
      'targets',
      'target_progress',
      'hr_employees',
      'hr_departments',
      'branches',
      'work_items',
      'work_links',
    ]) {
      expect(executableSql).not.toMatch(new RegExp(`UPDATE\\s+public\\.${table}`, 'i'))
      expect(executableSql).not.toMatch(new RegExp(`INSERT\\s+INTO\\s+public\\.${table}`, 'i'))
      expect(executableSql).not.toMatch(new RegExp(`DELETE\\s+FROM\\s+public\\.${table}`, 'i'))
    }
  })

  it('keeps all new guard primitives unavailable to generic API roles', () => {
    for (const signature of [
      'ai_ops.sales_target_routing_context_issues(UUID)',
      'ai_ops.current_decision_issues_multidomain_v3(UUID)',
      'ai_ops.current_decision_issues(UUID)',
    ]) {
      expect(migration).toContain(`REVOKE ALL ON FUNCTION ${signature}`)
    }
    expect(migration).toContain('FROM PUBLIC, anon, authenticated, service_role')
  })
})
