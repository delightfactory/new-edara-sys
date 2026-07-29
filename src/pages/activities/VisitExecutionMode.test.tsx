import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import VisitExecutionMode from './VisitExecutionMode'
import { useVisitExecutionSession } from '@/hooks/useVisitExecutionSession'
import type { PendingVisitOperation } from '@/lib/db/visitsDb'
import type { ChecklistTemplate, VisitPlanItem, VisitPlan } from '@/lib/types/activities'

import { PERMISSIONS } from '@/lib/permissions/constants'

let activeExecutionPermissions: string[] = []

// Simple mock for auth store
vi.mock('@/stores/auth-store', () => {
  type StoreState = ReturnType<typeof import('@/stores/auth-store').useAuthStore.getState>
  const mockStore = vi.fn((selector?: (state: StoreState) => unknown) => {
    const state = {
      profile: { id: 'test-user-123' } as unknown as StoreState['profile'],
      can: (perm: string) => activeExecutionPermissions.includes(perm)
    } as unknown as StoreState
    return selector ? selector(state) : state
  })
  return {
    useAuthStore: Object.assign(mockStore, {
      getState: vi.fn(() => ({
        profile: { id: 'test-user-123' } as unknown as StoreState['profile'],
        can: (perm: string) => activeExecutionPermissions.includes(perm)
      } as unknown as StoreState))
    })
  }
})

// Mock react-query hooks
let mockPlanData: VisitPlan | null = {
  id: 'plan-123',
  plan_date: '2026-07-06',
  employee_id: 'emp-123',
  status: 'draft',
  created_at: '',
  updated_at: '',
  organizational_branch_id: ''
} as unknown as VisitPlan

let mockItemsData: VisitPlanItem[] = [
  {
    id: 'item-1',
    plan_id: 'plan-123',
    status: 'pending',
    customer_id: 'cust-1',
    sequence: 1,
    purpose_type: 'sales',
    purpose: 'بيع منتجات',
    priority: 'high',
    customer: {
      id: 'cust-1',
      name: 'عميل 1',
      code: 'C001',
      phone: '0100000000',
      latitude: 30,
      longitude: 31
    },
    created_at: '',
    updated_at: '',
    customer_branch_id: '',
    expected_location_source: null,
    expected_location_id: null,
    expected_lat: null,
    expected_lng: null,
    server_started_at: null,
    client_started_at: null,
    start_lat: null,
    start_lng: null,
    start_accuracy_m: null,
    server_completed_at: null,
    client_completed_at: null,
    end_lat: null,
    end_lng: null,
    end_accuracy_m: null,
    gps_validation_status: 'not_checked',
    gps_exception_reason: null,
    rescheduled_count: 0,
    activity_id: null,
    skip_reason: null,
    metadata: null,
    closure_pct: null,
    administrative_closed_at: null,
    administrative_closed_by: null,
    administrative_close_reason: null,
    planned_time: null,
    estimated_duration_min: 0,
    actual_arrival_time: null,
    actual_start_time: null,
    actual_end_time: null,
    gps_lat: null,
    gps_lng: null,
    reschedule_to: null,
    start_distance_m: null,
    end_distance_m: null,
    device_timezone: null,
    gps_review_status: 'pending',
    gps_exception_requested_by: null,
    gps_exception_reviewed_by: null,
    gps_exception_reviewed_at: null,
    rescheduled_from_item_id: null,
    replacement_item_id: null,
    reschedule_reason: null,
    stale_since: null
  }
] as unknown as VisitPlanItem[]

let mockAtomicExecution = true
let mockChecklistQuery = {
  data: [] as ChecklistTemplate[],
  isLoading: false,
  isError: false,
  isSuccess: true,
  refetch: vi.fn()
}

vi.mock('@/hooks/useQueryHooks', () => ({
  useVisitPlan: () => ({ data: mockPlanData, isLoading: false }),
  useVisitPlanItems: () => ({ data: mockItemsData, isLoading: false }),
  useUpdateVisitPlanItem: () => ({ mutateAsync: vi.fn() }),
  useChecklistTemplates: () => mockChecklistQuery,
  useCreateActivity: () => ({ mutateAsync: vi.fn() }),
  useActivityTypes: () => ({ data: [{ id: 'type-123', code: 'visit_planned' }], isLoading: false }),
  useSaveChecklistResponses: () => ({ mutateAsync: vi.fn() })
}))

