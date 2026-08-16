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

export interface AiOpsOperationalContextItem {
  id: string
  subject_type: string
  subject_id: string
  subject_label: string
  context_type: string
  summary: string
  owner_label: string | null
  source_type: 'human' | 'system' | 'ai_proposed'
  confidence_class:
    | 'hard_policy'
    | 'approved_human'
    | 'explicit_human'
    | 'system_record'
    | 'system_inference'
    | 'ai_inference'
  lifecycle_type: 'permanent' | 'valid_until' | 'review_on' | 'one_time'
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
