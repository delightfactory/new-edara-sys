import { describe, expect, it } from 'vitest'
import { aiOpsWorkerDecisionSchema } from '@/features/ai-operations/worker-contracts'

const future = new Date(Date.now() + 86_400_000).toISOString()

describe('AI Operations final worker action schema', () => {
  it('accepts a fully specified CREATE_WORK quality envelope', () => {
    const parsed = aiOpsWorkerDecisionSchema.safeParse({
      case_id: '11111111-1111-4111-8111-111111111111',
      decision_type: 'CREATE_WORK',
      concise_rationale: 'A concrete intervention is justified by the frozen evidence.',
      confidence: 0.82,
      recommended_owner_user_id: '22222222-2222-4222-8222-222222222222',
      recommended_assignee_user_id: '33333333-3333-4333-8333-333333333333',
      responsibility_summary: 'The owner controls the business outcome and the assignee can execute the next step.',
      why_this_owner: 'Frozen responsibility evidence supports this owner.',
      why_now: 'Delay would reduce the expected business value.',
      expected_outcome: 'Obtain and record a concrete operational result.',
      next_action_text: 'Execute the focused next step and record the result in Work.',
      due_at: future,
      business_impact: 'high',
      urgency: 'high',
      evidence_completeness: 0.8,
      reversibility: 'reversible',
      estimated_effort: 'S',
      success_signal: 'A concrete result or documented blocker is recorded.',
      employee_safe_reason: 'This action is required to progress the current operational case.',
    })
    expect(parsed.success).toBe(true)
  })

  it('rejects consequential action when the structured quality envelope is missing', () => {
    const parsed = aiOpsWorkerDecisionSchema.safeParse({
      case_id: '11111111-1111-4111-8111-111111111111',
      decision_type: 'CREATE_WORK',
      concise_rationale: 'Action proposed.',
      confidence: 0.8,
      recommended_owner_user_id: '22222222-2222-4222-8222-222222222222',
      recommended_assignee_user_id: '33333333-3333-4333-8333-333333333333',
      expected_outcome: 'Outcome',
      next_action_text: 'Next action',
      due_at: future,
    })
    expect(parsed.success).toBe(false)
  })

  it('keeps non-action decisions lightweight', () => {
    const parsed = aiOpsWorkerDecisionSchema.safeParse({
      case_id: '11111111-1111-4111-8111-111111111111',
      decision_type: 'IGNORE',
      concise_rationale: 'The frozen condition does not justify interruption.',
      confidence: 0.9,
    })
    expect(parsed.success).toBe(true)
  })
})
