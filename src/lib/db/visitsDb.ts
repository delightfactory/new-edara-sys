import Dexie, { type Table } from 'dexie'
import type {
  StartVisitItemAtomicInput,
  CompleteVisitItemAtomicInput,
  SkipVisitItemAtomicInput,
  VisitCompletionChecklistResponseInput,
  GpsValidationStatus,
  VisitStoragePath
} from '@/lib/types/activities'

export type LocalChecklistDraftResponse =
  | { template_id: string; question_id: string; answer_value: string; answer_json: null }
  | { template_id: string; question_id: string; answer_value: null; answer_json: string[] }
  | { template_id: string; question_id: string; answer_value: null; answer_json: { local_blob_id: string } }
  | { template_id: string; question_id: string; answer_value: null; answer_json: { storage_path: VisitStoragePath } }

export interface ChecklistDraft {
  responses: LocalChecklistDraftResponse[]
  isComplete: boolean
}

export interface LocalVisitSession {
  userId: string
  planId: string
  itemId: string
  serverStartedAt: string | null
  clientStartedAt: string
  startGPS: { lat: number; lng: number } | null
  startGPSAccuracy: number | null
  gpsValidationStatus: GpsValidationStatus
  checklistDrafts: Record<string, ChecklistDraft> // keyed by templateId
  gpsExceptionReason: string | null
  updatedAt: number
  expiresAt: number
}

export interface BasePendingOperation {
  operationId: string
  userId: string
  planId: string
  itemId: string
  state: 'pending' | 'sending' | 'retryable' | 'failed' | 'conflict'
  attemptCount: number
  lastErrorCode: string | null
  lastErrorMessage?: string | null
  createdAt: number
  updatedAt: number
  expiresAt: number
  dependsOnOperationId?: string
}

export type PendingVisitOperation =
  | (BasePendingOperation & { kind: 'start'; payload: StartVisitItemAtomicInput })
  | (BasePendingOperation & { kind: 'complete'; payload: CompleteVisitItemAtomicInput })
  | (BasePendingOperation & { kind: 'skip'; payload: SkipVisitItemAtomicInput })

export interface OperationPayloadMap {
  start: StartVisitItemAtomicInput
  complete: CompleteVisitItemAtomicInput
  skip: SkipVisitItemAtomicInput
}

export interface LocalBlobRecord {
  localBlobId: string      // UUID
  userId: string
  planId: string
  itemId: string
  templateId: string
  questionId: string
  objectPath: string       // Target storage path
  mimeType: string
  extension: string
  sizeBytes: number
  checksum: string         // SHA-256 hash
  uploadState: 'pending' | 'uploading' | 'retryable' | 'uploaded' | 'failed'
  attemptCount: number
  lastErrorCode: string | null
  nextRetryAt: number | null
  blob: Blob
  createdAt: number
  updatedAt: number
  expiresAt: number
}

export class VisitsDb extends Dexie {
  visitSessions!: Table<LocalVisitSession, [string, string]>
  pendingVisitOperations!: Table<PendingVisitOperation, string>
  localBlobs!: Table<LocalBlobRecord, string>

  constructor() {
    super('edara_visits_db')
    // Version 1 schema (previous schema)
    this.version(1).stores({
      visitSessions: '[userId+planId], userId, expiresAt',
      pendingVisitOperations: 'operationId, userId, expiresAt, [userId+planId+itemId+kind]'
    })
    // Version 2 schema with unique constraint prefix &
    this.version(2).stores({
      visitSessions: '[userId+planId], userId, expiresAt',
      pendingVisitOperations: 'operationId, userId, expiresAt, &[userId+planId+itemId+kind]'
    })
    // Version 3 schema: adds localBlobs table
    this.version(3).stores({
      visitSessions: '[userId+planId], userId, expiresAt',
      pendingVisitOperations: 'operationId, userId, expiresAt, &[userId+planId+itemId+kind]',
      localBlobs: 'localBlobId, [userId+planId+itemId], [userId+planId+itemId+questionId], userId, uploadState, expiresAt'
    })
  }
}

