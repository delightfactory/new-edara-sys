import { supabase } from '@/lib/supabase/client'
import type { AtomicOperationResult } from './types'
import { WorkCommandError } from './runtime-api'

export interface WorkDueApprovalTemplate {
  id: string
  code: string
  name: string
  description: string | null
  current_published_version_id: string
}

export interface WorkDueExtensionResult {
  work_item_id: string
  status: string
  state_version: number
  approval_request_id: string
  requested_due_at: string
}

async function executeAtomic<T>(rpcName: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(rpcName, args)
  if (error) throw error
  const response = data as AtomicOperationResult<T>
  if (!response || response.ok !== true) {
    const failure = response && response.ok === false ? response.error : null
    throw new WorkCommandError(failure?.code ?? 'UNKNOWN_ERROR', failure?.message ?? 'تعذر تنفيذ طلب تمديد الموعد')
  }
  return response.data
}

export async function listDueApprovalTemplates(): Promise<WorkDueApprovalTemplate[]> {
  const { data, error } = await supabase
    .from('work_approval_templates')
    .select('id,code,name,description,current_published_version_id')
    .eq('is_active', true)
    .not('current_published_version_id', 'is', null)
    .order('name')
  if (error) throw error
  return (data ?? []) as WorkDueApprovalTemplate[]
}

export function requestWorkDueExtension(input: {
  workItemId: string
  expectedVersion: number
  newDueAt: string
  reason: string
  approvalTemplateId: string
}) {
  return executeAtomic<WorkDueExtensionResult>('work_request_due_change', {
    p_operation_id: crypto.randomUUID(),
    p_work_item_id: input.workItemId,
    p_expected_version: input.expectedVersion,
    p_new_due_at: input.newDueAt,
    p_reason: input.reason,
    p_approval_template_id: input.approvalTemplateId,
  })
}
