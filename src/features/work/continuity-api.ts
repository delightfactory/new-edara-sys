import { supabase } from '@/lib/supabase/client'
import type { AtomicOperationResult } from './types'
import type { WorkAssignmentCandidate } from './runtime-types'
import { WorkCommandError } from './runtime-api'

export interface WorkOrphanedAssignment {
  user_id: string
  full_name: string
  profile_status: string
  employee_status: string
  orphan_reason: 'profile_inactive' | 'employee_inactive' | 'unavailable'
  owner_count: number
  assignee_count: number
  work_item_count: number
}

export interface WorkContinuityResult {
  inactive_user_id: string
  replacement_user_id: string
  work_item_count: number
  owner_changes: number
  assignee_changes: number
  work_item_ids: string[]
}

async function executeAtomic<T>(rpcName: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(rpcName, args)
  if (error) throw error
  const response = data as AtomicOperationResult<T>
  if (!response || response.ok !== true) {
    const failure = response && response.ok === false ? response.error : null
    throw new WorkCommandError(failure?.code ?? 'UNKNOWN_ERROR', failure?.message ?? 'تعذر تنفيذ معالجة استمرارية الأعمال')
  }
  return response.data
}

export async function listOrphanedWorkAssignments(): Promise<WorkOrphanedAssignment[]> {
  const { data, error } = await supabase.rpc('work_list_orphaned_assignments')
  if (error) throw error
  return (data ?? []) as WorkOrphanedAssignment[]
}

export async function listWorkContinuityCandidates(search = '', limit = 100): Promise<WorkAssignmentCandidate[]> {
  const { data, error } = await supabase.rpc('work_list_continuity_candidates', {
    p_search: search.trim() || null,
    p_limit: Math.min(Math.max(limit, 1), 200),
  })
  if (error) throw error
  return (data ?? []) as WorkAssignmentCandidate[]
}

export function bulkReassignOrphanedWork(input: {
  inactiveUserId: string
  replacementUserId: string
  reason: string
}) {
  return executeAtomic<WorkContinuityResult>('work_bulk_reassign_orphaned', {
    p_operation_id: crypto.randomUUID(),
    p_inactive_user_id: input.inactiveUserId,
    p_replacement_user_id: input.replacementUserId,
    p_reason: input.reason,
  })
}
