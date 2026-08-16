export type AiOpsDataMode = 'preview' | 'rpc'

export type AiOpsRunStatus =
  | 'pending'
  | 'claimed'
  | 'reasoning'
  | 'staged'
  | 'committing'
  | 'completed'
  | 'partial'
  | 'failed'
  | 'abandoned'

export type AiOpsCaseSeverity = 'low' | 'medium' | 'high' | 'critical'
export type AiOpsCaseStatus = 'open' | 'monitored' | 'actioned' | 'resolved' | 'suppressed' | 'expired'
export type AiOpsAttentionClass = 'exception' | 'opportunity' | 'integrity' | 'continuity'
export type AiOpsDecisionType = 'IGNORE' | 'MONITOR' | 'INVESTIGATE' | 'INFORM' | 'CREATE_WORK' | 'ESCALATE'
export type AiOpsDecisionValidationState = 'pending' | 'validated' | 'rejected'
export type AiOpsHumanReviewState = 'approved' | 'rejected'
export type AiOpsCommitStatus = 'not_requested' | 'staged' | 'committed' | 'rejected' | 'failed' | 'skipped'
export type AiOpsEvidenceStrength = 'direct' | 'supporting' | 'contextual'
export type AiOpsContextConfidence =
  | 'hard_policy'
  | 'approved_human'
  | 'explicit_human'
  | 'system_record'
  | 'system_inference'
  | 'ai_inference'
export type AiOpsContextLifecycle = 'permanent' | 'valid_until' | 'review_on' | 'one_time'

export interface AiOpsSettings {
  planner_enabled: boolean
  shadow_mode: boolean
  auto_commit_enabled: boolean
  max_cases_per_snapshot: number
  max_actions_per_run: number
  planner_policy_version: string
  tool_contract_version: string
  state_version: number
  updated_at: string | null
}

export interface AiOpsTrustSignal {
  domain: string
  state: 'verified' | 'posting_consistency_only' | 'partial' | 'blocked' | 'unknown'
  as_of: string | null
  note?: string | null
}

export interface AiOpsPulseMetric {
  key: string
  label: string
  value: string
  trend?: 'up' | 'down' | 'flat' | 'unknown'
  tone?: 'neutral' | 'good' | 'warning' | 'danger'
  hint?: string | null
}

export interface AiOpsPlannerRun {
  id: string
  run_key: string
  run_type: string
  business_date: string
  scheduled_for: string
  status: AiOpsRunStatus
  checkpoint: string
  attempt_no: number
  cases_seen: number
  cases_investigated: number
  decisions_count: number
  work_created_count: number
  started_at: string | null
  completed_at: string | null
  error_class: string | null
  error_message: string | null
}

export interface AiOpsCase {
  id: string
  case_key: string
  domain: string
  case_type: string
  entity_type: string | null
  entity_id: string | null
  entity_label: string
  attention_class: AiOpsAttentionClass
  severity: AiOpsCaseSeverity
  status: AiOpsCaseStatus
  title: string
  reason: string
  first_seen_at: string
  last_seen_at: string
  source_as_of: string
  responsibility_label: string | null
  responsibility_basis: string | null
  value_label: string | null
  has_existing_work: boolean
  linked_work_number: number | null
  recommended_decision: AiOpsDecisionType | null
  review_after: string | null
}

export interface AiOpsResponsibilityEvidence {
  evidence_type: string
  label: string
  user_id: string | null
  user_label: string | null
  strength: AiOpsEvidenceStrength
  active_work_actor: boolean | null
  occurred_at: string | null
  note: string | null
}

export interface AiOpsWorkCollision {
  work_item_id: string
  work_number: number
  status: string
  relation_type: string
  title: string
}

export interface AiOpsFrozenContextEvidence {
  id: string
  subject_type: string
  subject_id: string
  context_type: string
  summary: string
  owner_user_id: string | null
  owner_label: string | null
  source_type: 'human' | 'system' | 'ai_proposed'
  confidence_class: AiOpsContextConfidence
  lifecycle_type: AiOpsContextLifecycle
  valid_from: string
  valid_until: string | null
  review_on: string | null
  visibility: 'management' | 'standard'
  content_trust: 'governed_untrusted_text'
}