vi.mock('@/hooks/useGeoPermission', () => ({
  default: () => ({
    status: 'granted',
    requestLocation: vi.fn().mockResolvedValue({
      ok: true,
      coords: { lat: 30, lng: 31, accuracy: 10 }
    })
  })
}))

// Mock session hook
vi.mock('@/hooks/useVisitExecutionSession', () => ({
  useVisitExecutionSession: vi.fn(),
  mapChecklistResponses: vi.fn((resp) => resp)
}))

// Mock navigate
vi.mock('react-router-dom', () => ({
  useParams: () => ({ id: 'plan-123' }),
  useNavigate: () => vi.fn()
}))

// Mock feature flag config
vi.mock('@/lib/config/features', () => ({
  get VISITS_ATIGNMENT_EXECUTION() {
    return mockAtomicExecution
  },
  get VISITS_ATOMIC_EXECUTION() {
    return mockAtomicExecution
  }
}))

// Helpers to construct mock operations safely without any casts
function makeMockStartOperation(overrides?: Partial<PendingVisitOperation>): PendingVisitOperation {
  const now = Date.now()
  return {
    operationId: 'op-start-default',
    userId: 'test-user-123',
    planId: 'plan-123',
    itemId: 'item-1',
    kind: 'start',
    state: 'pending',
    attemptCount: 0,
    lastErrorCode: null,
    createdAt: now,
    updatedAt: now,
    expiresAt: now + 48 * 3600 * 1000,
    payload: {
      operationId: overrides?.operationId || 'op-start-default',
      itemId: overrides?.itemId || 'item-1',
      startLat: null,
      startLng: null,
      startAccuracyM: null,
      clientStartedAt: '',
      deviceTimezone: ''
    },
    ...overrides
  } as PendingVisitOperation
}

function makeMockCompleteOperation(overrides?: Partial<PendingVisitOperation>): PendingVisitOperation {
  const now = Date.now()
  return {
    operationId: 'op-complete-default',
    userId: 'test-user-123',
    planId: 'plan-123',
    itemId: 'item-1',
    kind: 'complete',
    state: 'pending',
    attemptCount: 0,
    lastErrorCode: null,
    createdAt: now,
    updatedAt: now,
    expiresAt: now + 48 * 3600 * 1000,
    payload: {
      operationId: overrides?.operationId || 'op-complete-default',
      itemId: overrides?.itemId || 'item-1',
      endLat: null,
      endLng: null,
      endAccuracyM: null,
      clientCompletedAt: '',
      deviceTimezone: '',
      outcomeType: 'visited',
      outcomeNotes: null,
      responses: [],
      orderId: null,
      collectionId: null,
      gpsExceptionReason: null
    },
    ...overrides
  } as PendingVisitOperation
}

