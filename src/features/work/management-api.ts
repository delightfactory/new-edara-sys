import { supabase } from '@/lib/supabase/client'
import type { AtomicOperationResult } from './types'
import { WorkCommandError } from './runtime-api'
import type { WorkAssignmentCandidate } from './runtime-types'
import type {
  CreateQueueInput,
  CreateRecurrenceInput,
  CreateRequestTypeInput,
  UpdateQueueInput,
  WorkApprovalDefinitionDraft,
  WorkApprovalTemplateRow,
  WorkApprovalTemplateVersionRow,
  WorkOperationalSettingsRow,
  WorkQueueMemberRow,
  WorkQueueRow,
  WorkRecurrenceRow,
  WorkRequestTypeRow,
  WorkWorkflowDefinitionDraft,
  WorkWorkflowTemplateRow,
  WorkWorkflowTemplateVersionRow,
} from './management-types'

const operationId = () => crypto.randomUUID()

async function executeManagementAtomic<T>(rpcName: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(rpcName, args)
  if (error) throw error
  const response = data as AtomicOperationResult<T>
  if (!response || response.ok !== true) {
    const failure = response && response.ok === false ? response.error : null
    throw new WorkCommandError(failure?.code ?? 'UNKNOWN_ERROR', failure?.message ?? 'تعذر تنفيذ عملية الإدارة')
  }
  return response.data
}

export async function listManagementUsers(search = '', limit = 100): Promise<WorkAssignmentCandidate[]> {
  const { data, error } = await supabase.rpc('work_list_management_users', {
    p_search: search.trim() || null,
    p_limit: Math.min(Math.max(limit, 1), 200),
  })
  if (error) throw error
  return (data ?? []) as WorkAssignmentCandidate[]
}

export async function listWorkQueues(): Promise<WorkQueueRow[]> {
  const { data, error } = await supabase
    .from('work_queues')
    .select('id,code,name,description,branch_id,department_id,manager_user_id,default_priority,default_triage_sla_minutes,default_resolution_sla_minutes,is_active,state_version,created_at')
    .order('is_active', { ascending: false })
    .order('name')
  if (error) throw error
  return (data ?? []) as WorkQueueRow[]
}

export async function listWorkQueueMembers(): Promise<WorkQueueMemberRow[]> {
  const { data, error } = await supabase
    .from('work_queue_members')
    .select('id,queue_id,user_id,member_role,can_triage,can_assign,active_from,active_until')
    .is('active_until', null)
    .order('member_role', { ascending: false })
  if (error) throw error
  return (data ?? []) as WorkQueueMemberRow[]
}

export async function listWorkRequestTypes(): Promise<WorkRequestTypeRow[]> {
  const { data, error } = await supabase
    .from('work_request_types')
    .select('id,code,name,description,target_queue_id,target_department_id,intake_schema,expected_outcome_template,default_priority,default_visibility,triage_sla_minutes,default_resolution_sla_minutes,allow_requester_cancel,is_active,state_version,created_at')
    .order('is_active', { ascending: false })
    .order('name')
  if (error) throw error
  return (data ?? []) as WorkRequestTypeRow[]
}

export async function listApprovalTemplates(): Promise<WorkApprovalTemplateRow[]> {
  const { data, error } = await supabase
    .from('work_approval_templates')
    .select('id,code,name,description,is_active,current_published_version_id,created_at')
    .order('is_active', { ascending: false })
    .order('name')
  if (error) throw error
  return (data ?? []) as WorkApprovalTemplateRow[]
}

export async function listApprovalTemplateVersions(): Promise<WorkApprovalTemplateVersionRow[]> {
  const { data, error } = await supabase
    .from('work_approval_template_versions')
    .select('id,template_id,version_number,status,published_at,created_at')
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as WorkApprovalTemplateVersionRow[]
}

export async function listWorkflowTemplates(): Promise<WorkWorkflowTemplateRow[]> {
  const { data, error } = await supabase
    .from('work_workflow_templates')
    .select('id,code,name,description,is_active,current_published_version_id,created_at')
    .order('is_active', { ascending: false })
    .order('name')
  if (error) throw error
  return (data ?? []) as WorkWorkflowTemplateRow[]
}

export async function listWorkflowTemplateVersions(): Promise<WorkWorkflowTemplateVersionRow[]> {
  const { data, error } = await supabase
    .from('work_workflow_template_versions')
    .select('id,template_id,version_number,status,published_at,created_at')
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as WorkWorkflowTemplateVersionRow[]
}

