import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const panel = readFileSync(resolve(process.cwd(),'src/pages/work/management/AiOperationsManagementPanel.tsx'),'utf8')

describe('AI Operations ESCALATE management UI', () => {
  it('allows explicit execution of approved CREATE_WORK and ESCALATE decisions', () => {
    expect(panel).toContain("['CREATE_WORK', 'ESCALATE'].includes(decision.decision_type)")
    expect(panel).toContain("'تنفيذ التصعيد المعتمد'")
    expect(panel).toContain("result.operational_mutation === 'work_escalation_overlay'")
    expect(panel).not.toContain('تنفيذ ESCALATE غير مدعوم')
  })
})
