export type WorkItemKind = 'task' | 'request' | 'workflow_step'
export type WorkSourceKind = 'manual' | 'request_intake' | 'workflow' | 'recurrence' | 'system'
export type WorkItemStatus =
  | 'draft'
  | 'open'
  | 'in_progress'
  | 'waiting'
  | 'pending_approval'
  | 'done'
  | 'cancelled'

export type WorkPriority = 'low' | 'normal' | 'high' | 'urgent' | 'critical'
export type WorkVisibility = 'standard' | 'restricted' | 'private'
export type WorkCompletionMode = 'assignee_closes' | 'owner_review' | 'approval'
export type WorkWaitingOnType = 'user' | 'department' | 'queue' | 'external_party' | 'entity' | 'other'
export type WorkCommentKind = 'comment' | 'progress_update'
export type WorkDependencyStrength = 'hard' | 'soft'
export type WorkAttachmentPurpose = 'reference' | 'evidence' | 'output'

export interface WorkItem {
  id: string
  work_number: number
  kind: WorkItemKind
  source_kind: WorkSourceKind
  source_key: string | null
  title: string
  description: string | null
  expected_outcome: string | null
  completion_summary: string | null
  completion_output: Record<string, unknown>
  completed_by_user_id: string | null
  acknowledgement_required: boolean
  assigned_at: string | null
  first_viewed_at: string | null
  acknowledged_at: string | null
  blocks_parent_completion: boolean
  completion_approval_template_id: string | null
  status: WorkItemStatus
  priority: WorkPriority
  visibility: WorkVisibility
  creator_user_id: string | null
  requester_user_id: string | null
  accountable_owner_user_id: string | null
  current_assignee_user_id: string | null
  source_department_id: string | null
  owning_department_id: string | null
  branch_id: string | null
  queue_id: string | null
  parent_work_item_id: string | null
  request_type_id: string | null
  template_id: string | null
  workflow_run_id: string | null
  workflow_step_key: string | null
  policy_id: string | null
  recurrence_definition_id: string | null
  recurrence_occurrence_id: string | null
  activated_at: string | null
  started_at: string | null
  start_not_before: string | null
  due_at: string | null
  first_due_at: string | null
  next_action_text: string | null
  next_action_at: string | null
  waiting_on_type: WorkWaitingOnType | null
  waiting_on_user_id: string | null
  waiting_on_entity_type: string | null
  waiting_on_entity_id: string | null
  waiting_on_label: string | null
  waiting_reason: string | null
  waiting_since: string | null
  blocked_reason: string | null
  completion_mode: WorkCompletionMode
  reassign_on_inactive: boolean
  metadata: Record<string, unknown>
  state_version: number
  last_meaningful_activity_at: string | null
  completed_at: string | null
  cancelled_at: string | null
  archived_at: string | null
  reopened_at: string | null
  created_at: string
  updated_at: string
}

export interface WorkEvent {
  id: string
  work_item_id: string
  event_type: string
  actor_user_id: string | null
  acting_for_user_id: string | null
  actor_kind: 'user' | 'system'
  from_status: WorkItemStatus | null
  to_status: WorkItemStatus | null
  operation_id: string | null
  payload: Record<string, unknown>
  client_event_at: string | null
  created_at: string
}

export interface WorkChecklistItem {
  id: string
  work_item_id: string
  label: string
  is_required: boolean
  sort_order: number
  completed_at: string | null
  completed_by_user_id: string | null
  created_by_user_id: string | null
  created_at: string
}

export interface WorkComment {
  id: string
  work_item_id: string
  author_user_id: string | null
  comment_kind: WorkCommentKind
  body: string
  edited_at: string | null
  redacted_at: string | null
  redacted_by_user_id: string | null
  created_at: string
}

export interface WorkOperationalFlags {
  is_overdue: boolean
  is_followup_due: boolean
  is_blocked: boolean
  is_stale: boolean
  is_at_risk: boolean
  is_escalated: boolean
}

export interface CreateWorkItemInput {
  title: string
  description?: string | null
  expectedOutcome?: string | null
  priority?: WorkPriority
  visibility?: WorkVisibility
  accountableOwnerUserId?: string | null
  assigneeUserId?: string | null
  dueAt?: string | null
  nextActionText?: string | null
  nextActionAt?: string | null
  acknowledgementRequired?: boolean
  completionMode?: WorkCompletionMode
}

export interface AtomicOperationError {
  code: string
  message: string
}

export type AtomicOperationResult<T> =
  | {
      ok: true
      operation_id: string
      operation: string
      replayed: boolean
      data: T
    }
  | {
      ok: false
      operation_id: string | null
      operation: string
      replayed: boolean
      error: AtomicOperationError
    }

export interface WorkItemMutationResult {
  work_item_id: string
  work_number?: number
  status: WorkItemStatus
  state_version: number
}
