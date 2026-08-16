import { supabase } from '@/lib/supabase/client'
import type { AtomicOperationResult, WorkItemMutationResult } from './types'
import { WorkCommandError } from './runtime-api'

export type WorkLinkEntityType =
  | 'customer'
  | 'sales_order'
  | 'payment_receipt'
  | 'supplier'
  | 'purchase_invoice'
  | 'product'
  | 'warehouse'
  | 'employee'
  | 'activity'
  | 'target'

export interface WorkLinkRow {
  id: string
  work_item_id: string
  entity_type: WorkLinkEntityType
  entity_id: string
  relation_type: string
  label: string | null
  created_by_user_id: string | null
  created_at: string
}

export interface WorkDependencyRow {
  id: string
  blocked_work_item_id: string
  blocker_work_item_id: string
  dependency_strength: 'hard' | 'soft'
  created_by_user_id: string | null
  created_at: string
  resolved_at: string | null
  resolved_by_user_id: string | null
  resolution_reason: string | null
  blocker?: {
    id: string
    work_number: number
    title: string
    status: string
  } | null
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

export async function listWorkLinks(workItemId: string): Promise<WorkLinkRow[]> {
  const { data, error } = await supabase
    .from('work_links')
    .select('*')
    .eq('work_item_id', workItemId)
    .order('created_at', { ascending: true })
  if (error) throw error
  return (data ?? []) as WorkLinkRow[]
}

export async function listWorkDependencies(workItemId: string): Promise<WorkDependencyRow[]> {
  const { data, error } = await supabase
    .from('work_dependencies')
    .select('id,blocked_work_item_id,blocker_work_item_id,dependency_strength,created_by_user_id,created_at,resolved_at,resolved_by_user_id,resolution_reason')
    .eq('blocked_work_item_id', workItemId)
    .order('created_at', { ascending: true })
  if (error) throw error

  const rows = (data ?? []) as WorkDependencyRow[]
  const blockerIds = [...new Set(rows.map(row => row.blocker_work_item_id))]
  if (!blockerIds.length) return rows

  const { data: blockers, error: blockerError } = await supabase
    .from('work_items')
    .select('id,work_number,title,status')
    .in('id', blockerIds)
  if (blockerError) throw blockerError
  const blockerMap = new Map((blockers ?? []).map(blocker => [blocker.id, blocker]))
  return rows.map(row => ({ ...row, blocker: blockerMap.get(row.blocker_work_item_id) ?? null }))
}

export async function findVisibleWorkItemByNumber(workNumber: number) {
  const { data, error } = await supabase
    .from('work_items')
    .select('id,work_number,title,status')
    .eq('work_number', workNumber)
    .maybeSingle()
  if (error) throw error
  if (!data) throw new WorkCommandError('BLOCKER_NOT_FOUND', 'لم يتم العثور على عمل مرئي بهذا الرقم')
  return data
}

export async function addChecklistItem(input: {
  workItemId: string
  expectedVersion: number
  label: string
  isRequired: boolean
}) {
  return executeAtomic<WorkItemMutationResult & { checklist_item_id: string }>('work_add_checklist_item', {
    p_operation_id: crypto.randomUUID(),
    p_work_item_id: input.workItemId,
    p_expected_version: input.expectedVersion,
    p_label: input.label,
    p_is_required: input.isRequired,
    p_sort_order: null,
  })
}

export async function cancelWorkItem(input: { workItemId: string; expectedVersion: number; reason: string }) {
  return executeAtomic<WorkItemMutationResult>('work_cancel', {
    p_operation_id: crypto.randomUUID(),
    p_work_item_id: input.workItemId,
    p_expected_version: input.expectedVersion,
    p_reason: input.reason,
  })
}

export async function reopenWorkItem(input: {
  workItemId: string
  expectedVersion: number
  reason: string
  nextActionText: string
  nextActionAt?: string | null
}) {
  return executeAtomic<WorkItemMutationResult>('work_reopen', {
    p_operation_id: crypto.randomUUID(),
    p_work_item_id: input.workItemId,
    p_expected_version: input.expectedVersion,
    p_reason: input.reason,
    p_next_action_text: input.nextActionText,
    p_next_action_at: input.nextActionAt ?? null,
  })
}

export async function addWorkLink(input: {
  workItemId: string
  expectedVersion: number
  entityType: WorkLinkEntityType
  entityId: string
  relationType?: string
  label?: string | null
}) {
  return executeAtomic<WorkItemMutationResult & { link_id: string }>('work_add_link', {
    p_operation_id: crypto.randomUUID(),
    p_work_item_id: input.workItemId,
    p_expected_version: input.expectedVersion,
    p_entity_type: input.entityType,
    p_entity_id: input.entityId,
    p_relation_type: input.relationType ?? 'relates_to',
    p_label: input.label ?? null,
  })
}

export async function removeWorkLink(input: { linkId: string; expectedVersion: number; reason?: string | null }) {
  return executeAtomic<WorkItemMutationResult & { link_id: string }>('work_remove_link', {
    p_operation_id: crypto.randomUUID(),
    p_link_id: input.linkId,
    p_expected_version: input.expectedVersion,
    p_reason: input.reason ?? null,
  })
}

export async function addWorkDependency(input: {
  workItemId: string
  blockerWorkItemId: string
  expectedVersion: number
  strength: 'hard' | 'soft'
}) {
  return executeAtomic<WorkItemMutationResult & { dependency_id: string }>('work_add_dependency', {
    p_operation_id: crypto.randomUUID(),
    p_blocked_work_item_id: input.workItemId,
    p_blocker_work_item_id: input.blockerWorkItemId,
    p_expected_blocked_version: input.expectedVersion,
    p_strength: input.strength,
  })
}

export async function resolveWorkDependency(input: {
  dependencyId: string
  expectedVersion: number
  reason?: string | null
}) {
  return executeAtomic<WorkItemMutationResult & { dependency_id: string }>('work_resolve_dependency', {
    p_operation_id: crypto.randomUUID(),
    p_dependency_id: input.dependencyId,
    p_expected_blocked_version: input.expectedVersion,
    p_reason: input.reason ?? null,
  })
}
