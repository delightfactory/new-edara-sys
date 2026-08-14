import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase/client'

export interface WorkSupervisorRow {
  work_item_id: string
  work_number: number
  title: string
  status: 'open' | 'in_progress' | 'waiting' | 'pending_approval'
  priority: string
  visibility: string
  accountable_owner_user_id: string | null
  owner_name: string | null
  current_assignee_user_id: string | null
  assignee_name: string | null
  branch_id: string | null
  owning_department_id: string | null
  due_at: string | null
  next_action_text: string | null
  next_action_at: string | null
  waiting_reason: string | null
  state_version: number
  is_blocked: boolean
  is_overdue: boolean
  is_stale: boolean
  is_at_risk: boolean
  is_escalated: boolean
  is_due_soon: boolean
  is_follow_up_due: boolean
}

export async function getSupervisorOverview(input: {
  assigneeUserId?: string | null
  attentionOnly?: boolean
  limit?: number
} = {}): Promise<WorkSupervisorRow[]> {
  const { data, error } = await supabase.rpc('work_get_supervisor_overview', {
    p_assignee_user_id: input.assigneeUserId ?? null,
    p_attention_only: input.attentionOnly ?? false,
    p_limit: Math.min(Math.max(input.limit ?? 300, 1), 500),
  })
  if (error) throw error
  return (data ?? []) as WorkSupervisorRow[]
}

export function useSupervisorOverview(input: {
  assigneeUserId?: string | null
  attentionOnly?: boolean
  limit?: number
} = {}) {
  return useQuery({
    queryKey: ['work', 'supervisor-overview', input.assigneeUserId ?? 'all', Boolean(input.attentionOnly), input.limit ?? 300],
    queryFn: () => getSupervisorOverview(input),
    staleTime: 60_000,
  })
}
