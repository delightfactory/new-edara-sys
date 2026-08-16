import { z } from 'zod'

export const aiOpsWorkerDecisionSchema = z.object({
  case_id: z.string().uuid(),
  decision_type: z.enum(['IGNORE', 'MONITOR', 'INVESTIGATE', 'INFORM', 'CREATE_WORK', 'ESCALATE']),
  concise_rationale: z.string().trim().min(1).max(1200),
  confidence: z.number().min(0).max(1),
  recommended_owner_user_id: z.string().uuid().nullable().optional(),
  recommended_assignee_user_id: z.string().uuid().nullable().optional(),
  responsibility_summary: z.string().max(800).optional(),
  why_this_owner: z.string().max(800).optional(),
  why_now: z.string().max(800).optional(),
  expected_outcome: z.string().max(1000).optional(),
  next_action_text: z.string().max(1000).optional(),
  due_at: z.string().datetime({ offset: true }).nullable().optional(),
  review_after: z.string().datetime({ offset: true }).nullable().optional(),
}).strict().superRefine((value, context) => {
  if (value.decision_type === 'MONITOR' && !value.review_after) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['review_after'], message: 'MONITOR requires review_after' })
  }

  if (value.decision_type === 'CREATE_WORK') {
    if (!value.recommended_owner_user_id) {
      context.addIssue({ code: z.ZodIssueCode.custom, path: ['recommended_owner_user_id'], message: 'CREATE_WORK requires accountable owner' })
    }
    if (!value.expected_outcome?.trim()) {
      context.addIssue({ code: z.ZodIssueCode.custom, path: ['expected_outcome'], message: 'CREATE_WORK requires expected_outcome' })
    }
    if (!value.next_action_text?.trim()) {
      context.addIssue({ code: z.ZodIssueCode.custom, path: ['next_action_text'], message: 'CREATE_WORK requires next_action_text' })
    }
  }
})

export const aiOpsWorkerDecisionBatchSchema = z.array(aiOpsWorkerDecisionSchema).max(100)

const frozenContextSchema = z.object({
  items: z.array(z.object({
    id: z.string().uuid(),
    subject_type: z.string().min(1),
    subject_id: z.string().uuid(),
    context_type: z.string().min(1),
    summary: z.string().max(500),
    owner_user_id: z.string().uuid().nullable(),
    owner_label: z.string().nullable(),
    source_type: z.enum(['human', 'system', 'ai_proposed']),
    confidence_class: z.enum(['hard_policy', 'approved_human', 'explicit_human', 'system_record', 'system_inference', 'ai_inference']),
    lifecycle_type: z.enum(['permanent', 'valid_until', 'review_on', 'one_time']),
    valid_from: z.string(),
    valid_until: z.string().nullable(),
    review_on: z.string().nullable(),
    visibility: z.enum(['management', 'standard']),
    content_trust: z.literal('governed_untrusted_text'),
  })).max(5),
  total: z.number().int().min(0),
  captured: z.number().int().min(0).max(5),
  truncated: z.boolean(),
  max_per_case: z.literal(5),
})

const workerCaseSchema = z.object({
  case_id: z.string().uuid(),
  case_key: z.string().min(1),
  rank: z.number().int().positive(),
  domain: z.string().min(1),
  case_type: z.string().min(1),
  entity_type: z.string().nullable(),
  entity_id: z.string().uuid().nullable(),
  attention_class: z.enum(['exception', 'opportunity', 'integrity', 'continuity']),
  severity: z.enum(['low', 'medium', 'high', 'critical']),
  case_status_at_snapshot: z.enum(['open', 'monitored', 'actioned', 'resolved', 'suppressed', 'expired']),
  source_as_of: z.string(),
  facts: z.record(z.string(), z.unknown()),
  responsibility_evidence: z.record(z.string(), z.unknown()),
  operational_context: frozenContextSchema,
  trust: z.record(z.string(), z.unknown()),
})

const workerContextBodySchema = z.object({
  contract_version: z.string().min(1),
  run: z.object({
    run_id: z.string().uuid(),
    run_key: z.string().min(1),
    run_type: z.string().min(1),
    business_date: z.string().min(1),
    scheduled_for: z.string().min(1),
    attempt_no: z.number().int().positive(),
    planner_policy_version: z.string().min(1),
    prompt_version: z.string().min(1),
  }),
  snapshot: z.object({
    snapshot_id: z.string().uuid(),
    payload_version: z.string().min(1),
    generated_at: z.string().min(1),
    data_as_of: z.string().min(1),
    snapshot_status: z.enum(['ready', 'partial', 'blocked']),
    trust: z.record(z.string(), z.unknown()),
    company_pulse: z.record(z.string(), z.unknown()),
    coverage: z.record(z.string(), z.unknown()),
    domain_capture: z.object({
      domain: z.literal('receivables'),
      capture_status: z.enum(['completed', 'partial', 'blocked']),
      case_count: z.number().int().min(0),
      evidence_bytes: z.number().int().min(0),
      metadata: z.record(z.string(), z.unknown()),
    }),
  }),
  cases: z.array(workerCaseSchema),
  decision_contract: z.object({
    required_decision_for_each_case: z.literal(true),
    zero_cases_allows_zero_decisions: z.literal(true),
    allowed_decisions: z.array(z.enum(['IGNORE', 'MONITOR', 'INVESTIGATE', 'INFORM', 'CREATE_WORK', 'ESCALATE'])),
    action_decisions: z.array(z.enum(['CREATE_WORK', 'ESCALATE'])),
    max_actions_per_run: z.number().int().min(0),
    monitor_requires_review_after: z.literal(true),
    create_work_requires: z.array(z.string()),
    rationale_is_concise_not_chain_of_thought: z.literal(true),
  }),
})

export const aiOpsWorkerContextResponseSchema = z.discriminatedUnion('blocked', [
  z.object({
    blocked: z.literal(true),
    reason: z.literal('context_budget_exceeded'),
    run_id: z.string().uuid(),
    snapshot_id: z.string().uuid(),
    context_bytes: z.number().int().positive(),
    context_limit_bytes: z.number().int().positive(),
  }),
  z.object({
    blocked: z.literal(false),
    context_hash: z.string().regex(/^[a-f0-9]{32}$/),
    context_hash_algorithm: z.literal('md5-jsonb-identity'),
    context_bytes: z.number().int().positive(),
    context_limit_bytes: z.number().int().positive(),
    context: workerContextBodySchema,
  }),
])

export type AiOpsWorkerDecisionInput = z.infer<typeof aiOpsWorkerDecisionSchema>
export type AiOpsWorkerContextResponse = z.infer<typeof aiOpsWorkerContextResponseSchema>