export const visitsDb = new VisitsDb()

/**
 * Runtime Type Guard to validate schema and fields of PendingVisitOperation from Dexie.
 */
export function validatePendingOperation(op: unknown): op is PendingVisitOperation {
  if (!op || typeof op !== 'object' || Array.isArray(op)) return false
  const o = op as Record<string, unknown>

  if (typeof o.operationId !== 'string' || !o.operationId) return false
  if (typeof o.userId !== 'string' || !o.userId) return false
  if (typeof o.planId !== 'string' || !o.planId) return false
  if (typeof o.itemId !== 'string' || !o.itemId) return false
  if (typeof o.createdAt !== 'number') return false
  if (typeof o.updatedAt !== 'number') return false
  if (typeof o.expiresAt !== 'number') return false
  if (typeof o.attemptCount !== 'number') return false
  if ('lastErrorMessage' in o && o.lastErrorMessage !== undefined && o.lastErrorMessage !== null && typeof o.lastErrorMessage !== 'string') return false

  if ('dependsOnOperationId' in o && o.dependsOnOperationId !== undefined && o.dependsOnOperationId !== null && o.dependsOnOperationId !== '') {
    if (typeof o.dependsOnOperationId !== 'string') return false
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    if (!uuidRegex.test(o.dependsOnOperationId)) return false
    if (o.dependsOnOperationId === o.operationId) return false
    if (o.kind !== 'complete') return false
  }

  const validStates = ['pending', 'sending', 'retryable', 'failed', 'conflict']
  if (typeof o.state !== 'string' || !validStates.includes(o.state)) return false

  if (!o.payload || typeof o.payload !== 'object' || Array.isArray(o.payload)) return false
  const p = o.payload as Record<string, unknown>
  if (p.operationId !== o.operationId || p.itemId !== o.itemId) return false

  if (o.kind === 'start') {
    if (typeof p.clientStartedAt !== 'string' || !p.clientStartedAt) return false
    if (typeof p.deviceTimezone !== 'string' || !p.deviceTimezone) return false
    return true
  }

  if (o.kind === 'complete') {
    if (typeof p.clientCompletedAt !== 'string' || !p.clientCompletedAt) return false
    if (typeof p.deviceTimezone !== 'string' || !p.deviceTimezone) return false
    if (typeof p.outcomeType !== 'string' || !p.outcomeType) return false
    if (!Array.isArray(p.responses)) return false
    return true
  }

  if (o.kind === 'skip') {
    if (typeof p.skipReason !== 'string' || !p.skipReason) return false
    if (typeof p.clientEventAt !== 'string' || !p.clientEventAt) return false
    if (typeof p.deviceTimezone !== 'string' || !p.deviceTimezone) return false
    return true
  }


  return false
}

export class CorruptedPayloadError extends Error {
  constructor(message?: string) {
    super(message || 'CORRUPTED_PAYLOAD')
    this.name = 'CorruptedPayloadError'
  }
}

export class InvalidOperationDependencyError extends Error {
  constructor(message?: string) {
    super(message || 'INVALID_OPERATION_DEPENDENCY')
    this.name = 'InvalidOperationDependencyError'
  }
}

function assertAndNarrowOperation<K extends keyof OperationPayloadMap>(
  op: PendingVisitOperation,
  kind: K
): PendingVisitOperation & { kind: K; payload: OperationPayloadMap[K] } {
  if (op.kind !== kind) {
    throw new Error(`نوع العملية غير متطابق: المتوقع ${kind} ولكن وجد ${op.kind}`)
  }
  return op as PendingVisitOperation & { kind: K; payload: OperationPayloadMap[K] }
}

