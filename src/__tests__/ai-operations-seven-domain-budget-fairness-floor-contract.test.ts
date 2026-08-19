import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817009400_ai_operations_seven_domain_budget_fairness_floor.sql',
), 'utf8')

const sevenDomainBuilder = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817009000_ai_operations_hr_availability_global_budget_actionability.sql',
), 'utf8')

const allocator = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817006600_ai_operations_generic_domain_budget_customer_health.sql',
), 'utf8')

describe('AI Operations seven-domain case-budget fairness floor', () => {
  it('keeps the existing global round-robin allocator as the allocation primitive', () => {
    expect(allocator).toContain('CREATE OR REPLACE FUNCTION ai_ops.allocate_domain_case_budget')
    expect(allocator).toContain('WHILE v_remaining>0 LOOP')
    expect(allocator).toContain('FOREACH v_domain IN ARRAY p_domain_order LOOP')
  })

  it('confirms the canonical planner registry and builder contain all seven domains', () => {
    for (const domain of [
      'receivables', 'sales', 'customer_health', 'inventory',
      'field_execution', 'work_health', 'hr_availability',
    ]) {
      expect(sevenDomainBuilder).toContain(`'${domain}'`)
    }
    expect(sevenDomainBuilder).toContain('ai_ops.allocate_domain_case_budget(')
  })

  it('migrates legacy low budgets before enforcing the seven-domain floor', () => {
    expect(migration).toContain('cardinality(ai_ops.required_operational_domains())')
    expect(migration).toContain('max_cases_per_snapshot BETWEEN 7 AND 100')
    expect(migration.indexOf('UPDATE ai_ops.settings'))
      .toBeLessThan(migration.indexOf('ADD CONSTRAINT ai_ops_settings_case_budget_check'))
  })

  it('clamps explicit low caller hints to the live required-domain count', () => {
    expect(migration).toContain('v_required_domains:=ai_ops.required_operational_domains()')
    expect(migration).toContain('v_required_domain_count:=cardinality(v_required_domains)')
    expect(migration).toContain('COALESCE(p_case_limit,v_settings.max_cases_per_snapshot)')
    expect(migration).toContain('v_required_domain_count')
  })

  it('preserves the reviewed seven-domain builder under a private wrapper', () => {
    expect(migration).toContain('build_operational_snapshot_pre_seven_domain_fairness_floor_v1')
    expect(migration).toContain('RETURN ai_ops.build_operational_snapshot_pre_seven_domain_fairness_floor_v1(')
    expect(migration).toContain('FROM PUBLIC,anon,authenticated,service_role')
  })
})