export async function listRecurrenceDefinitions(): Promise<WorkRecurrenceRow[]> {
  const { data, error } = await supabase
    .from('work_recurrence_definitions')
    .select('id,name,description,target_kind,frequency,interval_count,weekdays,day_of_month,monthly_policy,local_time,timezone,starts_on,ends_on,overlap_policy,status,next_occurrence_at,state_version,task_config,workflow_template_id,workflow_version_policy,created_at')
    .order('status')
    .order('next_occurrence_at', { ascending: true, nullsFirst: false })
  if (error) throw error
  return (data ?? []) as WorkRecurrenceRow[]
}

export async function getOperationalSettings(): Promise<WorkOperationalSettingsRow> {
  const { data, error } = await supabase
    .from('work_operational_settings')
    .select('singleton,due_soon_hours,stale_after_hours,due_alert_cooldown_hours,follow_up_alert_cooldown_hours,stale_alert_cooldown_hours,blocked_alert_cooldown_hours,manager_escalation_enabled,hierarchy_validated_at,hierarchy_validated_by_user_id,state_version,updated_at')
    .eq('singleton', true)
    .single()
  if (error) throw error
  return data as WorkOperationalSettingsRow
}

export function createQueue(input: CreateQueueInput) {
  return executeManagementAtomic<{ queue_id: string; state_version: number }>('work_create_queue', {
    p_operation_id: operationId(), p_code: input.code, p_name: input.name,
    p_description: input.description ?? null, p_manager_user_id: input.managerUserId,
    p_branch_id: input.branchId ?? null, p_department_id: input.departmentId ?? null,
    p_default_priority: input.defaultPriority ?? 'normal',
    p_default_triage_sla_minutes: input.defaultTriageSlaMinutes,
    p_default_resolution_sla_minutes: input.defaultResolutionSlaMinutes ?? null,
  })
}

export function updateQueue(input: UpdateQueueInput) {
  return executeManagementAtomic<{ queue_id: string; state_version: number }>('work_update_queue', {
    p_operation_id: operationId(), p_queue_id: input.queueId, p_expected_version: input.expectedVersion,
    p_name: input.name, p_description: input.description ?? null, p_manager_user_id: input.managerUserId,
    p_branch_id: input.branchId ?? null, p_department_id: input.departmentId ?? null,
    p_default_priority: input.defaultPriority ?? 'normal',
    p_default_triage_sla_minutes: input.defaultTriageSlaMinutes,
    p_default_resolution_sla_minutes: input.defaultResolutionSlaMinutes ?? null,
    p_is_active: input.isActive,
  })
}

export function setQueueMember(input: { queueId: string; userId: string; memberRole: 'member' | 'triager' | 'manager'; canTriage: boolean; canAssign: boolean; isActive: boolean }) {
  return executeManagementAtomic<{ membership_id?: string; active: boolean }>('work_set_queue_member', {
    p_operation_id: operationId(), p_queue_id: input.queueId, p_user_id: input.userId,
    p_member_role: input.memberRole, p_can_triage: input.canTriage, p_can_assign: input.canAssign,
    p_is_active: input.isActive,
  })
}

export function createRequestType(input: CreateRequestTypeInput) {
  return executeManagementAtomic<{ request_type_id: string; state_version: number }>('work_create_request_type', {
    p_operation_id: operationId(), p_code: input.code, p_name: input.name,
    p_description: input.description ?? null, p_target_queue_id: input.targetQueueId,
    p_expected_outcome_template: input.expectedOutcomeTemplate, p_intake_schema: input.intakeSchema,
    p_target_department_id: input.targetDepartmentId ?? null, p_default_priority: input.defaultPriority ?? null,
    p_default_visibility: input.defaultVisibility ?? 'standard', p_triage_sla_minutes: input.triageSlaMinutes ?? null,
    p_default_resolution_sla_minutes: input.defaultResolutionSlaMinutes ?? null,
    p_allow_requester_cancel: input.allowRequesterCancel ?? true,
  })
}

export function createApprovalTemplate(input: { code: string; name: string; description?: string | null; definition: WorkApprovalDefinitionDraft; publish: boolean }) {
  return executeManagementAtomic<{ template_id: string; version_id: string; published: boolean }>('work_create_approval_template', {
    p_operation_id: operationId(), p_code: input.code, p_name: input.name,
    p_description: input.description ?? null, p_definition: input.definition, p_publish: input.publish,
  })
}

