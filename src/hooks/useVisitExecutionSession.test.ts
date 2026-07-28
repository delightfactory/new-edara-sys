import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { act, renderHook, waitFor } from '@testing-library/react'
import { useVisitExecutionSession, mapChecklistResponses, isVisitOperationSatisfiedByServer } from './useVisitExecutionSession'
import { visitsDb, cleanUpDatabase, type PendingVisitOperation, validatePendingOperation, getOrCreatePendingOperation, InvalidOperationDependencyError, CorruptedPayloadError, replaceLocalBlobTransaction } from '@/lib/db/visitsDb'
import {
  startVisitItemAtomic,
  completeVisitItemAtomic,
  skipVisitItemAtomic,
  VisitRpcTransportError
} from '@/lib/services/activities'
import type { VisitPlanItem, ChecklistQuestion, ChecklistResponseInput, StartVisitItemAtomicInput, SkipVisitItemAtomicInput, VisitCompletionChecklistResponseInput, StartVisitItemAtomicResult, CompleteVisitItemAtomicResult, SkipVisitItemAtomicResult, VisitRpcResult, VisitStoragePath } from '@/lib/types/activities'

// Local helper type for testing runtime rejection of dependsOnOperationId on non-complete kinds.
// getOrCreatePendingOperation overloads intentionally omit dependsOnOperationId for start/skip;
// this cast through unknown lets us verify the runtime guard without using `any`.
type GetOrCreateWithForbiddenDep = (
  userId: string, planId: string, itemId: string,
  kind: 'start' | 'skip',
  buildPayload: (opId: string) => StartVisitItemAtomicInput | SkipVisitItemAtomicInput,
  dependsOnOperationId: string
) => Promise<unknown>
const getOrCreateWithForbiddenDep = getOrCreatePendingOperation as unknown as GetOrCreateWithForbiddenDep
import type { PostgrestError } from '@supabase/supabase-js'

// Simple mock for auth store
vi.mock('@/stores/auth-store', () => ({
  useAuthStore: Object.assign((fn: (s: { profile: { id: string } }) => { profile: { id: string } }) => fn({ profile: { id: 'test-user-123' } }), {
    getState: () => ({ profile: { id: 'test-user-123' } })
  })
}))

// Mock API service methods
vi.mock('@/lib/services/activities', () => ({
  startVisitItemAtomic: vi.fn(),
  completeVisitItemAtomic: vi.fn(),
  skipVisitItemAtomic: vi.fn(),
  validateVisitStoragePath: vi.fn((path: string) => {
    if (path.includes('invalid') || path.includes('//') || path.includes('..')) {
      throw new Error('Unsafe path')
    }
    return path
  }),
  VisitRpcTransportError: class extends Error {
    readonly supabaseError: PostgrestError
    constructor(msg: string, supabaseError: PostgrestError) {
      super(msg)
      this.name = 'VisitRpcTransportError'
      this.supabaseError = supabaseError
    }
  }
}))

// Mock queryClient
const mockInvalidateQueries = vi.fn()
const mockFetchQuery = vi.fn()
vi.mock('@tanstack/react-query', () => ({
  useQueryClient: () => ({
    invalidateQueries: mockInvalidateQueries,
    fetchQuery: mockFetchQuery
  })
}))

