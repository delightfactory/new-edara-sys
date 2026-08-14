import { supabase } from '@/lib/supabase/client'
import type { AtomicOperationResult, WorkCommentKind, WorkItemMutationResult } from './types'
import type {
  AddCommentCommand,
  ApprovalDecisionCommand,
  CreateTaskCommand,
  SetWaitingCommand,
  TriageRequestCommand,
  WorkActionInboxItem,
  WorkAssignmentCandidate,
  WorkOperationalFlagRow,
} from './runtime-types'

export class WorkCommandError extends Error {
  code: string

  constructor(code: string, message: string) {
    super(message)
    this.name = 'WorkCommandError'
    this.code = code
  }
}

export interface WorkRequestIntakeField {
  key: string
  label: string
  type: 'string' | 'number' | 'boolean' | 'array' | 'object'
  required?: boolean
  help?: string
}

export interface WorkRequestTypeOption {
  id: string
  code: string
  name: string
  description: string | null
  target_queue_id: string
  target_queue_name: string
  intake_schema: {
    version?: number
    fields: WorkRequestIntakeField[]
  }
  expected_outcome_template: string | null
  triage_sla_minutes: number | null
  default_resolution_sla_minutes: number | null
}

export interface SubmitWorkRequestInput {
  operationId: string
  requestTypeId: string
  title: string
  description?: string | null
  intakePayload: Record<string, unknown>
}

export interface SubmitWorkRequestResult extends WorkItemMutationResult {
  queue_id: string
  request_type_id: string
  triage_due_at: string
  due_at: string | null
}

const operationId = () => crypto.randomUUID()

const WORK_ATTACHMENT_MAX_BYTES = 25 * 1024 * 1024
const WORK_ATTACHMENT_MIME_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'application/pdf',
  'text/plain',
  'text/csv',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
])

async function executeAtomic<T>(
  rpcName: string,
  args: Record<string, unknown>,
): Promise<T> {
  const { data, error } = await supabase.rpc(rpcName, args)
  if (error) throw error

  const response = data as AtomicOperationResult<T>
  if (!response || response.ok !== true) {
    const failure = response && response.ok === false ? response.error : null
    throw new WorkCommandError(
      failure?.code ?? 'UNKNOWN_ERROR',
      failure?.message ?? 'تعذر تنفيذ العملية',
    )
  }
  return response.data
}

export async function getMyActionInbox(limit = 100): Promise<WorkActionInboxItem[]> {
  const { data, error } = await supabase.rpc('work_get_action_inbox', {
    p_limit: Math.min(Math.max(limit, 1), 200),
  })
  if (error) throw error
  return (data ?? []) as WorkActionInboxItem[]
}

export async function getOperationalFlags(workItemIds?: string[]): Promise<WorkOperationalFlagRow[]> {
  let query = supabase.from('work_operational_flags').select('*')
  if (workItemIds?.length) query = query.in('work_item_id', workItemIds)
  const { data, error } = await query
  if (error) throw error
  return (data ?? []) as WorkOperationalFlagRow[]
}

export async function listAssignmentCandidates(search = '', limit = 50): Promise<WorkAssignmentCandidate[]> {
  const { data, error } = await supabase.rpc('work_list_assignment_candidates', {
    p_search: search.trim() || null,
    p_limit: Math.min(Math.max(limit, 1), 100),
  })
  if (error) throw error
  return (data ?? []) as WorkAssignmentCandidate[]
}

export async function listAvailableRequestTypes(): Promise<WorkRequestTypeOption[]> {
  const [queueResult, typeResult] = await Promise.all([
    supabase
      .from('work_queues')
      .select('id,name,default_triage_sla_minutes,default_resolution_sla_minutes')
      .eq('is_active', true),
    supabase
      .from('work_request_types')
      .select('id,code,name,description,target_queue_id,intake_schema,expected_outcome_template,triage_sla_minutes,default_resolution_sla_minutes')
      .eq('is_active', true)
      .order('name'),
  ])

  if (queueResult.error) throw queueResult.error
  if (typeResult.error) throw typeResult.error

  const queues = new Map(
    (queueResult.data ?? []).map(queue => [queue.id, queue]),
  )

  return (typeResult.data ?? [])
    .map(row => {
      const queue = queues.get(row.target_queue_id)
      if (!queue) return null

      const schema = row.intake_schema as { version?: number; fields?: WorkRequestIntakeField[] } | null
      return {
        id: row.id,
        code: row.code,
        name: row.name,
        description: row.description,
        target_queue_id: row.target_queue_id,
        target_queue_name: queue.name,
        intake_schema: {
          version: schema?.version,
          fields: Array.isArray(schema?.fields) ? schema.fields : [],
        },
        expected_outcome_template: row.expected_outcome_template,
        triage_sla_minutes: row.triage_sla_minutes ?? queue.default_triage_sla_minutes,
        default_resolution_sla_minutes:
          row.default_resolution_sla_minutes ?? queue.default_resolution_sla_minutes,
      } satisfies WorkRequestTypeOption
    })
    .filter((row): row is WorkRequestTypeOption => row !== null)
}

