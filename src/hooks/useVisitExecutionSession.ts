import { useState, useEffect, useCallback, useRef } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { useAuthStore } from '@/stores/auth-store'
import {
  visitsDb,
  getOrCreatePendingOperation,
  cleanUpDatabase,
  validatePendingOperation,
  CorruptedPayloadError,
  replaceLocalBlobTransaction,
  type LocalVisitSession,
  type PendingVisitOperation,
  type BasePendingOperation,
  type LocalChecklistDraftResponse
} from '@/lib/db/visitsDb'
import {
  startVisitItemAtomic,
  completeVisitItemAtomic,
  skipVisitItemAtomic,
  VisitRpcTransportError,
  validateVisitStoragePath
} from '@/lib/services/activities'
import { triggerPhotoSync, cleanupPhotoSyncService, subscribeToSyncChanges } from '@/lib/services/photoSyncService'
import type {
  VisitPlanItem,
  StartVisitItemAtomicInput,
  CompleteVisitItemAtomicInput,
  SkipVisitItemAtomicInput,
  VisitCompletionChecklistResponseInput,
  ChecklistResponseInput,
  ChecklistQuestion,
  GpsValidationStatus,
  VisitOutcomeType,
  VisitStoragePath,
  VisitCompletionChecklistScalarResponseInput,
  VisitCompletionChecklistMultiChoiceResponseInput,
  VisitCompletionChecklistPhotoResponseInput
} from '@/lib/types/activities'

export type ExecutionOutcomeState = PendingVisitOperation['state'] | 'succeeded'

export interface ExecutionOutcome {
  ok: boolean
  state: ExecutionOutcomeState
  errorCode: string | null
  errorMessage?: string | null
}

export interface ChecklistResponseValidationInput {
  template_id: string
  question_id: string
  answer_value?: string | null
  answer_json?: unknown
}

export function mapLocalChecklistResponses(
  responses: ChecklistResponseValidationInput[],
  questions: ChecklistQuestion[],
  templateId?: string
): LocalChecklistDraftResponse[] {
  return responses.map(r => {
    const q = questions.find(question => question.id === r.question_id)
    if (!q) {
      throw new Error(`تعذر العثور على سؤال الاستبيان بالمعرّف: ${r.question_id}`)
    }

    if (templateId && r.template_id !== templateId) {
      throw new Error(`معرّف القالب في الإجابة (${r.template_id}) لا يتطابق مع معرّف القالب الجاري (${templateId})`)
    }

    if (q.template_id !== r.template_id) {
      throw new Error(`السؤال "${q.question_text}" لا ينتمي للقالب المحدد في الإجابة (${r.template_id})`)
    }

    const base = {
      template_id: r.template_id,
      question_id: r.question_id
    }

    switch (q.question_type) {
      case 'photo': {
        if (r.answer_json && typeof r.answer_json === 'object') {
          const json = r.answer_json as Record<string, unknown>
          if (typeof json.local_blob_id === 'string' && json.local_blob_id) {
            return {
              ...base,
              answer_value: null,
              answer_json: { local_blob_id: json.local_blob_id }
            } as LocalChecklistDraftResponse
          }
          if (typeof json.storage_path === 'string' && json.storage_path) {
            return {
              ...base,
              answer_value: null,
              answer_json: {
                storage_path: validateVisitStoragePath(json.storage_path)
              }
            }
          }
        }
        throw new Error(`إجابة الصورة للسؤال "${q.question_text}" مطلوبة محلياً`)
      }

      case 'multi_choice': {
        if (!Array.isArray(r.answer_json)) {
          throw new Error(`إجابة الاختيار المتعدد للسؤال "${q.question_text}" يجب أن تكون مصفوفة خيارات`)
        }
        return {
          ...base,
          answer_value: null,
          answer_json: r.answer_json as string[]
        } as LocalChecklistDraftResponse
      }

      default: {
        if (r.answer_value === null || r.answer_value === undefined) {
          throw new Error(`إجابة السؤال "${q.question_text}" مطلوبة ويجب أن تكون نصية`)
        }
        return {
          ...base,
          answer_value: String(r.answer_value),
          answer_json: null
        } as LocalChecklistDraftResponse
      }
    }
  })
}

