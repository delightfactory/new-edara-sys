import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(process.cwd(),'supabase/migrations/20260817009800_ai_operations_case_disposition_feedback.sql'),'utf8')

describe('AI Operations case disposition feedback', () => {
  it('keeps Snooze/Dismiss temporary, permission gated and non-punitive', () => {
    expect(migration).toContain("p_action NOT IN ('snooze','dismiss')")
    expect(migration).toContain("public.check_permission(v_actor,'work.policies.manage')")
    expect(migration).toContain("v_now+interval '90 days'")
    expect(migration).toContain("'wrong_timing'")
    expect(migration).toContain("'not_actionable'")
    expect(migration).toContain("'employee_performance_signal',false")
  })
})