// Function Overloads for getOrCreatePendingOperation
export async function getOrCreatePendingOperation(
  userId: string,
  planId: string,
  itemId: string,
  kind: 'start',
  buildPayload: (operationId: string) => StartVisitItemAtomicInput
): Promise<{ operation: PendingVisitOperation & { kind: 'start'; payload: StartVisitItemAtomicInput }; isNew: boolean }>

export async function getOrCreatePendingOperation(
  userId: string,
  planId: string,
  itemId: string,
  kind: 'complete',
  buildPayload: (operationId: string) => CompleteVisitItemAtomicInput,
  dependsOnOperationId?: string
): Promise<{ operation: PendingVisitOperation & { kind: 'complete'; payload: CompleteVisitItemAtomicInput }; isNew: boolean }>

export async function getOrCreatePendingOperation(
  userId: string,
  planId: string,
  itemId: string,
  kind: 'skip',
  buildPayload: (operationId: string) => SkipVisitItemAtomicInput
): Promise<{ operation: PendingVisitOperation & { kind: 'skip'; payload: SkipVisitItemAtomicInput }; isNew: boolean }>

export async function getOrCreatePendingOperation<K extends keyof OperationPayloadMap>(
  userId: string,
  planId: string,
  itemId: string,
  kind: K,
  buildPayload: (operationId: string) => OperationPayloadMap[K],
  dependsOnOperationId?: string
): Promise<{ operation: PendingVisitOperation & { kind: K; payload: OperationPayloadMap[K] }; isNew: boolean }> {
  // Validate dependsOnOperationId parameter
  if (dependsOnOperationId !== undefined && dependsOnOperationId !== null) {
    if (kind !== 'complete') {
      throw new InvalidOperationDependencyError('DEPENDENCY_ONLY_ALLOWED_FOR_COMPLETE')
    }
    if (typeof dependsOnOperationId !== 'string' || dependsOnOperationId === '') {
      throw new InvalidOperationDependencyError('DEPENDENCY_MUST_BE_NON_EMPTY_STRING')
    }
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    if (!uuidRegex.test(dependsOnOperationId)) {
      throw new InvalidOperationDependencyError('DEPENDENCY_MUST_BE_VALID_UUID')
    }
  }

  // 1. Search for existing operation
  const existing = await visitsDb.pendingVisitOperations
    .where('[userId+planId+itemId+kind]')
    .equals([userId, planId, itemId, kind])
    .first()

  if (existing) {
    const opId = existing.operationId
    if (!validatePendingOperation(existing)) {
      await visitsDb.pendingVisitOperations.update(opId, {
        state: 'conflict',
        lastErrorCode: 'CORRUPTED_PAYLOAD',
        updatedAt: Date.now(),
        expiresAt: Date.now() + 7 * 24 * 3600 * 1000
      })
      throw new CorruptedPayloadError()
    }
    return {
      operation: assertAndNarrowOperation(existing, kind),
      isNew: false
    }
  }

  // 2. Generate operationId first, then call buildPayload once
  const operationId = globalThis.crypto.randomUUID()
  if (dependsOnOperationId && dependsOnOperationId === operationId) {
    throw new InvalidOperationDependencyError('SELF_DEPENDENCY_PROHIBITED')
  }

  const payloadData = buildPayload(operationId)

  if (payloadData.operationId !== operationId) {
    throw new Error('مُعرِّف العملية في الحمولة لا يتطابق مع المُعرِّف المولد')
  }

  const now = Date.now()
  const base: BasePendingOperation = {
    operationId,
    userId,
    planId,
    itemId,
    state: 'pending',
    attemptCount: 0,
    lastErrorCode: null,
    lastErrorMessage: null,
    createdAt: now,
    updatedAt: now,
    expiresAt: now + 48 * 3600 * 1000 // 48 hours TTL
  }
  if (kind === 'complete' && dependsOnOperationId && dependsOnOperationId !== operationId) {
    base.dependsOnOperationId = dependsOnOperationId
  }

  let operation: PendingVisitOperation
  if (kind === 'start') {
    operation = { ...base, kind: 'start', payload: payloadData as StartVisitItemAtomicInput }
  } else if (kind === 'complete') {
    operation = { ...base, kind: 'complete', payload: payloadData as CompleteVisitItemAtomicInput }
  } else if (kind === 'skip') {
    operation = { ...base, kind: 'skip', payload: payloadData as SkipVisitItemAtomicInput }
  } else {
    throw new Error(`Unsupported operation kind: ${kind}`)
  }

  if (!validatePendingOperation(operation)) {
    throw new CorruptedPayloadError('INVALID_OPERATION_PAYLOAD')
  }

  try {
    await visitsDb.pendingVisitOperations.add(operation)
    return { operation: assertAndNarrowOperation(operation, kind), isNew: true }
  } catch (err: unknown) {
    if (err instanceof Error && err.name === 'ConstraintError') {
      // Handle concurrent tab registration ConstraintError by returning the existing operation
      const concurrentExisting = await visitsDb.pendingVisitOperations
        .where('[userId+planId+itemId+kind]')
        .equals([userId, planId, itemId, kind])
        .first()

      if (concurrentExisting) {
        const opId = concurrentExisting.operationId
        if (!validatePendingOperation(concurrentExisting)) {
          await visitsDb.pendingVisitOperations.update(opId, {
            state: 'conflict',
            lastErrorCode: 'CORRUPTED_PAYLOAD',
            updatedAt: Date.now(),
            expiresAt: Date.now() + 7 * 24 * 3600 * 1000
          })
          throw new CorruptedPayloadError()
        }
        return {
          operation: assertAndNarrowOperation(concurrentExisting, kind),
          isNew: false
        }
      }
    }
    throw err
  }
}

