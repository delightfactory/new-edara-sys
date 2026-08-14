import { supabase } from '@/lib/supabase/client'
import type { AtomicOperationResult, WorkCommentKind, WorkItemMutationResult } from './types'
import type {
  AddCommentCommand,
  ApprovalDecisionCommand,
  CreateTaskCommand,
  SetWaitingCommand,
  TriageRequestCommand,
  WorkActionInboxItem,
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

const operationId = () => crypto.randomUUID()

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
  const safeName = input.file.name.replace(/[^a-zA-Z0-9._-]+/g, '_').slice(-120) || 'attachment'
  const storagePath = `work/${input.workItemId}/${crypto.randomUUID()}-${safeName}`
  const { error: uploadError } = await supabase.storage
    .from('work-attachments')
    .upload(storagePath, input.file, { upsert: false, contentType: input.file.type || undefined })
  if (uploadError) throw uploadError

  try {
    return await executeAtomic<WorkItemMutationResult & { attachment_id: string }>('work_add_attachment_metadata', {
      p_operation_id: operationId(),
      p_work_item_id: input.workItemId,
      p_expected_version: input.expectedVersion,
      p_storage_path: storagePath,
      p_original_filename: input.file.name,
      p_mime_type: input.file.type || 'application/octet-stream',
      p_size_bytes: input.file.size,
      p_purpose: input.purpose ?? 'reference',
      p_comment_id: input.commentId ?? null,
    })
  } catch (error) {
    await supabase.storage.from('work-attachments').remove([storagePath]).catch(() => undefined)
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
  const { error: storageError } = await supabase.storage
    .from('work-attachments')
    .remove([input.storagePath])
  if (storageError) throw storageError

  return executeAtomic<WorkItemMutationResult>('work_remove_attachment_metadata', {
    p_operation_id: operationId(),
    p_attachment_id: input.attachmentId,
    p_expected_version: input.expectedVersion,
    p_reason: input.reason ?? null,
  })
}

export function normalizeCommentKind(value?: WorkCommentKind): WorkCommentKind {
  return value ?? 'comment'
}