export async function submitWorkRequest(input: SubmitWorkRequestInput) {
  return executeAtomic<SubmitWorkRequestResult>('work_submit_request', {
    p_operation_id: input.operationId,
    p_request_type_id: input.requestTypeId,
    p_title: input.title,
    p_description: input.description ?? null,
    p_expected_outcome: null,
    p_intake_payload: input.intakePayload,
    p_priority: null,
    p_visibility: null,
  })
}

export async function createTask(input: CreateTaskCommand) {
  return executeAtomic<WorkItemMutationResult>('work_create_task', {
    p_operation_id: operationId(),
    p_title: input.title,
    p_description: input.description ?? null,
    p_expected_outcome: input.expectedOutcome,
    p_priority: input.priority ?? 'normal',
    p_visibility: input.visibility ?? 'standard',
    p_owner_user_id: input.ownerUserId ?? null,
    p_assignee_user_id: input.assigneeUserId ?? null,
    p_due_at: input.dueAt ?? null,
    p_next_action_text: input.nextActionText,
    p_next_action_at: input.nextActionAt ?? null,
    p_acknowledgement_required: input.acknowledgementRequired ?? false,
    p_completion_mode: input.completionMode ?? 'assignee_closes',
    p_activate: input.activate ?? true,
  })
}

export async function acknowledgeWork(workItemId: string, expectedVersion: number) {
  return executeAtomic<WorkItemMutationResult>('work_acknowledge', {
    p_operation_id: operationId(),
    p_work_item_id: workItemId,
    p_expected_version: expectedVersion,
  })
}

export async function startWork(workItemId: string, expectedVersion: number) {
  return executeAtomic<WorkItemMutationResult>('work_start', {
    p_operation_id: operationId(),
    p_work_item_id: workItemId,
    p_expected_version: expectedVersion,
  })
}

export async function setWorkWaiting(input: SetWaitingCommand) {
  return executeAtomic<WorkItemMutationResult>('work_set_waiting', {
    p_operation_id: operationId(),
    p_work_item_id: input.workItemId,
    p_expected_version: input.expectedVersion,
    p_waiting_on_type: input.waitingOnType,
    p_waiting_reason: input.reason,
    p_next_action_text: input.nextActionText,
    p_follow_up_at: input.followUpAt,
    p_waiting_on_user_id: input.waitingOnUserId ?? null,
    p_waiting_on_entity_type: input.waitingOnEntityType ?? null,
    p_waiting_on_entity_id: input.waitingOnEntityId ?? null,
    p_waiting_on_label: input.waitingOnLabel ?? null,
  })
}

export async function resumeWork(
  workItemId: string,
  expectedVersion: number,
  nextActionText: string,
  nextActionAt?: string | null,
) {
  return executeAtomic<WorkItemMutationResult>('work_resume', {
    p_operation_id: operationId(),
    p_work_item_id: workItemId,
    p_expected_version: expectedVersion,
    p_next_action_text: nextActionText,
    p_next_action_at: nextActionAt ?? null,
  })
}

export async function updateNextAction(
  workItemId: string,
  expectedVersion: number,
  nextActionText: string,
  nextActionAt?: string | null,
) {
  return executeAtomic<WorkItemMutationResult>('work_update_next_action', {
    p_operation_id: operationId(),
    p_work_item_id: workItemId,
    p_expected_version: expectedVersion,
    p_next_action_text: nextActionText,
    p_next_action_at: nextActionAt ?? null,
  })
}

export async function addWorkComment(input: AddCommentCommand) {
  return executeAtomic<WorkItemMutationResult & { comment_id: string }>('work_add_comment', {
    p_operation_id: operationId(),
    p_work_item_id: input.workItemId,
    p_body: input.body,
    p_comment_kind: input.commentKind ?? 'comment',
    p_mentioned_user_ids: input.mentionedUserIds ?? [],
  })
}

export async function setChecklistCompletion(
  workItemId: string,
  checklistItemId: string,
  expectedVersion: number,
  completed: boolean,
) {
  return executeAtomic<WorkItemMutationResult>('work_set_checklist_completion', {
    p_operation_id: operationId(),
    p_work_item_id: workItemId,
    p_checklist_item_id: checklistItemId,
    p_expected_version: expectedVersion,
    p_completed: completed,
  })
}

