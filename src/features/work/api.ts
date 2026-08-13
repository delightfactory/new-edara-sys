import { supabase } from '@/lib/supabase/client'
import type {
  WorkChecklistItem,
  WorkComment,
  WorkEvent,
  WorkItem,
  WorkItemStatus,
  WorkPriority,
} from './types'

export interface WorkListFilters {
  status?: WorkItemStatus
  priority?: WorkPriority
  ownerUserId?: string
  assigneeUserId?: string
  branchId?: string
  departmentId?: string
  search?: string
  limit?: number
}

export async function getWorkItem(id: string): Promise<WorkItem> {
  const { data, error } = await supabase
    .from('work_items')
    .select('*')
    .eq('id', id)
    .single()

  if (error) throw error
  return data as WorkItem
}

export async function listVisibleWorkItems(filters: WorkListFilters = {}): Promise<WorkItem[]> {
  let query = supabase
    .from('work_items')
    .select('*')
    .order('due_at', { ascending: true, nullsFirst: false })
    .order('created_at', { ascending: false })
    .limit(Math.min(Math.max(filters.limit ?? 100, 1), 250))

  if (filters.status) query = query.eq('status', filters.status)
  if (filters.priority) query = query.eq('priority', filters.priority)
  if (filters.ownerUserId) query = query.eq('accountable_owner_user_id', filters.ownerUserId)
  if (filters.assigneeUserId) query = query.eq('current_assignee_user_id', filters.assigneeUserId)
  if (filters.branchId) query = query.eq('branch_id', filters.branchId)
  if (filters.departmentId) query = query.eq('owning_department_id', filters.departmentId)
  if (filters.search?.trim()) {
    const term = filters.search.trim().replace(/[,%()]/g, ' ')
    query = query.ilike('title', `%${term}%`)
  }

  const { data, error } = await query
  if (error) throw error
  return (data ?? []) as WorkItem[]
}

export async function getWorkTimeline(workItemId: string): Promise<WorkEvent[]> {
  const { data, error } = await supabase
    .from('work_events')
    .select('*')
    .eq('work_item_id', workItemId)
    .order('created_at', { ascending: true })
    .order('id', { ascending: true })

  if (error) throw error
  return (data ?? []) as WorkEvent[]
}

export async function getWorkComments(workItemId: string): Promise<WorkComment[]> {
  const { data, error } = await supabase
    .from('work_comments')
    .select('*')
    .eq('work_item_id', workItemId)
    .order('created_at', { ascending: true })

  if (error) throw error
  return (data ?? []) as WorkComment[]
}

export async function getWorkChecklist(workItemId: string): Promise<WorkChecklistItem[]> {
  const { data, error } = await supabase
    .from('work_checklist_items')
    .select('*')
    .eq('work_item_id', workItemId)
    .order('sort_order', { ascending: true })
    .order('created_at', { ascending: true })

  if (error) throw error
  return (data ?? []) as WorkChecklistItem[]
}
