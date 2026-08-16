import { supabase } from '@/lib/supabase/client'
import type { WorkAssignmentCandidate } from './runtime-types'

export async function listRequestAssignmentCandidates(
  workItemId: string,
  search = '',
  limit = 50,
): Promise<WorkAssignmentCandidate[]> {
  const { data, error } = await supabase.rpc('work_list_request_assignment_candidates', {
    p_work_item_id: workItemId,
    p_search: search.trim() || null,
    p_limit: Math.min(Math.max(limit, 1), 100),
  })
  if (error) throw error
  return (data ?? []) as WorkAssignmentCandidate[]
}
