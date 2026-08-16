import { AI_OPERATIONS_DATA_MODE } from '@/lib/config/features'
import { supabase } from '@/lib/supabase/client'
import { AI_OPERATIONS_PREVIEW_DATA } from './preview-data'
import { AI_OPERATIONS_PREVIEW_CASE_DETAILS } from './preview-case-details'
import type { AiOpsCaseDetail, AiOpsConsoleSnapshot, AiOpsDataMode } from './types'

export class AiOperationsUnavailableError extends Error {
  readonly code = 'AI_OPERATIONS_NOT_READY'

  constructor(message = 'طبقة AI Operations غير مفعلة بعد على قاعدة البيانات.') {
    super(message)
    this.name = 'AiOperationsUnavailableError'
  }
}

export interface AiOperationsServiceOptions {
  mode?: AiOpsDataMode
}

function clonePreview(): AiOpsConsoleSnapshot {
  return structuredClone(AI_OPERATIONS_PREVIEW_DATA)
}

function clonePreviewCaseDetail(caseId: string): AiOpsCaseDetail {
  const detail = AI_OPERATIONS_PREVIEW_CASE_DETAILS[caseId]
  if (!detail) throw new Error('لا توجد تفاصيل Preview لهذه الحالة.')
  return structuredClone(detail)
}

function isMissingRpc(error: { code?: string; message?: string | null }) {
  return error.code === 'PGRST202' || /Could not find the function/i.test(error.message ?? '')
}

async function loadConsoleFromRpc(): Promise<AiOpsConsoleSnapshot> {
  // This RPC intentionally does not exist in production yet. It will be added only
  // after the reviewed ai_ops migrations are explicitly approved and applied.
  const { data, error } = await supabase.rpc('ai_ops_get_console_snapshot')

  if (error) {
    if (isMissingRpc(error)) throw new AiOperationsUnavailableError()
    throw error
  }

  if (!data || typeof data !== 'object') {
    throw new AiOperationsUnavailableError('لم تُرجع طبقة AI Operations Snapshot صالحة.')
  }

  return data as unknown as AiOpsConsoleSnapshot
}

async function loadCaseDetailFromRpc(caseId: string): Promise<AiOpsCaseDetail> {
  // Future bounded drill-down. It remains unavailable until the reviewed gateway
  // migration is explicitly approved; preview mode never calls it.
  const { data, error } = await supabase.rpc('ai_ops_get_case_detail', { p_case_id: caseId })

  if (error) {
    if (isMissingRpc(error)) throw new AiOperationsUnavailableError()
    throw error
  }

  if (!data || typeof data !== 'object') {
    throw new AiOperationsUnavailableError('لم تُرجع طبقة AI Operations تفاصيل حالة صالحة.')
  }

  return data as unknown as AiOpsCaseDetail
}

export async function getAiOperationsConsole(
  options: AiOperationsServiceOptions = {},
): Promise<AiOpsConsoleSnapshot> {
  const mode = options.mode ?? AI_OPERATIONS_DATA_MODE

  if (mode === 'preview') return clonePreview()
  return loadConsoleFromRpc()
}

export async function getAiOperationsCaseDetail(
  caseId: string,
  options: AiOperationsServiceOptions = {},
): Promise<AiOpsCaseDetail> {
  const mode = options.mode ?? AI_OPERATIONS_DATA_MODE
  if (!caseId.trim()) throw new Error('Case ID مطلوب لفتح التفاصيل.')

  if (mode === 'preview') return clonePreviewCaseDetail(caseId)
  return loadCaseDetailFromRpc(caseId)
}
