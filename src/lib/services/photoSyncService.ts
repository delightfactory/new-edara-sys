import { supabase } from '@/lib/supabase/client'
import { visitsDb, type LocalBlobRecord, type LocalChecklistDraftResponse } from '@/lib/db/visitsDb'
import type { VisitStoragePath } from '@/lib/types/activities'

type SyncListener = () => void
const listeners = new Set<SyncListener>()

export function subscribeToSyncChanges(listener: SyncListener): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

function notifyListeners() {
  listeners.forEach(l => l())
}

// In-memory set to lock concurrent uploads for the same blobId
const activeUploads = new Set<string>()

// Module-level network state and timer references
let cleanupCallback: (() => void) | null = null
let retryTimerId: ReturnType<typeof setInterval> | null = null

// Type Guard for Supabase StorageError
interface SupabaseStorageError {
  message: string
  statusCode?: string
  status?: number
  error?: string
}

function isSupabaseError(err: unknown): err is SupabaseStorageError {
  return (
    typeof err === 'object' &&
    err !== null &&
    'message' in err &&
    typeof (err as { message: unknown }).message === 'string'
  )
}

function isNetworkError(err: unknown): boolean {
  if (!err) return false
  const msg = String(err && typeof err === 'object' && 'message' in err ? (err as { message?: unknown }).message : '').toLowerCase()
  const status = err && typeof err === 'object' && 'status' in err ? (err as { status?: unknown }).status : -1
  if (
    msg.includes('network') ||
    msg.includes('failed to fetch') ||
    msg.includes('load failed') ||
    msg.includes('timeout') ||
    status === 0 ||
    status === 502 ||
    status === 503 ||
    status === 504
  ) {
    return true
  }
  return false
}

function classifyError(err: unknown): string {
  if (isNetworkError(err)) {
    return 'PHOTO_NETWORK_ERROR'
  }
  if (isSupabaseError(err)) {
    const code = err.statusCode || String(err.status || '')
    if (code === '403' || err.message.includes('Permission') || err.message.includes('unauthorized')) {
      return 'PHOTO_UNAUTHORIZED'
    }
    if (code === '413' || err.message.includes('Payload Too Large') || err.message.includes('size')) {
      return 'PHOTO_FILE_REJECTED'
    }
  }
  const msg = String(err && typeof err === 'object' && 'message' in err ? (err as { message?: unknown }).message : '').toLowerCase()
  if (msg.includes('permission') || msg.includes('unauthorized')) {
    return 'PHOTO_UNAUTHORIZED'
  }
  return 'PHOTO_UPLOAD_FAILED'
}

async function computeSha256(blob: Blob): Promise<string> {
  const buffer = await blob.arrayBuffer()
  const hashBuffer = await crypto.subtle.digest('SHA-256', buffer)
  const hashArray = Array.from(new Uint8Array(hashBuffer))
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('')
}

// Core upload function
async function uploadBlobRecord(record: LocalBlobRecord): Promise<void> {
  const { localBlobId, objectPath, blob, mimeType, userId, planId, itemId, templateId, questionId } = record

  if (activeUploads.has(localBlobId)) return
  activeUploads.add(localBlobId)

  // Transition to uploading state
  await visitsDb.localBlobs.update(localBlobId, {
    uploadState: 'uploading',
    updatedAt: Date.now()
  })
  notifyListeners()

  try {
    const { error } = await supabase.storage.from('visit-proofs').upload(objectPath, blob, {
      contentType: mimeType,
      cacheControl: '3600',
      upsert: false
    })

    let uploadSuccessful = !error

    if (error) {
      const errMsg = error.message || ''
      const errStorage = error as { error?: string; statusCode?: string; status?: number }
      const isDuplicate =
        errMsg.includes('Duplicate') ||
        errMsg.includes('already exists') ||
        errStorage.error === 'Duplicate' ||
        errStorage.statusCode === '409' ||
        errStorage.status === 409

      if (isDuplicate) {
        // Download the existing file and verify it matches the local one
        const { data: downloadData, error: downloadError } = await supabase.storage
          .from('visit-proofs')
          .download(objectPath)

        if (downloadData && !downloadError) {
          // Verify size
          if (downloadData.size !== record.sizeBytes) {
            throw new Error('PHOTO_REMOTE_MISMATCH')
          }
          // Verify checksum
          const downloadedChecksum = await computeSha256(downloadData)
          if (downloadedChecksum !== record.checksum) {
            throw new Error('PHOTO_REMOTE_MISMATCH')
          }
          uploadSuccessful = true
        } else {
          throw new Error('PHOTO_DUPLICATE_VERIFY_FAILED')
        }
      } else {
        throw error
      }
    }

    if (uploadSuccessful) {
      // Perform atomic database update inside a Dexie transaction
      await visitsDb.transaction('rw', [visitsDb.localBlobs, visitsDb.visitSessions], async () => {
        // 1. Verify session still matches context
        const session = await visitsDb.visitSessions.get([userId, planId])
        if (session && session.itemId === itemId) {
          const updatedDrafts = { ...(session.checklistDrafts || {}) }
          const currentDraft = updatedDrafts[templateId]

          if (currentDraft && currentDraft.responses) {
            let draftChanged = false
            const updatedResponses = currentDraft.responses.map(r => {
              if (r.question_id === questionId && r.answer_json && typeof r.answer_json === 'object') {
                const json = r.answer_json as Record<string, unknown>
                if (json.local_blob_id === localBlobId) {
                  draftChanged = true
                  return {
                    ...r,
                    answer_value: null,
                    answer_json: { storage_path: objectPath as VisitStoragePath }
                  } as LocalChecklistDraftResponse
                }
              }
              return r
            })

            if (draftChanged) {
              updatedDrafts[templateId] = {
                ...currentDraft,
                responses: updatedResponses
              }
              await visitsDb.visitSessions.put({
                ...session,
                checklistDrafts: updatedDrafts,
                updatedAt: Date.now()
              })
            }
          }
        }

        // 2. Mark local blob as uploaded
        await visitsDb.localBlobs.update(localBlobId, {
          uploadState: 'uploaded',
          lastErrorCode: null,
          updatedAt: Date.now()
        })
      })
    }
  } catch (err: unknown) {
    const errCode = (err instanceof Error && err.message === 'PHOTO_REMOTE_MISMATCH')
      ? 'PHOTO_REMOTE_MISMATCH'
      : (err instanceof Error && err.message === 'PHOTO_DUPLICATE_VERIFY_FAILED')
        ? 'PHOTO_DUPLICATE_VERIFY_FAILED'
        : classifyError(err)

    const isRetryable = errCode === 'PHOTO_NETWORK_ERROR'
    const newAttemptCount = record.attemptCount + 1

    if (isRetryable && newAttemptCount <= 5) {
      // Exponential backoff capped at 30 seconds
      const delay = Math.min(30000, 2000 * Math.pow(2, newAttemptCount))
      await visitsDb.localBlobs.update(localBlobId, {
        uploadState: 'retryable',
        attemptCount: newAttemptCount,
        lastErrorCode: errCode,
        nextRetryAt: Date.now() + delay,
        updatedAt: Date.now()
      })
    } else {
      await visitsDb.localBlobs.update(localBlobId, {
        uploadState: 'failed',
        attemptCount: newAttemptCount,
        lastErrorCode: errCode,
        nextRetryAt: null,
        updatedAt: Date.now()
      })
    }
  } finally {
    activeUploads.delete(localBlobId)
    notifyListeners()
  }
}

