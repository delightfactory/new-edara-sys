import { z } from 'zod'

const dataMode = z.enum(['preview', 'rpc'])
const runStatus = z.enum(['pending', 'claimed', 'reasoning', 'staged', 'committing', 'completed', 'partial', 'failed', 'abandoned'])
const caseSeverity = z.enum(['low', 'medium', 'high', 'critical'])
const caseStatus = z.enum(['open', 'monitored', 'actioned', 'resolved', 'suppressed', 'expired'])
const attentionClass = z.enum(['exception', 'opportunity', 'integrity', 'continuity'])
const decisionType = z.enum(['IGNORE', 'MONITOR', 'INVESTIGATE', 'INFORM', 'CREATE_WORK', 'ESCALATE'])
const evidenceStrength = z.enum(['direct', 'supporting', 'contextual'])
const contextConfidence = z.enum(['hard_policy', 'approved_human', 'explicit_human', 'system_record', 'system_inference', 'ai_inference'])
const contextLifecycle = z.enum(['permanent', 'valid_until', 'review_on', 'one_time'])

const settings = z.object({
  planner_enabled: z.boolean(),
  shadow_mode: z.boolean(),
  auto_commit_enabled: z.boolean(),
  max_cases_per_snapshot: z.number().int().min(1).max(100),
  max_actions_per_run: z.number().int().min(0).max(20),
  planner_policy_version: z.string().min(1),
  tool_contract_version: z.string().min(1),
  state_version: z.number().int().positive(),
  updated_at: z.string().nullable(),
})

const trustSignal = z.object({
  domain: z.string().min(1),
  state: z.enum(['verified', 'posting_consistency_only', 'partial', 'blocked', 'unknown']),
  as_of: z.string().nullable(),
  note: z.string().nullable().optional(),
})

const pulseMetric = z.object({
  key: z.string().min(1),
  label: z.string().min(1),
  value: z.string(),
  trend: z.enum(['up', 'down', 'flat', 'unknown']).optional(),
  tone: z.enum(['neutral', 'good', 'warning', 'danger']).optional(),
  hint: z.string().nullable().optional(),
})

const plannerRun = z.object({
  id: z.string().min(1),
  run_key: z.string().min(1),
  run_type: z.string().min(1),
  business_date: z.string().min(1),
  scheduled_for: z.string().min(1),
  status: runStatus,
  checkpoint: z.string().min(1),
  attempt_no: z.number().int().min(0),
  cases_seen: z.number().int().min(0),
  cases_investigated: z.number().int().min(0),
  decisions_count: z.number().int().min(0),
  work_created_count: z.number().int().min(0),
  started_at: z.string().nullable(),
  completed_at: z.string().nullable(),
  error_class: z.string().nullable(),
  error_message: z.string().nullable(),
})

const attentionCase = z.object({
  id: z.string().min(1),
  case_key: z.string().min(1),
  domain: z.string().min(1),
  case_type: z.string().min(1),
  entity_type: z.string().nullable(),
  entity_id: z.string().nullable(),
  entity_label: z.string(),
  attention_class: attentionClass,
  severity: caseSeverity,
  status: caseStatus,
  title: z.string().min(1),
  reason: z.string().min(1),
  first_seen_at: z.string().min(1),
  last_seen_at: z.string().min(1),
  source_as_of: z.string().min(1),
  responsibility_label: z.string().nullable(),
  responsibility_basis: z.string().nullable(),
  value_label: z.string().nullable(),
  has_existing_work: z.boolean(),
  linked_work_number: z.number().int().nullable(),
  recommended_decision: decisionType.nullable(),
  review_after: z.string().nullable(),
})

const contextItem = z.object({
  id: z.string().min(1),
  subject_type: z.string().min(1),
  subject_id: z.string().min(1),
  subject_label: z.string(),
  context_type: z.string().min(1),
  summary: z.string().min(1),
  owner_label: z.string().nullable(),
  source_type: z.enum(['human', 'system', 'ai_proposed']),
  confidence_class: contextConfidence,
  lifecycle_type: contextLifecycle,
  valid_until: z.string().nullable(),
  review_on: z.string().nullable(),
  status: z.enum(['active', 'expired', 'revoked', 'consumed']),
})

export const aiOpsConsoleSnapshotSchema = z.object({
  mode: dataMode,
  integration_state: z.enum(['preview_only', 'database_not_ready', 'ready']),
  generated_at: z.string().min(1),
  data_as_of: z.string().min(1),
  settings,
  trust: z.array(trustSignal),
  pulse: z.array(pulseMetric),
  attention: z.array(attentionCase),
  recent_runs: z.array(plannerRun),
  context: z.array(contextItem),
})

const responsibilityEvidence = z.object({
  evidence_type: z.string().min(1),
  label: z.string().min(1),
  user_id: z.string().nullable(),
  user_label: z.string().nullable(),
  strength: evidenceStrength,
  active_work_actor: z.boolean().nullable(),
  occurred_at: z.string().nullable(),
  note: z.string().nullable(),
})

const workCollision = z.object({
  work_item_id: z.string().min(1),
  work_number: z.number().int().positive(),
  status: z.string().min(1),
  relation_type: z.string().min(1),
  title: z.string().min(1),
})

const frozenContext = z.object({
  id: z.string().min(1),
  subject_type: z.string().min(1),
  subject_id: z.string().min(1),
  context_type: z.string().min(1),
  summary: z.string().min(1).max(500),
  owner_user_id: z.string().nullable(),
  owner_label: z.string().nullable(),
  source_type: z.enum(['human', 'system', 'ai_proposed']),
  confidence_class: contextConfidence,
  lifecycle_type: contextLifecycle,
  valid_from: z.string().min(1),
  valid_until: z.string().nullable(),
  review_on: z.string().nullable(),
  visibility: z.enum(['management', 'standard']),
  content_trust: z.literal('governed_untrusted_text'),
})

export const aiOpsCaseDetailSchema = z.object({
  case_id: z.string().min(1),
  case_key: z.string().min(1),
  business_date: z.string().min(1),
  facts: z.array(z.object({ label: z.string().min(1), value: z.string() })),
  responsibility_evidence: z.array(responsibilityEvidence),
  existing_work: z.array(workCollision),
  relevant_context_ids: z.array(z.string().min(1)),
  frozen_context: z.array(frozenContext).max(5),
  context_coverage: z.object({
    total: z.number().int().min(0),
    captured: z.number().int().min(0).max(5),
    truncated: z.boolean(),
  }).superRefine((value, context) => {
    if (value.captured > value.total) {
      context.addIssue({ code: z.ZodIssueCode.custom, message: 'captured context cannot exceed total context' })
    }
    if (value.truncated !== (value.total > value.captured)) {
      context.addIssue({ code: z.ZodIssueCode.custom, message: 'context truncation flag does not match coverage counts' })
    }
  }),
  decision_review: z.object({
    decision_type: decisionType.nullable(),
    concise_rationale: z.string().min(1),
    why_this_owner: z.string().nullable(),
    why_now: z.string().nullable(),
    confidence: z.number().min(0).max(1).nullable(),
    requires_human_review: z.boolean(),
  }),
})
