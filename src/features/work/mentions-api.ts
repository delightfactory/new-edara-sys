import { supabase } from '@/lib/supabase/client'

export interface WorkMentionCandidate {
  user_id: string
  full_name: string
}

export async function listWorkMentionCandidates(
  workItemId: string,
  search = '',
  limit = 20,
): Promise<WorkMentionCandidate[]> {
  const { data, error } = await supabase.rpc('work_list_mention_candidates', {
    p_work_item_id: workItemId,
    p_search: search.trim() || null,
    p_limit: Math.min(Math.max(limit, 1), 50),
  })
  if (error) throw error
  return (data ?? []) as WorkMentionCandidate[]
}
