import type {
  AtomicOperationResult,
  WorkCommentKind,
  WorkItemMutationResult,
  WorkItemStatus,
  WorkPriority,
  WorkVisibility,
} from './types'

export type WorkActionKind =
  | 'acknowledge'
  | 'execute_next_action'
  | 'follow_up'
  | 'completion_review'
  | 'approval_decision'
  | 'triage_request'

export interface WorkActionInboxItem {
  inbox_key: string
  action_kind: WorkActionKind
  work_item_id: string
  subject_id: string
  work_number: number
  title: string
  priority: WorkPriority
  visibility: WorkVisibility
  status: WorkItemStatus
  action_due_at: string | null
  work_state_version: number
  approval_state_version: number | null
  deep_link: string
  action_payload: Record<string, unknown>
}

export interface WorkOperationalFlagRow {
  work_item_id: string
  work_number: number
  status: WorkItemStatus
  priority: WorkPriority
  visibility: WorkVisibility
  current_assignee_user_id: string | null
  accountable_owner_user_id: string | null
  due_at: string | null
  next_action_at: string | null
  last_meaningful_activity_at: string | null
  is_blocked: boolean
  is_overdue: boolean
  is_stale: boolean
  is_escalated: boolean
  is_due_soon: boolean
  is_follow_up_due: boolean
  is_at_risk: boolean
}

export interface CreateTaskCommand {
  title: string
  description?: string | null
  expectedOutcome: string
  priority?: WorkPriority
  visibility?: WorkVisibility
  ownerUserId?: string | null
  assigneeUserId?: string | null
  dueAt?: string | null
  nextActionText: string
  nextActionAt?: string | null
  acknowledgementRequired?: boolean
  completionMode?: 'assignee_closes' | 'owner_review' | 'approval'
  activate?: boolean
}

export interface SetWaitingCommand {
  workItemId: string
  expectedVersion: number
  waitingOnType: 'user' | 'department' | 'queue' | 'external_party' | 'entity' | 'other'
  reason: string
  nextActionText: string
  followUpAt: string
  waitingOnUserId?: string | null
  waitingOnEntityType?: string | null
  waitingOnEntityId?: string | null
  waitingOnLabel?: string | null
}

export interface TriageRequestCommand {
  workItemId: string
  expectedVersion: number
  decision: 'accept' | 'needs_information' | 'reject'
  assigneeUserId?: string | null
  ownerUserId?: string | null
  dueAt?: string | null
  nextActionText?: string | null
  followUpAt?: string | null
  note?: string | null
}

export interface ApprovalDecisionCommand {
  assignmentId: string
  expectedApprovalVersion: number
  decision: 'approve' | 'reject' | 'changes_required'
  note?: string | null
}

export type WorkMutationResponse = AtomicOperationResult<WorkItemMutationResult & Record<string, unknown>>

export interface AddCommentCommand {
  workItemId: string
  body: string
  commentKind?: WorkCommentKind
  mentionedUserIds?: string[]
}