export function createApprovalTemplateVersion(templateId: string, definition: WorkApprovalDefinitionDraft, publish = false) {
  return executeManagementAtomic<{ template_id: string; version_id: string; version_number: number; published: boolean }>('work_create_approval_template_version', {
    p_operation_id: operationId(), p_template_id: templateId, p_definition: definition, p_publish: publish,
  })
}

export function publishApprovalTemplateVersion(versionId: string) {
  return executeManagementAtomic<{ template_id: string; version_id: string; version_number: number; published: boolean }>('work_publish_approval_template_version', {
    p_operation_id: operationId(), p_version_id: versionId,
  })
}

export function createWorkflowTemplate(input: { code: string; name: string; description?: string | null; definition: WorkWorkflowDefinitionDraft; publish: boolean }) {
  return executeManagementAtomic<{ template_id: string; version_id: string; published: boolean }>('work_create_workflow_template', {
    p_operation_id: operationId(), p_code: input.code, p_name: input.name,
    p_description: input.description ?? null, p_definition: input.definition, p_publish: input.publish,
  })
}

export function createWorkflowTemplateVersion(templateId: string, definition: WorkWorkflowDefinitionDraft, publish = false) {
  return executeManagementAtomic<{ template_id: string; version_id: string; version_number: number; published: boolean }>('work_create_workflow_template_version', {
    p_operation_id: operationId(), p_template_id: templateId, p_definition: definition, p_publish: publish,
  })
}

export function publishWorkflowTemplateVersion(versionId: string) {
  return executeManagementAtomic<{ template_id: string; version_id: string; version_number: number; published: boolean }>('work_publish_workflow_template_version', {
    p_operation_id: operationId(), p_version_id: versionId,
  })
}

export function createRecurrence(input: CreateRecurrenceInput) {
  return executeManagementAtomic<{ recurrence_definition_id: string; state_version: number }>('work_create_recurrence', {
    p_operation_id: operationId(), p_name: input.name, p_description: input.description ?? null,
    p_target_kind: input.targetKind, p_frequency: input.frequency, p_interval_count: input.intervalCount,
    p_local_time: input.localTime, p_timezone: input.timezone, p_starts_on: input.startsOn,
    p_ends_on: input.endsOn ?? null, p_weekdays: input.weekdays ?? null,
    p_day_of_month: input.dayOfMonth ?? null, p_monthly_policy: input.monthlyPolicy ?? null,
    p_overlap_policy: input.overlapPolicy ?? 'strict', p_task_config: input.taskConfig ?? {},
    p_workflow_template_id: input.workflowTemplateId ?? null,
    p_workflow_version_policy: input.workflowVersionPolicy ?? null, p_workflow_input: input.workflowInput ?? {},
    p_workflow_starter_user_id: input.workflowStarterUserId ?? null,
  })
}

export function setRecurrenceState(definitionId: string, expectedVersion: number, action: 'pause' | 'resume' | 'stop') {
  return executeManagementAtomic<{ recurrence_definition_id: string; state_version: number; status: string }>('work_set_recurrence_state', {
    p_operation_id: operationId(), p_definition_id: definitionId, p_expected_version: expectedVersion, p_action: action,
  })
}

export function updateOperationalSettings(input: { expectedVersion: number; dueSoonHours?: number; staleAfterHours?: number; dueAlertCooldownHours?: number; followUpAlertCooldownHours?: number; staleAlertCooldownHours?: number; blockedAlertCooldownHours?: number; validateHierarchy?: boolean; managerEscalationEnabled?: boolean }) {
  return executeManagementAtomic<{ state_version: number; manager_escalation_enabled: boolean }>('work_update_operational_settings', {
    p_operation_id: operationId(), p_expected_version: input.expectedVersion,
    p_due_soon_hours: input.dueSoonHours ?? null, p_stale_after_hours: input.staleAfterHours ?? null,
    p_due_alert_cooldown_hours: input.dueAlertCooldownHours ?? null,
    p_follow_up_alert_cooldown_hours: input.followUpAlertCooldownHours ?? null,
    p_stale_alert_cooldown_hours: input.staleAlertCooldownHours ?? null,
    p_blocked_alert_cooldown_hours: input.blockedAlertCooldownHours ?? null,
    p_validate_hierarchy: input.validateHierarchy ?? false,
    p_manager_escalation_enabled: input.managerEscalationEnabled ?? null,
  })
}
