import { AI_OPERATIONS_DATA_MODE } from '@/lib/config/features'
import { supabase } from '@/lib/supabase/client'
import {
  aiOpsCaseDecisionReviewResponseSchema,
  aiOpsCaseDetailSchema,
  aiOpsCommitDecisionResultSchema,
  aiOpsConsoleSnapshotSchema,
  aiOpsReviewDecisionResultSchema,
} from './contracts'
import { AI_OPERATIONS_PREVIEW_DATA } from './preview-data'
import { AI_OPERATIONS_PREVIEW_CASE_DETAILS } from './preview-case-details'
import type {
  AiOpsCaseDecisionReviewResponse,
  AiOpsCaseDetail,
  AiOpsCommitDecisionResult,
  AiOpsConsoleSnapshot,
  AiOpsDataMode,
  AiOpsHumanReviewState,
  AiOpsReviewDecisionResult,
} from './types'

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

function parseDecisionReviewPayload(payload: unknown): AiOpsCaseDecisionReviewResponse {
  const parsed = aiOpsCaseDecisionReviewResponseSchema.safeParse(payload)
  if (!parsed.success) throw new AiOperationsContractError('بيانات مراجعة قرار AI Operations لا تطابق العقد المعتمد.')
  return parsed.data as AiOpsCaseDecisionReviewResponse
}

function parseReviewResult(payload: unknown): AiOpsReviewDecisionResult {
  const parsed = aiOpsReviewDecisionResultSchema.safeParse(payload)
  if (!parsed.success) throw new AiOperationsContractError('نتيجة مراجعة قرار AI Operations غير صالحة.')
  return parsed.data as AiOpsReviewDecisionResult
}

function parseCommitResult(payload: unknown): AiOpsCommitDecisionResult {
  const parsed = aiOpsCommitDecisionResultSchema.safeParse(payload)
  if (!parsed.success) throw new AiOperationsContractError('نتيجة إنشاء Work من قرار AI Operations غير صالحة.')
  return parsed.data as AiOpsCommitDecisionResult
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

function assertRpcMutationMode(mode: AiOpsDataMode) {
  if (mode !== 'rpc') {
    throw new AiOperationsUnavailableError('Preview للقراءة فقط؛ لا يمكن اعتماد أو تنفيذ قرارات AI Operations منه.')
  }
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
  const { data, error } = await supabase.rpc('ai_ops_get_case_detail', { p_case_id: caseId })

  if (error) {
    if (isMissingRpc(error)) throw new AiOperationsUnavailableError()
    throw error
  }

  return parseCaseDetailPayload(data)
}

async function loadDecisionReviewFromRpc(caseId: string): Promise<AiOpsCaseDecisionReviewResponse> {
  const { data, error } = await supabase.rpc('ai_ops_get_case_decision_review', { p_case_id: caseId })

  if (error) {
    if (isMissingRpc(error)) throw new AiOperationsUnavailableError()
    throw error
  }

  return parseDecisionReviewPayload(data)
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

export async function getAiOperationsDecisionReview(
  caseId: string,
  options: AiOperationsServiceOptions = {},
): Promise<AiOpsCaseDecisionReviewResponse> {
  const mode = options.mode ?? AI_OPERATIONS_DATA_MODE
  if (!caseId.trim()) throw new Error('Case ID مطلوب لتحميل مراجعة القرار.')

  if (mode === 'preview') {
    return parseDecisionReviewPayload({ case_id: caseId, decision: null })
  }

  return loadDecisionReviewFromRpc(caseId)
}

export async function reviewAiOperationsDecision(
  decisionId: string,
  reviewState: AiOpsHumanReviewState,
  reviewNote?: string | null,
  options: AiOperationsServiceOptions = {},
): Promise<AiOpsReviewDecisionResult> {
  const mode = options.mode ?? AI_OPERATIONS_DATA_MODE
  assertRpcMutationMode(mode)
  if (!decisionId.trim()) throw new Error('Decision ID مطلوب للمراجعة.')

  const { data, error } = await supabase.rpc('ai_ops_review_decision', {
    p_decision_id: decisionId,
    p_review_state: reviewState,
    p_review_note: reviewNote?.trim() || null,
  })

  if (error) {
    if (isMissingRpc(error)) throw new AiOperationsUnavailableError()
    throw error
  }

  return parseReviewResult(data)
}

export async function commitAiOperationsDecision(
  decisionId: string,
  options: AiOperationsServiceOptions = {},
): Promise<AiOpsCommitDecisionResult> {
  const mode = options.mode ?? AI_OPERATIONS_DATA_MODE
  assertRpcMutationMode(mode)
  if (!decisionId.trim()) throw new Error('Decision ID مطلوب لإنشاء Work.')

  const { data, error } = await supabase.rpc('ai_ops_commit_reviewed_decision', {
    p_decision_id: decisionId,
  })

  if (error) {
    if (isMissingRpc(error)) throw new AiOperationsUnavailableError()
    throw error
  }

  return parseCommitResult(data)
}

export type AiOperationsCaseDispositionAction = 'snooze' | 'dismiss'

export interface AiOperationsCaseDispositionResult {
  updated: boolean
  idempotent_reuse?: boolean
  case_id: string
  case_status?: string
  suppressed_until?: string | null
  feedback_recorded?: boolean
}

export async function setAiOperationsCaseDisposition(
  caseId: string,
  action: AiOperationsCaseDispositionAction,
  until: string | null,
  note?: string | null,
  options: AiOperationsServiceOptions = {},
): Promise<AiOperationsCaseDispositionResult> {
  const mode = options.mode ?? AI_OPERATIONS_DATA_MODE
  assertRpcMutationMode(mode)
  if (!caseId.trim()) throw new Error('Case ID مطلوب لتحديث الحالة.')

  const { data, error } = await supabase.rpc('ai_ops_set_case_disposition', {
    p_case_id: caseId,
    p_action: action,
    p_until: until,
    p_note: note?.trim() || null,
  })

  if (error) {
    if (isMissingRpc(error)) throw new AiOperationsUnavailableError()
    throw error
  }

  if (!data || typeof data !== 'object' || Array.isArray(data) || (data as { case_id?: unknown }).case_id !== caseId) {
    throw new AiOperationsContractError('نتيجة تحديث حالة AI Operations غير صالحة.')
  }

  return data as AiOperationsCaseDispositionResult
}
