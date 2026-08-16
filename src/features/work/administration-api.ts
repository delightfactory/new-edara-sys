import { supabase } from '@/lib/supabase/client'
import type { AtomicOperationResult, WorkItemMutationResult, WorkPriority } from './types'
import type { WorkAssignmentCandidate } from './runtime-types'
import { WorkCommandError } from './runtime-api'

export type WorkParticipantRole = 'follower' | 'collaborator' | 'observer'

export interface WorkParticipantSnapshot {
  user_id: string
  full_name: string
  participant_role: WorkParticipantRole
  can_comment: boolean
  added_at: string
}

export interface WorkEscalationSnapshot {
  id: string
  work_item_id: string
  escalated_by_user_id: string
  target_user_id: string | null
  reason: string
  escalated_at: string
  resolved_at: string | null
  resolution_note: string | null
}

async function executeAtomic<T>(rpcName: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(rpcName, args)
  if (error) throw error
  const response = data as AtomicOperationResult<T>
  if (!response || response.ok !== true) {
    const failure = response && response.ok === false ? response.error : null
    throw new WorkCommandError(failure?.code ?? 'UNKNOWN_ERROR', failure?.message ?? 'تعذر تنفيذ العملية')
  }
  return response.data
}

export async function listItemPeopleCandidates(
  workItemId: string,
  purpose: 'participant' | 'delegate' | 'transfer_owner',
  search = '',
  limit = 50,
): Promise<WorkAssignmentCandidate[]> {
  const { data, error } = await supabase.rpc('work_list_item_people_candidates', {
    p_work_item_id: workItemId,
    p_purpose: purpose,
    p_search: search.trim() || null,
    p_limit: Math.min(Math.max(limit, 1), 100),
  })
  if (error) throw error
  return (data ?? []) as WorkAssignmentCandidate[]
}

export async function listWorkParticipants(workItemId: string): Promise<WorkParticipantSnapshot[]> {
  const { data, error } = await supabase.rpc('work_list_participants', { p_work_item_id: workItemId })
  if (error) throw error
  return (data ?? []) as WorkParticipantSnapshot[]
}

export async function getActiveWorkEscalation(workItemId: string): Promise<WorkEscalationSnapshot | null> {
  const { data, error } = await supabase
    .from('work_escalations')
    .select('id,work_item_id,escalated_by_user_id,target_user_id,reason,escalated_at,resolved_at,resolution_note')
    .eq('work_item_id', workItemId)
    .is('resolved_at', null)
    .maybeSingle()
  if (error) throw error
  return data as WorkEscalationSnapshot | null
}

export async function delegateWork(input: { workItemId: string; expectedVersion: number; userId: string; reason?: string | null }) {
  return executeAtomic<WorkItemMutationResult>('work_delegate', {
    p_operation_id: crypto.randomUUID(),
    p_work_item_id: input.workItemId,
    p_expected_version: input.expectedVersion,
    p_new_assignee_user_id: input.userId,
    p_reason: input.reason ?? null,
  })
}

export async function transferWorkOwnership(input: { workItemId: string; expectedVersion: number; userId: string; reason?: string | null }) {
  return executeAtomic<WorkItemMutationResult>('work_transfer_ownership', {
    p_operation_id: crypto.randomUUID(),
    p_work_item_id: input.workItemId,
    p_expected_version: input.expectedVersion,
    p_new_owner_user_id: input.userId,
    p_reason: input.reason ?? null,
  })
}

export async function changeWorkDue(input: { workItemId: string; expectedVersion: number; dueAt: string; reason: string }) {
  return executeAtomic<WorkItemMutationResult>('work_change_due', {
    p_operation_id: crypto.randomUUID(),
    p_work_item_id: input.workItemId,
    p_expected_version: input.expectedVersion,
    p_new_due_at: input.dueAt,
    p_reason: input.reason,
  })
}

export async function createWorkSubtask(input: {
  parentWorkItemId: string
  expectedParentVersion: number
  title: string
  description?: string | null
  expectedOutcome: string
  priority?: WorkPriority
  dueAt?: string | null
  nextActionText: string
  nextActionAt?: string | null
  blocksParentCompletion?: boolean
  activate?: boolean
}) {
  return executeAtomic<WorkItemMutationResult & { parent_work_item_id: string }>('work_create_subtask', {
    p_operation_id: crypto.randomUUID(),
    p_parent_work_item_id: input.parentWorkItemId,
    p_expected_parent_version: input.expectedParentVersion,
    p_title: input.title,
    p_description: input.description ?? null,
    p_expected_outcome: input.expectedOutcome,
    p_priority: input.priority ?? 'normal',
    p_owner_user_id: null,
    p_assignee_user_id: null,
    p_due_at: input.dueAt ?? null,
    p_next_action_text: input.nextActionText,
    p_next_action_at: input.nextActionAt ?? null,
    p_blocks_parent_completion: input.blocksParentCompletion ?? true,
    p_activate: input.activate ?? true,
  })
}

export async function setWorkParticipant(input: {
  workItemId: string
  expectedVersion: number
  userId: string
  role?: WorkParticipantRole
  canComment?: boolean
  active: boolean
}) {
  return executeAtomic<WorkItemMutationResult>('work_set_participant', {
    p_operation_id: crypto.randomUUID(),
    p_work_item_id: input.workItemId,
    p_expected_version: input.expectedVersion,
    p_user_id: input.userId,
    p_role: input.role ?? 'follower',
    p_can_comment: input.canComment ?? true,
    p_active: input.active,
  })
}

export async function escalateWork(input: { workItemId: string; expectedVersion: number; reason: string }) {
  return executeAtomic<WorkItemMutationResult & { escalation_id: string }>('work_escalate', {
    p_operation_id: crypto.randomUUID(),
    p_work_item_id: input.workItemId,
    p_expected_version: input.expectedVersion,
    p_reason: input.reason,
    p_target_user_id: null,
  })
}

export async function resolveWorkEscalation(input: { escalationId: string; expectedVersion: number; note?: string | null }) {
  return executeAtomic<WorkItemMutationResult & { escalation_id: string }>('work_resolve_escalation', {
    p_operation_id: crypto.randomUUID(),
    p_escalation_id: input.escalationId,
    p_expected_version: input.expectedVersion,
    p_resolution_note: input.note ?? null,
  })
}
