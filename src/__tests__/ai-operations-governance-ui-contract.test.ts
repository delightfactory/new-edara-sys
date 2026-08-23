import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const service = readFileSync(resolve(process.cwd(), 'src/features/ai-operations/service.ts'), 'utf8')
const hooks = readFileSync(resolve(process.cwd(), 'src/features/ai-operations/hooks.ts'), 'utf8')
const controls = readFileSync(resolve(process.cwd(), 'src/pages/work/management/AiOperationsGovernanceControls.tsx'), 'utf8')
const panel = readFileSync(resolve(process.cwd(), 'src/pages/work/management/AiOperationsManagementPanel.tsx'), 'utf8')

describe('AI Operations governance UX', () => {
  it('wires only narrow public RPCs for decision revision and context lifecycle', () => {
    expect(service).toContain("supabase.rpc('ai_ops_revise_decision'")
    expect(service).toContain('p_success_signal: input.successSignal.trim()')
    expect(service).toContain('p_employee_safe_reason: input.employeeSafeReason.trim()')
    expect(service).toContain("supabase.rpc('ai_ops_create_operational_context'")
    expect(service).toContain("supabase.rpc('ai_ops_revoke_operational_context'")
    expect(service).not.toContain(".from('operational_context')")
  })

  it('exposes audited quality-aligned revision instead of approve-or-reject only', () => {
    expect(hooks).toContain('useReviseAiOperationsDecision')
    expect(controls).toContain('تعديل القرار قبل الاعتماد')
    expect(controls).toContain('Revision جديدة')
    expect(controls).toContain('إشارة النجاح التي سنراجعها')
    expect(controls).toContain('السبب الآمن الذي يصل للموظف')
    expect(controls).toContain('successSignal,')
    expect(controls).toContain('employeeSafeReason,')
    expect(panel).toContain('<AiOperationsDecisionRevisionEditor')
  })

  it('lets management add and revoke expiring context from the live console', () => {
    expect(controls).toContain('إضافة سياق إداري للحالة')
    expect(controls).toContain('صالح حتى')
    expect(controls).toContain('إلغاء السياق')
    expect(panel).toContain('<AiOperationsCaseContextEditor')
    expect(panel).toContain('<AiOperationsContextRevokeButton')
  })
})
