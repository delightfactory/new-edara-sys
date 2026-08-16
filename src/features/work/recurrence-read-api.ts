import { supabase } from '@/lib/supabase/client'
import type { WorkRecurrenceRow } from './management-types'

/**
 * Management recurrence definitions are intentionally read through a
 * permission-gated RPC. Direct PostgREST reads on the backing table remain
 * closed so RLS/table grants are not widened just to power the admin screen.
 */
export async function listRecurrenceDefinitionsSecure(): Promise<WorkRecurrenceRow[]> {
  const { data, error } = await supabase.rpc('work_list_recurrence_definitions_admin')
  if (error) throw error
  return (data ?? []) as WorkRecurrenceRow[]
}
