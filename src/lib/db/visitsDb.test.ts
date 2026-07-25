import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import Dexie from 'dexie'
import {
  visitsDb,
  getOrCreatePendingOperation,
  cleanUpDatabase,
  validatePendingOperation,
  CorruptedPayloadError,
  replaceLocalBlobTransaction,
  getLocalBlobIdsFromPayload,
  type LocalVisitSession,
  type PendingVisitOperation
} from './visitsDb'
import type { StartVisitItemAtomicInput, SkipVisitItemAtomicInput } from '@/lib/types/activities'

describe('visitsDb IndexedDB Layer', () => {
  beforeEach(async () => {
    await Dexie.delete('edara_visits_db')
    await visitsDb.open()
    await visitsDb.visitSessions.clear()
    await visitsDb.pendingVisitOperations.clear()
    await visitsDb.localBlobs.clear()
  })

  afterEach(async () => {
    await visitsDb.close()
  })

  it('preserves sessions and operations data when migrating from v1 to v2 schema', async () => {
    const dbName = 'test_migrate_db'
    await Dexie.delete(dbName)

    const db1 = new Dexie(dbName)
    db1.version(1).stores({
      visitSessions: '[userId+planId], userId, expiresAt',
      pendingVisitOperations: 'operationId, userId, expiresAt, [userId+planId+itemId+kind]'
    })
    await db1.open()

    await db1.table('visitSessions').add({
      userId: 'u1',
      planId: 'p1',
      itemId: 'i1',
      expiresAt: Date.now() + 1000
    })

    await db1.table('pendingVisitOperations').add({
      operationId: 'op-1',
      userId: 'u1',
      planId: 'p1',
      itemId: 'i1',
      kind: 'start',
      payload: { operationId: 'op-1', itemId: 'i1' },
      state: 'pending',
      createdAt: Date.now(),
      updatedAt: Date.now(),
      expiresAt: Date.now() + 1000
    })
    await db1.close()

    const db2 = new Dexie(dbName)
    db2.version(1).stores({
      visitSessions: '[userId+planId], userId, expiresAt',
      pendingVisitOperations: 'operationId, userId, expiresAt, [userId+planId+itemId+kind]'
    })
    db2.version(2).stores({
      visitSessions: '[userId+planId], userId, expiresAt',
      pendingVisitOperations: 'operationId, userId, expiresAt, &[userId+planId+itemId+kind]'
    })
    await db2.open()

    const session = await db2.table('visitSessions').get(['u1', 'p1'])
    const op = await db2.table('pendingVisitOperations').get('op-1')

    expect(session).toBeDefined()
    expect(session?.itemId).toBe('i1')
    expect(op).toBeDefined()
    expect(op?.kind).toBe('start')

    await db2.close()
    await Dexie.delete(dbName)
  })

  it('generates operationId matching payload.operationId and stores correctly', async () => {
    const userId = 'user-1'
    const planId = 'plan-1'
    const itemId = 'item-1'

    const buildPayloadMock = vi.fn((opId: string) => ({
      operationId: opId,
      itemId,
      startLat: 30,
      startLng: 31,
      startAccuracyM: 10,
      clientStartedAt: '2026-07-06T19:00:00Z',
      deviceTimezone: 'Africa/Cairo'
    }))

    const { operation, isNew } = await getOrCreatePendingOperation(userId, planId, itemId, 'start', buildPayloadMock)

    expect(isNew).toBe(true)
    expect(operation.operationId).toBeDefined()
    expect(operation.payload.operationId).toBe(operation.operationId)
    expect(buildPayloadMock).toHaveBeenCalledTimes(1)

    const stored = await visitsDb.pendingVisitOperations.get(operation.operationId)
    expect(stored).toBeDefined()
    expect(stored?.userId).toBe(userId)
    expect(stored?.planId).toBe(planId)
    expect(stored?.kind).toBe('start')
  })

  it('returns existing operation without calling buildPayload again at all', async () => {
    const userId = 'user-1'
    const planId = 'plan-1'
    const itemId = 'item-1'

    const buildPayloadFirst = (opId: string) => ({
      operationId: opId,
      itemId,
      startLat: 30,
      startLng: 31,
      startAccuracyM: 10,
      clientStartedAt: '2026-07-06T19:00:00Z',
      deviceTimezone: 'Africa/Cairo'
    })

    const { operation: op1 } = await getOrCreatePendingOperation(userId, planId, itemId, 'start', buildPayloadFirst)

    const buildPayloadSecond = vi.fn((opId: string) => ({
      operationId: opId,
      itemId,
      startLat: 30,
      startLng: 31,
      startAccuracyM: 10,
      clientStartedAt: '2026-07-06T19:00:00Z',
      deviceTimezone: 'Africa/Cairo'
    }))

    const { operation: op2, isNew } = await getOrCreatePendingOperation(userId, planId, itemId, 'start', buildPayloadSecond)

    expect(isNew).toBe(false)
    expect(op2.operationId).toBe(op1.operationId)
    expect(buildPayloadSecond).toHaveBeenCalledTimes(0)
  })

  it('enforces compound uniqueness [userId+planId+itemId+kind]', async () => {
    const userId = 'user-1'
    const planId = 'plan-1'
    const itemId = 'item-1'

    const buildPayload = (opId: string) => ({
      operationId: opId,
      itemId,
      startLat: 30,
      startLng: 31,
      startAccuracyM: 10,
      clientStartedAt: '2026-07-06T19:00:00Z',
      deviceTimezone: 'Africa/Cairo'
    })

    await getOrCreatePendingOperation(userId, planId, itemId, 'start', buildPayload)

    const badOp: PendingVisitOperation = {
      operationId: 'op-diff-uuid',
      userId,
      planId,
      itemId,
      kind: 'start',
      payload: buildPayload('op-diff-uuid'),
      state: 'pending',
      attemptCount: 0,
      lastErrorCode: null,
      createdAt: Date.now(),
      updatedAt: Date.now(),
      expiresAt: Date.now() + 48 * 3600 * 1000
    }

    await expect(
      visitsDb.pendingVisitOperations.add(badOp)
    ).rejects.toThrow()
  })

  it('clears other users data on SWITCHing account', async () => {
    const user1Session: LocalVisitSession = {
      userId: 'user-1',
      planId: 'plan-1',
      itemId: 'item-1',
      serverStartedAt: null,
      clientStartedAt: '2026-07-06T19:00:00Z',
      startGPS: null,
      startGPSAccuracy: null,
      gpsValidationStatus: 'not_checked',
      checklistDrafts: {},
      gpsExceptionReason: null,
      updatedAt: Date.now(),
      expiresAt: Date.now() + 48 * 3600 * 1000
    }

    const user2Session: LocalVisitSession = {
      userId: 'user-2',
      planId: 'plan-1',
      itemId: 'item-1',
      serverStartedAt: null,
      clientStartedAt: '2026-07-06T19:00:00Z',
      startGPS: null,
      startGPSAccuracy: null,
      gpsValidationStatus: 'not_checked',
      checklistDrafts: {},
      gpsExceptionReason: null,
      updatedAt: Date.now(),
      expiresAt: Date.now() + 48 * 3600 * 1000
    }

    await visitsDb.visitSessions.add(user1Session)
    await visitsDb.visitSessions.add(user2Session)

    await cleanUpDatabase('user-2')

    const user1Local = await visitsDb.visitSessions.get(['user-1', 'plan-1'])
    const user2Local = await visitsDb.visitSessions.get(['user-2', 'plan-1'])

    expect(user1Local).toBeUndefined()
    expect(user2Local).toBeDefined()
  })

  it('implements TTL correctly: retryable/pending expires in 48 hours, failed/conflict in 7 days', async () => {
    const now = Date.now()

    const expiredRetryable: PendingVisitOperation = {
      operationId: 'op-exp-ret',
      userId: 'user-1',
      planId: 'plan-1',
      itemId: 'item-1',
      kind: 'start',
      payload: {
        operationId: 'op-exp-ret',
        itemId: 'item-1',
        startLat: 30,
        startLng: 31,
        startAccuracyM: 10,
        clientStartedAt: '',
        deviceTimezone: ''
      } as StartVisitItemAtomicInput,
      state: 'retryable',
      attemptCount: 1,
      lastErrorCode: 'RETRYABLE_ERROR',
      createdAt: now - 49 * 3600 * 1000,
      updatedAt: now - 49 * 3600 * 1000,
      expiresAt: now - 1 * 3600 * 1000
    }

    const expiredConflict: PendingVisitOperation = {
      operationId: 'op-exp-con',
      userId: 'user-1',
      planId: 'plan-1',
      itemId: 'item-1',
      kind: 'skip',
      payload: {
        operationId: 'op-exp-con',
        itemId: 'item-1',
        skipReason: 'Closed',
        clientEventAt: '',
        deviceTimezone: ''
      } as SkipVisitItemAtomicInput,
      state: 'conflict',
      attemptCount: 1,
      lastErrorCode: 'SYNC_CONFLICT',
      createdAt: now - 8 * 24 * 3600 * 1000,
      updatedAt: now - 8 * 24 * 3600 * 1000,
      expiresAt: now - 1 * 24 * 3600 * 1000
    }

    const validConflict: PendingVisitOperation = {
      operationId: 'op-val-con',
      userId: 'user-1',
      planId: 'plan-1',
      itemId: 'item-2',
      kind: 'skip',
      payload: {
        operationId: 'op-val-con',
        itemId: 'item-2',
        skipReason: 'Closed',
        clientEventAt: '',
        deviceTimezone: ''
      } as SkipVisitItemAtomicInput,
      state: 'conflict',
      attemptCount: 1,
      lastErrorCode: 'SYNC_CONFLICT',
      createdAt: now - 3 * 24 * 3600 * 1000,
      updatedAt: now - 3 * 24 * 3600 * 1000,
      expiresAt: now + 4 * 24 * 3600 * 1000
    }

    await visitsDb.pendingVisitOperations.add(expiredRetryable)
    await visitsDb.pendingVisitOperations.add(expiredConflict)
    await visitsDb.pendingVisitOperations.add(validConflict)

    await cleanUpDatabase('user-1')

    const op1 = await visitsDb.pendingVisitOperations.get('op-exp-ret')
    const op2 = await visitsDb.pendingVisitOperations.get('op-exp-con')
    const op3 = await visitsDb.pendingVisitOperations.get('op-val-con')

    expect(op1).toBeUndefined()
    expect(op2).toBeUndefined()
    expect(op3).toBeDefined()
  })

  it('detects corrupted or tampered operations using validatePendingOperation', () => {
    const valid: PendingVisitOperation = {
      operationId: 'op-123',
      userId: 'u1',
      planId: 'p1',
      itemId: 'i1',
      kind: 'start',
      state: 'pending',
      attemptCount: 0,
      lastErrorCode: null,
      createdAt: Date.now(),
      updatedAt: Date.now(),
      expiresAt: Date.now() + 1000,
      payload: {
        operationId: 'op-123',
        itemId: 'i1',
        clientStartedAt: '2026-07-06T20:00:00Z',
        deviceTimezone: 'Africa/Cairo'
      } as StartVisitItemAtomicInput
    }

    const invalidNoPayloadId = {
      ...valid,
      payload: {
        operationId: 'op-different',
        itemId: 'i1',
        clientStartedAt: '2026-07-06T20:00:00Z',
        deviceTimezone: 'Africa/Cairo'
      }
    }

    const invalidNoState = {
      ...valid,
      state: 'unknown-state'
    }

    expect(validatePendingOperation(valid)).toBe(true)
    expect(validatePendingOperation(invalidNoPayloadId)).toBe(false)
    expect(validatePendingOperation(invalidNoState)).toBe(false)
  })

  it('handles existing corrupted operation by marking it as conflict and throwing CorruptedPayloadError', async () => {
    const userId = 'user-1'
    const planId = 'plan-1'
    const itemId = 'item-1'

    const corruptedOp = {
      operationId: 'op-invalid',
      userId,
      planId,
      itemId,
      kind: 'start',
      state: 'pending',
      attemptCount: 0,
      lastErrorCode: null,
      createdAt: Date.now(),
      updatedAt: Date.now(),
      expiresAt: Date.now() + 1000,
      payload: {
        operationId: 'op-different',
        itemId,
        clientStartedAt: '2026-07-06T20:00:00Z',
        deviceTimezone: 'Africa/Cairo'
      }
    }
    await visitsDb.pendingVisitOperations.add(corruptedOp as any)

    const buildPayload = vi.fn((opId: string) => ({
      operationId: opId,
      itemId,
      startLat: 30,
      startLng: 31,
      startAccuracyM: 10,
      clientStartedAt: '2026-07-06T19:00:00Z',
      deviceTimezone: 'Africa/Cairo'
    }))

    await expect(
      getOrCreatePendingOperation(userId, planId, itemId, 'start', buildPayload)
    ).rejects.toThrow(CorruptedPayloadError)

    const stored = await visitsDb.pendingVisitOperations.get('op-invalid')
    expect(stored).toBeDefined()
    expect(stored?.state).toBe('conflict')
    expect(stored?.lastErrorCode).toBe('CORRUPTED_PAYLOAD')
    expect(buildPayload).toHaveBeenCalledTimes(0)
  })

  it('handles concurrent corrupted operation on unique constraint collision by marking it as conflict and throwing CorruptedPayloadError', async () => {
    const userId = 'user-1'
    const planId = 'plan-1'
    const itemId = 'item-1'

    const buildPayload = (opId: string) => ({
      operationId: opId,
      itemId,
      startLat: 30,
      startLng: 31,
      startAccuracyM: 10,
      clientStartedAt: '2026-07-06T19:00:00Z',
      deviceTimezone: 'Africa/Cairo'
    })

    const corruptedOp = {
      operationId: 'op-concurrent-corrupted',
      userId,
      planId,
      itemId,
      kind: 'start',
      state: 'pending',
      attemptCount: 0,
      lastErrorCode: null,
      createdAt: Date.now(),
      updatedAt: Date.now(),
      expiresAt: Date.now() + 1000,
      payload: {
        operationId: 'op-different-mismatch',
        itemId,
        clientStartedAt: '2026-07-06T20:00:00Z',
        deviceTimezone: 'Africa/Cairo'
      }
    }
    await visitsDb.pendingVisitOperations.add(corruptedOp as any)

    const originalWhere = visitsDb.pendingVisitOperations.where
    let isFirstCall = true
    const spy = (vi.spyOn(visitsDb.pendingVisitOperations, 'where') as any).mockImplementation(function (this: any, indexOrCriteria: any) {
      if (indexOrCriteria === '[userId+planId+itemId+kind]' && isFirstCall) {
        isFirstCall = false
        return {
          equals: () => ({
            first: async () => undefined
          })
        } as any
      }
      return originalWhere.call(this, indexOrCriteria)
    })

    await expect(
      getOrCreatePendingOperation(userId, planId, itemId, 'start', buildPayload)
    ).rejects.toThrow(CorruptedPayloadError)

    const stored = await visitsDb.pendingVisitOperations.get('op-concurrent-corrupted')
    expect(stored).toBeDefined()
    expect(stored?.state).toBe('conflict')
    expect(stored?.lastErrorCode).toBe('CORRUPTED_PAYLOAD')

    spy.mockRestore()
  })

  it('migrates and registers Version 3 localBlobs store correctly', async () => {
    expect(visitsDb.localBlobs).toBeDefined()
    const table = (visitsDb as any).localBlobs
    const indexNames = table.schema.indexes.map((idx: any) => idx.name)
    expect(indexNames).toContain('[userId+planId+itemId]')
    expect(indexNames).toContain('[userId+planId+itemId+questionId]')
    expect(indexNames).toContain('userId')
    expect(indexNames).toContain('uploadState')
    expect(indexNames).toContain('expiresAt')
  })

  it('performs atomic replacement and transaction checks', async () => {
    const userId = 'u1'
    const planId = 'p1'
    const itemId = 'i1'
    const templateId = 't1'
    const questionId = 'q1'

    // Seed session first
    const mockSession: LocalVisitSession = {
      userId,
      planId,
      itemId,
      serverStartedAt: null,
      clientStartedAt: new Date().toISOString(),
      startGPS: null,
      startGPSAccuracy: null,
      gpsValidationStatus: 'passed',
      checklistDrafts: {},
      gpsExceptionReason: null,
      updatedAt: Date.now(),
      expiresAt: Date.now() + 2 * 3600 * 1000
    }
    await visitsDb.visitSessions.add(mockSession)

    // Save a new local photo
    const firstBlob = new Blob(['blobcontent1'], { type: 'image/jpeg' })
    const firstBlobId = await replaceLocalBlobTransaction({
      userId,
      planId,
      itemId,
      templateId,
      questionId,
      newBlob: firstBlob,
      newMimeType: 'image/jpeg',
      newExtension: 'jpg',
      newChecksum: 'a'.repeat(64)
    })

    expect(firstBlobId).toBeDefined()

    // Verify it is stored and draft is updated
    const storedBlob1 = await visitsDb.localBlobs.get(firstBlobId)
    expect(storedBlob1).toBeDefined()
    expect(storedBlob1?.checksum).toBe('a'.repeat(64))
    expect(storedBlob1?.objectPath).toBe(`plans/${planId}/items/${itemId}/${firstBlobId}.jpg`)

    const updatedSession = await visitsDb.visitSessions.get([userId, planId])
    expect(updatedSession?.checklistDrafts[templateId]?.responses[0].answer_json).toEqual({
      local_blob_id: firstBlobId
    })

    // Overwrite the image
    const secondBlob = new Blob(['blobcontent2'], { type: 'image/jpeg' })
    const secondBlobId = await replaceLocalBlobTransaction({
      userId,
      planId,
      itemId,
      templateId,
      questionId,
      newBlob: secondBlob,
      newMimeType: 'image/jpeg',
      newExtension: 'jpg',
      newChecksum: 'b'.repeat(64)
    })

    // The old blob should be deleted since it has no other references
    const storedBlob1After = await visitsDb.localBlobs.get(firstBlobId)
    expect(storedBlob1After).toBeUndefined()

    // The new blob should be stored and draft is updated
    const storedBlob2 = await visitsDb.localBlobs.get(secondBlobId)
    expect(storedBlob2).toBeDefined()
    expect(storedBlob2?.checksum).toBe('b'.repeat(64))
    expect(storedBlob2?.objectPath).toBe(`plans/${planId}/items/${itemId}/${secondBlobId}.jpg`)

    const updatedSession2 = await visitsDb.visitSessions.get([userId, planId])
    expect(updatedSession2?.checklistDrafts[templateId]?.responses[0].answer_json).toEqual({
      local_blob_id: secondBlobId
    })
  })

  it('throws an error and rejects replacement if old blob context does not match', async () => {
    const userId = 'u1'
    const planId = 'p1'
    const itemId = 'i1'
    const templateId = 't1'
    const questionId = 'q1'

    // Seed session
    const mockSession: LocalVisitSession = {
      userId,
      planId,
      itemId,
      serverStartedAt: null,
      clientStartedAt: new Date().toISOString(),
      startGPS: null,
      startGPSAccuracy: null,
      gpsValidationStatus: 'passed',
      checklistDrafts: {},
      gpsExceptionReason: null,
      updatedAt: Date.now(),
      expiresAt: Date.now() + 2 * 3600 * 1000
    }
    await visitsDb.visitSessions.add(mockSession)

    const firstBlob = new Blob(['blobcontent1'], { type: 'image/jpeg' })
    const firstBlobId = await replaceLocalBlobTransaction({
      userId,
      planId,
      itemId,
      templateId,
      questionId,
      newBlob: firstBlob,
      newMimeType: 'image/jpeg',
      newExtension: 'jpg',
      newChecksum: 'a'.repeat(64)
    })

    // Now manually hack the stored blob context (e.g. change templateId)
    await visitsDb.localBlobs.update(firstBlobId, { templateId: 't-different' })

    // Trying to replace it should throw and reject
    const secondBlob = new Blob(['blobcontent2'], { type: 'image/jpeg' })
    await expect(
      replaceLocalBlobTransaction({
        userId,
        planId,
        itemId,
        templateId,
        questionId,
        newBlob: secondBlob,
        newMimeType: 'image/jpeg',
        newExtension: 'jpg',
        newChecksum: 'b'.repeat(64)
      })
    ).rejects.toThrow('البيانات المخزنة محلياً غير متطابقة أو تالفة')

    // Verify original blob was NOT deleted
    const storedBlob1 = await visitsDb.localBlobs.get(firstBlobId)
    expect(storedBlob1).toBeDefined()
  })

  it('keeps the old blob if it is still referenced in a pending operation', async () => {
    const userId = 'u1'
    const planId = 'p1'
    const itemId = 'i1'
    const templateId = 't1'
    const questionId = 'q1'

    // Seed session
    const mockSession: LocalVisitSession = {
      userId,
      planId,
      itemId,
      serverStartedAt: null,
      clientStartedAt: new Date().toISOString(),
      startGPS: null,
      startGPSAccuracy: null,
      gpsValidationStatus: 'passed',
      checklistDrafts: {},
      gpsExceptionReason: null,
      updatedAt: Date.now(),
      expiresAt: Date.now() + 2 * 3600 * 1000
    }
    await visitsDb.visitSessions.add(mockSession)

    // Save first photo
    const firstBlob = new Blob(['blobcontent1'], { type: 'image/jpeg' })
    const firstBlobId = await replaceLocalBlobTransaction({
      userId,
      planId,
      itemId,
      templateId,
      questionId,
      newBlob: firstBlob,
      newMimeType: 'image/jpeg',
      newExtension: 'jpg',
      newChecksum: 'a'.repeat(64)
    })

    // Create a pending complete operation referencing firstBlobId
    const pendingOp: unknown = {
      operationId: 'op-complete-1',
      userId,
      planId,
      itemId,
      kind: 'complete',
      state: 'pending',
      attemptCount: 0,
      lastErrorCode: null,
      createdAt: Date.now(),
      updatedAt: Date.now(),
      expiresAt: Date.now() + 24 * 3600 * 1000,
      payload: {
        operationId: 'op-complete-1',
        itemId,
        clientCompletedAt: new Date().toISOString(),
        deviceTimezone: 'UTC',
        outcomeType: 'visited',
        responses: [
          {
            template_id: templateId,
            question_id: questionId,
            answer_value: null,
            answer_json: { local_blob_id: firstBlobId }
          }
        ]
      }
    }
    await visitsDb.pendingVisitOperations.add(pendingOp as PendingVisitOperation)

    // Replace photo
    const secondBlob = new Blob(['blobcontent2'], { type: 'image/jpeg' })
    const secondBlobId = await replaceLocalBlobTransaction({
      userId,
      planId,
      itemId,
      templateId,
      questionId,
      newBlob: secondBlob,
      newMimeType: 'image/jpeg',
      newExtension: 'jpg',
      newChecksum: 'b'.repeat(64)
    })

    // Since firstBlobId is referenced in a pending operation, it should NOT be deleted!
    const storedBlob1After = await visitsDb.localBlobs.get(firstBlobId)
    expect(storedBlob1After).toBeDefined()

    // The new blob is also stored
    const storedBlob2 = await visitsDb.localBlobs.get(secondBlobId)
    expect(storedBlob2).toBeDefined()
  })

  it('enforces a 50MB storage quota constraint per user', async () => {
    const userId = 'u1'
    const planId = 'p1'
    const itemId = 'i1'
    const templateId = 't1'
    const questionId = 'q1'

    // Seed session
    const mockSession: LocalVisitSession = {
      userId,
      planId,
      itemId,
      serverStartedAt: null,
      clientStartedAt: new Date().toISOString(),
      startGPS: null,
      startGPSAccuracy: null,
      gpsValidationStatus: 'passed',
      checklistDrafts: {},
      gpsExceptionReason: null,
      updatedAt: Date.now(),
      expiresAt: Date.now() + 2 * 3600 * 1000
    }
    await visitsDb.visitSessions.add(mockSession)

    // Seed database with 25 blobs of 2MB each (total 50MB) to fill quota
    const seededBlobs = []
    for (let i = 0; i < 25; i++) {
      seededBlobs.push({
        localBlobId: `b-${i}`,
        userId,
        planId,
        itemId,
        templateId,
        questionId: `q-${i}`,
        objectPath: `plans/${planId}/items/${itemId}/b-${i}.jpg`,
        mimeType: 'image/jpeg',
        extension: 'jpg',
        sizeBytes: 2 * 1024 * 1024,
        checksum: 'a'.repeat(64),
        uploadState: 'pending' as const,
        attemptCount: 0,
        lastErrorCode: null,
        nextRetryAt: null,
        blob: new Blob(['dummy']),
        createdAt: Date.now(),
        updatedAt: Date.now(),
        expiresAt: Date.now() + 24 * 3600 * 1000
      })
    }
    await visitsDb.localBlobs.bulkAdd(seededBlobs)

    // Try to insert a valid 2MB blob which will exceed the 50MB quota
    const largeBlob = new Blob([new ArrayBuffer(2 * 1024 * 1024)], { type: 'image/jpeg' })
    await expect(
      replaceLocalBlobTransaction({
        userId,
        planId,
        itemId,
        templateId,
        questionId: 'q-overflow',
        newBlob: largeBlob,
        newMimeType: 'image/jpeg',
        newExtension: 'jpg',
        newChecksum: 'c'.repeat(64)
      })
    ).rejects.toThrow('QUOTA_EXCEEDED')
  })

  it('safely cleans up expired records but protects active sessions and operations', async () => {
    const userId = 'u1'
    const now = Date.now()

    // Expired session and unreferenced expired blob
    const sessionExpired: LocalVisitSession = {
      userId,
      planId: 'expired-plan',
      itemId: 'i1',
      serverStartedAt: null,
      clientStartedAt: new Date().toISOString(),
      startGPS: null,
      startGPSAccuracy: null,
      gpsValidationStatus: 'passed',
      checklistDrafts: {},
      gpsExceptionReason: null,
      updatedAt: now - 3600 * 1000,
      expiresAt: now - 1000 // expired
    }
    await visitsDb.visitSessions.add(sessionExpired)

    const expiredBlobRecordUnreferenced = {
      localBlobId: 'blob-expired-unref',
      userId,
      planId: 'expired-plan',
      itemId: 'i1',
      templateId: 't1',
      questionId: 'q1',
      objectPath: '...',
      mimeType: 'image/jpeg',
      extension: 'jpg',
      sizeBytes: 100,
      checksum: 'chk1',
      uploadState: 'pending' as const,
      attemptCount: 0,
      lastErrorCode: null,
      nextRetryAt: null,
      blob: new Blob(['expired-unref']),
      createdAt: now - 3600 * 1000,
      updatedAt: now - 3600 * 1000,
      expiresAt: now - 1000 // expired
    }
    await visitsDb.localBlobs.add(expiredBlobRecordUnreferenced)

    // Expired blob that is referenced in a pending operation
    const expiredBlobRecordReferenced = {
      localBlobId: 'blob-expired-ref',
      userId,
      planId: 'expired-plan',
      itemId: 'i1',
      templateId: 't1',
      questionId: 'q2',
      objectPath: '...',
      mimeType: 'image/jpeg',
      extension: 'jpg',
      sizeBytes: 100,
      checksum: 'chk2',
      uploadState: 'pending' as const,
      attemptCount: 0,
      lastErrorCode: null,
      nextRetryAt: null,
      blob: new Blob(['expired-ref']),
      createdAt: now - 3600 * 1000,
      updatedAt: now - 3600 * 1000,
      expiresAt: now - 1000 // expired
    }
    await visitsDb.localBlobs.add(expiredBlobRecordReferenced)

    const pendingOp: unknown = {
      operationId: 'op-ref-1',
      userId,
      planId: 'expired-plan',
      itemId: 'i1',
      kind: 'complete',
      state: 'pending',
      attemptCount: 0,
      lastErrorCode: null,
      createdAt: now,
      updatedAt: now,
      expiresAt: now + 3600 * 1000, // active
      payload: {
        operationId: 'op-ref-1',
        itemId: 'i1',
        clientCompletedAt: new Date().toISOString(),
        deviceTimezone: 'UTC',
        outcomeType: 'visited',
        responses: [
          {
            template_id: 't1',
            question_id: 'q2',
            answer_value: null,
            answer_json: { local_blob_id: 'blob-expired-ref' }
          }
        ]
      }
    }
    await visitsDb.pendingVisitOperations.add(pendingOp as PendingVisitOperation)

    // Run cleanup
    await cleanUpDatabase(userId)

    // The unreferenced expired session and blob should be deleted
    expect(await visitsDb.visitSessions.get([userId, 'expired-plan'])).toBeUndefined()
    expect(await visitsDb.localBlobs.get('blob-expired-unref')).toBeUndefined()

    // The referenced expired blob must NOT be deleted
    expect(await visitsDb.localBlobs.get('blob-expired-ref')).toBeDefined()
  })

  describe('getLocalBlobIdsFromPayload Helper', () => {
    it('correctly extracts multiple unique local blob IDs, handles duplicates, handles corrupted/null payload safely without throwing', () => {
      // 1. Happy path: extracts multiple IDs
      const payloadHappy = {
        responses: [
          { answer_json: { local_blob_id: 'blob-1' } },
          { answer_json: { local_blob_id: 'blob-2' } },
          { answer_json: { local_blob_id: 'blob-1' } } // duplicate
        ]
      }
      const ids = getLocalBlobIdsFromPayload(payloadHappy)
      expect(ids).toEqual(['blob-1', 'blob-2'])

      // 2. Corrupted payloads do not throw and return empty list
      expect(getLocalBlobIdsFromPayload(null)).toEqual([])
      expect(getLocalBlobIdsFromPayload(undefined)).toEqual([])
      expect(getLocalBlobIdsFromPayload('not-an-object')).toEqual([])
      expect(getLocalBlobIdsFromPayload({ responses: 'not-an-array' })).toEqual([])
      expect(getLocalBlobIdsFromPayload({
        responses: [
          { answer_json: null },
          { answer_json: { local_blob_id: 123 } }, // not a string
          { answer_json: { other_field: 'blob-1' } }
        ]
      })).toEqual([])
    })
  })
})