export function mapChecklistResponses(
  responses: ChecklistResponseValidationInput[],
  questions: ChecklistQuestion[],
  templateId?: string
): VisitCompletionChecklistResponseInput[] {
  return responses.map(r => {
    const q = questions.find(question => question.id === r.question_id)
    if (!q) {
      throw new Error(`تعذر العثور على سؤال الاستبيان بالمعرّف: ${r.question_id}`)
    }

    if (templateId && r.template_id !== templateId) {
      throw new Error(`معرّف القالب في الإجابة (${r.template_id}) لا يتطابق مع معرّف القالب الجاري (${templateId})`)
    }

    if (q.template_id !== r.template_id) {
      throw new Error(`السؤال "${q.question_text}" لا ينتمي للقالب المحدد في الإجابة (${r.template_id})`)
    }

    const base = {
      template_id: r.template_id,
      question_id: r.question_id
    }

    switch (q.question_type) {
      case 'photo': {
        if (r.answer_json && typeof r.answer_json === 'object') {
          const json = r.answer_json as Record<string, unknown>
          if ('local_blob_id' in json) {
            throw new Error('لا يمكن تمرير معرف الصورة المحلي لقالب الـ RPC')
          }
        }
        // Data URL/Base64 can come in answer_value from ChecklistForm before upload,
        // or as { storage_path: ... } in answer_json after upload.
        if (r.answer_value !== null && r.answer_value !== undefined) {
          const val = r.answer_value
          if (typeof val !== 'string') {
            throw new Error(`إجابة الصورة للسؤال "${q.question_text}" غير صالحة`)
          }
          if (val.startsWith('data:') || val.includes(';base64,')) {
            throw new Error('لا يمكن حفظ أو إرسال صور ترميز Base64/Data URL مباشرة')
          }
          validateVisitStoragePath(val)
          return {
            ...base,
            answer_value: null,
            answer_json: { storage_path: val as VisitStoragePath }
          } as VisitCompletionChecklistPhotoResponseInput
        }

        if (r.answer_json !== null && r.answer_json !== undefined) {
          if (typeof r.answer_json !== 'object' || Array.isArray(r.answer_json)) {
            throw new Error(`إجابة الصورة للسؤال "${q.question_text}" غير صالحة`)
          }
          const keys = Object.keys(r.answer_json)
          if (keys.length !== 1 || keys[0] !== 'storage_path') {
            throw new Error(`إجابة الصورة للسؤال "${q.question_text}" يجب أن تحتوي على مسار التخزين فقط`)
          }
          const path = (r.answer_json as Record<string, unknown>).storage_path
          if (typeof path !== 'string') {
            throw new Error(`مسار تخزين الصورة للسؤال "${q.question_text}" يجب أن يكون نصًا`)
          }
          if (path.startsWith('data:') || path.includes(';base64,')) {
            throw new Error('لا يمكن حفظ أو إرسال صور ترميز Base64/Data URL مباشرة')
          }
          validateVisitStoragePath(path)
          return {
            ...base,
            answer_value: null,
            answer_json: { storage_path: path as VisitStoragePath }
          } as VisitCompletionChecklistPhotoResponseInput
        }

        throw new Error(`إجابة الصورة للسؤال "${q.question_text}" مطلوبة`)
      }

      case 'multi_choice': {
        if (!Array.isArray(r.answer_json)) {
          throw new Error(`إجابة الاختيار المتعدد للسؤال "${q.question_text}" يجب أن تكون مصفوفة خيارات`)
        }
        const arr = r.answer_json as unknown[]
        if (!arr.every(item => typeof item === 'string')) {
          throw new Error(`مصفوفة خيارات السؤال "${q.question_text}" يجب أن تحتوي على نصوص فقط`)
        }
        return {
          ...base,
          answer_value: null,
          answer_json: r.answer_json as string[]
        } as VisitCompletionChecklistMultiChoiceResponseInput
      }

      default: {
        if (r.answer_value === null || r.answer_value === undefined) {
          throw new Error(`إجابة السؤال "${q.question_text}" مطلوبة ويجب أن تكون نصية`)
        }
        if (typeof r.answer_value !== 'string') {
          throw new Error(`إجابة السؤال "${q.question_text}" غير صالحة`)
        }
        if (r.answer_value.startsWith('data:') || r.answer_value.includes(';base64,')) {
          throw new Error('لا يمكن حفظ أو إرسال صور ترميز Base64/Data URL مباشرة')
        }
        return {
          ...base,
          answer_value: r.answer_value,
          answer_json: null
        } as VisitCompletionChecklistScalarResponseInput
      }
    }
  })
}

function sortOperations(ops: PendingVisitOperation[]) {
  ops.sort((a, b) => {
    if (a.createdAt !== b.createdAt) {
      return a.createdAt - b.createdAt
    }
    if (a.itemId === b.itemId) {
      const kindPriority: Record<string, number> = { start: 1, complete: 2, skip: 3 }
      return (kindPriority[a.kind] || 99) - (kindPriority[b.kind] || 99)
    }
    return a.itemId.localeCompare(b.itemId)
  })
}

export function isVisitOperationSatisfiedByServer(
  operation: PendingVisitOperation,
  item: VisitPlanItem | undefined
): boolean {
  if (!item) return false

  if (operation.kind === 'start') {
    return item.status !== 'pending'
  }
  if (operation.kind === 'complete') {
    return item.status === 'completed'
  }
  return item.status === 'skipped'
}

async function reconcileOperationsWithServer(
  operations: PendingVisitOperation[],
  items: VisitPlanItem[]
): Promise<PendingVisitOperation[]> {
  const satisfiedIds = operations
    .filter(operation => isVisitOperationSatisfiedByServer(
      operation,
      items.find(item => item.id === operation.itemId)
    ))
    .map(operation => operation.operationId)

  if (satisfiedIds.length === 0) return operations

  await visitsDb.pendingVisitOperations.bulkDelete(satisfiedIds)
  const satisfiedIdSet = new Set(satisfiedIds)
  return operations.filter(operation => !satisfiedIdSet.has(operation.operationId))
}