export async function completeWork(
  workItemId: string,
  expectedVersion: number,
  completionSummary: string,
  completionOutput: Record<string, unknown> = {},
) {
  return executeAtomic<WorkItemMutationResult>('work_complete', {
    p_operation_id: operationId(),
    p_work_item_id: workItemId,
    p_expected_version: expectedVersion,
    p_completion_summary: completionSummary,
    p_completion_output: completionOutput,
  })
}

export async function reviewCompletion(
  reviewId: string,
  expectedVersion: number,
  decision: 'approve' | 'changes_required',
  note?: string | null,
) {
  return executeAtomic<WorkItemMutationResult>('work_review_completion', {
    p_operation_id: operationId(),
    p_review_id: reviewId,
    p_expected_version: expectedVersion,
    p_decision: decision,
    p_note: note ?? null,
  })
}

export async function decideApproval(input: ApprovalDecisionCommand) {
  return executeAtomic<Record<string, unknown>>('work_decide_approval', {
    p_operation_id: operationId(),
    p_assignment_id: input.assignmentId,
    p_expected_approval_version: input.expectedApprovalVersion,
    p_decision: input.decision,
    p_note: input.note ?? null,
  })
}

export async function triageRequest(input: TriageRequestCommand) {
  return executeAtomic<WorkItemMutationResult>('work_triage_request', {
    p_operation_id: operationId(),
    p_work_item_id: input.workItemId,
    p_expected_version: input.expectedVersion,
    p_decision: input.decision,
    p_assignee_user_id: input.assigneeUserId ?? null,
    p_owner_user_id: input.ownerUserId ?? null,
    p_due_at: input.dueAt ?? null,
    p_next_action_text: input.nextActionText ?? null,
    p_follow_up_at: input.followUpAt ?? null,
    p_note: input.note ?? null,
  })
}

export async function recordFirstView(workItemId: string) {
  const { data, error } = await supabase.rpc('work_record_first_view', {
    p_work_item_id: workItemId,
  })
  if (error) throw error
  return data as { ok: boolean; work_item_id?: string }
}

export async function uploadWorkAttachment(input: {
  workItemId: string
  expectedVersion: number
  file: File
  purpose?: 'reference' | 'evidence' | 'output'
  commentId?: string | null
}) {
  if (input.file.size <= 0 || input.file.size > WORK_ATTACHMENT_MAX_BYTES) {
    throw new WorkCommandError('INVALID_FILE_SIZE', 'حجم المرفق غير مسموح')
  }
  if (!WORK_ATTACHMENT_MIME_TYPES.has(input.file.type)) {
    throw new WorkCommandError('INVALID_FILE_TYPE', 'نوع المرفق غير مسموح')
  }

  const safeName = input.file.name.replace(/[^a-zA-Z0-9._-]+/g, '_').slice(-120) || 'attachment'
  const storagePath = `work/${input.workItemId}/${crypto.randomUUID()}-${safeName}`
  const { error: uploadError } = await supabase.storage
    .from('work-attachments')
    .upload(storagePath, input.file, { upsert: false, contentType: input.file.type })
  if (uploadError) throw uploadError

  try {
    return await executeAtomic<WorkItemMutationResult & { attachment_id: string }>('work_add_attachment_metadata', {
      p_operation_id: operationId(),
      p_work_item_id: input.workItemId,
      p_expected_version: input.expectedVersion,
      p_storage_path: storagePath,
      p_original_filename: input.file.name,
      p_mime_type: input.file.type,
      p_size_bytes: input.file.size,
      p_purpose: input.purpose ?? 'reference',
      p_comment_id: input.commentId ?? null,
    })
  } catch (error) {
    try {
      await supabase.storage.from('work-attachments').remove([storagePath])
    } catch {
      // The object is not readable without active metadata, so a failed cleanup
      // does not expose content. A service cleanup job can remove the orphan later.
    }
    throw error
  }
}

export async function removeWorkAttachment(input: {
  attachmentId: string
  workItemId: string
  expectedVersion: number
  storagePath: string
  reason?: string | null
}) {
  const result = await executeAtomic<WorkItemMutationResult & {
    storage_bucket: string
    storage_path: string
  }>('work_remove_attachment_metadata', {
    p_operation_id: operationId(),
    p_attachment_id: input.attachmentId,
    p_expected_version: input.expectedVersion,
    p_reason: input.reason ?? null,
  })

  const { error: cleanupError } = await supabase.storage
    .from('work-attachments')
    .remove([input.storagePath])

  return {
    ...result,
    storage_cleanup_pending: Boolean(cleanupError),
  }
}

export function normalizeCommentKind(value?: WorkCommentKind): WorkCommentKind {
  return value ?? 'comment'
}