export interface AiOpsContextCoverage {
  total: number
  captured: number
  truncated: boolean
}

export interface AiOpsCaseDecisionReview {
  decision_type: AiOpsDecisionType | null
  concise_rationale: string
  why_this_owner: string | null
  why_now: string | null
  confidence: number | null
  requires_human_review: boolean
}

export interface AiOpsCaseDetail {
  case_id: string
  case_key: string
  business_date: string
  facts: Array<{ label: string; value: string }>
  responsibility_evidence: AiOpsResponsibilityEvidence[]
  existing_work: AiOpsWorkCollision[]
  relevant_context_ids: string[]
  frozen_context: AiOpsFrozenContextEvidence[]
  context_coverage: AiOpsContextCoverage
  decision_review: AiOpsCaseDecisionReview
}

export interface AiOpsDecisionReviewDetail {
  decision_id: string
  run_id: string
  run_status: AiOpsRunStatus
  run_checkpoint: string
  revision: number
  decision_type: AiOpsDecisionType
  concise_rationale: string
  why_this_owner: string | null
  why_now: string | null
  confidence: number | null
  recommended_owner_user_id: string | null
  recommended_owner_label: string | null
  recommended_assignee_user_id: string | null
  recommended_assignee_label: string | null
  expected_outcome: string | null
  next_action_text: string | null
  due_at: string | null
  review_after: string | null
  validation_state: AiOpsDecisionValidationState
  validation_codes: string[]
  requires_human_review: boolean
  review_state: AiOpsHumanReviewState | null
  reviewed_by_user_id: string | null
  reviewed_by_label: string | null
  reviewed_at: string | null
  review_note: string | null
  commit_status: AiOpsCommitStatus
  committed_work_item_id: string | null
  committed_work_number: number | null
  committed_at: string | null
  updated_at: string
}

export interface AiOpsCaseDecisionReviewResponse {
  case_id: string
  decision: AiOpsDecisionReviewDetail | null
}

export interface AiOpsRunLifecycleResult {
  run_id?: string
  status?: AiOpsRunStatus
  checkpoint?: string
  terminal?: boolean
  changed?: boolean
  reason?: string
  pending_human_review?: number
  pending_work_commit?: number
  system_rejected_decisions?: number
  blocked_work_commit?: number
  unsupported_execution_decisions?: number
}

export interface AiOpsReviewDecisionResult {
  reviewed: boolean
  idempotent_reuse?: boolean
  approval_blocked?: boolean
  review_id?: string
  decision_id: string
  review_state?: AiOpsHumanReviewState
  validation_state?: AiOpsDecisionValidationState
  validation_codes?: string[]
  reason?: string
  execution_performed?: boolean
  run_lifecycle?: AiOpsRunLifecycleResult
}

export interface AiOpsCommitDecisionResult {
  committed: boolean
  blocked?: boolean
  idempotent_reuse?: boolean
  decision_id?: string
  reason?: string
  work_item_id?: string
  work_number?: number
  source_key?: string
  operational_mutation?: string
  validation_codes?: string[]
  run_lifecycle?: AiOpsRunLifecycleResult
}

export interface AiOpsOperationalContextItem {
  id: string
  subject_type: string
  subject_id: string
  subject_label: string
  context_type: string
  summary: string
  owner_label: string | null
  source_type: 'human' | 'system' | 'ai_proposed'
  confidence_class: AiOpsContextConfidence
  lifecycle_type: AiOpsContextLifecycle
  valid_until: string | null
  review_on: string | null
  status: 'active' | 'expired' | 'revoked' | 'consumed'
}

export interface AiOpsConsoleSnapshot {
  mode: AiOpsDataMode
  integration_state: 'preview_only' | 'database_not_ready' | 'ready'
  generated_at: string
  data_as_of: string
  settings: AiOpsSettings
  trust: AiOpsTrustSignal[]
  pulse: AiOpsPulseMetric[]
  attention: AiOpsCase[]
  recent_runs: AiOpsPlannerRun[]
  context: AiOpsOperationalContextItem[]
}