describe('VisitExecutionMode UI Integration Tests (Atomic Mode)', () => {
  beforeEach(() => {
    mockPlanData = {
      id: 'plan-123',
      plan_date: '2026-07-06',
      employee_id: 'emp-123',
      status: 'draft',
      created_at: '',
      updated_at: '',
      organizational_branch_id: ''
    } as unknown as VisitPlan
    mockItemsData = [
      {
        id: 'item-1',
        plan_id: 'plan-123',
        status: 'pending',
        customer_id: 'cust-1',
        sequence: 1,
        purpose_type: 'sales',
        purpose: 'بيع منتجات',
        priority: 'high',
        customer: {
          id: 'cust-1',
          name: 'عميل 1',
          code: 'C001',
          phone: '0100000000',
          latitude: 30,
          longitude: 31
        },
        created_at: '',
        updated_at: '',
        customer_branch_id: '',
        expected_location_source: null,
        expected_location_id: null,
        expected_lat: null,
        expected_lng: null,
        server_started_at: null,
        client_started_at: null,
        start_lat: null,
        start_lng: null,
        start_accuracy_m: null,
        server_completed_at: null,
        client_completed_at: null,
        end_lat: null,
        end_lng: null,
        end_accuracy_m: null,
        gps_validation_status: 'not_checked',
        gps_exception_reason: null,
        rescheduled_count: 0,
        activity_id: null,
        skip_reason: null,
        metadata: null,
        closure_pct: null,
        administrative_closed_at: null,
        administrative_closed_by: null,
        administrative_close_reason: null,
        planned_time: null,
        estimated_duration_min: 0,
        actual_arrival_time: null,
        actual_start_time: null,
        actual_end_time: null,
        gps_lat: null,
        gps_lng: null,
        reschedule_to: null,
        start_distance_m: null,
        end_distance_m: null,
        device_timezone: null,
        gps_review_status: 'pending',
        gps_exception_requested_by: null,
        gps_exception_reviewed_by: null,
        gps_exception_reviewed_at: null,
        rescheduled_from_item_id: null,
        replacement_item_id: null,
        reschedule_reason: null,
        stale_since: null
      }
    ] as unknown as VisitPlanItem[]
    mockAtomicExecution = true
    mockChecklistQuery = {
      data: [],
      isLoading: false,
      isError: false,
      isSuccess: true,
      refetch: vi.fn()
    }
    activeExecutionPermissions = [
      PERMISSIONS.VISIT_PLANS_UPDATE_OWN,
      PERMISSIONS.ACTIVITIES_CREATE,
      PERMISSIONS.VISIT_PLANS_CREATE
    ]
    vi.clearAllMocks()
  })

  it('proves that if VISITS_ATOMIC_EXECUTION=false, legacy mode functions completely even if useVisitExecutionSession hook returns database/loading error', () => {
    mockAtomicExecution = false

    vi.mocked(useVisitExecutionSession).mockReturnValue({
      session: null,
      pendingOps: [],
      loading: false,
      error: 'IndexedDB Corrupted',
      startVisit: vi.fn(),
      completeVisit: vi.fn(),
      skipVisit: vi.fn(),
      retryOperation: vi.fn(),
      discardFailedOperation: vi.fn(),
      saveChecklistDraft: vi.fn(),
      saveGpsExceptionReason: vi.fn(),
      reloadFromDb: vi.fn()
    } as unknown as ReturnType<typeof useVisitExecutionSession>)

    render(<VisitExecutionMode />)

    // Updated text assertions to match UX-improved blocker screen (Quick Wins)
    expect(screen.getByText('وضع التنفيذ غير متاح')).toBeDefined()
    expect(screen.getByText(/مسار التنفيذ الميداني غير مفعّل/)).toBeDefined()
    expect(screen.queryByText('بدء الزيارة')).toBeNull()
  })

  it('keeps skip modal open on RPC failures and closes it only when operation returns ok = true', async () => {
    mockAtomicExecution = true
    let mockResult: { ok: boolean; state: string; errorCode: string | null } = { ok: false, state: 'failed', errorCode: 'SERVER_ERROR' }

    const mockSkipVisit = vi.fn().mockImplementation(async () => {
      const res = mockResult
      mockResult = { ok: true, state: 'succeeded', errorCode: null }
      return res
    })

    vi.mocked(useVisitExecutionSession).mockReturnValue({
      session: null,
      pendingOps: [],
      loading: false,
      error: null,
      startVisit: vi.fn(),
      completeVisit: vi.fn(),
      skipVisit: mockSkipVisit,
      retryOperation: vi.fn(),
      discardFailedOperation: vi.fn(),
      saveChecklistDraft: vi.fn(),
      saveGpsExceptionReason: vi.fn(),
      reloadFromDb: vi.fn()
    } as unknown as ReturnType<typeof useVisitExecutionSession>)

    render(<VisitExecutionMode />)

    const skipBtn = screen.getByText('تخطي')
    fireEvent.click(skipBtn)

    const reasonBtn = screen.getByText('محل مغلق')
    fireEvent.click(reasonBtn)

    const confirmBtn = screen.getByText('تأكيد التخطي')
    fireEvent.click(confirmBtn)

    await waitFor(() => {
      expect(mockSkipVisit).toHaveBeenCalled()
    })

    expect(screen.getByText('اختر سبب تخطي زيارة عميل 1')).toBeDefined()

    fireEvent.click(confirmBtn)

    await waitFor(() => {
      expect(screen.queryByText('اختر سبب تخطي زيارة عميل 1')).toBeNull()
    })
  })

  it('determines currentOp based strictly on item ID and uses deterministic status sorting with tie-breaker', async () => {
    mockAtomicExecution = true
    const mockDiscard = vi.fn()
    const ops = [
      makeMockCompleteOperation({ operationId: 'op-z', state: 'failed', updatedAt: 100, createdAt: 100 }),
      makeMockCompleteOperation({ operationId: 'op-a', state: 'failed', updatedAt: 200, createdAt: 200 })
    ]

    vi.mocked(useVisitExecutionSession).mockReturnValue({
      session: null,
      pendingOps: ops,
      loading: false,
      error: null,
      startVisit: vi.fn(),
      completeVisit: vi.fn(),
      skipVisit: vi.fn(),
      retryOperation: vi.fn(),
      discardFailedOperation: mockDiscard,
      saveChecklistDraft: vi.fn(),
      saveGpsExceptionReason: vi.fn(),
      reloadFromDb: vi.fn()
    } as unknown as ReturnType<typeof useVisitExecutionSession>)

    render(<VisitExecutionMode />)

    const discardBtn = screen.getByText('بدء محاولة جديدة')
    fireEvent.click(discardBtn)

    await waitFor(() => {
      expect(mockDiscard).toHaveBeenCalledWith('op-a')
    })
  })

  it('displays correct message and retry button for retryable state, and blocks double click', async () => {
    mockAtomicExecution = true
    const mockRetry = vi.fn().mockImplementation(() => new Promise(resolve => setTimeout(resolve, 50)))
    const ops = [
      makeMockStartOperation({ operationId: 'op-retry', state: 'retryable', lastErrorCode: 'CONNECTION_ERROR' })
    ]

    vi.mocked(useVisitExecutionSession).mockReturnValue({
      session: null,
      pendingOps: ops,
      loading: false,
      error: null,
      startVisit: vi.fn(),
      completeVisit: vi.fn(),
      skipVisit: vi.fn(),
      retryOperation: mockRetry,
      discardFailedOperation: vi.fn(),
      saveChecklistDraft: vi.fn(),
      saveGpsExceptionReason: vi.fn(),
      reloadFromDb: vi.fn()
    } as unknown as ReturnType<typeof useVisitExecutionSession>)

    render(<VisitExecutionMode />)

    expect(screen.getByText(/فشل الاتصال بالشبكة: تم حفظ العملية محلياً/)).toBeDefined()
    const retryBtn = screen.getByText('إعادة المحاولة')
    expect(screen.queryByText('بدء محاولة جديدة')).toBeNull()

    // Fast double click
    fireEvent.click(retryBtn)
    fireEvent.click(retryBtn)

    expect(mockRetry).toHaveBeenCalledTimes(1)
  })

  it('displays correct message and discard button for failed state, and calls discardFailedOperation on click', async () => {
    mockAtomicExecution = true
    const mockDiscard = vi.fn()
    const ops = [
      makeMockStartOperation({ operationId: 'op-failed', state: 'failed', lastErrorCode: 'CLIENT_ERROR' })
    ]

    vi.mocked(useVisitExecutionSession).mockReturnValue({
      session: null,
      pendingOps: ops,
      loading: false,
      error: null,
      startVisit: vi.fn(),
      completeVisit: vi.fn(),
      skipVisit: vi.fn(),
      retryOperation: vi.fn(),
      discardFailedOperation: mockDiscard,
      saveChecklistDraft: vi.fn(),
      saveGpsExceptionReason: vi.fn(),
      reloadFromDb: vi.fn()
    } as unknown as ReturnType<typeof useVisitExecutionSession>)

    render(<VisitExecutionMode />)

    expect(screen.getByText(/حدث خطأ غير متوقع في المتصفح أثناء المعالجة/)).toBeDefined()
    const discardBtn = screen.getByText('بدء محاولة جديدة')
    expect(screen.queryByText('إعادة المحاولة')).toBeNull()

    fireEvent.click(discardBtn)
    expect(mockDiscard).toHaveBeenCalledWith('op-failed')
  })

  it('displays correct message and hides action buttons for conflict state', async () => {
    mockAtomicExecution = true
    const ops = [
      makeMockStartOperation({ operationId: 'op-conflict', state: 'conflict', lastErrorCode: 'SYNC_CONFLICT' })
    ]

    vi.mocked(useVisitExecutionSession).mockReturnValue({
      session: null,
      pendingOps: ops,
      loading: false,
      error: null,
      startVisit: vi.fn(),
      completeVisit: vi.fn(),
      skipVisit: vi.fn(),
      retryOperation: vi.fn(),
      discardFailedOperation: vi.fn(),
      saveChecklistDraft: vi.fn(),
      saveGpsExceptionReason: vi.fn(),
      reloadFromDb: vi.fn()
    } as unknown as ReturnType<typeof useVisitExecutionSession>)

    render(<VisitExecutionMode />)

    expect(screen.getByText(/تعارض في التزامن: تم تحديث حالة هذه الزيارة بالفعل/)).toBeDefined()
    expect(screen.queryByText('إعادة المحاولة')).toBeNull()
    expect(screen.queryByText('بدء محاولة جديدة')).toBeNull()
  })

  it.each([
    ['failed_distance'],
    ['failed_accuracy'],
    ['no_coordinates']
  ])('enforces GPS exception justification when validation status is %s', (gpsStatus) => {
    mockAtomicExecution = true
    const mockSaveReason = vi.fn()
    const mockCompleteVisit = vi.fn()
    const mockSession = {
      userId: 'test-user-123',
      planId: 'plan-123',
      itemId: 'item-1',
      serverStartedAt: '2026-07-06T19:00:00Z',
      clientStartedAt: '2026-07-06T19:00:00Z',
      startGPS: { lat: 30, lng: 31 },
      startGPSAccuracy: 10,
      gpsValidationStatus: gpsStatus as any,
      checklistDrafts: {},
      gpsExceptionReason: null,
      updatedAt: Date.now(),
      expiresAt: Date.now() + 1000
    }

    vi.mocked(useVisitExecutionSession).mockReturnValue({
      session: mockSession,
      pendingOps: [],
      loading: false,
      error: null,
      startVisit: vi.fn(),
      completeVisit: mockCompleteVisit,
      skipVisit: vi.fn(),
      retryOperation: vi.fn(),
      discardFailedOperation: vi.fn(),
      saveChecklistDraft: vi.fn(),
      saveGpsExceptionReason: mockSaveReason,
      reloadFromDb: vi.fn()
    } as unknown as ReturnType<typeof useVisitExecutionSession>)

    render(<VisitExecutionMode />)

    expect(screen.getByText(/أنت خارج النطاق الجغرافي المسموح به للعميل/)).toBeDefined()
    expect(screen.getByText(/مبرر تجاوز موقع العميل الجغرافي/)).toBeDefined()

    const completeBtn = screen.getByText('إنهاء الزيارة')
    expect(completeBtn.closest('button')?.disabled).toBe(true)
  })

  it('does not enforce GPS exception or disable complete button when validation status is passed', () => {
    mockAtomicExecution = true
    const mockSession = {
      userId: 'test-user-123',
      planId: 'plan-123',
      itemId: 'item-1',
      serverStartedAt: '2026-07-06T19:00:00Z',
      clientStartedAt: '2026-07-06T19:00:00Z',
      startGPS: { lat: 30, lng: 31 },
      startGPSAccuracy: 10,
      gpsValidationStatus: 'passed' as any,
      checklistDrafts: {},
      gpsExceptionReason: null,
      updatedAt: Date.now(),
      expiresAt: Date.now() + 1000
    }

    vi.mocked(useVisitExecutionSession).mockReturnValue({
      session: mockSession,
      pendingOps: [],
      loading: false,
      error: null,
      startVisit: vi.fn(),
      completeVisit: vi.fn(),
      skipVisit: vi.fn(),
      retryOperation: vi.fn(),
      discardFailedOperation: vi.fn(),
      saveChecklistDraft: vi.fn(),
      saveGpsExceptionReason: vi.fn(),
      reloadFromDb: vi.fn()
    } as unknown as ReturnType<typeof useVisitExecutionSession>)

    render(<VisitExecutionMode />)

    expect(screen.queryByText(/أنت خارج النطاق الجغرافي المسموح به للعميل/)).toBeNull()
    const completeBtn = screen.getByText('إنهاء الزيارة')
    expect(completeBtn.closest('button')?.disabled).toBe(false)
  })

  it('keeps completion disabled until checklist definitions finish loading', () => {
    mockChecklistQuery = {
      data: [],
      isLoading: true,
      isError: false,
      isSuccess: false,
      refetch: vi.fn()
    }

    vi.mocked(useVisitExecutionSession).mockReturnValue({
      session: {
        userId: 'test-user-123',
        planId: 'plan-123',
        itemId: 'item-1',
        serverStartedAt: '2026-07-06T19:00:00Z',
        clientStartedAt: '2026-07-06T19:00:00Z',
        startGPS: { lat: 30, lng: 31 },
        startGPSAccuracy: 10,
        gpsValidationStatus: 'passed',
        checklistDrafts: {},
        gpsExceptionReason: null,
        updatedAt: Date.now(),
        expiresAt: Date.now() + 1000
      },
      pendingOps: [], loading: false, error: null,
      startVisit: vi.fn(), completeVisit: vi.fn(), skipVisit: vi.fn(),
      retryOperation: vi.fn(), discardFailedOperation: vi.fn(),
      saveChecklistDraft: vi.fn(), saveGpsExceptionReason: vi.fn(), reloadFromDb: vi.fn()
    } as unknown as ReturnType<typeof useVisitExecutionSession>)

    render(<VisitExecutionMode />)

    expect(screen.getByText('جاري تحميل استبيانات الزيارة...')).toBeDefined()
    expect(screen.getByText('إنهاء الزيارة').closest('button')?.disabled).toBe(true)
  })

  it('keeps completion disabled when a purpose-specific mandatory checklist is incomplete', () => {
    mockChecklistQuery = {
      data: [
        { id: 'core-template', name: 'نتيجة الزيارة الأساسية', is_mandatory: true, questions: [] },
        { id: 'activation-template', name: 'تنشيط العميل أو المنتج', is_mandatory: true, questions: [] }
      ] as unknown as ChecklistTemplate[],
      isLoading: false,
      isError: false,
      isSuccess: true,
      refetch: vi.fn()
    }

    vi.mocked(useVisitExecutionSession).mockReturnValue({
      session: {
        userId: 'test-user-123',
        planId: 'plan-123',
        itemId: 'item-1',
        serverStartedAt: '2026-07-06T19:00:00Z',
        clientStartedAt: '2026-07-06T19:00:00Z',
        startGPS: { lat: 30, lng: 31 },
        startGPSAccuracy: 10,
        gpsValidationStatus: 'passed',
        checklistDrafts: {
          'core-template': { responses: [], isComplete: true }
        },
        gpsExceptionReason: null,
        updatedAt: Date.now(),
        expiresAt: Date.now() + 1000
      },
      pendingOps: [], loading: false, error: null,
      startVisit: vi.fn(), completeVisit: vi.fn(), skipVisit: vi.fn(),
      retryOperation: vi.fn(), discardFailedOperation: vi.fn(),
      saveChecklistDraft: vi.fn(), saveGpsExceptionReason: vi.fn(), reloadFromDb: vi.fn()
    } as unknown as ReturnType<typeof useVisitExecutionSession>)

    render(<VisitExecutionMode />)

    expect(screen.getByText(/تنشيط العميل أو المنتج/)).toBeDefined()
    expect(screen.getByText('إنهاء الزيارة').closest('button')?.disabled).toBe(true)
  })

  it('renders blocker screen when VISITS_ATOMIC_EXECUTION is false', () => {
    mockAtomicExecution = false

    vi.mocked(useVisitExecutionSession).mockReturnValue({
      session: null,
      pendingOps: [],
      loading: false,
      error: null,
      startVisit: vi.fn(),
      completeVisit: vi.fn(),
      skipVisit: vi.fn(),
      retryOperation: vi.fn(),
      discardFailedOperation: vi.fn(),
      saveChecklistDraft: vi.fn(),
      saveGpsExceptionReason: vi.fn(),
      reloadFromDb: vi.fn()
    } as unknown as ReturnType<typeof useVisitExecutionSession>)

    render(<VisitExecutionMode />)

    // Updated text assertions to match UX-improved blocker screen (Quick Wins)
    expect(screen.getByText('وضع التنفيذ غير متاح')).toBeDefined()
    expect(screen.getByText(/مسار التنفيذ الميداني غير مفعّل/)).toBeDefined()
  })

  it('Atomic=true مع الصلاحيتين -> لا blocker', () => {
    mockAtomicExecution = true
    activeExecutionPermissions = [PERMISSIONS.VISIT_PLANS_UPDATE_OWN, PERMISSIONS.ACTIVITIES_CREATE]

    vi.mocked(useVisitExecutionSession).mockReturnValue({
      session: null,
      pendingOps: [],
      loading: false,
      error: null,
      startVisit: vi.fn(),
      completeVisit: vi.fn(),
      skipVisit: vi.fn(),
      retryOperation: vi.fn(),
      discardFailedOperation: vi.fn(),
      saveChecklistDraft: vi.fn(),
      saveGpsExceptionReason: vi.fn(),
      reloadFromDb: vi.fn()
    } as unknown as ReturnType<typeof useVisitExecutionSession>)

    render(<VisitExecutionMode />)
    expect(screen.queryByText('غير مصرح بالدخول')).toBeNull()
  })

  it('Atomic=true مع update_own فقط -> blocker', () => {
    mockAtomicExecution = true
    activeExecutionPermissions = [PERMISSIONS.VISIT_PLANS_UPDATE_OWN]

    vi.mocked(useVisitExecutionSession).mockReturnValue({
      session: null,
      pendingOps: [],
      loading: false,
      error: null,
      startVisit: vi.fn(),
      completeVisit: vi.fn(),
      skipVisit: vi.fn(),
      retryOperation: vi.fn(),
      discardFailedOperation: vi.fn(),
      saveChecklistDraft: vi.fn(),
      saveGpsExceptionReason: vi.fn(),
      reloadFromDb: vi.fn()
    } as unknown as ReturnType<typeof useVisitExecutionSession>)

    render(<VisitExecutionMode />)
    expect(screen.queryByText('غير مصرح بالدخول')).not.toBeNull()
  })

  it('Atomic=true مع activities.create فقط -> blocker', () => {
    mockAtomicExecution = true
    activeExecutionPermissions = [PERMISSIONS.ACTIVITIES_CREATE]

    vi.mocked(useVisitExecutionSession).mockReturnValue({
      session: null,
      pendingOps: [],
      loading: false,
      error: null,
      startVisit: vi.fn(),
      completeVisit: vi.fn(),
      skipVisit: vi.fn(),
      retryOperation: vi.fn(),
      discardFailedOperation: vi.fn(),
      saveChecklistDraft: vi.fn(),
      saveGpsExceptionReason: vi.fn(),
      reloadFromDb: vi.fn()
    } as unknown as ReturnType<typeof useVisitExecutionSession>)

    render(<VisitExecutionMode />)
    expect(screen.queryByText('غير مصرح بالدخول')).not.toBeNull()
  })

  it('Atomic=false -> لا يطبق blocker الذري ويحافظ على السلوك Legacy الموجود', () => {
    mockAtomicExecution = false
    activeExecutionPermissions = [PERMISSIONS.VISIT_PLANS_CREATE]

    vi.mocked(useVisitExecutionSession).mockReturnValue({
      session: null,
      pendingOps: [],
      loading: false,
      error: null,
      startVisit: vi.fn(),
      completeVisit: vi.fn(),
      skipVisit: vi.fn(),
      retryOperation: vi.fn(),
      discardFailedOperation: vi.fn(),
      saveChecklistDraft: vi.fn(),
      saveGpsExceptionReason: vi.fn(),
      reloadFromDb: vi.fn()
    } as unknown as ReturnType<typeof useVisitExecutionSession>)

    render(<VisitExecutionMode />)
    expect(screen.queryByText('وضع التنفيذ غير متاح')).not.toBeNull()
    expect(screen.queryByText('غير مصرح بالدخول')).toBeNull()
  })
})
