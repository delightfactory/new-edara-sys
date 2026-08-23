import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817010600_ai_operations_structured_decision_quality.sql',
), 'utf8')
const reviewSurface = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817010800_ai_operations_decision_quality_review_surface.sql',
), 'utf8')
const worker = readFileSync(resolve(process.cwd(), 'supabase/functions/ai-operations-worker/index.ts'), 'utf8')
const panel = readFileSync(resolve(process.cwd(), 'src/pages/work/management/AiOperationsManagementPanel.tsx'), 'utf8')

describe('AI Operations structured decision quality runtime', () => {
  it('freezes a configured prompt version on future runs and keeps policy versions immutable', () => {
    expect(migration).toContain("ADD COLUMN prompt_version TEXT NOT NULL DEFAULT 'v1'")
    expect(migration).toContain("'v2',true")
    expect(migration).toContain("SET prompt_version='v2'")
    expect(migration).toContain('CREATE TRIGGER trg_ai_ops_planner_policies_immutable')
    expect(migration).toContain('v_settings.prompt_version')
    expect(migration).toContain('configured AI planner policy/prompt version is not registered')
  })

  it('requires a complete bounded quality envelope for consequential actions', () => {
    for (const field of [
      'business_impact', 'urgency', 'evidence_completeness', 'reversibility',
      'estimated_effort', 'success_signal', 'employee_safe_reason',
    ]) {
      expect(migration).toContain(field)
      expect(worker).toContain(`'${field}'`)
    }
    expect(migration).toContain("item->>'decision_type' IN ('CREATE_WORK','ESCALATE')")
    expect(migration).toContain('action decisions require complete structured quality fields')
    expect(migration).toContain("item->>'estimated_effort' NOT IN ('S','M','L')")
    expect(migration).toContain('fake numerical cutoff')
  })

  it('preserves canonical staging while adding an exact quality retry hash', () => {
    expect(migration).toContain('worker_stage_decisions_pre_structured_quality_v1')
    expect(migration).toContain("- 'business_impact' - 'urgency' - 'evidence_completeness'")
    expect(migration).toContain('v_quality_hash:=md5(p_decisions::TEXT)')
    expect(migration).toContain('staged retry quality payload does not match the persisted submission')
    expect(migration).toContain("'worker_quality_submission_hash'")
  })

  it('surfaces the quality envelope to the human reviewer without exposing raw metadata', () => {
    expect(reviewSurface).toContain("'business_impact',v_decision.business_impact")
    expect(reviewSurface).toContain("'success_signal',NULLIF(v_decision.success_signal->>'summary','')")
    expect(reviewSurface).toContain("'employee_safe_reason',v_decision.employee_safe_reason")
    expect(reviewSurface).not.toContain("'management_only_metadata'")
    expect(panel).toContain('الأثر التجاري')
    expect(panel).toContain('اكتمال الأدلة')
    expect(panel).toContain('إشارة النجاح التي سنراجعها')
    expect(panel).toContain('السبب الآمن الذي يصل للموظف')
  })
})
