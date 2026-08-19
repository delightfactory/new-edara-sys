import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817012300_ai_operations_legacy_prompt_stage_compatibility.sql',
), 'utf8')

describe('AI Operations legacy prompt staging compatibility', () => {
  it('routes frozen prompt-v1 runs through their original canonical staging contract', () => {
    expect(migration).toContain("IF v_run.prompt_version='v1'")
    expect(migration).toContain('worker_stage_decisions_pre_structured_quality_v1')
    expect(migration).toContain("'quality_contract','legacy_prompt_v1'")
    expect(migration).toContain("'legacy_contract_preserved',true")
  })

  it('keeps v2/v3 on the strict structured-quality path', () => {
    expect(migration).toContain('worker_stage_decisions_structured_quality_v1')
    expect(migration).toContain('RETURN ai_ops.worker_stage_decisions_structured_quality_v1')
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.worker_stage_decisions(UUID,TEXT,TEXT,JSONB)')
  })
})