export function useVisitExecutionSession(
  planId: string | undefined,
  serverItems: VisitPlanItem[],
  enabled: boolean,
  externalActionInProgressRef?: { readonly current: boolean }
) {
  const queryClient = useQueryClient()
  const profile = useAuthStore(s => s.profile)
  const userId = profile?.id || ''

  const [session, setSession] = useState<LocalVisitSession | null>(null)
  const [pendingOps, setPendingOps] = useState<PendingVisitOperation[]>([])
  const [loading, setLoading] = useState(enabled)
  const [error, setError] = useState<string | null>(null)

  const isExecutingRef = useRef(false)
  const isMountedRef = useRef(true)

  // Update ref directly in render body to guarantee it's always up to date
  const serverItemsRef = useRef(serverItems)
  serverItemsRef.current = serverItems

  useEffect(() => {
    isMountedRef.current = true
    return () => {
      isMountedRef.current = false
    }
  }, [])

  // Load session and operations from DB
  const reloadFromDb = useCallback(async (freshItems?: VisitPlanItem[]) => {
    if (!enabled) return
    if (!userId || !planId) return
    try {
      await cleanUpDatabase(userId)
      const localSession = await visitsDb.visitSessions.get([userId, planId])
      let ops = await visitsDb.pendingVisitOperations
        .where('userId')
        .equals(userId)
        .and(op => op.planId === planId)
        .toArray()

      // Validate all operations loaded from database before using them
      for (const op of ops) {
        if (!validatePendingOperation(op)) {
          const corrupted = op as unknown as BasePendingOperation
          corrupted.state = 'conflict'
          corrupted.lastErrorCode = 'CORRUPTED_PAYLOAD'
          corrupted.updatedAt = Date.now()
          await visitsDb.pendingVisitOperations.put(corrupted as PendingVisitOperation)
        }
      }

      const itemsToUse = freshItems || serverItemsRef.current
      ops = await reconcileOperationsWithServer(ops, itemsToUse)

      if (isMountedRef.current) {
        let sessionToSet: LocalVisitSession | null = null

        if (localSession) {
          const matchedItem = itemsToUse.find(i => i.id === localSession.itemId)
          const startOp = ops.find(o => o.itemId === localSession.itemId && o.kind === 'start')

          const hasPendingStart = startOp && (startOp.state === 'pending' || startOp.state === 'retryable' || startOp.state === 'sending')
          const hasTerminalStartFailure = startOp && (startOp.state === 'failed' || startOp.state === 'conflict')
          const serverConfirmsInProgress = matchedItem?.status === 'in_progress'

          if (hasPendingStart) {
            sessionToSet = localSession
          } else if (hasTerminalStartFailure) {
            sessionToSet = null
          } else {
            sessionToSet = serverConfirmsInProgress ? localSession : null
          }
        }
        setSession(sessionToSet)

        sortOperations(ops)
        setPendingOps(ops)
        setError(null)
      }
    } catch (err) {
      console.error('فشل تحميل الجلسة من قاعدة البيانات المحلية', err)
      if (isMountedRef.current) {
        const msg = err instanceof Error ? err.message : 'خطأ غير متوقع في قاعدة البيانات المحلية'
        setError(msg)
      }
    }
  }, [userId, planId, enabled])

  // Stable key to reactively sync serverItems list updates
  const serverItemsSyncKey = serverItems.map(i => `${i.id}-${i.status}-${i.updated_at}`).join(',')

  // Sync state between server items and local session on mount/updates
  useEffect(() => {
    if (!enabled) {
      setLoading(false)
      return
    }

    if (!userId || !planId) {
      setLoading(false)
      return
    }

    const syncWithServer = async () => {
      try {
        await cleanUpDatabase(userId)

        // Restore interrupted pending/sending operations to retryable state
        await visitsDb.pendingVisitOperations
          .where('userId')
          .equals(userId)
          .and(op => op.planId === planId && (op.state === 'pending' || op.state === 'sending'))
          .modify({ state: 'retryable', updatedAt: Date.now(), expiresAt: Date.now() + 48 * 3600 * 1000 })

        const localSession = await visitsDb.visitSessions.get([userId, planId])
        let ops = await visitsDb.pendingVisitOperations
          .where('userId')
          .equals(userId)
          .and(op => op.planId === planId)
          .toArray()

        // Validate on sync
        for (const op of ops) {
          if (!validatePendingOperation(op)) {
            const corrupted = op as unknown as BasePendingOperation
            corrupted.state = 'conflict'
            corrupted.lastErrorCode = 'CORRUPTED_PAYLOAD'
            corrupted.updatedAt = Date.now()
            await visitsDb.pendingVisitOperations.put(corrupted as PendingVisitOperation)
          }
        }

        const currentServerItems = serverItemsRef.current
        ops = await reconcileOperationsWithServer(ops, currentServerItems)

        if (localSession) {
          const matchedItem = currentServerItems.find(i => i.id === localSession.itemId)
          if (matchedItem) {
            // Delete local session if item status is final on server
            if (['completed', 'skipped', 'rescheduled', 'missed'].includes(matchedItem.status)) {
              await visitsDb.visitSessions.delete([userId, planId])
              await visitsDb.localBlobs
                .where('[userId+planId+itemId]')
                .equals([userId, planId, matchedItem.id])
                .delete()
              if (isMountedRef.current) setSession(null)
            } else {
              const startOp = ops.find(o => o.itemId === localSession.itemId && o.kind === 'start')
              const hasPendingStart = startOp && (startOp.state === 'pending' || startOp.state === 'retryable' || startOp.state === 'sending')
              const hasTerminalStartFailure = startOp && (startOp.state === 'failed' || startOp.state === 'conflict')
              const serverConfirmsInProgress = matchedItem.status === 'in_progress'

              // Server truth wins over a stale local terminal start operation.
              // This is the normal recovery path when the start RPC succeeded
              // but the phone refreshed before its local operation was cleaned.
              if (serverConfirmsInProgress) {
                if (isMountedRef.current) setSession(localSession)
              } else if (hasPendingStart) {
                if (isMountedRef.current) setSession(localSession)
              } else if (hasTerminalStartFailure) {
                if (isMountedRef.current) setSession(null)
              } else {
                if (isMountedRef.current) setSession(null)
              }
            }
          } else {
            await visitsDb.visitSessions.delete([userId, planId])
            if (isMountedRef.current) setSession(null)
          }
        } else {
          // Sync server-initiated sessions
          const inProgressServerItems = currentServerItems.filter(i => i.status === 'in_progress')
          if (inProgressServerItems.length === 1) {
            const item = inProgressServerItems[0]
            const now = Date.now()
            const restored: LocalVisitSession = {
              userId,
              planId,
              itemId: item.id,
              serverStartedAt: item.server_started_at || null,
              clientStartedAt: item.client_started_at || new Date().toISOString(),
              startGPS: (item.start_lat !== null && item.start_lng !== null) ? { lat: item.start_lat, lng: item.start_lng } : null,
              startGPSAccuracy: item.start_accuracy_m,
              gpsValidationStatus: (item.gps_validation_status as GpsValidationStatus) || 'not_checked',
              checklistDrafts: {},
              gpsExceptionReason: item.gps_exception_reason || null,
              updatedAt: now,
              expiresAt: now + 48 * 3600 * 1000
            }
            await visitsDb.visitSessions.put(restored)
            if (isMountedRef.current) setSession(restored)
            toast.success('تمت استعادة الزيارة الجارية')
          } else if (inProgressServerItems.length > 1) {
            if (isMountedRef.current) {
              setError('يوجد أكثر من بند قيد التنفيذ بالخادم. يرجى مراجعة الخطة والتحكم يدوياً')
            }
          }
        }

        const freshOps = await visitsDb.pendingVisitOperations
          .where('userId')
          .equals(userId)
          .and(op => op.planId === planId)
          .toArray()

        if (isMountedRef.current) {
          sortOperations(freshOps)
          setPendingOps(freshOps)
          setLoading(false)
        }
      } catch (err) {
        console.error('Error syncing local session with server', err)
        if (isMountedRef.current) {
          const msg = err instanceof Error ? err.message : 'حدث خطأ غير متوقع أثناء مزامنة البيانات المحلية'
          setError(msg)
          setLoading(false)
        }
      }
    }

    if (serverItemsRef.current.length > 0) {
      syncWithServer()
    } else {
      setLoading(false)
    }
  }, [userId, planId, enabled, serverItemsSyncKey])

  useEffect(() => {
    if (enabled && userId) {
      triggerPhotoSync(userId)
    }
    return () => {
      cleanupPhotoSyncService()
    }
  }, [enabled, userId])

  useEffect(() => {
    if (!enabled || !userId) return
    const unsubscribe = subscribeToSyncChanges(() => {
      reloadFromDb()
    })
    return () => {
      unsubscribe()
    }
  }, [enabled, userId, reloadFromDb])

  // Save checklist draft updates (Validates before saving to IndexedDB)
  const saveChecklistDraft = useCallback(async (
    templateId: string,
    responses: ChecklistResponseValidationInput[],
    templateQuestions: ChecklistQuestion[],
    isComplete: boolean
  ) => {
    if (!enabled) return
    const localSession = await visitsDb.visitSessions.get([userId, planId || ''])
    if (!localSession || !userId || !planId) return
    try {
      const validated = mapLocalChecklistResponses(responses, templateQuestions, templateId)

      const updatedDrafts = {
        ...localSession.checklistDrafts,
        [templateId]: { responses: validated, isComplete }
      }
      const updatedSession = {
        ...localSession,
        checklistDrafts: updatedDrafts,
        updatedAt: Date.now()
      }
      await visitsDb.visitSessions.put(updatedSession)

      const ops = await visitsDb.pendingVisitOperations
        .where('userId')
        .equals(userId)
        .and(op => op.planId === planId)
        .toArray()
      const startOp = ops.find(o => o.itemId === localSession.itemId && o.kind === 'start')
      const hasPendingStart = startOp && (startOp.state === 'pending' || startOp.state === 'retryable' || startOp.state === 'sending')
      const hasTerminalStartFailure = startOp && (startOp.state === 'failed' || startOp.state === 'conflict')
      const serverConfirmsInProgress = (serverItemsRef.current.find(i => i.id === localSession.itemId))?.status === 'in_progress'

      if (isMountedRef.current) {
        if (hasPendingStart) {
          setSession(updatedSession)
        } else if (hasTerminalStartFailure) {
          setSession(null)
        } else {
          setSession(serverConfirmsInProgress ? updatedSession : null)
        }
      }
    } catch (err) {
      if (err instanceof Error) {
        toast.error(err.message || 'فشل حفظ المسودة')
      }
    }
  }, [userId, planId, enabled])

  const gpsReasonWriteRef = useRef<Promise<void>>(Promise.resolve())

  // Keep typing synchronous in React and serialize IndexedDB writes so an
  // older keystroke can never overwrite a newer one on slower Android phones.
  const saveGpsExceptionReason = useCallback(async (reason: string | null) => {
    if (!enabled || !userId || !planId) return

    setSession(current => current
      ? { ...current, gpsExceptionReason: reason, updatedAt: Date.now() }
      : current
    )

    const persistReason = async () => {
      // Patch only the two changed fields so this write cannot overwrite a
      // checklist draft saved at the same time.
      await visitsDb.visitSessions.update([userId, planId], {
        gpsExceptionReason: reason,
        updatedAt: Date.now()
      })
    }

    const write = gpsReasonWriteRef.current
      .catch(() => undefined)
      .then(persistReason)
    gpsReasonWriteRef.current = write

    try {
      await write
    } catch (err) {
      console.error('Failed to save gps exception reason', err)
    }
  }, [userId, planId, enabled])

  // Result success helper defined inside Hook with strict dependencies
  const handleResultSuccess = useCallback(async (): Promise<ExecutionOutcome> => {
    await queryClient.invalidateQueries({ queryKey: ['visit-plan', planId] })
    await queryClient.invalidateQueries({ queryKey: ['visit-plan-items', planId] })
    await queryClient.invalidateQueries({ queryKey: ['activities'] })

    // Fetch fresh items immediately, updating the ref to prevent stale closures/flickers
    const freshItems = await queryClient.fetchQuery<VisitPlanItem[]>({ queryKey: ['visit-plan-items', planId] }) || []
    serverItemsRef.current = freshItems

    await reloadFromDb(freshItems)
    return { ok: true, state: 'succeeded', errorCode: null }
  }, [planId, queryClient, reloadFromDb])

  // Result failure helper defined inside Hook with strict dependencies
  const handleResultFailure = useCallback(async (
    operation: PendingVisitOperation,
    code: string,
    message: string | null = null
  ): Promise<ExecutionOutcome> => {
    operation.lastErrorCode = code
    operation.lastErrorMessage = message
    operation.attemptCount += 1
    operation.updatedAt = Date.now()

    if (code === 'RETRYABLE_ERROR') {
      operation.state = 'retryable'
      operation.expiresAt = Date.now() + 48 * 3600 * 1000
    } else if (code === 'SYNC_CONFLICT' || code === 'IDEMPOTENCY_KEY_CONFLICT') {
      operation.state = 'conflict'
      operation.expiresAt = Date.now() + 7 * 24 * 3600 * 1000
    } else {
      operation.state = 'failed'
      operation.expiresAt = Date.now() + 7 * 24 * 3600 * 1000
    }

    if (code === 'SYNC_CONFLICT' || code === 'IDEMPOTENCY_KEY_CONFLICT') {
      await queryClient.invalidateQueries({ queryKey: ['visit-plan-items', planId] })
      const freshItems = await queryClient.fetchQuery<VisitPlanItem[]>({
        queryKey: ['visit-plan-items', planId]
      }).catch(() => serverItemsRef.current)
      serverItemsRef.current = freshItems || serverItemsRef.current
    }

    await visitsDb.pendingVisitOperations.put(operation)
    await reloadFromDb(serverItemsRef.current)

    return { ok: false, state: operation.state, errorCode: code, errorMessage: message }
  }, [planId, queryClient, reloadFromDb])

  // Helper to execute an operation and apply the Result Policy
  const executeOperation = useCallback(async (
    operation: PendingVisitOperation
  ): Promise<ExecutionOutcome> => {
    if (!planId) return { ok: false, state: operation.state, errorCode: 'INVALID_PLAN_ID' }
    try {
      operation.state = 'sending'
      operation.updatedAt = Date.now()
      await visitsDb.pendingVisitOperations.put(operation)
      if (isMountedRef.current) {
        setPendingOps(prev => prev.map(o => o.operationId === operation.operationId ? operation : o))
      }

      if (operation.kind === 'start') {
        const result = await startVisitItemAtomic(operation.payload)
        if (!result || typeof result !== 'object' || !('ok' in result)) {
          return await handleResultFailure(operation, 'CLIENT_ERROR')
        }

        if (result.ok === true) {
          await visitsDb.pendingVisitOperations.delete(operation.operationId)
          const localSession = await visitsDb.visitSessions.get([userId, planId])
          if (localSession) {
            localSession.serverStartedAt = result.data.server_started_at || null
            localSession.gpsValidationStatus = result.data.gps_validation_status || 'not_checked'
            await visitsDb.visitSessions.put(localSession)
            if (isMountedRef.current) setSession(localSession)
          }
          return await handleResultSuccess()
        } else {
          return await handleResultFailure(operation, result.error?.code || 'UNKNOWN_ERROR', result.error?.message || null)
        }
      } else if (operation.kind === 'complete') {
        const result = await completeVisitItemAtomic(operation.payload)
        if (!result || typeof result !== 'object' || !('ok' in result)) {
          return await handleResultFailure(operation, 'CLIENT_ERROR')
        }

        if (result.ok === true) {
          await visitsDb.pendingVisitOperations.delete(operation.operationId)
          await visitsDb.visitSessions.delete([userId, planId])
          await visitsDb.localBlobs.where('[userId+planId+itemId]').equals([userId, planId, operation.itemId]).delete()
          if (isMountedRef.current) setSession(null)
          return await handleResultSuccess()
        } else {
          return await handleResultFailure(operation, result.error?.code || 'UNKNOWN_ERROR', result.error?.message || null)
        }
      } else {
        const result = await skipVisitItemAtomic(operation.payload)
        if (!result || typeof result !== 'object' || !('ok' in result)) {
          return await handleResultFailure(operation, 'CLIENT_ERROR')
        }

        if (result.ok === true) {
          await visitsDb.pendingVisitOperations.delete(operation.operationId)
          await visitsDb.visitSessions.delete([userId, planId])
          if (isMountedRef.current) setSession(null)
          return await handleResultSuccess()
        } else {
          return await handleResultFailure(operation, result.error?.code || 'UNKNOWN_ERROR', result.error?.message || null)
        }
      }
    } catch (err: unknown) {
      console.error('Error in atomic execution', err)
      operation.attemptCount += 1
      operation.updatedAt = Date.now()

      if (err instanceof VisitRpcTransportError || (err && typeof err === 'object' && 'name' in err && err.name === 'VisitRpcTransportError')) {
        operation.state = 'retryable'
        operation.lastErrorCode = 'CONNECTION_ERROR'
        operation.lastErrorMessage = 'تعذر الاتصال بالخادم. تم حفظ العملية وستتم إعادة المحاولة عند عودة الإنترنت.'
        operation.expiresAt = Date.now() + 48 * 3600 * 1000
      } else {
        operation.state = 'failed'
        operation.lastErrorCode = 'CLIENT_ERROR'
        operation.lastErrorMessage = 'حدث خطأ غير متوقع في الجهاز أثناء تجهيز العملية.'
        operation.expiresAt = Date.now() + 7 * 24 * 3600 * 1000
      }

      await visitsDb.pendingVisitOperations.put(operation)
      await reloadFromDb()
      return {
        ok: false,
        state: operation.state,
        errorCode: operation.lastErrorCode,
        errorMessage: operation.lastErrorMessage
      }
    }
  }, [userId, planId, handleResultSuccess, handleResultFailure, reloadFromDb])

  const syncPromiseRef = useRef<Promise<void> | null>(null)
  const syncRequestGenerationRef = useRef(0)

  const syncPendingOperations = useCallback((): Promise<void> => {
    syncRequestGenerationRef.current += 1
    if (syncPromiseRef.current) {
      return syncPromiseRef.current
    }

    const promise = (async () => {
      let handledGeneration = 0
      // Never retry the same operation twice in one user-triggered sync. The
      // generation loop is only for operations added after the first snapshot.
      const attemptedIds = new Set<string>()
      do {
        handledGeneration = syncRequestGenerationRef.current
      // 1. Stale Recovery
      try {
        await visitsDb.pendingVisitOperations
          .where('userId')
          .equals(userId)
          .and(op => op.planId === planId && op.state === 'sending')
          .modify({ state: 'retryable', updatedAt: Date.now() })
      } catch (err) {
        console.error('فشل معالجة العمليات المعلقة العالقة', err)
      }

      let passes = 0
      const maxPasses = 5
      let hasUpdates = true

      while (passes < maxPasses && hasUpdates) {
        passes++
        hasUpdates = false

        let ops = await visitsDb.pendingVisitOperations
          .where('userId')
          .equals(userId)
          .and(op => op.planId === planId)
          .toArray()

        sortOperations(ops)

        const runableOps = ops.filter(op => !attemptedIds.has(op.operationId) && (op.state === 'pending' || op.state === 'retryable'))
        if (runableOps.length === 0) break

        for (const op of runableOps) {
          const operationId = op.operationId
          // Runtime validation check on the operation itself
          if (!validatePendingOperation(op)) {
            // Use a partial update — do not touch the corrupt payload
            await visitsDb.pendingVisitOperations.update(operationId, {
              state: 'conflict',
              lastErrorCode: 'CORRUPTED_PAYLOAD',
              updatedAt: Date.now(),
              expiresAt: Date.now() + 7 * 24 * 3600 * 1000
            })
            hasUpdates = true
            continue
          }

          // Verify dependency
          if (op.dependsOnOperationId) {
            const parent = await visitsDb.pendingVisitOperations.get(op.dependsOnOperationId)
            if (parent) {
              // Validate dependency safety (userId, planId, itemId, kind)
              if (
                parent.userId !== op.userId ||
                parent.planId !== op.planId ||
                parent.itemId !== op.itemId ||
                parent.kind !== 'start' ||
                op.operationId === op.dependsOnOperationId
              ) {
                op.state = 'conflict'
                op.lastErrorCode = 'INVALID_DEPENDENCY'
                op.updatedAt = Date.now()
                await visitsDb.pendingVisitOperations.put(op)
                hasUpdates = true
                continue
              }

              // Parent pending, retryable, sending -> skip child in this pass
              if (parent.state === 'pending' || parent.state === 'retryable' || parent.state === 'sending') {
                continue
              }

              // Parent failed/conflict -> transition child to conflict DEPENDENCY_FAILED
              if (parent.state === 'conflict' || parent.state === 'failed') {
                op.state = 'conflict'
                op.lastErrorCode = 'DEPENDENCY_FAILED'
                op.updatedAt = Date.now()
                await visitsDb.pendingVisitOperations.put(op)
                hasUpdates = true
                continue
              }
            } else {
              // Parent not found in queue -> proceed
            }
          }

          // Execute operation
          attemptedIds.add(op.operationId)
          try {
            await executeOperation(op)
            hasUpdates = true
          } catch (err) {
            console.error('فشل إرسال العملية في المزامنة', err)
            hasUpdates = true
          }
        }
      }
      // If another action enqueued work while this single-flight sync was
      // running, drain the queue again before releasing the shared promise.
      } while (handledGeneration !== syncRequestGenerationRef.current)
    })()

    const finalPromise = promise.finally(() => {
      syncPromiseRef.current = null
    })
    syncPromiseRef.current = finalPromise
    return finalPromise
  }, [userId, planId, executeOperation])

  const resumePromiseRef = useRef<Promise<void> | null>(null)
  const resumeVisitFlow = useCallback((): Promise<void> => {
    if (!enabled || !userId || !planId || !navigator.onLine) return Promise.resolve()
    // Android may fire focus/visibilitychange while the GPS permission sheet is
    // closing. Reloading the visit session during that user action can race the
    // completion flow and make the execution screen visibly jump.
    if (isExecutingRef.current || externalActionInProgressRef?.current) return Promise.resolve()
    if (resumePromiseRef.current) return resumePromiseRef.current

    const promise = (async () => {
      await queryClient.invalidateQueries({ queryKey: ['visit-plan', planId] })
      await queryClient.invalidateQueries({ queryKey: ['visit-plan-items', planId] })
      const freshItems = await queryClient.fetchQuery<VisitPlanItem[]>({
        queryKey: ['visit-plan-items', planId]
      }) || []
      serverItemsRef.current = freshItems
      await reloadFromDb(freshItems)
      await syncPendingOperations()
    })().catch(err => {
      console.warn('[Visits] تعذر استئناف مزامنة الزيارة بعد العودة للتطبيق', err)
    })

    const finalPromise = promise.finally(() => {
      resumePromiseRef.current = null
    })
    resumePromiseRef.current = finalPromise
    return finalPromise
  }, [enabled, userId, planId, queryClient, reloadFromDb, syncPendingOperations, externalActionInProgressRef])

  useEffect(() => {
    if (!enabled || !userId || !planId) return

    const handleOnline = () => { void resumeVisitFlow() }
    const handleFocus = () => { void resumeVisitFlow() }
    const handleVisibility = () => {
      if (document.visibilityState === 'visible') void resumeVisitFlow()
    }

    window.addEventListener('online', handleOnline)
    window.addEventListener('focus', handleFocus)
    document.addEventListener('visibilitychange', handleVisibility)
    return () => {
      window.removeEventListener('online', handleOnline)
      window.removeEventListener('focus', handleFocus)
      document.removeEventListener('visibilitychange', handleVisibility)
    }
  }, [enabled, userId, planId, resumeVisitFlow])

  // Trigger start visit operation
  const startVisit = useCallback(async (
    itemId: string,
    coords: { lat: number, lng: number } | null,
    accuracy: number | null
  ): Promise<ExecutionOutcome> => {
    if (!planId || !userId) {
      return { ok: false, state: 'failed', errorCode: 'MISSING_PARAMS' }
    }
    if (isExecutingRef.current) {
      return { ok: false, state: 'sending', errorCode: 'LOCKED' }
    }
    isExecutingRef.current = true

    try {
      const existingSession = await visitsDb.visitSessions.get([userId, planId])
      if (existingSession) {
        if (existingSession.itemId !== itemId) {
          return {
            ok: false,
            state: 'conflict',
            errorCode: 'ACTIVE_VISIT_EXISTS',
            errorMessage: 'توجد زيارة أخرى جارية على هذا الجهاز. تمت حماية بياناتها من الاستبدال.'
          }
        }

        const existingStartOp = await visitsDb.pendingVisitOperations
          .where('[userId+planId+itemId+kind]')
          .equals([userId, planId, itemId, 'start'])
          .first()

        const serverItem = serverItemsRef.current.find(item => item.id === itemId)
        const hasTerminalStartFailure = existingStartOp &&
          (existingStartOp.state === 'conflict' || existingStartOp.state === 'failed')

        // A genuine failed Start must stay failed. Only server-confirmed
        // in_progress state may override and reconcile a stale local failure.
        if (hasTerminalStartFailure && serverItem?.status !== 'in_progress') {
          return {
            ok: false,
            state: existingStartOp.state,
            errorCode: existingStartOp.lastErrorCode,
            errorMessage: existingStartOp.lastErrorMessage
          }
        }

        if (hasTerminalStartFailure && serverItem?.status === 'in_progress') {
          await visitsDb.pendingVisitOperations.delete(existingStartOp.operationId)
        }

        // Never overwrite an existing session or its checklist drafts. A
        // second Start after refresh is treated as session recovery.
        if (isMountedRef.current) setSession(existingSession)
        if (existingStartOp && (existingStartOp.state === 'pending' || existingStartOp.state === 'retryable' || existingStartOp.state === 'sending')) {
          await syncPendingOperations()
          const updatedStartOp = await visitsDb.pendingVisitOperations.get(existingStartOp.operationId)
          if (updatedStartOp) {
            return {
              ok: false,
              state: updatedStartOp.state,
              errorCode: updatedStartOp.lastErrorCode,
              errorMessage: updatedStartOp.lastErrorMessage
            }
          }
        }
        return { ok: true, state: 'succeeded', errorCode: 'SESSION_RESTORED' }
      }

      const clientStartedAt = new Date().toISOString()
      const { operation, isNew } = await getOrCreatePendingOperation(userId, planId, itemId, 'start', (opId) => {
        return {
          operationId: opId,
          itemId,
          startLat: coords?.lat ?? null,
          startLng: coords?.lng ?? null,
          startAccuracyM: accuracy ?? null,
          clientStartedAt,
          deviceTimezone: Intl.DateTimeFormat().resolvedOptions().timeZone
        }
      })

      if (isNew) {
        const now = Date.now()
        const tempSession: LocalVisitSession = {
          userId,
          planId,
          itemId,
          serverStartedAt: null,
          clientStartedAt,
          startGPS: coords,
          startGPSAccuracy: accuracy,
          gpsValidationStatus: 'not_checked',
          checklistDrafts: {},
          gpsExceptionReason: null,
          updatedAt: now,
          expiresAt: now + 48 * 3600 * 1000
        }
        await visitsDb.visitSessions.put(tempSession)
      }

      if (!isNew && (operation.state === 'conflict' || operation.state === 'failed')) {
        return { ok: false, state: operation.state, errorCode: operation.lastErrorCode, errorMessage: operation.lastErrorMessage }
      }

      await syncPendingOperations()
      const updatedOp = await visitsDb.pendingVisitOperations.get(operation.operationId)
      if (!updatedOp) {
        return { ok: true, state: 'succeeded', errorCode: null }
      } else {
        return { ok: false, state: updatedOp.state, errorCode: updatedOp.lastErrorCode, errorMessage: updatedOp.lastErrorMessage }
      }
    } catch (err) {
      if (err instanceof CorruptedPayloadError) {
        return { ok: false, state: 'conflict', errorCode: 'CORRUPTED_PAYLOAD' }
      }
      toast.error('حدث خطأ غير متوقع أثناء تنفيذ العملية')
      return { ok: false, state: 'failed', errorCode: 'CLIENT_ERROR' }
    } finally {
      isExecutingRef.current = false
    }
  }, [planId, userId, syncPendingOperations])

  // Trigger complete visit operation
  const completeVisit = useCallback(async (
    itemId: string,
    coords: { lat: number, lng: number } | null,
    accuracy: number | null,
    outcomeType: VisitOutcomeType,
    outcomeNotes: string | null,
    responses: VisitCompletionChecklistResponseInput[],
    orderId: string | null,
    collectionId: string | null,
    gpsExceptionReason: string | null,
    ignoreUnuploadedOptionalPhotos = false
  ): Promise<ExecutionOutcome> => {
    if (!planId || !userId) {
      return { ok: false, state: 'failed', errorCode: 'MISSING_PARAMS' }
    }

    try {
      const session = await visitsDb.visitSessions.get([userId, planId])
      if (!session) {
        return { ok: false, state: 'failed', errorCode: 'MISSING_SESSION' }
      }

      // Optional proof must not stop the rep. The caller only enables this
      // when every unuploaded local photo belongs to an optional question.
      if (!ignoreUnuploadedOptionalPhotos) {
        // Collect all local_blob_ids referenced in draft responses.
        const referencedBlobIdsSet = new Set<string>()
        if (session.checklistDrafts) {
          for (const draft of Object.values(session.checklistDrafts)) {
            if (draft.responses) {
              for (const r of draft.responses) {
                if (r.answer_json && typeof r.answer_json === 'object') {
                  const json = r.answer_json as Record<string, unknown>
                  if (typeof json.local_blob_id === 'string' && json.local_blob_id) {
                    referencedBlobIdsSet.add(json.local_blob_id)
                  }
                }
              }
            }
          }
        }
        if (responses) {
          for (const r of responses) {
            if (r.answer_json && typeof r.answer_json === 'object') {
              const json = r.answer_json as unknown as Record<string, unknown>
              if (typeof json.local_blob_id === 'string' && json.local_blob_id) {
                referencedBlobIdsSet.add(json.local_blob_id)
              }
            }
          }
        }

        const referencedBlobIds = Array.from(referencedBlobIdsSet)

        // Verify each referenced blob is present in IndexedDB.
        for (const blobId of referencedBlobIds) {
          const record = await visitsDb.localBlobs.get(blobId)
          if (!record) {
            return { ok: false, state: 'failed', errorCode: 'LOCAL_PHOTO_MISSING' }
          }
        }

        // Required photo responses must reach storage before the server can validate them.
        if (referencedBlobIds.length > 0) {
          return { ok: false, state: 'failed', errorCode: 'LOCAL_PHOTOS_PENDING_UPLOAD' }
        }
      }
    } catch (dbErr) {
      console.error('Failed to verify local photos in completeVisit', dbErr)
      return { ok: false, state: 'failed', errorCode: 'DB_ERROR' }
    }

    if (isExecutingRef.current) {
      return { ok: false, state: 'sending', errorCode: 'LOCKED' }
    }
    isExecutingRef.current = true

    try {
      const clientCompletedAt = new Date().toISOString()

      // Look up any pending/retryable/sending start operation for this item in the queue
      const startOp = await visitsDb.pendingVisitOperations
        .where('[userId+planId+itemId+kind]')
        .equals([userId, planId, itemId, 'start'])
        .first()

      let dependsOnOperationId: string | undefined = undefined
      if (startOp && (startOp.state === 'pending' || startOp.state === 'retryable' || startOp.state === 'sending')) {
        dependsOnOperationId = startOp.operationId
      }

      const { operation, isNew } = await getOrCreatePendingOperation(userId, planId, itemId, 'complete', (opId) => {
        return {
          operationId: opId,
          itemId,
          endLat: coords?.lat ?? null,
          endLng: coords?.lng ?? null,
          endAccuracyM: accuracy ?? null,
          clientCompletedAt,
          deviceTimezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
          outcomeType,
          outcomeNotes,
          responses,
          orderId,
          collectionId,
          gpsExceptionReason
        }
      }, dependsOnOperationId)

      if (!isNew && (operation.state === 'conflict' || operation.state === 'failed')) {
        return { ok: false, state: operation.state, errorCode: operation.lastErrorCode, errorMessage: operation.lastErrorMessage }
      }

      await syncPendingOperations()
      const updatedOp = await visitsDb.pendingVisitOperations.get(operation.operationId)
      if (!updatedOp) {
        return { ok: true, state: 'succeeded', errorCode: null }
      } else {
        return { ok: false, state: updatedOp.state, errorCode: updatedOp.lastErrorCode, errorMessage: updatedOp.lastErrorMessage }
      }
    } catch (err) {
      if (err instanceof CorruptedPayloadError) {
        return { ok: false, state: 'conflict', errorCode: 'CORRUPTED_PAYLOAD' }
      }
      toast.error('حدث خطأ غير متوقع أثناء تنفيذ العملية')
      return { ok: false, state: 'failed', errorCode: 'CLIENT_ERROR' }
    } finally {
      isExecutingRef.current = false
    }
  }, [planId, userId, syncPendingOperations])

  // Trigger skip visit operation
  const skipVisit = useCallback(async (
    itemId: string,
    skipReason: string
  ): Promise<ExecutionOutcome> => {
    if (!planId || !userId) {
      return { ok: false, state: 'failed', errorCode: 'MISSING_PARAMS' }
    }
    if (isExecutingRef.current) {
      return { ok: false, state: 'sending', errorCode: 'LOCKED' }
    }
    isExecutingRef.current = true

    try {
      const clientEventAt = new Date().toISOString()
      const { operation, isNew } = await getOrCreatePendingOperation(userId, planId, itemId, 'skip', (opId) => {
        return {
          operationId: opId,
          itemId,
          skipReason,
          clientEventAt,
          deviceTimezone: Intl.DateTimeFormat().resolvedOptions().timeZone
        }
      })

      if (!isNew && (operation.state === 'conflict' || operation.state === 'failed')) {
        return { ok: false, state: operation.state, errorCode: operation.lastErrorCode, errorMessage: operation.lastErrorMessage }
      }

      await syncPendingOperations()
      const updatedOp = await visitsDb.pendingVisitOperations.get(operation.operationId)
      if (!updatedOp) {
        return { ok: true, state: 'succeeded', errorCode: null }
      } else {
        return { ok: false, state: updatedOp.state, errorCode: updatedOp.lastErrorCode, errorMessage: updatedOp.lastErrorMessage }
      }
    } catch (err) {
      if (err instanceof CorruptedPayloadError) {
        return { ok: false, state: 'conflict', errorCode: 'CORRUPTED_PAYLOAD' }
      }
      toast.error('حدث خطأ غير متوقع أثناء تنفيذ العملية')
      return { ok: false, state: 'failed', errorCode: 'CLIENT_ERROR' }
    } finally {
      isExecutingRef.current = false
    }
  }, [planId, userId, syncPendingOperations])

  // Retry a pending retryable operation manually
  const retryOperation = useCallback(async (operationId: string) => {
    const op = await visitsDb.pendingVisitOperations.get(operationId)
    if (!op || op.state !== 'retryable') return
    if (isExecutingRef.current) return
    isExecutingRef.current = true
    try {
      await syncPendingOperations()
    } finally {
      isExecutingRef.current = false
    }
  }, [syncPendingOperations])

  // Remove a failed operation to start a new one (only allowed for failed operations)
  const discardFailedOperation = useCallback(async (operationId: string) => {
    const op = await visitsDb.pendingVisitOperations.get(operationId)
    if (!op || op.state !== 'failed') return
    try {
      // 1. Invalidate and fetch latest items from server
      await queryClient.invalidateQueries({ queryKey: ['visit-plan-items', planId] })
      const freshItems = await queryClient.fetchQuery<VisitPlanItem[]>({ queryKey: ['visit-plan-items', planId] }) || []

      const item = freshItems.find(i => i.id === op.itemId)
      if (!item) {
        op.state = 'conflict'
        op.lastErrorCode = 'SYNC_CONFLICT'
        op.updatedAt = Date.now()
        op.expiresAt = Date.now() + 7 * 24 * 3600 * 1000
        await visitsDb.pendingVisitOperations.put(op)
        await reloadFromDb()
        return
      }

      // Validate status match
      let isMatch = false
      if (op.kind === 'start' && item.status === 'pending') isMatch = true
      else if (op.kind === 'complete' && item.status === 'in_progress') isMatch = true
      else if (op.kind === 'skip' && item.status === 'pending') isMatch = true

      if (isMatch) {
        // Safe to discard
        await visitsDb.pendingVisitOperations.delete(operationId)
        if (op.kind === 'start') {
          await visitsDb.visitSessions.delete([userId, planId || ''])
        }
      } else {
        // Diverged server status
        op.state = 'conflict'
        op.lastErrorCode = 'SYNC_CONFLICT'
        op.updatedAt = Date.now()
        op.expiresAt = Date.now() + 7 * 24 * 3600 * 1000
        await visitsDb.pendingVisitOperations.put(op)
      }
      await reloadFromDb(freshItems)
    } catch (err) {
      console.error('Failed to discard operation', err)
    }
  }, [reloadFromDb, planId, queryClient, userId])

  const loadLocalPhoto = useCallback(async (localBlobId: string): Promise<Blob | null> => {
    if (!userId) return null
    try {
      const record = await visitsDb.localBlobs.get(localBlobId)
      if (!record) return null
      if (record.userId !== userId) return null
      return record.blob
    } catch (err) {
      console.error('Failed to load local photo', err)
      return null
    }
  }, [userId])

  const saveLocalPhoto = useCallback(async (
    templateId: string,
    questionId: string,
    blob: Blob,
    meta: { mimeType: string; extension: string; checksum: string }
  ): Promise<{ local_blob_id: string }> => {
    if (!userId || !planId || !session?.itemId) {
      throw new Error('الجلسة غير نشطة')
    }
    const localBlobId = await replaceLocalBlobTransaction({
      userId,
      planId,
      itemId: session.itemId,
      templateId,
      questionId,
      newBlob: blob,
      newMimeType: meta.mimeType,
      newExtension: meta.extension,
      newChecksum: meta.checksum
    })
    await reloadFromDb()
    triggerPhotoSync(userId)
    return { local_blob_id: localBlobId }
  }, [userId, planId, session?.itemId, reloadFromDb])

  return {
    session,
    pendingOps,
    loading,
    error,
    startVisit,
    completeVisit,
    skipVisit,
    retryOperation,
    discardFailedOperation,
    saveChecklistDraft,
    saveGpsExceptionReason,
    reloadFromDb,
    syncPendingOperations,
    loadLocalPhoto,
    saveLocalPhoto
  }
}
