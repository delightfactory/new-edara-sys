import type { WorkPriority, WorkVisibility } from './types'

export type WorkManagementTab = 'queues' | 'approvals' | 'workflows' | 'recurrence' | 'policies'

export interface WorkQueueRow {
  id: string
  code: string
  name: string
  description: string | null
  branch_id: string | null
  department_id: string | null
  manager_user_id: string
  default_priority: WorkPriority
  default_triage_sla_minutes: number
  default_resolution_sla_minutes: number | null
  is_active: boolean
  state_version: number
  created_at: string
}

export interface WorkQueueMemberRow {
  id: string
  queue_id: string
  user_id: string
  member_role: 'member' | 'triager' | 'manager'
  can_triage: boolean
  can_assign: boolean
  active_from: string
  active_until: string | null
}

export interface WorkRequestTypeRow {
  id: string
  code: string
  name: string
  description: string | null
  target_queue_id: string
  target_department_id: string | null
  intake_schema: WorkIntakeSchema
  expected_outcome_template: string
  default_priority: WorkPriority | null
  default_visibility: WorkVisibility
  triage_sla_minutes: number | null
  default_resolution_sla_minutes: number | null
  allow_requester_cancel: boolean
  is_active: boolean
  state_version: number
  created_at: string
}

export interface WorkIntakeField {
  key: string
  label: string
  type: 'string' | 'number' | 'boolean' | 'array' | 'object'
  required?: boolean
  help?: string
}

export interface WorkIntakeSchema {
  version: number
  fields: WorkIntakeField[]
}

export interface WorkApprovalTemplateRow {
  id: string
  code: string
  name: string
  description: string | null
  is_active: boolean
  current_published_version_id: string | null
  created_at: string
}

export interface WorkApprovalTemplateVersionRow {
  id: string
  template_id: string
  version_number: number
  status: 'draft' | 'published' | 'retired'
  published_at: string | null
  created_at: string
}

export interface WorkApprovalApproverDraft {
  selector_kind: 'user' | 'work_owner' | 'assignee' | 'department_manager' | 'branch_manager'
  user_id?: string
  sort_order?: number
}

export interface WorkApprovalStageDraft {
  name: string
  mode: 'all' | 'any'
  deadline_minutes?: number | null
  allow_changes_required: boolean
  approvers: WorkApprovalApproverDraft[]
}

export interface WorkApprovalDefinitionDraft {
  metadata?: Record<string, unknown>
  stages: WorkApprovalStageDraft[]
}

export interface WorkWorkflowTemplateRow {
  id: string
  code: string
  name: string
  description: string | null
  is_active: boolean
  current_published_version_id: string | null
  created_at: string
}

export interface WorkWorkflowTemplateVersionRow {
  id: string
  template_id: string
  version_number: number
  status: 'draft' | 'published' | 'retired'
  published_at: string | null
  created_at: string
}

export interface WorkWorkflowStepDraft {
  key: string
  name: string
  kind: 'task' | 'approval'
  depends_on: string[]
  condition: Record<string, unknown>
  output_schema: WorkIntakeSchema
  task?: {
    expected_outcome: string
    next_action_text?: string
    owner_user_id?: string
    assignee_user_id?: string
    due_after_minutes?: number
    priority?: WorkPriority
    visibility?: WorkVisibility
    completion_mode?: 'assignee_closes' | 'owner_review' | 'approval'
    completion_approval_template_id?: string
  }
  approval_template_id?: string
}

export interface WorkWorkflowDefinitionDraft {
  metadata?: Record<string, unknown>
  steps: WorkWorkflowStepDraft[]
}

export interface WorkRecurrenceRow {
  id: string
  name: string
  description: string | null
  target_kind: 'task' | 'workflow'
  frequency: 'daily' | 'weekly' | 'monthly'
  interval_count: number
  weekdays: number[] | null
  day_of_month: number | null
  monthly_policy: 'exact_day' | 'last_day' | null
  local_time: string
  timezone: string
  starts_on: string
  ends_on: string | null
  overlap_policy: 'strict' | 'single_open'
  status: 'active' | 'paused' | 'stopped'
  next_occurrence_at: string | null
  state_version: number
  task_config: Record<string, unknown>
  workflow_template_id: string | null
  workflow_version_policy: 'pinned' | 'latest_published' | null
  created_at: string
}

export interface WorkOperationalSettingsRow {
  singleton: boolean
  due_soon_hours: number
  stale_after_hours: number
  due_alert_cooldown_hours: number
  follow_up_alert_cooldown_hours: number
  stale_alert_cooldown_hours: number
  blocked_alert_cooldown_hours: number
  manager_escalation_enabled: boolean
  hierarchy_validated_at: string | null
  hierarchy_validated_by_user_id: string | null
  state_version: number
  updated_at: string
}

export interface CreateQueueInput {
  code: string
  name: string
  description?: string | null
  managerUserId: string
  branchId?: string | null
  departmentId?: string | null
  defaultPriority?: WorkPriority
  defaultTriageSlaMinutes: number
  defaultResolutionSlaMinutes?: number | null
}

export interface UpdateQueueInput extends Omit<CreateQueueInput, 'code'> {
  queueId: string
  expectedVersion: number
  isActive: boolean
}

export interface CreateRequestTypeInput {
  code: string
  name: string
  description?: string | null
  targetQueueId: string
  targetDepartmentId?: string | null
  expectedOutcomeTemplate: string
  intakeSchema: WorkIntakeSchema
  defaultPriority?: WorkPriority | null
  defaultVisibility?: WorkVisibility
  triageSlaMinutes?: number | null
  defaultResolutionSlaMinutes?: number | null
  allowRequesterCancel?: boolean
}

export interface CreateRecurrenceInput {
  name: string
  description?: string | null
  targetKind: 'task' | 'workflow'
  frequency: 'daily' | 'weekly' | 'monthly'
  intervalCount: number
  localTime: string
  timezone: string
  startsOn: string
  endsOn?: string | null
  weekdays?: number[] | null
  dayOfMonth?: number | null
  monthlyPolicy?: 'exact_day' | 'last_day' | null
  overlapPolicy?: 'strict' | 'single_open'
  taskConfig?: Record<string, unknown>
  workflowTemplateId?: string | null
  workflowVersionPolicy?: 'pinned' | 'latest_published' | null
  workflowInput?: Record<string, unknown>
  workflowStarterUserId?: string | null
}