// Master sync loop
export async function triggerPhotoSync(userId: string): Promise<void> {
  setupNetworkListener(userId)
  setupRetryTimer(userId)

  try {
    // 1. Recover stuck 'uploading' states from previous app sessions
    const stuckBlobs = await visitsDb.localBlobs
      .where('userId')
      .equals(userId)
      .filter(b => b.uploadState === 'uploading' && !activeUploads.has(b.localBlobId))
      .toArray()

    for (const b of stuckBlobs) {
      await visitsDb.localBlobs.update(b.localBlobId, {
        uploadState: 'retryable',
        updatedAt: Date.now()
      })
    }

    // 2. Get pending records that are ready
    const records = await visitsDb.localBlobs
      .where('userId')
      .equals(userId)
      .filter(b => b.uploadState === 'pending' && !activeUploads.has(b.localBlobId))
      .toArray()

    // 3. Process uploads in sequence
    for (const record of records) {
      await uploadBlobRecord(record)
    }

    // 4. Process retryable records
    await processRetryableUploads(userId)
  } catch (err) {
    console.error('PHOTO_SYNC_LOOP_FAILED')
  }
}

async function processRetryableUploads(userId: string) {
  const now = Date.now()
  const records = await visitsDb.localBlobs
    .where('userId')
    .equals(userId)
    .filter(b => b.uploadState === 'retryable' && (!b.nextRetryAt || b.nextRetryAt <= now) && !activeUploads.has(b.localBlobId))
    .toArray()

  for (const record of records) {
    await uploadBlobRecord(record)
  }
}

// Reset failed retry timers and trigger upload for retryable items only
export async function resumeUploads(userId: string): Promise<void> {
  try {
    const retryable = await visitsDb.localBlobs
      .where('userId')
      .equals(userId)
      .filter(b => b.uploadState === 'retryable')
      .toArray()

    for (const b of retryable) {
      await visitsDb.localBlobs.update(b.localBlobId, {
        uploadState: 'pending',
        nextRetryAt: null,
        attemptCount: 0,
        updatedAt: Date.now()
      })
    }
    notifyListeners()
    await triggerPhotoSync(userId)
  } catch (err) {
    console.error('Failed to resume photo uploads')
  }
}

// Manual retry single failed/retryable blob
export async function retrySingleUpload(userId: string, localBlobId: string): Promise<void> {
  try {
    const record = await visitsDb.localBlobs.get(localBlobId)
    if (record && record.userId === userId) {
      await visitsDb.localBlobs.update(localBlobId, {
        uploadState: 'pending',
        nextRetryAt: null,
        attemptCount: 0,
        updatedAt: Date.now()
      })
      notifyListeners()
      await uploadBlobRecord({
        ...record,
        uploadState: 'pending',
        nextRetryAt: null,
        attemptCount: 0
      })
    }
  } catch (err) {
    console.error('Manual photo retry failed')
  }
}

function setupNetworkListener(userId: string) {
  if (cleanupCallback) return

  const handleOnline = () => {
    resumeUploads(userId).catch(() => {})
  }

  window.addEventListener('online', handleOnline)

  cleanupCallback = () => {
    window.removeEventListener('online', handleOnline)
  }
}

function setupRetryTimer(userId: string) {
  if (retryTimerId) return
  retryTimerId = setInterval(() => {
    processRetryableUploads(userId).catch(() => {})
  }, 10000) // Poll for retryable records every 10 seconds
}

export function cleanupPhotoSyncService(): void {
  if (cleanupCallback) {
    cleanupCallback()
    cleanupCallback = null
  }
  if (retryTimerId) {
    clearInterval(retryTimerId)
    retryTimerId = null
  }
}
