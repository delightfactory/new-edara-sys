import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import Dexie from 'dexie'
import { visitsDb } from '@/lib/db/visitsDb'
import { triggerPhotoSync, retrySingleUpload, resumeUploads } from './photoSyncService'

// Mock Supabase client
const mockUpload = vi.fn()
const mockDownload = vi.fn()

vi.mock('@/lib/supabase/client', () => ({
  supabase: {
    storage: {
      from: () => ({
        upload: mockUpload,
        download: mockDownload
      })
    }
  }
}))

describe('photoSyncService Sync Loop', () => {
  const userId = 'u1'
  const planId = 'p1'
  const itemId = 'i1'
  const templateId = 't1'
  const questionId = 'q1'
  const blobId = 'b1-uuid'
  const objectPath = `plans/${planId}/items/${itemId}/${blobId}.jpg`

  beforeEach(async () => {
    if (typeof window !== 'undefined') {
      const nodeCrypto = require('crypto')
      Object.defineProperty(window, 'crypto', {
        value: nodeCrypto.webcrypto,
        writable: true,
        configurable: true
      })
      globalThis.crypto = nodeCrypto.webcrypto as any
    }
    if (typeof Blob !== 'undefined' && !Blob.prototype.arrayBuffer) {
      Blob.prototype.arrayBuffer = function(this: Blob) {
        return new Promise<ArrayBuffer>((resolve, reject) => {
          const reader = new FileReader()
          reader.onload = () => resolve(reader.result as ArrayBuffer)
          reader.onerror = reject
          reader.readAsArrayBuffer(this)
        })
      }
    }
    vi.clearAllMocks()
    await Dexie.delete('edara_visits_db')
    await visitsDb.open()
    await visitsDb.visitSessions.clear()
    await visitsDb.localBlobs.clear()
  })

  afterEach(async () => {
    await visitsDb.close()
  })

  it('successfully uploads pending blob and updates session draft references', async () => {
    // 1. Setup draft session pointing to local_blob_id
    await visitsDb.visitSessions.add({
      userId,
      planId,
      itemId,
      serverStartedAt: null,
      clientStartedAt: new Date().toISOString(),
      startGPS: null,
      startGPSAccuracy: null,
      gpsValidationStatus: 'passed',
      checklistDrafts: {
        [templateId]: {
          isComplete: false,
          responses: [
            {
              template_id: templateId,
              question_id: questionId,
              answer_value: null,
              answer_json: { local_blob_id: blobId }
            }
          ]
        }
      },
      gpsExceptionReason: null,
      updatedAt: Date.now(),
      expiresAt: Date.now() + 24 * 3600 * 1000
    })

    // 2. Setup pending local blob record
    await visitsDb.localBlobs.add({
      localBlobId: blobId,
      userId,
      planId,
      itemId,
      templateId,
      questionId,
      objectPath,
      mimeType: 'image/jpeg',
      extension: 'jpg',
      sizeBytes: 123,
      checksum: 'hash-abc',
      uploadState: 'pending',
      attemptCount: 0,
      lastErrorCode: null,
      nextRetryAt: null,
      blob: new Blob(['hello']),
      createdAt: Date.now(),
      updatedAt: Date.now(),
      expiresAt: Date.now() + 24 * 3600 * 1000
    })

    mockUpload.mockResolvedValueOnce({ error: null })

    // 3. Trigger sync
    await triggerPhotoSync(userId)

    // 4. Verify upload was called
    expect(mockUpload).toHaveBeenCalledWith(objectPath, expect.anything(), {
      contentType: 'image/jpeg',
      cacheControl: '3600',
      upsert: false
    })

    // 5. Verify local blob record status is uploaded
    const record = await visitsDb.localBlobs.get(blobId)
    expect(record?.uploadState).toBe('uploaded')

    // 6. Verify session draft converted local_blob_id to storage_path
    const session = await visitsDb.visitSessions.get([userId, planId])
    const responses = session?.checklistDrafts[templateId]?.responses
    expect(responses?.[0].answer_json).toEqual({ storage_path: objectPath })
  })

  it('recovers from Duplicate error by downloading and validating existing storage file', async () => {
    await visitsDb.visitSessions.add({
      userId,
      planId,
      itemId,
      serverStartedAt: null,
      clientStartedAt: new Date().toISOString(),
      startGPS: null,
      startGPSAccuracy: null,
      gpsValidationStatus: 'passed',
      checklistDrafts: {
        [templateId]: {
          isComplete: false,
          responses: [
            {
              template_id: templateId,
              question_id: questionId,
              answer_value: null,
              answer_json: { local_blob_id: blobId }
            }
          ]
        }
      },
      gpsExceptionReason: null,
      updatedAt: Date.now(),
      expiresAt: Date.now() + 24 * 3600 * 1000
    })

    await visitsDb.localBlobs.add({
      localBlobId: blobId,
      userId,
      planId,
      itemId,
      templateId,
      questionId,
      objectPath,
      mimeType: 'image/jpeg',
      extension: 'jpg',
      sizeBytes: 5,
      checksum: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
      uploadState: 'pending',
      attemptCount: 0,
      lastErrorCode: null,
      nextRetryAt: null,
      blob: new Blob(['hello']),
      createdAt: Date.now(),
      updatedAt: Date.now(),
      expiresAt: Date.now() + 24 * 3600 * 1000
    })

    // Upload returns a 409 conflict duplicate error
    mockUpload.mockResolvedValueOnce({
      error: { message: 'Asset already exists', statusCode: '409' }
    })
    // Download successfully fetches file metadata to confirm existence
    mockDownload.mockResolvedValueOnce({ data: new Blob(['hello']), error: null })

    await triggerPhotoSync(userId)

    expect(mockUpload).toHaveBeenCalled()
    expect(mockDownload).toHaveBeenCalledWith(objectPath)

    const record = await visitsDb.localBlobs.get(blobId)
    expect(record?.uploadState).toBe('uploaded')

    const session = await visitsDb.visitSessions.get([userId, planId])
    expect(session?.checklistDrafts[templateId]?.responses[0].answer_json).toEqual({ storage_path: objectPath })
  })

  it('marks retryable and sets backoff timer upon network failure', async () => {
    await visitsDb.localBlobs.add({
      localBlobId: blobId,
      userId,
      planId,
      itemId,
      templateId,
      questionId,
      objectPath,
      mimeType: 'image/jpeg',
      extension: 'jpg',
      sizeBytes: 123,
      checksum: 'hash-abc',
      uploadState: 'pending',
      attemptCount: 0,
      lastErrorCode: null,
      nextRetryAt: null,
      blob: new Blob(['hello']),
      createdAt: Date.now(),
      updatedAt: Date.now(),
      expiresAt: Date.now() + 24 * 3600 * 1000
    })

    mockUpload.mockRejectedValueOnce(new Error('Failed to fetch (network error)'))

    await triggerPhotoSync(userId)

    const record = await visitsDb.localBlobs.get(blobId)
    expect(record?.uploadState).toBe('retryable')
    expect(record?.attemptCount).toBe(1)
    expect(record?.lastErrorCode).toBe('PHOTO_NETWORK_ERROR')
    expect(record?.nextRetryAt).toBeGreaterThan(Date.now())
  })

  it('marks failed on permanent permission denied error', async () => {
    await visitsDb.localBlobs.add({
      localBlobId: blobId,
      userId,
      planId,
      itemId,
      templateId,
      questionId,
      objectPath,
      mimeType: 'image/jpeg',
      extension: 'jpg',
      sizeBytes: 123,
      checksum: 'hash-abc',
      uploadState: 'pending',
      attemptCount: 0,
      lastErrorCode: null,
      nextRetryAt: null,
      blob: new Blob(['hello']),
      createdAt: Date.now(),
      updatedAt: Date.now(),
      expiresAt: Date.now() + 24 * 3600 * 1000
    })

    mockUpload.mockResolvedValueOnce({
      error: { message: 'Permission Denied', statusCode: '403' }
    })

    await triggerPhotoSync(userId)

    const record = await visitsDb.localBlobs.get(blobId)
    expect(record?.uploadState).toBe('failed')
    expect(record?.attemptCount).toBe(1)
    expect(record?.lastErrorCode).toBe('PHOTO_UNAUTHORIZED')
    expect(record?.nextRetryAt).toBeNull()
  })

  it('resets failed/retryable blobs and uploads during manual retrySingleUpload', async () => {
    await visitsDb.localBlobs.add({
      localBlobId: blobId,
      userId,
      planId,
      itemId,
      templateId,
      questionId,
      objectPath,
      mimeType: 'image/jpeg',
      extension: 'jpg',
      sizeBytes: 123,
      checksum: 'hash-abc',
      uploadState: 'failed',
      attemptCount: 3,
      lastErrorCode: 'Permission Denied',
      nextRetryAt: null,
      blob: new Blob(['hello']),
      createdAt: Date.now(),
      updatedAt: Date.now(),
      expiresAt: Date.now() + 24 * 3600 * 1000
    })

    mockUpload.mockResolvedValueOnce({ error: null })

    await retrySingleUpload(userId, blobId)

    const record = await visitsDb.localBlobs.get(blobId)
    expect(record?.uploadState).toBe('uploaded')
    expect(record?.attemptCount).toBe(0)
    expect(record?.lastErrorCode).toBeNull()
  })
})
