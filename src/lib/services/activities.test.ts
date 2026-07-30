import { describe, it, expect, vi, beforeEach, expectTypeOf } from 'vitest'
import { supabase } from '@/lib/supabase/client'
import {
  isRetryableVisitErrorCode,
  validateVisitStoragePath,
  isPhotoResponse,
  VisitRpcTransportError,
  createVisitPlanAtomic,
  confirmVisitPlanAtomic,
  cancelVisitPlanAtomic,
  reorderVisitPlanItemsAtomic,
  closeVisitPlanAdministrativelyAtomic,
  startVisitItemAtomic,
  completeVisitItemAtomic,
  skipVisitItemAtomic,
  rescheduleVisitItemAtomic,
  createActivity
} from './activities'
import type {
  PlanStatus,
  PlanItemStatus,
  VisitOutcomeType,
  VisitStoragePath,
  PhotoResponse,
  CreateVisitPlanAtomicResult,
  ConfirmVisitPlanAtomicResult,
  CancelVisitPlanAtomicResult,
  CloseVisitPlanAdministrativelyAtomicResult,
  StartVisitItemAtomicResult,
  CompleteVisitItemAtomicResult,
  SkipVisitItemAtomicResult,
  RescheduleVisitItemAtomicResult,
  ActivityInput
} from '@/lib/types/activities'

vi.mock('@/lib/services/_get-user-id', () => ({
  getAuthUserId: vi.fn().mockResolvedValue('user-123')
}))

vi.mock('@/lib/supabase/client', () => ({
  supabase: {
    rpc: vi.fn(),
    from: vi.fn(() => ({
      select: vi.fn(() => ({
        eq: vi.fn(() => ({
          maybeSingle: vi.fn().mockResolvedValue({ data: { id: 'emp-123' } })
        }))
      }))
    }))
  }
}))