describe('useVisitExecutionSession Hook Core Logic', () => {
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
    if (!visitsDb.isOpen()) {
      await visitsDb.open()
    }
    await visitsDb.visitSessions.clear()
    await visitsDb.pendingVisitOperations.clear()
    await visitsDb.localBlobs.clear()
    vi.clearAllMocks()
    vi.mocked(startVisitItemAtomic).mockReset()
    vi.mocked(completeVisitItemAtomic).mockReset()
    vi.mocked(skipVisitItemAtomic).mockReset()
  })

  const mockQuestions: ChecklistQuestion[] = [
    { id: 'q-photo', template_id: 't-1', question_text: 'صورة', question_type: 'photo' } as unknown as ChecklistQuestion,
    { id: 'q-multi', template_id: 't-1', question_text: 'متعدد', question_type: 'multi_choice' } as unknown as ChecklistQuestion,
    { id: 'q-scalar', template_id: 't-1', question_text: 'نص', question_type: 'text' } as unknown as ChecklistQuestion
  ]

  it('reconciles a stale local start conflict when the server already started the visit', async () => {
    const operationId = '78fd0ac5-35f8-4815-aa81-bf4ec4b042b4'
    const now = Date.now()
    const operation: PendingVisitOperation = {
      operationId,
      userId: 'test-user-123',
      planId: 'plan-123',
      itemId: 'item-1',
      kind: 'start',
      state: 'conflict',
      attemptCount: 1,
      lastErrorCode: 'SYNC_CONFLICT',
      createdAt: now,
      updatedAt: now,
      expiresAt: now + 10_000,
      payload: {
        operationId,
        itemId: 'item-1',
        startLat: null,
        startLng: null,
        startAccuracyM: null,
        clientStartedAt: new Date().toISOString(),
        deviceTimezone: 'Africa/Cairo'
      }
    }
    const serverItems = [{
      id: 'item-1', plan_id: 'plan-123', customer_id: 'customer-1', sequence: 1,
      status: 'in_progress', server_started_at: new Date().toISOString(),
      client_started_at: new Date().toISOString(), start_lat: null, start_lng: null,
      start_accuracy_m: null, gps_validation_status: 'no_coordinates',
      updated_at: new Date().toISOString()
    }] as unknown as VisitPlanItem[]

    await visitsDb.pendingVisitOperations.put(operation)
    await visitsDb.visitSessions.put({
      userId: 'test-user-123', planId: 'plan-123', itemId: 'item-1',
      serverStartedAt: serverItems[0].server_started_at,
      clientStartedAt: serverItems[0].client_started_at || new Date().toISOString(),
      startGPS: null, startGPSAccuracy: null, gpsValidationStatus: 'no_coordinates',
      checklistDrafts: {}, gpsExceptionReason: null, updatedAt: now, expiresAt: now + 10_000
    })

    expect(isVisitOperationSatisfiedByServer(operation, serverItems[0])).toBe(true)
    const { result } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))

    await waitFor(async () => {
      expect(await visitsDb.pendingVisitOperations.get(operationId)).toBeUndefined()
      expect(result.current.pendingOps).toHaveLength(0)
      expect(result.current.session?.itemId).toBe('item-1')
    })
  })

  it('mapChecklistResponses validates types, templateIds, extra properties, and blocks Base64', () => {
    const validPhoto: ChecklistResponseInput = {
      template_id: 't-1',
      question_id: 'q-photo',
      answer_json: { storage_path: 'visits/123/img.jpg' }
    } as unknown as ChecklistResponseInput

    const extraPropPhoto: ChecklistResponseInput = {
      template_id: 't-1',
      question_id: 'q-photo',
      answer_json: { storage_path: 'visits/123/img.jpg', extra_hack: 'value' }
    } as unknown as ChecklistResponseInput

    const mismatchedTemplatePhoto: ChecklistResponseInput = {
      template_id: 't-mismatch',
      question_id: 'q-photo',
      answer_json: { storage_path: 'visits/123/img.jpg' }
    } as unknown as ChecklistResponseInput

    const dataUrlPhoto: ChecklistResponseInput = {
      template_id: 't-1',
      question_id: 'q-photo',
      answer_value: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUA'
    } as unknown as ChecklistResponseInput

    const mapped = mapChecklistResponses([validPhoto], mockQuestions, 't-1')
    expect(mapped[0].answer_json).toEqual({ storage_path: 'visits/123/img.jpg' })

    expect(() => {
      mapChecklistResponses([extraPropPhoto], mockQuestions, 't-1')
    }).toThrow('إجابة الصورة للسؤال "صورة" يجب أن تحتوي على مسار التخزين فقط')

    expect(() => {
      mapChecklistResponses([mismatchedTemplatePhoto], mockQuestions, 't-1')
    }).toThrow('لا يتطابق مع معرّف القالب الجاري')

    expect(() => {
      mapChecklistResponses([dataUrlPhoto], mockQuestions, 't-1')
    }).toThrow('لا يمكن حفظ أو إرسال صور ترميز Base64/Data URL مباشرة')
  })

  it('proves IndexedDB is not touched if enabled is false', async () => {
    const sessionGetSpy = vi.spyOn(visitsDb.visitSessions, 'get')
    const sessionWhereSpy = vi.spyOn(visitsDb.visitSessions, 'where')
    const sessionPutSpy = vi.spyOn(visitsDb.visitSessions, 'put')
    const sessionDeleteSpy = vi.spyOn(visitsDb.visitSessions, 'delete')
    const opsWhereSpy = vi.spyOn(visitsDb.pendingVisitOperations, 'where')
    const opsPutSpy = vi.spyOn(visitsDb.pendingVisitOperations, 'put')
    const opsDeleteSpy = vi.spyOn(visitsDb.pendingVisitOperations, 'delete')

    const serverItems: VisitPlanItem[] = [
      { id: 'item-1', plan_id: 'p-1', status: 'pending', customer_id: 'c-1', sequence: 1 } as unknown as VisitPlanItem
    ]

    const { result } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, false))

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 50))
    })

    expect(result.current.session).toBeNull()
    expect(result.current.loading).toBe(false)
    expect(sessionGetSpy).not.toHaveBeenCalled()
    expect(sessionWhereSpy).not.toHaveBeenCalled()
    expect(sessionPutSpy).not.toHaveBeenCalled()
    expect(sessionDeleteSpy).not.toHaveBeenCalled()
    expect(opsWhereSpy).not.toHaveBeenCalled()
    expect(opsPutSpy).not.toHaveBeenCalled()
    expect(opsDeleteSpy).not.toHaveBeenCalled()
  })

  it('handles non-Error exceptions in sync/reload without hanging loading=true and hides console.error', async () => {
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
    const cleanUpSpy = vi.spyOn(visitsDb.visitSessions, 'where').mockImplementationOnce(() => {
      throw 'IndexedDB Corrupted String'
    })

    const serverItems: VisitPlanItem[] = [
      { id: 'item-1', plan_id: 'plan-123', status: 'pending', customer_id: 'c-1', sequence: 1 } as unknown as VisitPlanItem
    ]

    const { result } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 50))
    })

    expect(result.current.loading).toBe(false)
    expect(result.current.error).toBe('حدث خطأ غير متوقع أثناء مزامنة البيانات المحلية')
    cleanUpSpy.mockRestore()
    errorSpy.mockRestore()
  })

  it('checks server status before discarding failed operations and accepts an already-satisfied start', async () => {
    const now = Date.now()
    await visitsDb.pendingVisitOperations.put({
      operationId: 'op-failed-start',
      userId: 'test-user-123',
      planId: 'plan-123',
      itemId: 'item-1',
      kind: 'start',
      payload: {
        operationId: 'op-failed-start',
        itemId: 'item-1',
        startLat: null,
        startLng: null,
        startAccuracyM: null,
        clientStartedAt: '2026-07-06T21:00:00Z',
        deviceTimezone: 'Africa/Cairo'
      },
      state: 'failed',
      attemptCount: 1,
      lastErrorCode: 'SERVER_ERROR',
      createdAt: now,
      updatedAt: now,
      expiresAt: now + 7 * 24 * 3600 * 1000
    })

    mockFetchQuery.mockResolvedValueOnce([
      { id: 'item-1', status: 'pending' } as unknown as VisitPlanItem
    ])

    const serverItems: VisitPlanItem[] = [
      { id: 'item-1', plan_id: 'plan-123', status: 'pending', customer_id: 'c-1', sequence: 1 } as unknown as VisitPlanItem
    ]

    const { result } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 50))
    })

    await act(async () => {
      await result.current.discardFailedOperation('op-failed-start')
    })

    const stored = await visitsDb.pendingVisitOperations.get('op-failed-start')
    expect(stored).toBeUndefined()

    await visitsDb.pendingVisitOperations.put({
      operationId: 'op-failed-start-2',
      userId: 'test-user-123',
      planId: 'plan-123',
      itemId: 'item-1',
      kind: 'start',
      payload: {
        operationId: 'op-failed-start-2',
        itemId: 'item-1',
        startLat: null,
        startLng: null,
        startAccuracyM: null,
        clientStartedAt: '2026-07-06T21:00:00Z',
        deviceTimezone: 'Africa/Cairo'
      },
      state: 'failed',
      attemptCount: 1,
      lastErrorCode: 'SERVER_ERROR',
      createdAt: now,
      updatedAt: now,
      expiresAt: now + 7 * 24 * 3600 * 1000
    })

    mockFetchQuery.mockResolvedValueOnce([
      { id: 'item-1', status: 'in_progress' } as unknown as VisitPlanItem
    ])

    await act(async () => {
      await result.current.discardFailedOperation('op-failed-start-2')
    })

    const reconciled = await visitsDb.pendingVisitOperations.get('op-failed-start-2')
    expect(reconciled).toBeUndefined()
  })

  it('restores interrupted pending/sending operations to retryable on initialization', async () => {
    const now = Date.now()
    await visitsDb.pendingVisitOperations.put({
      operationId: 'op-interrupted',
      userId: 'test-user-123',
      planId: 'plan-123',
      itemId: 'item-1',
      kind: 'start',
      payload: {
        operationId: 'op-interrupted',
        itemId: 'item-1',
        startLat: null,
        startLng: null,
        startAccuracyM: null,
        clientStartedAt: '2026-07-06T21:00:00Z',
        deviceTimezone: 'Africa/Cairo'
      },
      state: 'pending',
      attemptCount: 0,
      lastErrorCode: null,
      createdAt: now,
      updatedAt: now,
      expiresAt: now + 48 * 3600 * 1000
    })

    const serverItems: VisitPlanItem[] = [
      { id: 'item-1', plan_id: 'plan-123', status: 'pending', customer_id: 'c-1', sequence: 1 } as unknown as VisitPlanItem
    ]

    renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 50))
    })

    const stored = await visitsDb.pendingVisitOperations.get('op-interrupted')
    expect(stored?.state).toBe('retryable')
  })

  it('checks that temporary start session is kept active in UI during pending start operation', async () => {
    const now = Date.now()
    await visitsDb.pendingVisitOperations.put({
      operationId: 'op-pending-start',
      userId: 'test-user-123',
      planId: 'plan-123',
      itemId: 'item-1',
      kind: 'start',
      payload: {
        operationId: 'op-pending-start',
        itemId: 'item-1',
        startLat: null,
        startLng: null,
        startAccuracyM: null,
        clientStartedAt: '2026-07-06T21:00:00Z',
        deviceTimezone: 'Africa/Cairo'
      },
      state: 'pending',
      attemptCount: 0,
      lastErrorCode: null,
      createdAt: now,
      updatedAt: now,
      expiresAt: now + 48 * 3600 * 1000
    })

    await visitsDb.visitSessions.put({
      userId: 'test-user-123',
      planId: 'plan-123',
      itemId: 'item-1',
      serverStartedAt: null,
      clientStartedAt: '2026-07-06T20:00:00Z',
      startGPS: null,
      startGPSAccuracy: null,
      gpsValidationStatus: 'not_checked',
      checklistDrafts: {},
      gpsExceptionReason: null,
      updatedAt: now,
      expiresAt: now + 48 * 3600 * 1000
    })

    const serverItems: VisitPlanItem[] = [
      { id: 'item-1', plan_id: 'plan-123', status: 'pending', customer_id: 'c-1', sequence: 1 } as unknown as VisitPlanItem
    ]

    const { result } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 50))
    })

    expect(result.current.session).not.toBeNull()
  })

  it('deletes temporary session when start operation fails permanently and does not return after discard', async () => {
    const now = Date.now()
    await visitsDb.pendingVisitOperations.put({
      operationId: 'op-failed-start',
      userId: 'test-user-123',
      planId: 'plan-123',
      itemId: 'item-1',
      kind: 'start',
      payload: {
        operationId: 'op-failed-start',
        itemId: 'item-1',
        startLat: null,
        startLng: null,
        startAccuracyM: null,
        clientStartedAt: '2026-07-06T21:00:00Z',
        deviceTimezone: 'Africa/Cairo'
      },
      state: 'failed',
      attemptCount: 1,
      lastErrorCode: 'SERVER_ERROR',
      createdAt: now,
      updatedAt: now,
      expiresAt: now + 7 * 24 * 3600 * 1000
    })

    await visitsDb.visitSessions.put({
      userId: 'test-user-123',
      planId: 'plan-123',
      itemId: 'item-1',
      serverStartedAt: null,
      clientStartedAt: '2026-07-06T20:00:00Z',
      startGPS: null,
      startGPSAccuracy: null,
      gpsValidationStatus: 'not_checked',
      checklistDrafts: {},
      gpsExceptionReason: null,
      updatedAt: now,
      expiresAt: now + 48 * 3600 * 1000
    })

    mockFetchQuery.mockResolvedValueOnce([
      { id: 'item-1', status: 'pending' } as unknown as VisitPlanItem
    ])

    const serverItems: VisitPlanItem[] = [
      { id: 'item-1', plan_id: 'plan-123', status: 'pending', customer_id: 'c-1', sequence: 1 } as unknown as VisitPlanItem
    ]

    const { result } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 50))
    })

    expect(result.current.session).toBeNull()

    // Discard it
    await act(async () => {
      await result.current.discardFailedOperation('op-failed-start')
    })

    const storedSession = await visitsDb.visitSessions.get(['test-user-123', 'plan-123'])
    expect(storedSession).toBeUndefined()
  })

  it('restores session using server values and start coordinates including zero values', async () => {
    const serverItems: VisitPlanItem[] = [
      {
        id: 'item-1',
        plan_id: 'plan-123',
        status: 'in_progress',
        customer_id: 'c-1',
        sequence: 1,
        server_started_at: '2026-07-06T20:10:00Z',
        client_started_at: '2026-07-06T20:05:00Z',
        start_lat: 0,
        start_lng: 0,
        start_accuracy_m: 5,
        gps_validation_status: 'valid',
        gps_exception_reason: 'Testing exception',
        updated_at: '2026-07-06T20:10:00Z'
      } as unknown as VisitPlanItem
    ]

    const { result } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 50))
    })

    expect(result.current.session).toBeDefined()
    expect(result.current.session?.serverStartedAt).toBe('2026-07-06T20:10:00Z')
    expect(result.current.session?.startGPS).toEqual({ lat: 0, lng: 0 })
    expect(result.current.session?.startGPSAccuracy).toBe(5)
    expect(result.current.session?.gpsValidationStatus).toBe('valid')
    expect(result.current.session?.gpsExceptionReason).toBe('Testing exception')
  })

  it('prevents double-click concurrency and triggers RPC execution once', async () => {
    let rpcCount = 0
    vi.mocked(startVisitItemAtomic).mockImplementationOnce(async () => {
      rpcCount++
      await new Promise(resolve => setTimeout(resolve, 50))
      return {
        ok: true,
        operation_id: 'op-uuid',
        operation: 'start_visit_item_atomic',
        replayed: false,
        data: {
          item_id: 'item-1',
          status: 'in_progress',
          server_started_at: '2026-07-06T20:15:00Z',
          start_distance_m: null,
          gps_validation_status: 'not_checked',
          plan_id: 'plan-123',
          plan_status: 'in_progress'
        }
      }
    })

    const serverItems: VisitPlanItem[] = [
      { id: 'item-1', plan_id: 'plan-123', status: 'pending', customer_id: 'c-1', sequence: 1 } as unknown as VisitPlanItem
    ]

    const { result } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 50))
    })

    let p1: Promise<unknown>
    let p2: Promise<unknown>

    await act(async () => {
      p1 = result.current.startVisit('item-1', null, null)
      p2 = result.current.startVisit('item-1', null, null)
      await Promise.all([p1, p2])
    })

    expect(rpcCount).toBe(1)
  })

  it('differentiates VisitRpcTransportError (connection issue) from malformed response', async () => {
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {})

    vi.mocked(startVisitItemAtomic).mockRejectedValueOnce(
      new VisitRpcTransportError('Connection issue', { message: 'Network offline', details: '', hint: '', code: '', name: 'PostgrestError' })
    )

    vi.mocked(startVisitItemAtomic).mockResolvedValueOnce(
      {} as unknown as VisitRpcResult<StartVisitItemAtomicResult>
    )

    const serverItems: VisitPlanItem[] = [
      { id: 'item-1', plan_id: 'plan-123', status: 'pending', customer_id: 'c-1', sequence: 1 } as unknown as VisitPlanItem
    ]

    const { result } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 50))
    })

    let resA: any
    await act(async () => {
      resA = await result.current.startVisit('item-1', null, null)
    })

    expect(resA.state).toBe('retryable')
    expect(resA.errorCode).toBe('CONNECTION_ERROR')

    let resB: any
    await act(async () => {
      resB = await result.current.startVisit('item-1', null, null)
    })

    expect(resB.state).toBe('failed')
    expect(resB.errorCode).toBe('CLIENT_ERROR')

    errorSpy.mockRestore()
  })

  it('syncs reactively when serverItems updates from empty list to populated list', async () => {
    const { result, rerender } = renderHook(
      ({ itemsList }) => useVisitExecutionSession('plan-123', itemsList, true),
      { initialProps: { itemsList: [] as VisitPlanItem[] } }
    )

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 50))
    })

    expect(result.current.session).toBeNull()

    const populatedList: VisitPlanItem[] = [
      {
        id: 'item-1',
        plan_id: 'plan-123',
        status: 'in_progress',
        customer_id: 'c-1',
        sequence: 1,
        server_started_at: '2026-07-06T20:30:00Z',
        client_started_at: '2026-07-06T20:25:00Z',
        start_lat: 30,
        start_lng: 31,
        start_accuracy_m: 10,
        gps_validation_status: 'valid',
        updated_at: '2026-07-06T20:31:00Z'
      } as unknown as VisitPlanItem
    ]

    await act(async () => {
      rerender({ itemsList: populatedList })
    })

    await waitFor(() => {
      expect(result.current.session).not.toBeNull()
    })

    expect(result.current.session?.serverStartedAt).toBe('2026-07-06T20:30:00Z')
    expect(result.current.session?.startGPS).toEqual({ lat: 30, lng: 31 })
  })

   describe('Phase \u0635\u0641\u0631-\u0623 Specific Tests', () => {
    let consoleErrorSpy: any
    beforeEach(() => {
      consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
    })
    afterEach(() => {
      consoleErrorSpy.mockRestore()
    })

    it('visitsDb: validatePendingOperation validation cases', () => {
      const opWithoutDep = {
        operationId: '12345678-1234-1234-1234-1234567890ab',
        userId: 'test-user',
        planId: 'test-plan',
        itemId: 'test-item',
        state: 'pending',
        attemptCount: 0,
        lastErrorCode: null,
        createdAt: Date.now(),
        updatedAt: Date.now(),
        expiresAt: Date.now() + 10000,
        kind: 'start',
        payload: {
          operationId: '12345678-1234-1234-1234-1234567890ab',
          itemId: 'test-item',
          clientStartedAt: '2026-07-06T20:30:00Z',
          deviceTimezone: 'Africa/Cairo'
        }
      }
      expect(validatePendingOperation(opWithoutDep)).toBe(true)

      // dependsOnOperationId is only valid for 'complete' operations
      const completeOpId = '99999999-9999-9999-9999-999999999999'
      const opWithValidDep = {
        operationId: completeOpId,
        userId: 'test-user',
        planId: 'test-plan',
        itemId: 'test-item',
        state: 'pending',
        attemptCount: 0,
        lastErrorCode: null,
        createdAt: Date.now(),
        updatedAt: Date.now(),
        expiresAt: Date.now() + 10000,
        kind: 'complete',
        dependsOnOperationId: '87654321-4321-4321-4321-ba0987654321',
        payload: {
          operationId: completeOpId,
          itemId: 'test-item',
          clientCompletedAt: '2026-07-06T21:00:00Z',
          deviceTimezone: 'Africa/Cairo',
          outcomeType: 'visited',
          outcomeNotes: null,
          endLat: null,
          endLng: null,
          endAccuracyM: null,
          orderId: null,
          collectionId: null,
          gpsExceptionReason: null,
          responses: []
        }
      }
      expect(validatePendingOperation(opWithValidDep)).toBe(true)

      const opWithNonStringDep = {
        ...opWithoutDep,
        dependsOnOperationId: 123
      }
      expect(validatePendingOperation(opWithNonStringDep)).toBe(false)

      const opWithMalformedDep = {
        ...opWithoutDep,
        dependsOnOperationId: 'invalid-uuid-format'
      }
      expect(validatePendingOperation(opWithMalformedDep)).toBe(false)
    })

    it('complete accepts a correct UUID dependency', async () => {
      const userId = 'test-user-123'
      const planId = 'plan-123'
      const itemId = 'item-1'
      const parentUuid = globalThis.crypto.randomUUID()
      
      const { operation } = await getOrCreatePendingOperation(
        userId, planId, itemId, 'complete',
        (opId) => ({
          operationId: opId,
          itemId,
          clientCompletedAt: '2026-07-06T20:30:00Z',
          deviceTimezone: 'Africa/Cairo',
          outcomeType: 'visited',
          outcomeNotes: null,
          endLat: null,
          endLng: null,
          endAccuracyM: null,
          orderId: null,
          collectionId: null,
          gpsExceptionReason: null,
          responses: []
        }),
        parentUuid
      )
      expect(operation.dependsOnOperationId).toBe(parentUuid)
      expect(validatePendingOperation(operation)).toBe(true)
    })

    it('complete rejects a dependency that is not a UUID before storing', async () => {
      const userId = 'test-user-123'
      const planId = 'plan-123'
      const itemId = 'item-1'
      const initialCount = await visitsDb.pendingVisitOperations.count()

      await expect(
        getOrCreatePendingOperation(
          userId, planId, itemId, 'complete',
          (opId) => ({
            operationId: opId,
            itemId,
            clientCompletedAt: '2026-07-06T20:30:00Z',
            deviceTimezone: 'Africa/Cairo',
            outcomeType: 'visited',
            outcomeNotes: null,
            endLat: null,
            endLng: null,
            endAccuracyM: null,
            orderId: null,
            collectionId: null,
            gpsExceptionReason: null,
            responses: []
          }),
          'not-a-valid-uuid'
        )
      ).rejects.toThrow(InvalidOperationDependencyError)

      const finalCount = await visitsDb.pendingVisitOperations.count()
      expect(finalCount).toBe(initialCount)
    })

    it('start rejects any dependency', async () => {
      const userId = 'test-user-123'
      const planId = 'plan-123'
      const itemId = 'item-1'
      const parentUuid = globalThis.crypto.randomUUID()
      const initialCount = await visitsDb.pendingVisitOperations.count()

      // Cast via unknown to test the runtime guard — overloads intentionally omit this param for start
      await expect(
        getOrCreateWithForbiddenDep(
          userId, planId, itemId, 'start',
          (opId) => ({
            operationId: opId,
            itemId,
            clientStartedAt: '2026-07-06T20:30:00Z',
            deviceTimezone: 'Africa/Cairo',
            startLat: null,
            startLng: null,
            startAccuracyM: null
          }),
          parentUuid
        )
      ).rejects.toThrow(InvalidOperationDependencyError)

      const finalCount = await visitsDb.pendingVisitOperations.count()
      expect(finalCount).toBe(initialCount)
    })

    it('skip rejects any dependency', async () => {
      const userId = 'test-user-123'
      const planId = 'plan-123'
      const itemId = 'item-1'
      const parentUuid = globalThis.crypto.randomUUID()
      const initialCount = await visitsDb.pendingVisitOperations.count()

      // Cast via unknown to test the runtime guard — overloads intentionally omit this param for skip
      await expect(
        getOrCreateWithForbiddenDep(
          userId, planId, itemId, 'skip',
          (opId) => ({
            operationId: opId,
            itemId,
            clientEventAt: '2026-07-06T20:30:00Z',
            deviceTimezone: 'Africa/Cairo',
            skipReason: 'محل مغلق'
          }),
          parentUuid
        )
      ).rejects.toThrow(InvalidOperationDependencyError)

      const finalCount = await visitsDb.pendingVisitOperations.count()
      expect(finalCount).toBe(initialCount)
    })

    it('self-dependency is rejected when passing same UUID', async () => {
      const userId = 'test-user-123'
      const planId = 'plan-123'
      const itemId = 'item-1'
      const fixedUuid = 'd3b07384-d113-4956-a5db-86b6a22f30b9'
      const initialCount = await visitsDb.pendingVisitOperations.count()

      const originalUUID = globalThis.crypto.randomUUID
      globalThis.crypto.randomUUID = () => fixedUuid as `${string}-${string}-${string}-${string}-${string}`

      try {
        await expect(
          getOrCreatePendingOperation(
            userId, planId, itemId, 'complete',
            (opId) => ({
              operationId: opId,
              itemId,
              clientCompletedAt: '2026-07-06T20:30:00Z',
              deviceTimezone: 'Africa/Cairo',
              outcomeType: 'visited',
              outcomeNotes: null,
              endLat: null,
              endLng: null,
              endAccuracyM: null,
              orderId: null,
              collectionId: null,
              gpsExceptionReason: null,
              responses: []
            }),
            fixedUuid
          )
        ).rejects.toThrow(InvalidOperationDependencyError)
      } finally {
        globalThis.crypto.randomUUID = originalUUID
      }

      const finalCount = await visitsDb.pendingVisitOperations.count()
      expect(finalCount).toBe(initialCount)
    })

    it('useVisitExecutionSession: complete operation dependency linking logic', async () => {
      const serverItems: VisitPlanItem[] = [
        { id: 'item-1', plan_id: 'plan-123', status: 'pending', customer_id: 'c-1', sequence: 1 } as unknown as VisitPlanItem
      ]

      const { result } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))
      await act(async () => {
        await new Promise(resolve => setTimeout(resolve, 50))
      })

      vi.mocked(startVisitItemAtomic).mockRejectedValueOnce(
        new VisitRpcTransportError('Connection issue', { message: 'Network offline', details: '', hint: '', code: '', name: 'PostgrestError' })
      )
      await act(async () => {
        await result.current.startVisit('item-1', null, null)
      })

      const startOp = await visitsDb.pendingVisitOperations
        .where('[userId+planId+itemId+kind]')
        .equals(['test-user-123', 'plan-123', 'item-1', 'start'])
        .first()
      expect(startOp).toBeDefined()
      expect(startOp?.state).toBe('retryable')

      vi.mocked(completeVisitItemAtomic).mockRejectedValueOnce(
        new VisitRpcTransportError('Connection issue', { message: 'Network offline', details: '', hint: '', code: '', name: 'PostgrestError' })
      )
      await act(async () => {
        await result.current.completeVisit(
          'item-1',
          null, null,
          'visited', 'notes',
          [], null, null, null
        )
      })

      const completeOp = await visitsDb.pendingVisitOperations
        .where('[userId+planId+itemId+kind]')
        .equals(['test-user-123', 'plan-123', 'item-1', 'complete'])
        .first()
      expect(completeOp).toBeDefined()
      expect(completeOp?.dependsOnOperationId).toBe(startOp?.operationId)

      const serverItems2: VisitPlanItem[] = [
        { id: 'item-2', plan_id: 'plan-123', status: 'pending', customer_id: 'c-2', sequence: 2 } as unknown as VisitPlanItem
      ]
      const { result: result2 } = renderHook(() => useVisitExecutionSession('plan-123', serverItems2, true))
      await act(async () => {
        await visitsDb.visitSessions.put({
          userId: 'test-user-123',
          planId: 'plan-123',
          itemId: 'item-2',
          serverStartedAt: null,
          clientStartedAt: new Date().toISOString(),
          startGPS: null,
          startGPSAccuracy: null,
          gpsValidationStatus: 'passed',
          checklistDrafts: {},
          gpsExceptionReason: null,
          updatedAt: Date.now(),
          expiresAt: Date.now() + 24 * 3600 * 1000
        })
        await new Promise(resolve => setTimeout(resolve, 50))
      })

      vi.mocked(completeVisitItemAtomic).mockRejectedValueOnce(
        new VisitRpcTransportError('Connection issue', { message: 'Network offline', details: '', hint: '', code: '', name: 'PostgrestError' })
      )
      await act(async () => {
        await result2.current.completeVisit(
          'item-2',
          null, null,
          'visited', 'notes',
          [], null, null, null
        )
      })

      const completeOp2 = await visitsDb.pendingVisitOperations
        .where('[userId+planId+itemId+kind]')
        .equals(['test-user-123', 'plan-123', 'item-2', 'complete'])
        .first()
      expect(completeOp2).toBeDefined()
      expect(completeOp2?.dependsOnOperationId).toBeUndefined()
    })

    it('useVisitExecutionSession: complete blocks sending and handles start outcome', async () => {
      const serverItems: VisitPlanItem[] = [
        { id: 'item-1', plan_id: 'plan-123', status: 'pending', customer_id: 'c-1', sequence: 1 } as unknown as VisitPlanItem
      ]

      const { result } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))
      await act(async () => {
        await new Promise(resolve => setTimeout(resolve, 50))
      })

      vi.mocked(startVisitItemAtomic).mockRejectedValueOnce(
        new VisitRpcTransportError('Connection issue', { message: 'Network offline', details: '', hint: '', code: '', name: 'PostgrestError' })
      )
      await act(async () => {
        await result.current.startVisit('item-1', null, null)
      })

      vi.mocked(completeVisitItemAtomic).mockClear()
      vi.mocked(startVisitItemAtomic).mockRejectedValueOnce(
        new VisitRpcTransportError('Connection issue', { message: 'Network offline', details: '', hint: '', code: '', name: 'PostgrestError' })
      )

      await act(async () => {
        await result.current.completeVisit(
          'item-1',
          null, null,
          'visited', 'notes',
          [], null, null, null
        )
      })
      expect(completeVisitItemAtomic).not.toHaveBeenCalled()

      const successStartResult: VisitRpcResult<StartVisitItemAtomicResult> = {
        ok: true,
        operation_id: 'op-123',
        operation: 'start_visit_item_atomic',
        replayed: false,
        data: {
          item_id: 'item-1',
          status: 'in_progress',
          server_started_at: '2026-07-06T20:30:00Z',
          start_distance_m: null,
          gps_validation_status: 'passed',
          plan_id: 'plan-123',
          plan_status: 'in_progress'
        }
      }
      vi.mocked(startVisitItemAtomic).mockResolvedValueOnce(successStartResult)

      const successCompleteResult: VisitRpcResult<CompleteVisitItemAtomicResult> = {
        ok: true,
        operation_id: 'op-456',
        operation: 'complete_visit_item_atomic',
        replayed: false,
        data: {
          item_id: 'item-1',
          status: 'completed',
          activity_id: null,
          gps_validation_status: 'passed',
          gps_review_status: 'not_required',
          plan_id: 'plan-123',
          plan_status: 'in_progress'
        }
      }
      vi.mocked(completeVisitItemAtomic).mockResolvedValueOnce(successCompleteResult)

      await act(async () => {
        await result.current.syncPendingOperations()
      })

      const ops = await visitsDb.pendingVisitOperations.toArray()
      expect(ops.length).toBe(0)
    })

    it('useVisitExecutionSession: dependency failure marks complete as DEPENDENCY_FAILED without deleting session/record', async () => {
      const serverItems: VisitPlanItem[] = [
        { id: 'item-1', plan_id: 'plan-123', status: 'pending', customer_id: 'c-1', sequence: 1 } as unknown as VisitPlanItem
      ]

      const { result } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))
      await act(async () => {
        await new Promise(resolve => setTimeout(resolve, 50))
      })

      vi.mocked(startVisitItemAtomic).mockRejectedValueOnce(
        new VisitRpcTransportError('Connection issue', { message: 'Network offline', details: '', hint: '', code: '', name: 'PostgrestError' })
      )
      await act(async () => {
        await result.current.startVisit('item-1', null, null)
      })

      await act(async () => {
        await result.current.completeVisit(
          'item-1',
          null, null,
          'visited', 'notes',
          [], null, null, null
        )
      })

      const errorResult: VisitRpcResult<StartVisitItemAtomicResult> = {
        ok: false,
        operation_id: 'op-error',
        operation: 'start_visit_item_atomic',
        replayed: false,
        error: {
          code: 'STATUS_CONFLICT',
          message: 'Conflict error'
        }
      }
      vi.mocked(startVisitItemAtomic).mockResolvedValueOnce(errorResult)

      await act(async () => {
        await result.current.syncPendingOperations()
      })

      const completeOp = await visitsDb.pendingVisitOperations
        .where('[userId+planId+itemId+kind]')
        .equals(['test-user-123', 'plan-123', 'item-1', 'complete'])
        .first()
      expect(completeOp).toBeDefined()
      expect(completeOp?.state).toBe('conflict')
      expect(completeOp?.lastErrorCode).toBe('DEPENDENCY_FAILED')

      const session = await visitsDb.visitSessions.get(['test-user-123', 'plan-123'])
      expect(session).toBeDefined()
    })

    it('useVisitExecutionSession: cross-scope parent validations', async () => {
      const itemId = 'item-1'
      const planId = 'plan-123'
      const userId = 'test-user-123'
      const now = Date.now()

      const serverItems = [
        { id: itemId, plan_id: planId, status: 'pending', customer_id: 'c-1', sequence: 1 } as unknown as VisitPlanItem
      ]

      const { result } = renderHook(() => useVisitExecutionSession(planId, serverItems, true))
      await act(async () => {
        await new Promise(resolve => setTimeout(resolve, 50))
      })

      // 1. Parent from another userId
      const parentIdUser = globalThis.crypto.randomUUID()
      await visitsDb.pendingVisitOperations.put({
        operationId: parentIdUser,
        userId: 'different-user',
        planId,
        itemId,
        kind: 'start',
        state: 'pending',
        attemptCount: 0,
        lastErrorCode: null,
        createdAt: now,
        updatedAt: now,
        expiresAt: now + 10000,
        payload: {
          operationId: parentIdUser,
          itemId,
          clientStartedAt: new Date().toISOString(),
          deviceTimezone: 'Africa/Cairo',
          startLat: null,
          startLng: null,
          startAccuracyM: null
        }
      })

      const childIdUser = globalThis.crypto.randomUUID()
      await visitsDb.pendingVisitOperations.put({
        operationId: childIdUser,
        userId,
        planId,
        itemId,
        kind: 'complete',
        state: 'pending',
        attemptCount: 0,
        lastErrorCode: null,
        createdAt: now + 10,
        updatedAt: now + 10,
        expiresAt: now + 10000,
        dependsOnOperationId: parentIdUser,
        payload: {
          operationId: childIdUser,
          itemId,
          clientCompletedAt: new Date().toISOString(),
          deviceTimezone: 'Africa/Cairo',
          outcomeType: 'visited',
          outcomeNotes: null,
          endLat: null,
          endLng: null,
          endAccuracyM: null,
          orderId: null,
          collectionId: null,
          gpsExceptionReason: null,
          responses: []
        }
      })

      vi.mocked(completeVisitItemAtomic).mockClear()
      await act(async () => {
        await result.current.syncPendingOperations()
      })

      expect(completeVisitItemAtomic).not.toHaveBeenCalled()
      const op1 = await visitsDb.pendingVisitOperations.get(childIdUser)
      expect(op1?.state).toBe('conflict')
      expect(op1?.lastErrorCode).toBe('INVALID_DEPENDENCY')

      await visitsDb.pendingVisitOperations.clear()

      // 2. Parent from another planId
      const parentIdPlan = globalThis.crypto.randomUUID()
      await visitsDb.pendingVisitOperations.put({
        operationId: parentIdPlan,
        userId,
        planId: 'different-plan',
        itemId,
        kind: 'start',
        state: 'pending',
        attemptCount: 0,
        lastErrorCode: null,
        createdAt: now,
        updatedAt: now,
        expiresAt: now + 10000,
        payload: {
          operationId: parentIdPlan,
          itemId,
          clientStartedAt: new Date().toISOString(),
          deviceTimezone: 'Africa/Cairo',
          startLat: null,
          startLng: null,
          startAccuracyM: null
        }
      })

      const childIdPlan = globalThis.crypto.randomUUID()
      await visitsDb.pendingVisitOperations.put({
        operationId: childIdPlan,
        userId,
        planId,
        itemId,
        kind: 'complete',
        state: 'pending',
        attemptCount: 0,
        lastErrorCode: null,
        createdAt: now + 10,
        updatedAt: now + 10,
        expiresAt: now + 10000,
        dependsOnOperationId: parentIdPlan,
        payload: {
          operationId: childIdPlan,
          itemId,
          clientCompletedAt: new Date().toISOString(),
          deviceTimezone: 'Africa/Cairo',
          outcomeType: 'visited',
          outcomeNotes: null,
          endLat: null,
          endLng: null,
          endAccuracyM: null,
          orderId: null,
          collectionId: null,
          gpsExceptionReason: null,
          responses: []
        }
      })

      await act(async () => {
        await result.current.syncPendingOperations()
      })

      expect(completeVisitItemAtomic).not.toHaveBeenCalled()
      const op2 = await visitsDb.pendingVisitOperations.get(childIdPlan)
      expect(op2?.state).toBe('conflict')
      expect(op2?.lastErrorCode).toBe('INVALID_DEPENDENCY')

      await visitsDb.pendingVisitOperations.clear()

      // 3. Parent from another itemId
      const parentIdItem = globalThis.crypto.randomUUID()
      await visitsDb.pendingVisitOperations.put({
        operationId: parentIdItem,
        userId,
        planId,
        itemId: 'different-item',
        kind: 'start',
        state: 'pending',
        attemptCount: 0,
        lastErrorCode: null,
        createdAt: now,
        updatedAt: now,
        expiresAt: now + 10000,
        payload: {
          operationId: parentIdItem,
          itemId: 'different-item',
          clientStartedAt: new Date().toISOString(),
          deviceTimezone: 'Africa/Cairo',
          startLat: null,
          startLng: null,
          startAccuracyM: null
        }
      })

      const childIdItem = globalThis.crypto.randomUUID()
      await visitsDb.pendingVisitOperations.put({
        operationId: childIdItem,
        userId,
        planId,
        itemId,
        kind: 'complete',
        state: 'pending',
        attemptCount: 0,
        lastErrorCode: null,
        createdAt: now + 10,
        updatedAt: now + 10,
        expiresAt: now + 10000,
        dependsOnOperationId: parentIdItem,
        payload: {
          operationId: childIdItem,
          itemId,
          clientCompletedAt: new Date().toISOString(),
          deviceTimezone: 'Africa/Cairo',
          outcomeType: 'visited',
          outcomeNotes: null,
          endLat: null,
          endLng: null,
          endAccuracyM: null,
          orderId: null,
          collectionId: null,
          gpsExceptionReason: null,
          responses: []
        }
      })

      await act(async () => {
        await result.current.syncPendingOperations()
      })

      expect(completeVisitItemAtomic).not.toHaveBeenCalled()
      const op3 = await visitsDb.pendingVisitOperations.get(childIdItem)
      expect(op3?.state).toBe('conflict')
      expect(op3?.lastErrorCode).toBe('INVALID_DEPENDENCY')

      await visitsDb.pendingVisitOperations.clear()

      // 4. Parent kind is not start
      const parentIdSkip = globalThis.crypto.randomUUID()
      await visitsDb.pendingVisitOperations.put({
        operationId: parentIdSkip,
        userId,
        planId,
        itemId,
        kind: 'skip',
        state: 'pending',
        attemptCount: 0,
        lastErrorCode: null,
        createdAt: now,
        updatedAt: now,
        expiresAt: now + 10000,
        payload: {
          operationId: parentIdSkip,
          itemId,
          clientEventAt: new Date().toISOString(),
          deviceTimezone: 'Africa/Cairo',
          skipReason: 'محل مغلق'
        }
      })

      const childIdSkip = globalThis.crypto.randomUUID()
      await visitsDb.pendingVisitOperations.put({
        operationId: childIdSkip,
        userId,
        planId,
        itemId,
        kind: 'complete',
        state: 'pending',
        attemptCount: 0,
        lastErrorCode: null,
        createdAt: now + 10,
        updatedAt: now + 10,
        expiresAt: now + 10000,
        dependsOnOperationId: parentIdSkip,
        payload: {
          operationId: childIdSkip,
          itemId,
          clientCompletedAt: new Date().toISOString(),
          deviceTimezone: 'Africa/Cairo',
          outcomeType: 'visited',
          outcomeNotes: null,
          endLat: null,
          endLng: null,
          endAccuracyM: null,
          orderId: null,
          collectionId: null,
          gpsExceptionReason: null,
          responses: []
        }
      })

      await act(async () => {
        await result.current.syncPendingOperations()
      })

      expect(completeVisitItemAtomic).not.toHaveBeenCalled()
      const op4 = await visitsDb.pendingVisitOperations.get(childIdSkip)
      expect(op4?.state).toBe('conflict')
      expect(op4?.lastErrorCode).toBe('INVALID_DEPENDENCY')

      await visitsDb.pendingVisitOperations.clear()

      // 5. Valid UUID but not found in IndexedDB -> allows complete RPC to proceed
      const nonExistentUuid = globalThis.crypto.randomUUID()
      const childIdOrphan = globalThis.crypto.randomUUID()
      await visitsDb.pendingVisitOperations.put({
        operationId: childIdOrphan,
        userId,
        planId,
        itemId,
        kind: 'complete',
        state: 'pending',
        attemptCount: 0,
        lastErrorCode: null,
        createdAt: now,
        updatedAt: now,
        expiresAt: now + 10000,
        dependsOnOperationId: nonExistentUuid,
        payload: {
          operationId: childIdOrphan,
          itemId,
          clientCompletedAt: new Date().toISOString(),
          deviceTimezone: 'Africa/Cairo',
          outcomeType: 'visited',
          outcomeNotes: null,
          endLat: null,
          endLng: null,
          endAccuracyM: null,
          orderId: null,
          collectionId: null,
          gpsExceptionReason: null,
          responses: []
        }
      })

      const successCompleteResult: VisitRpcResult<CompleteVisitItemAtomicResult> = {
        ok: true,
        operation_id: childIdOrphan,
        operation: 'complete_visit_item_atomic',
        replayed: false,
        data: {
          item_id: itemId,
          status: 'completed',
          activity_id: null,
          gps_validation_status: 'passed',
          gps_review_status: 'not_required',
          plan_id: planId,
          plan_status: 'in_progress'
        }
      }
      vi.mocked(completeVisitItemAtomic).mockResolvedValueOnce(successCompleteResult)

      await act(async () => {
        await result.current.syncPendingOperations()
      })

      expect(completeVisitItemAtomic).toHaveBeenCalled()
      const op5 = await visitsDb.pendingVisitOperations.get(childIdOrphan)
      expect(op5).toBeUndefined()

      await visitsDb.pendingVisitOperations.clear()

      // 6. Malformed dependency ID saved historically -> processed as CORRUPTED_PAYLOAD and no RPC
      const childIdCorrupted = globalThis.crypto.randomUUID()
      await visitsDb.pendingVisitOperations.put({
        operationId: childIdCorrupted,
        userId,
        planId,
        itemId,
        kind: 'complete',
        state: 'pending',
        attemptCount: 0,
        lastErrorCode: null,
        createdAt: now,
        updatedAt: now,
        expiresAt: now + 10000,
        dependsOnOperationId: 'invalid-non-uuid-format',
        payload: {
          operationId: childIdCorrupted,
          itemId,
          clientCompletedAt: new Date().toISOString(),
          deviceTimezone: 'Africa/Cairo',
          outcomeType: 'visited',
          outcomeNotes: null,
          endLat: null,
          endLng: null,
          endAccuracyM: null,
          orderId: null,
          collectionId: null,
          gpsExceptionReason: null,
          responses: []
        }
      })

      vi.mocked(completeVisitItemAtomic).mockClear()
      await act(async () => {
        await result.current.syncPendingOperations()
      })

      expect(completeVisitItemAtomic).not.toHaveBeenCalled()
      const op6 = await visitsDb.pendingVisitOperations.get(childIdCorrupted)
      expect(op6?.state).toBe('conflict')
      expect(op6?.lastErrorCode).toBe('CORRUPTED_PAYLOAD')
    })

    it('useVisitExecutionSession: session and operations retention checks', async () => {
      const itemId = 'item-1'
      const planId = 'plan-123'
      const userId = 'test-user-123'
      const now = Date.now()

      const serverItems = [
        { id: itemId, plan_id: planId, status: 'pending', customer_id: 'c-1', sequence: 1 } as unknown as VisitPlanItem
      ]

      const { result } = renderHook(() => useVisitExecutionSession(planId, serverItems, true))
      await act(async () => {
        await new Promise(resolve => setTimeout(resolve, 50))
      })

      await visitsDb.visitSessions.put({
        userId,
        planId,
        itemId,
        clientStartedAt: new Date().toISOString(),
        updatedAt: now,
        expiresAt: now + 3600000,
        gpsValidationStatus: 'not_checked',
        checklistDrafts: {},
        gpsExceptionReason: null,
        serverStartedAt: null,
        startGPS: null,
        startGPSAccuracy: null
      })

      vi.mocked(startVisitItemAtomic).mockRejectedValueOnce(
        new VisitRpcTransportError('Connection issue', { message: 'Network offline', details: '', hint: '', code: '', name: 'PostgrestError' })
      )
      
      const startOpId = globalThis.crypto.randomUUID()
      await visitsDb.pendingVisitOperations.put({
        operationId: startOpId,
        userId,
        planId,
        itemId,
        kind: 'start',
        state: 'pending',
        attemptCount: 0,
        lastErrorCode: null,
        createdAt: now,
        updatedAt: now,
        expiresAt: now + 10000,
        payload: {
          operationId: startOpId,
          itemId,
          clientStartedAt: new Date().toISOString(),
          deviceTimezone: 'Africa/Cairo',
          startLat: null,
          startLng: null,
          startAccuracyM: null
        }
      })

      await act(async () => {
        await result.current.syncPendingOperations()
      })

      let session = await visitsDb.visitSessions.get([userId, planId])
      expect(session).toBeDefined()

      await visitsDb.pendingVisitOperations.put({
        operationId: startOpId,
        userId,
        planId,
        itemId,
        kind: 'start',
        state: 'conflict',
        attemptCount: 1,
        lastErrorCode: 'STATUS_CONFLICT',
        createdAt: now,
        updatedAt: now,
        expiresAt: now + 10000,
        payload: {
          operationId: startOpId,
          itemId,
          clientStartedAt: new Date().toISOString(),
          deviceTimezone: 'Africa/Cairo',
          startLat: null,
          startLng: null,
          startAccuracyM: null
        }
      })

      const completeOpId = globalThis.crypto.randomUUID()
      await visitsDb.pendingVisitOperations.put({
        operationId: completeOpId,
        userId,
        planId,
        itemId,
        kind: 'complete',
        state: 'pending',
        attemptCount: 0,
        lastErrorCode: null,
        createdAt: now + 10,
        updatedAt: now + 10,
        expiresAt: now + 10000,
        dependsOnOperationId: startOpId,
        payload: {
          operationId: completeOpId,
          itemId,
          clientCompletedAt: new Date().toISOString(),
          deviceTimezone: 'Africa/Cairo',
          outcomeType: 'visited',
          outcomeNotes: null,
          endLat: null,
          endLng: null,
          endAccuracyM: null,
          orderId: null,
          collectionId: null,
          gpsExceptionReason: null,
          responses: []
        }
      })

      await act(async () => {
        await result.current.syncPendingOperations()
      })

      session = await visitsDb.visitSessions.get([userId, planId])
      expect(session).toBeDefined()

      let completeOp = await visitsDb.pendingVisitOperations.get(completeOpId)
      expect(completeOp).toBeDefined()
      expect(completeOp?.state).toBe('conflict')
      expect(completeOp?.lastErrorCode).toBe('DEPENDENCY_FAILED')

      const parentIdWrongItem = globalThis.crypto.randomUUID()
      await visitsDb.pendingVisitOperations.put({
        operationId: parentIdWrongItem,
        userId,
        planId,
        itemId: 'wrong-item-id',
        kind: 'start',
        state: 'pending',
        attemptCount: 0,
        lastErrorCode: null,
        createdAt: now,
        updatedAt: now,
        expiresAt: now + 10000,
        payload: {
          operationId: parentIdWrongItem,
          itemId: 'wrong-item-id',
          clientStartedAt: new Date().toISOString(),
          deviceTimezone: 'Africa/Cairo',
          startLat: null,
          startLng: null,
          startAccuracyM: null
        }
      })

      await visitsDb.pendingVisitOperations.put({
        operationId: completeOpId,
        userId,
        planId,
        itemId,
        kind: 'complete',
        state: 'pending',
        attemptCount: 0,
        lastErrorCode: null,
        createdAt: now + 10,
        updatedAt: now + 10,
        expiresAt: now + 10000,
        dependsOnOperationId: parentIdWrongItem,
        payload: {
          operationId: completeOpId,
          itemId,
          clientCompletedAt: new Date().toISOString(),
          deviceTimezone: 'Africa/Cairo',
          outcomeType: 'visited',
          outcomeNotes: null,
          endLat: null,
          endLng: null,
          endAccuracyM: null,
          orderId: null,
          collectionId: null,
          gpsExceptionReason: null,
          responses: []
        }
      })

      await act(async () => {
        await result.current.syncPendingOperations()
      })

      session = await visitsDb.visitSessions.get([userId, planId])
      expect(session).toBeDefined()

      completeOp = await visitsDb.pendingVisitOperations.get(completeOpId)
      expect(completeOp).toBeDefined()
      expect(completeOp?.state).toBe('conflict')
      expect(completeOp?.lastErrorCode).toBe('INVALID_DEPENDENCY')
    })

    it('useVisitExecutionSession: syncPromiseRef single-flight protection and exceptions lock release', async () => {
      const serverItems: VisitPlanItem[] = [
        { id: 'item-1', plan_id: 'plan-123', status: 'pending', customer_id: 'c-1', sequence: 1 } as unknown as VisitPlanItem
      ]

      const { result } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))
      await act(async () => {
        await new Promise(resolve => setTimeout(resolve, 50))
      })

      // Verify single-flight: two concurrent calls must return the exact same Promise
      const p1 = result.current.syncPendingOperations()
      const p2 = result.current.syncPendingOperations()
      expect(p1).toBe(p2)

      await act(async () => {
        await p1
      })

      // Verify that a real exception releases syncPromiseRef (finally block)
      // Close the DB to force a genuine Dexie error in the next sync
      visitsDb.close()

      let throwErr: Error | null = null
      try {
        await result.current.syncPendingOperations()
      } catch (err: unknown) {
        if (err instanceof Error) {
          throwErr = err
        }
      } finally {
        // Always reopen so subsequent tests/cleanup can access the DB
        await visitsDb.open()
      }

      // The closed-DB must have produced an error that propagated out
      expect(throwErr).toBeDefined()

      // After the exception the lock must have been released:
      // a fresh call must return a NEW promise, not the stale rejected one
      const p3 = result.current.syncPendingOperations()
      expect(p3).not.toBe(p1)

      await act(async () => {
        await p3
      })
    })

    it('useVisitExecutionSession: Offline integration test (start retryable keeps session, permits draft, blocks complete RPC)', async () => {
      const serverItems: VisitPlanItem[] = [
        { id: 'item-1', plan_id: 'plan-123', status: 'pending', customer_id: 'c-1', sequence: 1 } as unknown as VisitPlanItem
      ]

      const { result, unmount } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))
      await act(async () => {
        await new Promise(resolve => setTimeout(resolve, 50))
      })

      // 1. start RPC fails with transport/connection issue
      vi.mocked(startVisitItemAtomic).mockRejectedValue(
        new VisitRpcTransportError('Connection issue', { message: 'Network offline', details: '', hint: '', code: '', name: 'PostgrestError' })
      )

      await act(async () => {
        await result.current.startVisit('item-1', null, null)
      })

      // 2. start operation is now in 'retryable' state
      const startOp = await visitsDb.pendingVisitOperations
        .where('[userId+planId+itemId+kind]')
        .equals(['test-user-123', 'plan-123', 'item-1', 'start'])
        .first()
      expect(startOp).toBeDefined()
      expect(startOp?.state).toBe('retryable')

      // 3. React session state is still retained
      expect(result.current.session).not.toBeNull()
      expect(result.current.session?.itemId).toBe('item-1')

      // 4. Checklist draft can be successfully written/updated in the retained session
      const mockResponses: ChecklistResponseInput[] = [
        { template_id: 't-1', question_id: 'q-scalar', answer_value: 'draft-answer' } as unknown as ChecklistResponseInput
      ]
      await act(async () => {
        await result.current.saveChecklistDraft('t-1', mockResponses, mockQuestions, false)
      })

      expect(result.current.session?.checklistDrafts['t-1']?.responses[0].answer_value).toBe('draft-answer')

      // 5. Unmount and remount/reload the session while start is still retryable on a pending server item
      unmount()

      const { result: newResult } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))
      await act(async () => {
        await new Promise(resolve => setTimeout(resolve, 50))
      })

      // Session must be restored upon reload
      expect(newResult.current.session).not.toBeNull()
      expect(newResult.current.session?.itemId).toBe('item-1')

      // 6. Complete visit gets dependsOnOperationId of the start operation, and complete RPC is blocked
      // completeVisit should trigger complete operation creation and queue sync
      vi.mocked(completeVisitItemAtomic).mockResolvedValueOnce({
        ok: true,
        operation_id: 'op-comp-123',
        operation: 'complete_visit_item_atomic',
        replayed: false,
        data: {
          item_id: 'item-1',
          status: 'completed',
          activity_id: null,
          gps_validation_status: 'passed',
          gps_review_status: 'not_required',
          plan_id: 'plan-123',
          plan_status: 'in_progress'
        }
      })

      await act(async () => {
        await newResult.current.completeVisit('item-1', null, null, 'visited', 'Done offline', [], null, null, null)
      })

      // Verify the complete operation carries the dependency
      const compOp = await visitsDb.pendingVisitOperations
        .where('[userId+planId+itemId+kind]')
        .equals(['test-user-123', 'plan-123', 'item-1', 'complete'])
        .first()
      expect(compOp).toBeDefined()
      expect(compOp?.dependsOnOperationId).toBe(startOp?.operationId)

      // Since parent startOp is still 'retryable', the complete RPC must NOT have been called
      expect(completeVisitItemAtomic).not.toHaveBeenCalled()
      // complete operation remains pending/retryable
      expect(compOp?.state).toBe('pending')
    })

    it('useVisitExecutionSession: Terminal start failure hides session from React state but preserves database record', async () => {
      const serverItems: VisitPlanItem[] = [
        { id: 'item-1', plan_id: 'plan-123', status: 'pending', customer_id: 'c-1', sequence: 1 } as unknown as VisitPlanItem
      ]

      const { result, unmount } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))
      await act(async () => {
        await new Promise(resolve => setTimeout(resolve, 50))
      })

      // Mock terminal failure for start (e.g. SYNC_CONFLICT)
      vi.mocked(startVisitItemAtomic).mockResolvedValueOnce({
        ok: false,
        operation_id: 'op-failed-start-123',
        operation: 'start_visit_item_atomic',
        replayed: false,
        error: { code: 'SYNC_CONFLICT', message: 'Database Conflict' }
      })

      await act(async () => {
        await result.current.startVisit('item-1', null, null)
      })

      // 1. Start operation state is terminal failure (conflict)
      const startOp = await visitsDb.pendingVisitOperations
        .where('[userId+planId+itemId+kind]')
        .equals(['test-user-123', 'plan-123', 'item-1', 'start'])
        .first()
      expect(startOp).toBeDefined()
      expect(startOp?.state).toBe('conflict')

      // 2. React session state is null to prevent continued invalid execution
      expect(result.current.session).toBeNull()

      // 3. Database session is preserved (not deleted)
      const dbSession = await visitsDb.visitSessions.get(['test-user-123', 'plan-123'])
      expect(dbSession).toBeDefined()
      expect(dbSession?.itemId).toBe('item-1')

      // 4. Updating operation state back to retryable (admin intervention) and reloading restores the session
      if (startOp) {
        await visitsDb.pendingVisitOperations.update(startOp.operationId, { state: 'retryable' })
      }

      unmount()

      const { result: restoredResult } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))
      await act(async () => {
        await new Promise(resolve => setTimeout(resolve, 50))
      })

      expect(restoredResult.current.session).not.toBeNull()
      expect(restoredResult.current.session?.itemId).toBe('item-1')
    })

    it('useVisitExecutionSession: local photos, replacement, remount restore, and complete Visit safety gate', async () => {
      const serverItems: VisitPlanItem[] = [
        { id: 'item-1', plan_id: 'plan-123', status: 'pending', customer_id: 'c-1', sequence: 1 } as unknown as VisitPlanItem
      ]

      const { result, unmount } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))
      await act(async () => {
        await new Promise(resolve => setTimeout(resolve, 50))
      })

      // Start the visit (Offline/Transport failure keeps local session active)
      vi.mocked(startVisitItemAtomic).mockRejectedValueOnce(
        new VisitRpcTransportError('Connection issue', { message: 'Network offline', details: '', hint: '', code: '', name: 'PostgrestError' })
      )

      await act(async () => {
        await result.current.startVisit('item-1', null, null)
      })

      expect(result.current.session).not.toBeNull()

      const newBlob = new Blob(['newblobcontent'], { type: 'image/jpeg' })
      const userId = 'test-user-123'
      const planId = 'plan-123'
      const itemId = 'item-1'
      const templateId = 't-1'
      const questionId = 'q-photo'

      // 1. Integration: saveLocalPhoto saves Blob to DB and updates draft
      let firstBlobId = ''
      await act(async () => {
        const captureRes = await result.current.saveLocalPhoto(
          templateId,
          questionId,
          newBlob,
          { mimeType: 'image/jpeg', extension: 'jpg', checksum: 'a'.repeat(64) }
        )
        firstBlobId = captureRes.local_blob_id
      })

      expect(firstBlobId).toBeDefined()

      // 2. Integration: localBlobId matches the end of objectPath (without question prefix)
      const recordDirect = await visitsDb.localBlobs.get(firstBlobId)
      expect(recordDirect?.objectPath).toBe(`plans/plan-123/items/item-1/${firstBlobId}.jpg`)
      expect(recordDirect?.sizeBytes).toBe(14) // size of 'newblobcontent'

      // Check draft saves { local_blob_id } correctly
      const draftResponses = result.current.session?.checklistDrafts[templateId]?.responses
      expect(draftResponses).toBeDefined()
      expect(draftResponses?.[0].answer_json).toEqual({
        local_blob_id: firstBlobId
      })

      // Unmount hook (simulate page refresh/app close)
      unmount()

      // 3. Integration: remount restores the preview
      const { result: restoredResult } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))
      await act(async () => {
        await new Promise(resolve => setTimeout(resolve, 200))
      })

      expect(restoredResult.current.session).not.toBeNull()
      const restoredDraft = restoredResult.current.session?.checklistDrafts[templateId]?.responses
      expect(restoredDraft?.[0].answer_json).toEqual({
        local_blob_id: firstBlobId
      })

      // Verify loadLocalPhoto can fetch the blob
      const loadedBlob = await restoredResult.current.loadLocalPhoto(firstBlobId)
      expect(loadedBlob).toBeDefined()

      // 4. Integration: Orphaned local blob in database does NOT block completeVisit
      // Add an orphan blob record that belongs to this item but is NOT referenced in drafts
      const orphanBlobId = globalThis.crypto.randomUUID()
      await visitsDb.localBlobs.add({
        localBlobId: orphanBlobId,
        userId,
        planId,
        itemId,
        templateId,
        questionId: 'q-other',
        objectPath: '...',
        mimeType: 'image/jpeg',
        extension: 'jpg',
        sizeBytes: 100,
        checksum: 'b'.repeat(64),
        uploadState: 'pending',
        attemptCount: 0,
        lastErrorCode: null,
        nextRetryAt: null,
        blob: new Blob(['orphan']),
        createdAt: Date.now(),
        updatedAt: Date.now(),
        expiresAt: Date.now() + 24 * 3600 * 1000
      })

      // 5. Gating check: completeVisit is blocked with LOCAL_PHOTOS_PENDING_UPLOAD because draft references firstBlobId
      const validatedResponses = [
        {
          template_id: templateId,
          question_id: questionId,
          answer_value: null,
          answer_json: { local_blob_id: firstBlobId }
        }
      ]

      // A: Verify block on 'pending' uploadState
      let completeOutcome: unknown
      await act(async () => {
        completeOutcome = await restoredResult.current.completeVisit(
          'item-1',
          null,
          null,
          'visited',
          'Done with local photo',
          validatedResponses as unknown as VisitCompletionChecklistResponseInput[],
          null,
          null,
          null
        )
      })

      const outcome1 = completeOutcome as { ok: boolean; errorCode: string }
      expect(outcome1.ok).toBe(false)
      expect(outcome1.errorCode).toBe('LOCAL_PHOTOS_PENDING_UPLOAD')
      expect(completeVisitItemAtomic).not.toHaveBeenCalled()

      // B: Verify block on 'failed' uploadState
      await visitsDb.localBlobs.update(firstBlobId, { uploadState: 'failed' })
      let completeOutcomeFailed: unknown
      await act(async () => {
        completeOutcomeFailed = await restoredResult.current.completeVisit(
          'item-1',
          null,
          null,
          'visited',
          'Done with local photo',
          validatedResponses as unknown as VisitCompletionChecklistResponseInput[],
          null,
          null,
          null
        )
      })
      const outcomeFailed = completeOutcomeFailed as { ok: boolean; errorCode: string }
      expect(outcomeFailed.ok).toBe(false)
      expect(outcomeFailed.errorCode).toBe('LOCAL_PHOTOS_PENDING_UPLOAD')

      // C: Verify block on 'uploaded' uploadState (gating blocks as long as reference remains local in Phase 1A)
      await visitsDb.localBlobs.update(firstBlobId, { uploadState: 'uploaded' })
      let completeOutcomeUploaded: unknown
      await act(async () => {
        completeOutcomeUploaded = await restoredResult.current.completeVisit(
          'item-1',
          null,
          null,
          'visited',
          'Done with local photo',
          validatedResponses as unknown as VisitCompletionChecklistResponseInput[],
          null,
          null,
          null
        )
      })
      const outcomeUploaded = completeOutcomeUploaded as { ok: boolean; errorCode: string }
      expect(outcomeUploaded.ok).toBe(false)
      expect(outcomeUploaded.errorCode).toBe('LOCAL_PHOTOS_PENDING_UPLOAD')

      // Restore uploadState to check missing blob next
      await visitsDb.localBlobs.update(firstBlobId, { uploadState: 'pending' })

      // D: Verify priority order: draft references two images - one exists, one is missing -> returns LOCAL_PHOTO_MISSING
      const missingBlobId = globalThis.crypto.randomUUID()
      const mixedResponses = [
        {
          template_id: templateId,
          question_id: questionId,
          answer_value: null,
          answer_json: { local_blob_id: firstBlobId }
        },
        {
          template_id: templateId,
          question_id: 'q-photo-2',
          answer_value: null,
          answer_json: { local_blob_id: missingBlobId }
        }
      ]

      let completeOutcomeMixed: unknown
      await act(async () => {
        completeOutcomeMixed = await restoredResult.current.completeVisit(
          'item-1',
          null,
          null,
          'visited',
          'Done with mixed local photos',
          mixedResponses as unknown as VisitCompletionChecklistResponseInput[],
          null,
          null,
          null
        )
      })
      const outcomeMixed = completeOutcomeMixed as { ok: boolean; errorCode: string }
      expect(outcomeMixed.ok).toBe(false)
      expect(outcomeMixed.errorCode).toBe('LOCAL_PHOTO_MISSING')
      expect(completeVisitItemAtomic).not.toHaveBeenCalled()

      // 6. Integration: missing local blob returns LOCAL_PHOTO_MISSING
      // Delete the referenced blob from localBlobs database
      await visitsDb.localBlobs.delete(firstBlobId)

      let completeOutcome2: unknown
      await act(async () => {
        completeOutcome2 = await restoredResult.current.completeVisit(
          'item-1',
          null,
          null,
          'visited',
          'Done with local photo',
          validatedResponses as unknown as VisitCompletionChecklistResponseInput[],
          null,
          null,
          null
        )
      })

      const outcome2 = completeOutcome2 as { ok: boolean; errorCode: string }
      expect(outcome2.ok).toBe(false)
      expect(outcome2.errorCode).toBe('LOCAL_PHOTO_MISSING')

      // 7. Verify no complete operation is created in pending queue for either failure
      const compOp = await visitsDb.pendingVisitOperations
        .where('[userId+planId+itemId+kind]')
        .equals([userId, planId, itemId, 'complete'])
        .first()
      expect(compOp).toBeUndefined()
    })

    it('useVisitExecutionSession: successful upload sync updates active session state, removes safety gate, and allows completion', async () => {
      const serverItems: VisitPlanItem[] = [
        { id: 'item-1', plan_id: 'plan-123', status: 'pending', customer_id: 'c-1', sequence: 1 } as unknown as VisitPlanItem
      ]

      const { result } = renderHook(() => useVisitExecutionSession('plan-123', serverItems, true))
      await act(async () => {
        await new Promise(resolve => setTimeout(resolve, 50))
      })

      // Start visit
      vi.mocked(startVisitItemAtomic).mockResolvedValueOnce({
        ok: true,
        operation_id: 'op-start-123',
        operation: 'start_visit_item',
        replayed: false,
        data: {
          item_id: 'item-1',
          plan_id: 'plan-123',
          status: 'in_progress',
          server_started_at: new Date().toISOString(),
          gps_validation_status: 'passed',
          start_distance_m: 5,
          plan_status: 'in_progress'
        }
      } as unknown as VisitRpcResult<StartVisitItemAtomicResult>)
      await act(async () => {
        await result.current.startVisit('item-1', null, null)
        serverItems[0].status = 'in_progress'
      })

      await waitFor(() => expect(result.current.session).not.toBeNull())

      // Capture a local photo
      const templateId = 't-1'
      const questionId = 'q-photo'
      let localBlobId = ''

      await act(async () => {
        const captureRes = await result.current.saveLocalPhoto(
          templateId,
          questionId,
          new Blob(['image_contents'], { type: 'image/jpeg' }),
          { mimeType: 'image/jpeg', extension: 'jpg', checksum: 'd'.repeat(64) }
        )
        localBlobId = captureRes.local_blob_id
      })

      // Safety gate should initially block completion
      let initialComplete: any
      await act(async () => {
        initialComplete = await result.current.completeVisit(
          'item-1',
          null, null,
          'visited', 'notes',
          [], null, null, null
        )
      })
      expect(initialComplete.ok).toBe(false)
      expect(initialComplete.errorCode).toBe('LOCAL_PHOTOS_PENDING_UPLOAD')

      // Mock successful storage sync trigger
      await act(async () => {
        // 1. Update draft session references in IndexedDB
        const session = await visitsDb.visitSessions.get(['test-user-123', 'plan-123'])
        if (session) {
          session.checklistDrafts[templateId].responses[0].answer_json = {
            storage_path: `plans/plan-123/items/item-1/${localBlobId}.jpg` as VisitStoragePath
          }
          await visitsDb.visitSessions.put(session)
        }
        // 2. Mark local blob as uploaded
        await visitsDb.localBlobs.update(localBlobId, { uploadState: 'uploaded' })
        
        // 3. Trigger subscription notifying the hook to reload
        await result.current.reloadFromDb()
      })

      // Expect React session state to update and convert local_blob_id to storage_path
      const updatedResponse = result.current.session?.checklistDrafts[templateId]?.responses[0]
      expect(updatedResponse?.answer_json).toEqual({
        storage_path: `plans/plan-123/items/item-1/${localBlobId}.jpg`
      })

      // Gating barrier is removed, completeVisit should now succeed in creating complete operation (no LOCAL_PHOTOS_PENDING_UPLOAD error)
      vi.mocked(completeVisitItemAtomic).mockRejectedValueOnce(
        new VisitRpcTransportError('Connection issue', { message: 'Network offline', details: '', hint: '', code: '', name: 'PostgrestError' })
      )
      let finalComplete: any
      await act(async () => {
        finalComplete = await result.current.completeVisit(
          'item-1',
          null, null,
          'visited', 'notes',
          [], null, null, null
        )
      })
      expect(finalComplete.ok).toBe(false)
      expect(finalComplete.errorCode).toBe('CONNECTION_ERROR') // Passes local gate, reaches atomic transport

      const compOp = await visitsDb.pendingVisitOperations
        .where('[userId+planId+itemId+kind]')
        .equals(['test-user-123', 'plan-123', 'item-1', 'complete'])
        .first()
      expect(compOp).toBeDefined()
    })
  })
})

