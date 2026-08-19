import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const policyMigration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817010200_ai_operations_policy_global_outcome_closure.sql',
), 'utf8')
const freezeMigration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817010400_ai_operations_snapshot_global_context_freeze.sql',
), 'utf8')
const worker = readFileSync(resolve(
  process.cwd(),
  'supabase/functions/ai-operations-worker/index.ts',
), 'utf8')

describe('AI Operations versioned decision policy runtime', () => {
  it('stores an exact private versioned prompt with a deterministic hash', () => {
    expect(policyMigration).toContain('CREATE TABLE ai_ops.planner_policies')
    expect(policyMigration).toContain('PRIMARY KEY (policy_version, prompt_version)')
    expect(policyMigration).toContain('prompt_hash = md5(system_prompt)')
    expect(policyMigration).toContain('REVOKE ALL ON TABLE ai_ops.planner_policies FROM PUBLIC, anon, authenticated, service_role')
    expect(policyMigration).toContain('Cause')
    expect(policyMigration).toContain('MANAGEMENT REASONING METHOD')
    expect(policyMigration).toContain('Compare expected business value with interruption cost')
    expect(policyMigration).toContain('manager fallback is last resort')
    expect(policyMigration).toContain('A successful run may create zero actions')
  })

  it('fails closed when the frozen run cannot resolve the exact enabled policy', () => {
    expect(freezeMigration).toContain('p.policy_version=v_run.planner_policy_version')
    expect(freezeMigration).toContain('p.prompt_version=v_run.prompt_version')
    expect(freezeMigration).toContain('planner_policy_missing')
    expect(freezeMigration).toContain('v_policy.prompt_hash IS DISTINCT FROM md5(v_policy.system_prompt)')
    expect(freezeMigration).toContain('prompt_hash=v_policy.prompt_hash')
  })

  it('makes the Edge worker consume only the database versioned policy', () => {
    expect(worker).toContain('readVersionedPolicy(contextResult)')
    expect(worker).toContain("{ role: 'system', content: versionedPolicy.systemPrompt }")
    expect(worker).toContain("contextResult.prompt_hash !== promptHash")
    expect(worker).not.toContain("const systemPrompt = [")
  })
})