describe('Visits Atomic RPC Services', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  describe('isRetryableVisitErrorCode Helper', () => {
    it('identifies RETRYABLE_ERROR correctly', () => {
      expect(isRetryableVisitErrorCode('RETRYABLE_ERROR')).toBe(true)
      expect(isRetryableVisitErrorCode('DOMAIN_VALIDATION_FAILED')).toBe(false)
      expect(isRetryableVisitErrorCode('INTERNAL_ERROR')).toBe(false)
    })
  })

  describe('validateVisitStoragePath Runtime Validator', () => {
    it('passes safe and valid photo paths', () => {
      const validPaths = [
        'reps/123/2026-07/photo_456.jpg',
        'my-folder/sub_folder/file-name.png',
        'just_a_filename.jpg',
        'folder1/folder2/file'
      ]
      for (const p of validPaths) {
        expect(() => validateVisitStoragePath(p)).not.toThrow()
      }
    })

    it('throws error for path exceeding 2048 characters', () => {
      const longPath = 'a/'.repeat(1025) + 'test.jpg'
      expect(() => validateVisitStoragePath(longPath)).toThrow('مسار تخزين الصورة طويل جداً')
    })

    it('throws error for unsafe characters and traversal patterns', () => {
      const invalidPaths = [
        'reps\\123\\photo.jpg',
        'reps/123/photo.jpg?query=1',
        'reps/123/photo.jpg%20',
        'reps/123//photo.jpg',
        '/reps/123/photo.jpg',
        '.reps/123/photo.jpg',
        'reps/./photo.jpg',
        'reps/../photo.jpg',
        'reps/123/photo.jpg#hash',
        'reps/123/phóto.jpg'
      ]
      for (const p of invalidPaths) {
        expect(() => validateVisitStoragePath(p)).toThrow('مسار تخزين الصورة غير صالح أو غير آمن')
      }
    })
  })

  describe('isPhotoResponse Type Guard', () => {
    it('identifies photo response inputs correctly', () => {
      expect(isPhotoResponse({
        template_id: 't-1',
        question_id: 'q-1',
        answer_json: { storage_path: validateVisitStoragePath('reps/123/file.jpg') }
      })).toBe(true)

      expect(isPhotoResponse({
        template_id: 't-1',
        question_id: 'q-1',
        answer_value: 'test'
      })).toBe(false)
    })

    it('throws error when storage_path is present but is not a string', () => {
      const badResponse = {
        template_id: 't-1',
        question_id: 'q-1',
        answer_json: { storage_path: 123 as unknown as VisitStoragePath }
      }
      expect(() => isPhotoResponse(badResponse)).toThrow('مسار تخزين الصورة غير صالح أو غير آمن')
    })

    it('throws error when storage_path is not owned directly by the record (e.g. inherited from prototype)', () => {
      const protoObj = { storage_path: 'reps/123/file.jpg' }
      const inheritedObj = Object.create(protoObj)
      const badResponse = {
        template_id: 't-1',
        question_id: 'q-1',
        answer_json: inheritedObj as unknown as PhotoResponse
      }
      expect(() => isPhotoResponse(badResponse)).toThrow('مسار تخزين الصورة غير صالح أو غير آمن')
    })

    it('throws error when answer_json is an empty object {}', () => {
      const badResponse = {
        template_id: 't-1',
        question_id: 'q-1',
        answer_json: {} as unknown as PhotoResponse
      }
      expect(() => isPhotoResponse(badResponse)).toThrow('مسار تخزين الصورة غير صالح أو غير آمن')
    })
  })

  describe('callVisitRpc Error Handling & Validation', () => {
    it('throws transport error when supabase.rpc returns an error', async () => {
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: { name: 'PostgrestError', message: 'Network connection failure', code: '500', details: '', hint: '' },
        data: null, status: 500, statusText: 'Error', count: null
      })

      await expect(
        confirmVisitPlanAtomic({ operationId: 'op-1', planId: 'plan-1' })
      ).rejects.toThrow('فشل الاتصال بالخادم أثناء تنفيذ العملية: Network connection failure')
    })

    it('throws error when supabase.rpc returns a malformed response', async () => {
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: null,
        data: { ok: true, data: {} },
        status: 200, statusText: 'OK', count: null
      })

      await expect(
        confirmVisitPlanAtomic({ operationId: 'op-1', planId: 'plan-1' })
      ).rejects.toThrow('رد غير صالح أو مشوه من الخادم')
    })

    it('returns VisitRpcFailure when ok is false and keeps replayed/error details', async () => {
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: null,
        data: {
          ok: false,
          operation_id: 'op-123',
          operation: 'confirm_visit_plan_atomic',
          replayed: true,
          error: { code: 'DOMAIN_VALIDATION_FAILED', message: 'شروط الأعمال غير متطابقة' }
        },
        status: 200, statusText: 'OK', count: null
      })

      const result = await confirmVisitPlanAtomic({ operationId: 'op-123', planId: 'plan-1' })
      expect(result.ok).toBe(false)
      if (!result.ok) {
        expect(result.operation_id).toBe('op-123')
        expect(result.operation).toBe('confirm_visit_plan_atomic')
        expect(result.replayed).toBe(true)
        expect(result.error.code).toBe('DOMAIN_VALIDATION_FAILED')
        expect(result.error.message).toBe('شروط الأعمال غير متطابقة')
      }
    })

    it('throws error when operation_id from response does not match request operationId', async () => {
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: null,
        data: {
          ok: true,
          operation_id: 'op-different',
          operation: 'confirm_visit_plan_atomic',
          replayed: false,
          data: {
            plan_id: 'plan-123',
            status: 'confirmed' as const,
            confirmed_at: null,
            confirmed_by: null
          }
        },
        status: 200, statusText: 'OK', count: null
      })

      await expect(
        confirmVisitPlanAtomic({ operationId: 'op-confirm', planId: 'plan-123' })
      ).rejects.toThrow('رد غير صالح أو مشوه من الخادم')
    })

    it('throws error when operation name from response does not match the called RPC name', async () => {
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: null,
        data: {
          ok: true,
          operation_id: 'op-confirm',
          operation: 'create_visit_plan_atomic', // mismatch
          replayed: false,
          data: {
            plan_id: 'plan-123',
            status: 'confirmed' as const,
            confirmed_at: null,
            confirmed_by: null
          }
        },
        status: 200, statusText: 'OK', count: null
      })

      await expect(
        confirmVisitPlanAtomic({ operationId: 'op-confirm', planId: 'plan-123' })
      ).rejects.toThrow('رد غير صالح أو مشوه من الخادم')
    })

    it('throws error when response is ok: true but data is missing/null/undefined', async () => {
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: null,
        data: {
          ok: true,
          operation_id: 'op-confirm',
          operation: 'confirm_visit_plan_atomic',
          replayed: false
          // data is missing
        },
        status: 200, statusText: 'OK', count: null
      })

      await expect(
        confirmVisitPlanAtomic({ operationId: 'op-confirm', planId: 'plan-123' })
      ).rejects.toThrow('رد غير صالح أو مشوه من الخادم')
    })

    it('throws error when response is ok: true but data is a string or array or null instead of record', async () => {
      // 1. data is a string
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: null,
        data: {
          ok: true,
          operation_id: 'op-confirm',
          operation: 'confirm_visit_plan_atomic',
          replayed: false,
          data: 'some-string'
        },
        status: 200, statusText: 'OK', count: null
      })

      await expect(
        confirmVisitPlanAtomic({ operationId: 'op-confirm', planId: 'plan-123' })
      ).rejects.toThrow('رد غير صالح أو مشوه من الخادم')

      // 2. data is an array
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: null,
        data: {
          ok: true,
          operation_id: 'op-confirm',
          operation: 'confirm_visit_plan_atomic',
          replayed: false,
          data: [1, 2, 3]
        },
        status: 200, statusText: 'OK', count: null
      })

      await expect(
        confirmVisitPlanAtomic({ operationId: 'op-confirm', planId: 'plan-123' })
      ).rejects.toThrow('رد غير صالح أو مشوه من الخادم')

      // 3. data is null
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: null,
        data: {
          ok: true,
          operation_id: 'op-confirm',
          operation: 'confirm_visit_plan_atomic',
          replayed: false,
          data: null
        },
        status: 200, statusText: 'OK', count: null
      })

      await expect(
        confirmVisitPlanAtomic({ operationId: 'op-confirm', planId: 'plan-123' })
      ).rejects.toThrow('رد غير صالح أو مشوه من الخادم')
    })

    it('throws error when response is ok: false but error object is missing or invalid', async () => {
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: null,
        data: {
          ok: false,
          operation_id: 'op-confirm',
          operation: 'confirm_visit_plan_atomic',
          replayed: false
          // error is missing
        },
        status: 200, statusText: 'OK', count: null
      })

      await expect(
        confirmVisitPlanAtomic({ operationId: 'op-confirm', planId: 'plan-123' })
      ).rejects.toThrow('رد غير صالح أو مشوه من الخادم')
    })

    it('throws VisitRpcTransportError and preserves Supabase error object on transport error', async () => {
      const originalError = { name: 'PostgrestError', message: 'DB connection timeout', code: '504', details: '', hint: '' }
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: originalError,
        data: null, status: 504, statusText: 'Error', count: null
      })

      try {
        await confirmVisitPlanAtomic({ operationId: 'op-confirm', planId: 'plan-123' })
        expect.fail('Expected to throw')
      } catch (err) {
        expect(err).toBeInstanceOf(VisitRpcTransportError)
        expect((err as VisitRpcTransportError).supabaseError).toEqual(originalError)
      }
    })
  })

  describe('Atomic RPC wrappers parameter mapping', () => {
    it('creates visit plan with exact parameters and types', async () => {
      const mockResult = {
        plan_id: 'plan-123',
        employee_id: 'emp-123',
        plan_date: '2026-07-06',
        status: 'draft' as PlanStatus,
        total_customers: 1,
        items: [{ id: 'item-1', customer_id: 'cust-1', sequence: 1, status: 'pending' as PlanItemStatus }]
      }
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: null,
        data: {
          ok: true,
          operation_id: 'op-create',
          operation: 'create_visit_plan_atomic',
          replayed: false,
          data: mockResult
        },
        status: 200, statusText: 'OK', count: null
      })

      const input = {
        operationId: 'op-create',
        employeeId: 'emp-123',
        planDate: '2026-07-06',
        planType: 'daily' as const,
        notes: 'Some notes',
        items: [{
          customer_id: 'cust-1',
          customer_branch_id: null,
          sequence: 1,
          planned_time: '09:00:00',
          estimated_duration_min: 30,
          priority: 'normal' as const,
          purpose: 'Sales visit',
          purpose_type: 'sales' as const
        }]
      }

      const result = await createVisitPlanAtomic(input)
      expect(result.ok).toBe(true)
      if (result.ok) {
        expect(result.data).toEqual(mockResult)
      }

      expect(supabase.rpc).toHaveBeenCalledWith('create_visit_plan_atomic', {
        p_operation_id: 'op-create',
        p_employee_id: 'emp-123',
        p_plan_date: '2026-07-06',
        p_plan_type: 'daily',
        p_notes: 'Some notes',
        p_items: input.items
      })
    })

    it('confirms visit plan with exact parameters', async () => {
      const mockResult = {
        plan_id: 'plan-123',
        status: 'confirmed' as PlanStatus,
        confirmed_at: '2026-07-06T17:00:00Z',
        confirmed_by: 'user-123'
      }
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: null,
        data: {
          ok: true,
          operation_id: 'op-confirm',
          operation: 'confirm_visit_plan_atomic',
          replayed: false,
          data: mockResult
        },
        status: 200, statusText: 'OK', count: null
      })

      const result = await confirmVisitPlanAtomic({ operationId: 'op-confirm', planId: 'plan-123' })
      expect(result.ok).toBe(true)
      expect(supabase.rpc).toHaveBeenCalledWith('confirm_visit_plan_atomic', {
        p_operation_id: 'op-confirm',
        p_plan_id: 'plan-123'
      })
    })

    it('cancels visit plan with exact parameters', async () => {
      const mockResult = {
        plan_id: 'plan-123',
        status: 'cancelled' as PlanStatus,
        cancellation_reason: 'Canceled'
      }
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: null,
        data: {
          ok: true,
          operation_id: 'op-cancel',
          operation: 'cancel_visit_plan_atomic',
          replayed: false,
          data: mockResult
        },
        status: 200, statusText: 'OK', count: null
      })

      const result = await cancelVisitPlanAtomic({ operationId: 'op-cancel', planId: 'plan-123', reason: 'Canceled' })
      expect(result.ok).toBe(true)
      expect(supabase.rpc).toHaveBeenCalledWith('cancel_visit_plan_atomic', {
        p_operation_id: 'op-cancel',
        p_plan_id: 'plan-123',
        p_cancellation_reason: 'Canceled'
      })
    })

    it('reorders visit plan items with exact parameters', async () => {
      const mockResult = {
        plan_id: 'plan-123',
        items: [{ id: 'item-1', sequence: 1 }]
      }
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: null,
        data: {
          ok: true,
          operation_id: 'op-reorder',
          operation: 'reorder_visit_plan_items_atomic',
          replayed: false,
          data: mockResult
        },
        status: 200, statusText: 'OK', count: null
      })

      const items = [{ item_id: 'item-1', sequence: 1 }]
      const result = await reorderVisitPlanItemsAtomic({ operationId: 'op-reorder', planId: 'plan-123', items })
      expect(result.ok).toBe(true)
      expect(supabase.rpc).toHaveBeenCalledWith('reorder_visit_plan_items_atomic', {
        p_operation_id: 'op-reorder',
        p_plan_id: 'plan-123',
        p_reorder_data: items
      })
    })

    it('closes visit plan administratively with exact parameters', async () => {
      const mockResult = {
        plan_id: 'plan-123',
        status: 'completed' as PlanStatus,
        skipped_count: 2,
        administrative_closed_by: 'admin-1',
        administrative_closed_at: '2026-07-06T17:00:00Z',
        administrative_close_reason: 'Closed by admin'
      }
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: null,
        data: {
          ok: true,
          operation_id: 'op-close',
          operation: 'close_visit_plan_administratively_atomic',
          replayed: false,
          data: mockResult
        },
        status: 200, statusText: 'OK', count: null
      })

      const result = await closeVisitPlanAdministrativelyAtomic({
        operationId: 'op-close',
        planId: 'plan-123',
        reason: 'Closed by admin'
      })
      expect(result.ok).toBe(true)
      expect(supabase.rpc).toHaveBeenCalledWith('close_visit_plan_administratively_atomic', {
        p_operation_id: 'op-close',
        p_plan_id: 'plan-123',
        p_close_reason: 'Closed by admin'
      })
    })

    it('starts visit item with exact parameters', async () => {
      const mockResult = {
        item_id: 'item-1',
        status: 'in_progress' as PlanItemStatus,
        server_started_at: '2026-07-06T17:00:00Z',
        start_distance_m: 10,
        gps_validation_status: 'passed' as const,
        plan_id: 'plan-123',
        plan_status: 'in_progress' as PlanStatus
      }
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: null,
        data: {
          ok: true,
          operation_id: 'op-start',
          operation: 'start_visit_item_atomic',
          replayed: false,
          data: mockResult
        },
        status: 200, statusText: 'OK', count: null
      })

      const input = {
        operationId: 'op-start',
        itemId: 'item-1',
        startLat: 30.0123,
        startLng: 31.0123,
        startAccuracyM: 15,
        clientStartedAt: '2026-07-06T17:00:00Z',
        deviceTimezone: 'Africa/Cairo'
      }

      const result = await startVisitItemAtomic(input)
      expect(result.ok).toBe(true)
      expect(supabase.rpc).toHaveBeenCalledWith('start_visit_item_atomic', {
        p_operation_id: 'op-start',
        p_item_id: 'item-1',
        p_start_lat: 30.0123,
        p_start_lng: 31.0123,
        p_start_accuracy_m: 15,
        p_client_started_at: '2026-07-06T17:00:00Z',
        p_device_timezone: 'Africa/Cairo'
      })
    })

    it('turns a hanging visit RPC into a retryable transport error after the safety timeout', async () => {
      vi.useFakeTimers()
      try {
        vi.mocked(supabase.rpc).mockImplementationOnce(() => new Promise(() => {}) as never)
        const request = startVisitItemAtomic({
          operationId: 'op-timeout', itemId: 'item-1',
          startLat: null, startLng: null, startAccuracyM: null,
          clientStartedAt: '2026-07-30T12:22:50.000Z', deviceTimezone: 'Africa/Cairo'
        })
        const assertion = expect(request).rejects.toMatchObject({
          name: 'VisitRpcTransportError',
          supabaseError: null
        })
        await vi.advanceTimersByTimeAsync(30_000)
        await assertion
      } finally {
        vi.useRealTimers()
      }
    })

    it('completes visit item with safe photo path validation and exact parameters', async () => {
      const mockResult = {
        item_id: 'item-1',
        status: 'completed' as PlanItemStatus,
        activity_id: 'act-1',
        gps_validation_status: 'passed' as const,
        gps_review_status: 'not_required' as const,
        plan_id: 'plan-123',
        plan_status: 'completed' as PlanStatus
      }
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: null,
        data: {
          ok: true,
          operation_id: 'op-complete',
          operation: 'complete_visit_item_atomic',
          replayed: false,
          data: mockResult
        },
        status: 200, statusText: 'OK', count: null
      })

      const responses = [
        { template_id: 't-1', question_id: 'q-1', answer_value: 'Ans text' },
        { template_id: 't-1', question_id: 'q-2', answer_json: ['A', 'B'] },
        { template_id: 't-1', question_id: 'q-3', answer_json: { storage_path: 'reps/123/file.jpg' as unknown as VisitStoragePath } }
      ]

      const input = {
        operationId: 'op-complete',
        itemId: 'item-1',
        endLat: 30.0123,
        endLng: 31.0123,
        endAccuracyM: 10,
        clientCompletedAt: '2026-07-06T17:30:00Z',
        deviceTimezone: 'Africa/Cairo',
        outcomeType: 'visited' as const,
        outcomeNotes: 'Notes',
        responses,
        orderId: null,
        collectionId: null,
        gpsExceptionReason: null
      }

      const result = await completeVisitItemAtomic(input)
      expect(result.ok).toBe(true)
      expect(supabase.rpc).toHaveBeenCalledWith('complete_visit_item_atomic', {
        p_operation_id: 'op-complete',
        p_item_id: 'item-1',
        p_end_lat: 30.0123,
        p_end_lng: 31.0123,
        p_end_accuracy_m: 10,
        p_client_completed_at: '2026-07-06T17:30:00Z',
        p_device_timezone: 'Africa/Cairo',
        p_outcome_type: 'visited',
        p_outcome_notes: 'Notes',
        p_responses: responses,
        p_order_id: null,
        p_collection_id: null,
        p_gps_exception_reason: null
      })
    })

    it('throws error before complete RPC if photo path has invalid traversal or Base64', async () => {
      const responses = [
        { template_id: 't-1', question_id: 'q-3', answer_json: { storage_path: 'reps/../../file.jpg' as unknown as VisitStoragePath } }
      ]

      const input = {
        operationId: 'op-complete',
        itemId: 'item-1',
        endLat: 30.0123,
        endLng: 31.0123,
        endAccuracyM: 10,
        clientCompletedAt: '2026-07-06T17:30:00Z',
        deviceTimezone: 'Africa/Cairo',
        outcomeType: 'visited' as const,
        outcomeNotes: 'Notes',
        responses,
        orderId: null,
        collectionId: null,
        gpsExceptionReason: null
      }

      await expect(
        completeVisitItemAtomic(input)
      ).rejects.toThrow('مسار تخزين الصورة غير صالح أو غير آمن')

      expect(supabase.rpc).not.toHaveBeenCalled()
    })

    it('throws error before complete RPC if storage_path is not a string', async () => {
      const responses = [
        {
          template_id: 't-1',
          question_id: 'q-3',
          answer_json: {
            storage_path: 123 as unknown as VisitStoragePath
          }
        }
      ]

      const input = {
        operationId: 'op-complete',
        itemId: 'item-1',
        endLat: 30.0123,
        endLng: 31.0123,
        endAccuracyM: 10,
        clientCompletedAt: '2026-07-06T17:30:00Z',
        deviceTimezone: 'Africa/Cairo',
        outcomeType: 'visited' as const,
        outcomeNotes: 'Notes',
        responses,
        orderId: null,
        collectionId: null,
        gpsExceptionReason: null
      }

      await expect(
        completeVisitItemAtomic(input)
      ).rejects.toThrow('مسار تخزين الصورة غير صالح أو غير آمن')

      expect(supabase.rpc).not.toHaveBeenCalled()
    })

    it('throws error before complete RPC if answer_json is an empty object {}', async () => {
      const responses = [
        {
          template_id: 't-1',
          question_id: 'q-3',
          answer_json: {} as unknown as PhotoResponse
        }
      ]

      const input = {
        operationId: 'op-complete',
        itemId: 'item-1',
        endLat: 30.0123,
        endLng: 31.0123,
        endAccuracyM: 10,
        clientCompletedAt: '2026-07-06T17:30:00Z',
        deviceTimezone: 'Africa/Cairo',
        outcomeType: 'visited' as const,
        outcomeNotes: 'Notes',
        responses,
        orderId: null,
        collectionId: null,
        gpsExceptionReason: null
      }

      await expect(
        completeVisitItemAtomic(input)
      ).rejects.toThrow('مسار تخزين الصورة غير صالح أو غير آمن')

      expect(supabase.rpc).not.toHaveBeenCalled()
    })

    it('throws error before complete RPC if answer_json inherits storage_path from prototype but does not own it directly', async () => {
      const protoObj = { storage_path: 'reps/123/file.jpg' }
      const inheritedObj = Object.create(protoObj)

      const responses = [
        {
          template_id: 't-1',
          question_id: 'q-3',
          answer_json: inheritedObj as unknown as PhotoResponse
        }
      ]

      const input = {
        operationId: 'op-complete',
        itemId: 'item-1',
        endLat: 30.0123,
        endLng: 31.0123,
        endAccuracyM: 10,
        clientCompletedAt: '2026-07-06T17:30:00Z',
        deviceTimezone: 'Africa/Cairo',
        outcomeType: 'visited' as const,
        outcomeNotes: 'Notes',
        responses,
        orderId: null,
        collectionId: null,
        gpsExceptionReason: null
      }

      await expect(
        completeVisitItemAtomic(input)
      ).rejects.toThrow('مسار تخزين الصورة غير صالح أو غير آمن')

      expect(supabase.rpc).not.toHaveBeenCalled()
    })

    it('skips visit item with exact parameters', async () => {
      const mockResult = {
        item_id: 'item-1',
        status: 'skipped' as PlanItemStatus,
        skip_reason: 'Client away',
        plan_id: 'plan-123',
        plan_status: 'in_progress' as PlanStatus
      }
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: null,
        data: {
          ok: true,
          operation_id: 'op-skip',
          operation: 'skip_visit_item_atomic',
          replayed: false,
          data: mockResult
        },
        status: 200, statusText: 'OK', count: null
      })

      const input = {
        operationId: 'op-skip',
        itemId: 'item-1',
        skipReason: 'Client away',
        clientEventAt: '2026-07-06T17:00:00Z',
        deviceTimezone: 'Africa/Cairo'
      }

      const result = await skipVisitItemAtomic(input)
      expect(result.ok).toBe(true)
      expect(supabase.rpc).toHaveBeenCalledWith('skip_visit_item_atomic', {
        p_operation_id: 'op-skip',
        p_item_id: 'item-1',
        p_skip_reason: 'Client away',
        p_client_event_at: '2026-07-06T17:00:00Z',
        p_device_timezone: 'Africa/Cairo'
      })
    })

    it('reschedules visit item with exact parameters', async () => {
      const mockResult = {
        source_item_id: 'item-1',
        source_status: 'rescheduled' as PlanItemStatus,
        new_item_id: 'item-2',
        new_status: 'pending' as PlanItemStatus,
        source_plan_id: 'plan-123',
        target_plan_id: 'plan-456'
      }
      vi.mocked(supabase.rpc).mockResolvedValueOnce({
        error: null,
        data: {
          ok: true,
          operation_id: 'op-reschedule',
          operation: 'reschedule_visit_item_atomic',
          replayed: false,
          data: mockResult
        },
        status: 200, statusText: 'OK', count: null
      })

      const input = {
        operationId: 'op-reschedule',
        itemId: 'item-1',
        targetPlanId: 'plan-456',
        rescheduleReason: 'Rescheduled reason',
        plannedTime: '10:00:00',
        clientEventAt: '2026-07-06T17:00:00Z',
        deviceTimezone: 'Africa/Cairo'
      }

      const result = await rescheduleVisitItemAtomic(input)
      expect(result.ok).toBe(true)
      expect(supabase.rpc).toHaveBeenCalledWith('reschedule_visit_item_atomic', {
        p_operation_id: 'op-reschedule',
        p_item_id: 'item-1',
        p_target_plan_id: 'plan-456',
        p_reschedule_reason: 'Rescheduled reason',
        p_planned_time: '10:00:00',
        p_client_event_at: '2026-07-06T17:00:00Z',
        p_device_timezone: 'Africa/Cairo'
      })
    })
  })

  describe('TypeScript exact type matches', () => {
    it('forces outcomeType to match VisitOutcomeType strictly', () => {
      expectTypeOf<VisitOutcomeType>().toEqualTypeOf<
        | 'visited'
        | 'order_placed'
        | 'collection'
        | 'refused'
        | 'closed'
        | 'promotion'
        | 'exploratory'
        | 'followup_scheduled'
        | 'info_only'
        | 'agreed_order'
        | 'promised_payment'
        | 'followup_visit'
        | 'not_interested'
      >()
    })

    it('RPC result types match PlanStatus and PlanItemStatus strictly', () => {
      expectTypeOf<CreateVisitPlanAtomicResult['status']>().toEqualTypeOf<PlanStatus>()
      expectTypeOf<CreateVisitPlanAtomicResult['items'][number]['status']>().toEqualTypeOf<PlanItemStatus>()
      expectTypeOf<ConfirmVisitPlanAtomicResult['status']>().toEqualTypeOf<PlanStatus>()
      expectTypeOf<CancelVisitPlanAtomicResult['status']>().toEqualTypeOf<PlanStatus>()
      expectTypeOf<CloseVisitPlanAdministrativelyAtomicResult['status']>().toEqualTypeOf<PlanStatus>()
      expectTypeOf<StartVisitItemAtomicResult['status']>().toEqualTypeOf<PlanItemStatus>()
      expectTypeOf<StartVisitItemAtomicResult['plan_status']>().toEqualTypeOf<PlanStatus>()
      expectTypeOf<CompleteVisitItemAtomicResult['status']>().toEqualTypeOf<PlanItemStatus>()
      expectTypeOf<CompleteVisitItemAtomicResult['plan_status']>().toEqualTypeOf<PlanStatus>()
      expectTypeOf<SkipVisitItemAtomicResult['status']>().toEqualTypeOf<PlanItemStatus>()
      expectTypeOf<SkipVisitItemAtomicResult['plan_status']>().toEqualTypeOf<PlanStatus>()
      expectTypeOf<RescheduleVisitItemAtomicResult['source_status']>().toEqualTypeOf<PlanItemStatus>()
      expectTypeOf<RescheduleVisitItemAtomicResult['new_status']>().toEqualTypeOf<PlanItemStatus>()
    })
  })

  describe('createActivity Guard Validation', () => {
    it('throws error when visit_plan_item_id is provided in createActivity', async () => {
      const invalidPayload = {
        type_id: 'type-123',
        visit_plan_item_id: 'item-123',
        customer_id: 'cust-123',
        outcome_type: 'visited'
      } as unknown as ActivityInput

      await expect(createActivity(invalidPayload)).rejects.toThrow(
        'تسجيل أنشطة الزيارات المخططة محظور عبر هذا النموذج'
      )
    })

    it('does not throw when visit_plan_item_id is not provided', async () => {
      const validPayload = {
        type_id: 'type-123',
        customer_id: 'cust-123',
        outcome_type: 'visited'
      } as unknown as ActivityInput

      // Mock insert chain
      const mockInsert = vi.fn().mockReturnValue({
        select: vi.fn().mockReturnValue({
          single: vi.fn().mockResolvedValue({ data: { id: 'act-123' } })
        })
      })
      vi.mocked(supabase.from).mockReturnValue({
        select: vi.fn().mockReturnValue({
          eq: vi.fn().mockReturnValue({
            maybeSingle: vi.fn().mockResolvedValue({ data: { id: 'emp-123' } })
          })
        }),
        insert: mockInsert
      } as any)

      const result = await createActivity(validPayload)
      expect(result).toBeDefined()
      expect(result.id).toBe('act-123')
    })
  })
})