export async function replaceLocalBlobTransaction(params: {
  userId: string
  planId: string
  itemId: string
  templateId: string
  questionId: string
  newBlob: Blob
  newMimeType: string
  newExtension: string
  newChecksum: string
}): Promise<string> {
  const {
    userId,
    planId,
    itemId,
    templateId,
    questionId,
    newBlob,
    newMimeType,
    newExtension,
    newChecksum
  } = params

  // 1. Validations
  if (newBlob.size <= 0 || newBlob.size > 2 * 1024 * 1024) {
    throw new Error('حجم الصورة غير صالح (يجب أن يكون بين 1 بايت و 2 ميجابايت)')
  }

  if (newBlob.type !== newMimeType) {
    throw new Error('نوع MIME الممرر لا يتطابق مع نوع ملف Blob الفعلي')
  }

  if (newMimeType === 'image/jpeg') {
    if (newExtension !== 'jpg') {
      throw new Error('امتداد الملف غير متطابق مع نوع MIME الممرر (image/jpeg)')
    }
  } else if (newMimeType === 'image/png') {
    if (newExtension !== 'png') {
      throw new Error('امتداد الملف غير متطابق مع نوع MIME الممرر (image/png)')
    }
  } else {
    throw new Error('نوع MIME غير صالح. مسموح فقط بـ image/jpeg و image/png')
  }

  if (!/^[0-9a-fA-F]{64}$/.test(newChecksum)) {
    throw new Error('بصمة SHA-256 للتحقق من سلامة الملف غير صالحة')
  }

  const newBlobId = globalThis.crypto.randomUUID()
  const now = Date.now()
  const objectPath = `plans/${planId}/items/${itemId}/${newBlobId}.${newExtension}`

  await visitsDb.transaction('rw', [visitsDb.localBlobs, visitsDb.visitSessions, visitsDb.pendingVisitOperations], async () => {
    // 2. Read current session draft
    const session = await visitsDb.visitSessions.get([userId, planId])
    if (!session) {
      throw new Error('تعذر العثور على الجلسة الحالية')
    }

    if (session.itemId !== itemId) {
      throw new Error('معرّف البند في الجلسة لا يتطابق مع المعرّف الممرر')
    }

    // 3. Identify old localBlobId from current draft responses first
    let oldBlobId: string | null = null
    const draft = session.checklistDrafts?.[templateId]
    if (draft && draft.responses) {
      const resp = draft.responses.find(r => r.question_id === questionId)
      if (resp && resp.answer_json && typeof resp.answer_json === 'object') {
        const json = resp.answer_json as Record<string, unknown>
        if (typeof json.local_blob_id === 'string') {
          oldBlobId = json.local_blob_id
        }
      }
    }

    // 4. Validate context on old blob
    let oldBlobSize = 0
    if (oldBlobId) {
      const oldBlob = await visitsDb.localBlobs.get(oldBlobId)
      if (oldBlob) {
        if (
          oldBlob.userId !== userId ||
          oldBlob.planId !== planId ||
          oldBlob.itemId !== itemId ||
          oldBlob.templateId !== templateId ||
          oldBlob.questionId !== questionId
        ) {
          throw new Error('البيانات المخزنة محلياً غير متطابقة أو تالفة')
        }
        oldBlobSize = oldBlob.sizeBytes
      }
    }

    // 5. Check if the oldBlobId is referenced elsewhere in other sessions or active operations
    let isOldBlobReferenced = false
    if (oldBlobId) {
      // Check other questions/templates/sessions for this oldBlobId
      const allSessions = await visitsDb.visitSessions.toArray()
      let referenceCount = 0
      for (const s of allSessions) {
        if (s.checklistDrafts) {
          for (const [tId, d] of Object.entries(s.checklistDrafts)) {
            if (d.responses) {
              for (const r of d.responses) {
                // If it is the current question we are editing in this session, skip checking it
                if (r.question_id === questionId && s.planId === planId && s.userId === userId && templateId === tId) {
                  continue
                }
                if (r.answer_json && typeof r.answer_json === 'object') {
                  const json = r.answer_json as Record<string, unknown>
                  if (json.local_blob_id === oldBlobId) {
                    referenceCount++
                  }
                }
              }
            }
          }
        }
      }

      // Check active operations (pending, sending, retryable, conflict)
      const activeOps = await visitsDb.pendingVisitOperations
        .where('userId')
        .equals(userId)
        .filter(op => ['pending', 'sending', 'retryable', 'conflict'].includes(op.state))
        .toArray()

      for (const op of activeOps) {
        const referencedIds = getLocalBlobIdsFromPayload(op.payload)
        if (referencedIds.includes(oldBlobId)) {
          referenceCount++
        }
      }

      if (referenceCount > 0) {
        isOldBlobReferenced = true
      }
    }

    // 6. Calculate expected quota consumption
    const allUserBlobs = await visitsDb.localBlobs.where('userId').equals(userId).toArray()
    const currentTotalSize = allUserBlobs.reduce((acc, curr) => acc + curr.sizeBytes, 0)

    const quotaDeducedOldSize = isOldBlobReferenced ? 0 : oldBlobSize
    const projectedSize = currentTotalSize - quotaDeducedOldSize + newBlob.size

    const quotaLimit = 50 * 1024 * 1024 // 50MB
    if (projectedSize > quotaLimit) {
      throw new Error('QUOTA_EXCEEDED')
    }

    // 7. Store the new local blob
    const newBlobRecord: LocalBlobRecord = {
      localBlobId: newBlobId,
      userId,
      planId,
      itemId,
      templateId,
      questionId,
      objectPath,
      mimeType: newMimeType,
      extension: newExtension,
      sizeBytes: newBlob.size,
      checksum: newChecksum,
      uploadState: 'pending',
      attemptCount: 0,
      lastErrorCode: null,
      nextRetryAt: null,
      blob: newBlob,
      createdAt: now,
      updatedAt: now,
      expiresAt: now + 7 * 24 * 60 * 60 * 1000 // 7 days TTL
    }
    await visitsDb.localBlobs.put(newBlobRecord)

    // 8. Update session draft
    const updatedDrafts = { ...(session.checklistDrafts || {}) }
    const currentDraft = updatedDrafts[templateId] || { responses: [], isComplete: false }
    const filteredResponses = (currentDraft.responses || []).filter(r => r.question_id !== questionId)

    const newResponse: LocalChecklistDraftResponse = {
      template_id: templateId,
      question_id: questionId,
      answer_value: null,
      answer_json: { local_blob_id: newBlobId }
    }
    filteredResponses.push(newResponse)

    updatedDrafts[templateId] = {
      ...currentDraft,
      responses: filteredResponses
    }

    const updatedSession = {
      ...session,
      checklistDrafts: updatedDrafts,
      updatedAt: now
    }
    await visitsDb.visitSessions.put(updatedSession)

    // 9. Delete the old blob record only if it is no longer referenced anywhere
    if (oldBlobId && !isOldBlobReferenced) {
      await visitsDb.localBlobs.delete(oldBlobId)
    }
  })

  return newBlobId
}

