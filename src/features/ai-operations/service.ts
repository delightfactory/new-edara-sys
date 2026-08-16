import { AI_OPERATIONS_DATA_MODE } from '@/lib/config/features'
import { supabase } from '@/lib/supabase/client'
import { aiOpsCaseDetailSchema, aiOpsConsoleSnapshotSchema } from './contracts'
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

export class AiOperationsContractError extends Error {
  readonly code = 'AI_OPERATIONS_INVALID_PAYLOAD'

  constructor(message = 'استجابة AI Operations لا تطابق عقد البيانات المعتمد.') {
    super(message)
    this.name = 'AiOperationsContractError'
  }
}

export interface AiOperationsServiceOptions {
  mode?: AiOpsDataMode
}

function parseConsolePayload(payload: unknown): AiOpsConsoleSnapshot {
  const parsed = aiOpsConsoleSnapshotSchema.safeParse(payload)
  if (!parsed.success) throw new AiOperationsContractError()
  return parsed.data as AiOpsConsoleSnapshot
}

function parseCaseDetailPayload(payload: unknown): AiOpsCaseDetail {
  const parsed = aiOpsCaseDetailSchema.safeParse(payload)
  if (!parsed.success) throw new AiOperationsContractError('تفاصيل حالة AI Operations لا تطابق عقد البيانات المعتمد.')
  return parsed.data as AiOpsCaseDetail
}

function clonePreview(): AiOpsConsoleSnapshot {
  return parseConsolePayload(structuredClone(AI_OPERATIONS_PREVIEW_DATA))
}

function clonePreviewCaseDetail(caseId: string): AiOpsCaseDetail {
  const detail = AI_OPERATIONS_PREVIEW_CASE_DETAILS[caseId]
  if (!detail) throw new Error('لا توجد تفاصيل Preview لهذه الحالة.')
  return parseCaseDetailPayload(structuredClone(detail))
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

  return parseConsolePayload(data)
}

async function loadCaseDetailFromRpc(caseId: string): Promise<AiOpsCaseDetail> {
  // Future bounded drill-down. It remains unavailable until the reviewed gateway
  // migration is explicitly approved; preview mode never calls it.
  const { data, error } = await supabase.rpc('ai_ops_get_case_detail', { p_case_id: caseId })

  if (error) {
    if (isMissingRpc(error)) throw new AiOperationsUnavailableError()
    throw error
  }

  return parseCaseDetailPayload(data)
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