export function getLocalBlobIdsFromPayload(payload: unknown): string[] {
  const ids = new Set<string>()
  if (!payload || typeof payload !== 'object') return []
  const responses = (payload as Record<string, unknown>).responses
  if (!Array.isArray(responses)) return []
  for (const r of responses) {
    if (r && typeof r === 'object') {
      const answerJson = (r as Record<string, unknown>).answer_json
      if (answerJson && typeof answerJson === 'object') {
        const localBlobId = (answerJson as Record<string, unknown>).local_blob_id
        if (typeof localBlobId === 'string' && localBlobId) {
          ids.add(localBlobId)
        }
      }
    }
  }
  return Array.from(ids)
}

// TTL & isolation cleanup
export async function cleanUpDatabase(currentUserId: string) {
  const now = Date.now()
  // 1. Delete other users' data
  await visitsDb.visitSessions.where('userId').notEqual(currentUserId).delete()
  await visitsDb.pendingVisitOperations.where('userId').notEqual(currentUserId).delete()
  await visitsDb.localBlobs.where('userId').notEqual(currentUserId).delete()

  // 2. Collect referenced blob IDs in active sessions and pending/sending/retryable/conflict operations
  const referencedBlobIds = new Set<string>()

  const activeSessions = await visitsDb.visitSessions
    .where('userId')
    .equals(currentUserId)
    .and(session => session.expiresAt >= now)
    .toArray()

  for (const session of activeSessions) {
    if (session.checklistDrafts) {
      for (const draft of Object.values(session.checklistDrafts)) {
        if (draft.responses) {
          for (const resp of draft.responses) {
            if (resp.answer_json && typeof resp.answer_json === 'object') {
              const json = resp.answer_json as Record<string, unknown>
              if (typeof json.local_blob_id === 'string') {
                referencedBlobIds.add(json.local_blob_id)
              }
            }
          }
        }
      }
    }
  }

  const activeOps = await visitsDb.pendingVisitOperations
    .where('userId')
    .equals(currentUserId)
    .filter(op => ['pending', 'sending', 'retryable', 'conflict'].includes(op.state))
    .toArray()

  for (const op of activeOps) {
    const blobIds = getLocalBlobIdsFromPayload(op.payload)
    for (const id of blobIds) {
      referencedBlobIds.add(id)
    }
  }

  // 3. Delete expired sessions
  await visitsDb.visitSessions.where('expiresAt').below(now).delete()

  // 4. Delete expired pending operations
  await visitsDb.pendingVisitOperations.where('expiresAt').below(now).delete()

  // 5. Delete expired local blobs that are not referenced
  const expiredBlobs = await visitsDb.localBlobs
    .where('expiresAt')
    .below(now)
    .and(blob => !referencedBlobIds.has(blob.localBlobId))
    .toArray()

  const idsToDelete = expiredBlobs.map(b => b.localBlobId)
  if (idsToDelete.length > 0) {
    await visitsDb.localBlobs.bulkDelete(idsToDelete)
  }
}
