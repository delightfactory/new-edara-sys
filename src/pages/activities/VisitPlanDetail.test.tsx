import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, within, waitFor, cleanup } from '@testing-library/react'
import VisitPlanDetail from './VisitPlanDetail'
import { toast } from 'sonner'
import type { VisitPlan, VisitPlanItem, VisitRpcResult, CreateVisitPlanAtomicResult } from '@/lib/types/activities'
import { useAuthStore } from '@/stores/auth-store'
import { PERMISSIONS } from '@/lib/permissions/constants'

const mockNavigate = vi.fn()

function tomorrow(): string {
  const d = new Date()
  d.setDate(d.getDate() + 1)
  return d.toISOString().split('T')[0]
}

vi.mock('react-router-dom', () => ({
  useParams: () => ({ id: 'plan-123' }),
  useNavigate: () => mockNavigate
}))

vi.mock('sonner', () => ({
  toast: {
    success: vi.fn(),
    error: vi.fn(),
    warning: vi.fn()
  }
}))

vi.mock('@/stores/auth-store', () => {
  type StoreState = ReturnType<typeof import('@/stores/auth-store').useAuthStore.getState>
  const mockStore = vi.fn((selector?: (state: StoreState) => unknown) => {
    const state = {
      profile: { id: 'user-123' } as unknown as StoreState['profile'],
      can: () => true,
      canAny: () => true,
      canAll: () => true
    } as unknown as StoreState
    return selector ? selector(state) : state
  })
  return {
    useAuthStore: Object.assign(mockStore, {
      getState: vi.fn(() => ({
        profile: { id: 'user-123' } as unknown as StoreState['profile'],
        can: () => true,
        canAny: () => true,
        canAll: () => true
      } as unknown as StoreState))
    })
  }
})

const mockUpdatePlanItemMutate = vi.fn()
const mockUpdatePlanItemMutateAsync = vi.fn().mockResolvedValue({})
const mockSkipVisitAtomicMutate = vi.fn()
const mockRescheduleAtomicMutate = vi.fn()
const mockCloseMissedAtomicMutate = vi.fn()

const mockConfirmPlanMutate = vi.fn()
const mockCancelPlanMutate = vi.fn()
const mockConfirmPlanAtomicMutate = vi.fn()
const mockCancelPlanAtomicMutate = vi.fn()
const mockCreatePlanAtomicMutate = vi.fn()
const mockReorderPlanItemsAtomicMutate = vi.fn()
const mockAddPlanItemAtomicMutate = vi.fn()
const mockDeletePlanItemAtomicMutate = vi.fn()

let mockPlanStatus = 'in_progress'
let mockCurrentEmployee: { id: string } | null = { id: 'emp-123' }
let mockPlanEmployeeId = 'emp-123'

type StoreState = ReturnType<typeof useAuthStore.getState>
type PermissionType = Parameters<StoreState['can']>[0]

function mockPermissions(
  permissions: PermissionType[] | ((perm: PermissionType) => boolean),
  profileId = 'user-123'
) {
  const check = typeof permissions === 'function'
    ? permissions
    : (perm: PermissionType) => permissions.includes(perm) || permissions.includes('*')

  vi.mocked(useAuthStore).mockImplementation((selector?: (state: StoreState) => unknown) => {
    const state: StoreState = {
      profile: { id: profileId } as unknown as StoreState['profile'],
      permissions: Array.isArray(permissions) ? permissions : [],
      isLoading: false,
      isInitialized: true,
      hasSession: true,
      profileLoadError: null,
      setProfile: vi.fn(),
      setPermissions: vi.fn(),
      setLoading: vi.fn(),
      setInitialized: vi.fn(),
      setHasSession: vi.fn(),
      setProfileLoadError: vi.fn(),
      can: check,
      canAny: (perms: PermissionType[]) => perms.some(check),
      canAll: (perms: PermissionType[]) => perms.every(check),
      reset: vi.fn()
    }
    return selector ? selector(state) : state
  })
}

vi.mock('@/hooks/useCustomerBranches', () => ({
  useCustomerBranches: () => ({
    branches: [
      { id: 'branch-1', customer_id: 'cust-1', name: 'الفرع الرئيسي', is_primary: true }
    ],
    isLoading: false
  })
}))

vi.mock('@/hooks/useCustomerSearch', () => ({
  useCustomerSearch: () => ({
    results: [],
    isLoading: false,
    hasMore: false,
    search: '',
    setSearch: vi.fn(),
    loadMore: vi.fn(),
    refresh: vi.fn(),
  }),
  default: () => ({
    results: [],
    isLoading: false,
    hasMore: false,
    search: '',
    setSearch: vi.fn(),
    loadMore: vi.fn(),
    refresh: vi.fn(),
  }),
}))

vi.mock('@/hooks/useQueryHooks', () => ({
  useCurrentEmployee: () => ({
    data: mockCurrentEmployee,
    isLoading: false
  }),
  useVisitPlan: () => ({
    data: {
      id: 'plan-123',
      plan_date: '2026-07-06',
      employee_id: mockPlanEmployeeId,
      employee: { full_name: 'موظف 1' },
      status: mockPlanStatus,
      total_customers: 1,
      completed_count: 0,
      skipped_count: 0,
      completion_pct: 0
    } as VisitPlan,
    isLoading: false
  }),
  useVisitPlanItems: () => ({
    data: [
      {
        id: 'item-1',
        plan_id: 'plan-123',
        status: 'pending',
        customer_id: 'cust-1',
        customer_branch_id: 'branch-123',
        customer: { id: 'cust-1', name: 'عميل 1', code: 'C1' },
        sequence: 1,
        priority: 'normal',
        expected_lat: 30.123,
        expected_lng: 31.456,
      } as unknown as VisitPlanItem,
      {
        id: 'item-2',
        plan_id: 'plan-123',
        status: 'pending',
        customer_id: 'cust-2',
        customer_branch_id: null,
        customer: { id: 'cust-2', name: 'عميل 2', code: 'C2' },
        sequence: 2,
        priority: 'normal',
        expected_lat: 30.456,
        expected_lng: 31.789,
      } as unknown as VisitPlanItem,
      {
        id: 'item-3',
        plan_id: 'plan-123',
        status: 'pending',
        customer_id: 'cust-3',
        customer: { id: 'cust-3', name: 'عميل 3', code: 'C3' },
        sequence: 3,
        priority: 'normal'
      } as unknown as VisitPlanItem
    ],
    isLoading: false
  }),
  useConfirmVisitPlan: () => ({ mutate: mockConfirmPlanMutate }),
  useCancelVisitPlan: () => ({ mutate: mockCancelPlanMutate }),
  useConfirmVisitPlanAtomic: () => ({ mutate: mockConfirmPlanAtomicMutate }),
  useCancelVisitPlanAtomic: () => ({ mutate: mockCancelPlanAtomicMutate }),
  useAddVisitPlanItem: () => ({ mutate: vi.fn() }),
  useUpdateVisitPlanItem: () => ({ mutate: mockUpdatePlanItemMutate, mutateAsync: mockUpdatePlanItemMutateAsync }),
  useCustomers: () => ({ data: { data: [{ id: 'cust-1', name: 'عميل 1', code: 'C1' }] } }),
  useCreateVisitPlan: () => ({ mutate: vi.fn() }),
  useDeleteVisitPlanItem: () => ({ mutate: vi.fn() }),
  useReorderVisitPlanItems: () => ({ mutate: vi.fn() }),
  useCreateVisitPlanTemplateMutation: () => ({ mutate: vi.fn() }),
  useSkipVisitItemAtomic: () => ({ mutate: mockSkipVisitAtomicMutate }),
  useRescheduleVisitItemToDateAtomic: () => ({ mutate: mockRescheduleAtomicMutate }),
  useCloseVisitDayMissedAtomic: () => ({ mutate: mockCloseMissedAtomicMutate }),
  useCreateVisitPlanAtomic: () => ({ mutate: mockCreatePlanAtomicMutate }),
  useReorderVisitPlanItemsAtomic: () => ({ mutate: mockReorderPlanItemsAtomicMutate }),
  useAddVisitPlanItemAtomic: () => ({ mutate: mockAddPlanItemAtomicMutate }),
  useDeleteVisitPlanItemAtomic: () => ({ mutate: mockDeletePlanItemAtomicMutate }),
}))

// Mock components used in VisitPlanDetail so we can trigger the actions
vi.mock('@/components/shared/PlanItemCard', () => ({
  default: ({ item, onStart, onSkip, onReschedule }: { item: VisitPlanItem; onStart?: () => void; onSkip?: (item: VisitPlanItem) => void; onReschedule?: (item: VisitPlanItem) => void }) => (
    <div>
      <span>{item.customer?.name}</span>
      {onStart && <button onClick={onStart}>بدء الزيارة</button>}
      {onSkip && <button onClick={() => onSkip(item)}>تخطي</button>}
      {onReschedule && <button onClick={() => onReschedule(item)}>إعادة جدولة</button>}
    </div>
  )
}))

let mockIsAtomic = true
vi.mock('@/lib/config/features', () => ({
  get VISITS_ATOMIC_EXECUTION() { return mockIsAtomic }
}))

describe('VisitPlanDetail - Execution Actions', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockIsAtomic = true
    mockPlanStatus = 'in_progress'
    mockPermissions(['*'])
  })

  it('redirects to visit execution route on start visit click', async () => {
    render(<VisitPlanDetail />)
    const startBtn = screen.getAllByRole('button', { name: 'بدء الزيارة' })[0]
    fireEvent.click(startBtn)
    expect(mockNavigate).toHaveBeenCalledWith('/activities/visit-plans/plan-123/execute')
  })

  it('uses atomic skip RPC when VISITS_ATOMIC_EXECUTION=true and does not call updateVisitPlanItem', async () => {
    render(<VisitPlanDetail />)
    
    fireEvent.click(screen.getAllByRole('button', { name: 'تخطي' })[0])
    
    const reasonBtn = screen.getByRole('button', { name: 'محل مغلق' })
    fireEvent.click(reasonBtn)
    
    const confirmBtn = screen.getByRole('button', { name: 'تخطي البند' })
    fireEvent.click(confirmBtn)
    
    expect(mockUpdatePlanItemMutate).not.toHaveBeenCalled()
    expect(mockSkipVisitAtomicMutate).toHaveBeenCalled()
    expect(mockSkipVisitAtomicMutate.mock.calls[0][0].input.skipReason).toBe('محل مغلق')
    expect(mockSkipVisitAtomicMutate.mock.calls[0][0].input.operationId).toBeDefined()
  })

  it('uses legacy updateVisitPlanItem for skip when VISITS_ATOMIC_EXECUTION=false', async () => {
    mockIsAtomic = false
    render(<VisitPlanDetail />)
    
    fireEvent.click(screen.getAllByRole('button', { name: 'تخطي' })[0])
    
    const reasonBtn = screen.getByRole('button', { name: 'محل مغلق' })
    fireEvent.click(reasonBtn)
    
    const confirmBtn = screen.getByRole('button', { name: 'تخطي البند' })
    fireEvent.click(confirmBtn)
    
    expect(mockSkipVisitAtomicMutate).not.toHaveBeenCalled()
    expect(mockUpdatePlanItemMutate).toHaveBeenCalled()
    expect(mockUpdatePlanItemMutate.mock.calls[0][0].input.status).toBe('skipped')
    expect(mockUpdatePlanItemMutate.mock.calls[0][0].input.skip_reason).toBe('محل مغلق')
  })

  it('blocks atomic reschedule RPC when VISITS_ATOMIC_EXECUTION=true if reason is empty', async () => {
    const { container } = render(<VisitPlanDetail />)
    
    fireEvent.click(screen.getAllByRole('button', { name: 'إعادة جدولة' })[0])
    const confirmBtn = screen.getByRole('button', { name: 'تأكيد إعادة الجدولة' })
    
    const dateInputs = container.querySelectorAll('input[type="date"]')
    if(dateInputs.length > 0) fireEvent.change(dateInputs[0], { target: { value: '2026-07-10' } })
    
    fireEvent.click(confirmBtn)
    
    expect(toast.error).toHaveBeenCalledWith('يرجى كتابة سبب إعادة الجدولة')
    expect(mockRescheduleAtomicMutate).not.toHaveBeenCalled()
  })

  it('uses atomic reschedule RPC when VISITS_ATOMIC_EXECUTION=true and reason is provided', async () => {
    const { container } = render(<VisitPlanDetail />)
    
    fireEvent.click(screen.getAllByRole('button', { name: 'إعادة جدولة' })[0])
    const confirmBtn = screen.getByRole('button', { name: 'تأكيد إعادة الجدولة' })
    
    const dateInputs = container.querySelectorAll('input[type="date"]')
    if(dateInputs.length > 0) fireEvent.change(dateInputs[0], { target: { value: '2026-07-10' } })
    
    const textareas = container.querySelectorAll('textarea')
    if(textareas.length > 0) fireEvent.change(textareas[0], { target: { value: 'العميل مسافر' } })

    fireEvent.click(confirmBtn)
    
    expect(mockRescheduleAtomicMutate).toHaveBeenCalled()
    expect(mockRescheduleAtomicMutate.mock.calls[0][0].input.targetDate).toBe('2026-07-10')
    expect(mockRescheduleAtomicMutate.mock.calls[0][0].input.rescheduleReason).toBe('العميل مسافر')
    expect(mockUpdatePlanItemMutate).not.toHaveBeenCalled()
  })

  it('uses atomic close missed RPC when VISITS_ATOMIC_EXECUTION=true', async () => {
    render(<VisitPlanDetail />)
    
    const bulkCloseTrigger = screen.queryByText('إنهاء اليومية المتبقية')
    if (bulkCloseTrigger) {
      fireEvent.click(bulkCloseTrigger)
      const confirmBtn = screen.getByRole('button', { name: 'تسجيل كافة المعلقات كزيارات فائتة' })
      fireEvent.click(confirmBtn)
      
      expect(mockCloseMissedAtomicMutate).toHaveBeenCalled()
      expect(mockCloseMissedAtomicMutate.mock.calls[0][0].input.closeReason).toBe('انتهاء الدوام الزمني')
      expect(mockUpdatePlanItemMutateAsync).not.toHaveBeenCalled()
    }
  })

  describe('Confirm & Cancel Plan Actions - Idempotency & Mutex Locking', () => {
    beforeEach(() => {
      mockPlanStatus = 'draft'
    })

    it('uses atomic confirm when VISITS_ATOMIC_EXECUTION=true, locks double click, and reuses operationId on failure', async () => {
      // Mock failure trigger and call onSettled asynchronously to release lock
      mockConfirmPlanAtomicMutate.mockImplementationOnce((_args: unknown, options: { onError: (err: Error) => void; onSettled: () => void }) => {
        setTimeout(() => {
          options.onError(new Error('Confirm API failed'))
          options.onSettled()
        }, 0)
      })

      render(<VisitPlanDetail />)
      const confirmTriggerBtn = screen.getByRole('button', { name: 'تأكيد واعتماد' })
      fireEvent.click(confirmTriggerBtn)

      const modalConfirmBtn = screen.getByRole('button', { name: 'تأكيد' })
      // double click
      fireEvent.click(modalConfirmBtn)
      fireEvent.click(modalConfirmBtn)

      // mutex locks ensures only 1 mutation is sent
      expect(mockConfirmPlanAtomicMutate).toHaveBeenCalledTimes(1)
      
      // Wait for async execution timeout (releases lock)
      await new Promise(resolve => setTimeout(resolve, 0))
      
      const firstOpId = mockConfirmPlanAtomicMutate.mock.calls[0][0].operationId

      // retry again after failure
      fireEvent.click(modalConfirmBtn)
      expect(mockConfirmPlanAtomicMutate).toHaveBeenCalledTimes(2)
      const secondOpId = mockConfirmPlanAtomicMutate.mock.calls[1][0].operationId

      expect(secondOpId).toBe(firstOpId) // Idempotent opId is reused
      expect(mockConfirmPlanMutate).not.toHaveBeenCalled()
    })

    it('uses legacy confirm when VISITS_ATOMIC_EXECUTION=false', () => {
      mockIsAtomic = false
      render(<VisitPlanDetail />)
      const confirmTriggerBtn = screen.getByRole('button', { name: 'تأكيد واعتماد' })
      fireEvent.click(confirmTriggerBtn)

      const modalConfirmBtn = screen.getByRole('button', { name: 'تأكيد' })
      fireEvent.click(modalConfirmBtn)

      expect(mockConfirmPlanMutate).toHaveBeenCalledWith('plan-123', expect.any(Object))
      expect(mockConfirmPlanAtomicMutate).not.toHaveBeenCalled()
    })

    it('atomic cancel mandates reason, locks reason textarea and reuses opId/reason on retry', async () => {
      mockCancelPlanAtomicMutate.mockImplementationOnce((_args: unknown, options: { onError: (err: Error) => void; onSettled: () => void }) => {
        setTimeout(() => {
          options.onError(new Error('Cancel RPC failed'))
          options.onSettled()
        }, 0)
      })

      render(<VisitPlanDetail />)
      const cancelTriggerBtn = screen.getByRole('button', { name: 'إلغاء خطة الزيارات' })
      fireEvent.click(cancelTriggerBtn)

      const modalCancelBtn = screen.getByRole('button', { name: 'إلغاء الخطة' })
      fireEvent.click(modalCancelBtn)
      expect(mockCancelPlanAtomicMutate).not.toHaveBeenCalled() // blocked: empty reason

      const reasonTextarea = screen.getByPlaceholderText('اذكر سبب الإلغاء وجوباً...')
      fireEvent.change(reasonTextarea, { target: { value: 'إلغاء مشرف' } })
      
      // first cancel call (fails)
      fireEvent.click(modalCancelBtn)
      await new Promise(resolve => setTimeout(resolve, 0))

      expect(mockCancelPlanAtomicMutate).toHaveBeenCalledTimes(1)
      const firstArgs = mockCancelPlanAtomicMutate.mock.calls[0][0]
      expect(firstArgs.reason).toBe('إلغاء مشرف')
      expect(reasonTextarea.hasAttribute('disabled')).toBe(true) // locks input

      // second call (retries with same opId and reason)
      fireEvent.click(modalCancelBtn)
      expect(mockCancelPlanAtomicMutate).toHaveBeenCalledTimes(2)
      const secondArgs = mockCancelPlanAtomicMutate.mock.calls[1][0]
      expect(secondArgs.operationId).toBe(firstArgs.operationId)
      expect(secondArgs.reason).toBe('إلغاء مشرف')
      expect(mockCancelPlanMutate).not.toHaveBeenCalled()
    })

    it('legacy cancel triggers legacy cancel mutate', () => {
      mockIsAtomic = false
      render(<VisitPlanDetail />)
      const cancelTriggerBtn = screen.getByRole('button', { name: 'إلغاء خطة الزيارات' })
      fireEvent.click(cancelTriggerBtn)

      const modalCancelBtn = screen.getByRole('button', { name: 'إلغاء الخطة' })
      fireEvent.click(modalCancelBtn)

      expect(mockCancelPlanMutate).toHaveBeenCalledWith({ id: 'plan-123', reason: undefined }, expect.any(Object))
      expect(mockCancelPlanAtomicMutate).not.toHaveBeenCalled()
    })
  })

  describe('Wave 1.5 Atomic Operations - Idempotency & Mutex & Permissions', () => {
    beforeEach(() => {
      vi.clearAllMocks()
      mockIsAtomic = true
      mockPlanStatus = 'confirmed'
      mockCurrentEmployee = { id: 'emp-123' }
      mockPlanEmployeeId = 'emp-123'

      mockPermissions(['*'])
    })

    it('skip item preserves operationId & payload, locks double click, disables UI inputs and resets on close', async () => {
      mockSkipVisitAtomicMutate.mockImplementation((_args: unknown, options: { onError: (err: Error) => void; onSettled: () => void }) => {
        setTimeout(() => {
          options.onError(new Error('Skip failed'))
          options.onSettled()
        }, 0)
      })

      render(<VisitPlanDetail />)
      fireEvent.click(screen.getAllByRole('button', { name: 'تخطي' })[0])

      // Click on Skip Reason button
      const reasonBtn = screen.getByRole('button', { name: 'محل مغلق' })
      fireEvent.click(reasonBtn)

      const confirmBtn = screen.getByRole('button', { name: 'تخطي البند' })
      // Mutex test: double-click
      fireEvent.click(confirmBtn)
      fireEvent.click(confirmBtn)

      expect(mockSkipVisitAtomicMutate).toHaveBeenCalledTimes(1)
      expect(reasonBtn.hasAttribute('disabled')).toBe(true)

      const firstCallArgs = mockSkipVisitAtomicMutate.mock.calls[0][0].input
      expect(firstCallArgs.skipReason).toBe('محل مغلق')
      expect(firstCallArgs.clientEventAt).toBeDefined()
      expect(firstCallArgs.deviceTimezone).toBeDefined()

      // wait for mock timeout to resolve
      await new Promise(r => setTimeout(r, 0))

      // retry again
      fireEvent.click(confirmBtn)
      expect(mockSkipVisitAtomicMutate).toHaveBeenCalledTimes(2)

      const secondCallArgs = mockSkipVisitAtomicMutate.mock.calls[1][0].input
      expect(secondCallArgs.operationId).toBe(firstCallArgs.operationId)
      expect(secondCallArgs.clientEventAt).toBe(firstCallArgs.clientEventAt)
      expect(secondCallArgs.deviceTimezone).toBe(firstCallArgs.deviceTimezone)

      // wait for mock timeout to resolve
      const skipModal = screen.getByRole('dialog', { name: /تخطي:/ })
      const cancelBtn = within(skipModal).getByRole('button', { name: 'إلغاء' })
      await waitFor(() => expect(cancelBtn.hasAttribute('disabled')).toBe(false))

      // Close modal
      fireEvent.click(cancelBtn)
      await waitFor(() => expect(screen.queryByRole('dialog', { name: /تخطي:/ })).toBeNull())

      // Reopen modal: should generate a new UUID
      fireEvent.click(screen.getAllByRole('button', { name: 'تخطي' })[0])
      const newSkipModal = await screen.findByRole('dialog', { name: /تخطي:/ })
      const newReasonBtn = within(newSkipModal).getByRole('button', { name: 'محل مغلق' })
      fireEvent.click(newReasonBtn)
      const newConfirmBtn = within(newSkipModal).getByRole('button', { name: 'تخطي البند' })
      fireEvent.click(newConfirmBtn)

      expect(mockSkipVisitAtomicMutate).toHaveBeenCalledTimes(3)
      const thirdCallArgs = mockSkipVisitAtomicMutate.mock.calls[2][0].input
      expect(thirdCallArgs.operationId).not.toBe(firstCallArgs.operationId)
    })

    it('reschedule item preserves operationId & payload, locks inputs and resets on close', async () => {
      mockRescheduleAtomicMutate.mockImplementation((_args: unknown, options: { onError: (err: Error) => void; onSettled: () => void }) => {
        setTimeout(() => {
          options.onError(new Error('Reschedule failed'))
          options.onSettled()
        }, 0)
      })

      const { container } = render(<VisitPlanDetail />)
      fireEvent.click(screen.getAllByRole('button', { name: 'إعادة جدولة' })[0])

      const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
      fireEvent.change(dateInput, { target: { value: '2026-07-10' } })

      const reasonTextarea = container.querySelector('textarea') as HTMLTextAreaElement
      fireEvent.change(reasonTextarea, { target: { value: 'طلب العميل تأجيل' } })

      const confirmBtn = screen.getByRole('button', { name: 'تأكيد إعادة الجدولة' })
      // Double click
      fireEvent.click(confirmBtn)
      fireEvent.click(confirmBtn)

      expect(mockRescheduleAtomicMutate).toHaveBeenCalledTimes(1)
      expect(dateInput.hasAttribute('disabled')).toBe(true)
      expect(reasonTextarea.hasAttribute('disabled')).toBe(true)

      const firstArgs = mockRescheduleAtomicMutate.mock.calls[0][0].input
      expect(firstArgs.targetDate).toBe('2026-07-10')
      expect(firstArgs.rescheduleReason).toBe('طلب العميل تأجيل')

      await new Promise(r => setTimeout(r, 0))

      // Click again
      fireEvent.click(confirmBtn)
      expect(mockRescheduleAtomicMutate).toHaveBeenCalledTimes(2)

      const secondArgs = mockRescheduleAtomicMutate.mock.calls[1][0].input
      expect(secondArgs.operationId).toBe(firstArgs.operationId)
      expect(secondArgs.clientEventAt).toBe(firstArgs.clientEventAt)
      expect(secondArgs.deviceTimezone).toBe(firstArgs.deviceTimezone)

      // wait for mock timeout to resolve
      const rescheduleModal = screen.getByRole('dialog', { name: /إعادة جدولة:/ })
      const cancelBtn = within(rescheduleModal).getByRole('button', { name: 'إلغاء' })
      await waitFor(() => expect(cancelBtn.hasAttribute('disabled')).toBe(false))

      // Close modal
      fireEvent.click(cancelBtn)
      await waitFor(() => expect(screen.queryByRole('dialog', { name: /إعادة جدولة:/ })).toBeNull())

      // Reopen modal: should generate new UUID
      fireEvent.click(screen.getAllByRole('button', { name: 'إعادة جدولة' })[0])
      const newRescheduleModal = await screen.findByRole('dialog', { name: /إعادة جدولة:/ })
      const newReasonTextarea = within(newRescheduleModal).getByPlaceholderText('اكتب سبب إعادة الجدولة...')
      fireEvent.change(newReasonTextarea, { target: { value: 'تأجيل جديد' } })
      const newConfirmBtn = within(newRescheduleModal).getByRole('button', { name: 'تأكيد إعادة الجدولة' })
      fireEvent.click(newConfirmBtn)
      expect(mockRescheduleAtomicMutate).toHaveBeenCalledTimes(3)
      const thirdArgs = mockRescheduleAtomicMutate.mock.calls[2][0].input
      expect(thirdArgs.operationId).not.toBe(firstArgs.operationId)
    })

    it('bulk close missed day preserves operationId & payload, locks inputs and resets on close', async () => {
      mockPlanStatus = 'in_progress'
      mockCloseMissedAtomicMutate.mockImplementation((_args: unknown, options: { onError: (err: Error) => void; onSettled: () => void }) => {
        setTimeout(() => {
          options.onError(new Error('Close day missed failed'))
          options.onSettled()
        }, 0)
      })

      const { container } = render(<VisitPlanDetail />)
      fireEvent.click(screen.getByRole('button', { name: 'إنهاء اليومية المتبقية' }))

      const reasonInput = container.querySelector('input[placeholder="مثال: انتهاء الدوام، ظروف جوية، مشكلة طارئة..."]') as HTMLInputElement
      fireEvent.change(reasonInput, { target: { value: 'انتهاء الدوام' } })

      const confirmBtn = screen.getByRole('button', { name: 'تسجيل كافة المعلقات كزيارات فائتة' })
      // Double click
      fireEvent.click(confirmBtn)
      fireEvent.click(confirmBtn)

      expect(mockCloseMissedAtomicMutate).toHaveBeenCalledTimes(1)
      expect(reasonInput.hasAttribute('disabled')).toBe(true)

      const firstArgs = mockCloseMissedAtomicMutate.mock.calls[0][0].input
      expect(firstArgs.closeReason).toBe('انتهاء الدوام')

      await new Promise(r => setTimeout(r, 0))

      // Click again
      fireEvent.click(confirmBtn)
      expect(mockCloseMissedAtomicMutate).toHaveBeenCalledTimes(2)

      const secondArgs = mockCloseMissedAtomicMutate.mock.calls[1][0].input
      expect(secondArgs.operationId).toBe(firstArgs.operationId)
      expect(secondArgs.clientEventAt).toBe(firstArgs.clientEventAt)
      expect(secondArgs.deviceTimezone).toBe(firstArgs.deviceTimezone)

      // wait for mock timeout to resolve
      const bulkModal = screen.getByRole('dialog', { name: /إنهاء يومية/ })
      const cancelBtn = within(bulkModal).getByRole('button', { name: 'إلغاء' })
      await waitFor(() => expect(cancelBtn.hasAttribute('disabled')).toBe(false))

      // Close modal
      fireEvent.click(cancelBtn)
      await waitFor(() => expect(screen.queryByRole('dialog', { name: /إنهاء يومية/ })).toBeNull())

      // Reopen modal: should generate new UUID
      fireEvent.click(screen.getByRole('button', { name: 'إنهاء اليومية المتبقية' }))
      const newBulkModal = await screen.findByRole('dialog', { name: /إنهاء يومية/ })
      const reasonInput2 = within(newBulkModal).getByRole('textbox')
      fireEvent.change(reasonInput2, { target: { value: 'انتهاء الدوام' } })
      const newConfirmBtn = within(newBulkModal).getByRole('button', { name: 'تسجيل كافة المعلقات كزيارات فائتة' })
      fireEvent.click(newConfirmBtn)
      expect(mockCloseMissedAtomicMutate).toHaveBeenCalledTimes(3)
      const thirdArgs = mockCloseMissedAtomicMutate.mock.calls[2][0].input
      expect(thirdArgs.operationId).not.toBe(firstArgs.operationId)
    })

    it('atomic reorder drag-and-drop reuses operationId on retry, blocks different movement and clears on success', async () => {
      mockPlanStatus = 'draft'
      mockReorderPlanItemsAtomicMutate.mockImplementationOnce((_args: unknown, options: { onError: (err: Error) => void; onSettled: () => void }) => {
        setTimeout(() => {
          options.onError(new Error('Reorder failed'))
          options.onSettled()
        }, 0)
      })

      render(<VisitPlanDetail />)
      // Toggle edit mode
      fireEvent.click(screen.getByRole('button', { name: 'تعديل الخطة' }))

      const upBtns = screen.getAllByTitle('تحريك للأعلى')
      // upBtns[1] is for item-2, which is enabled!
      fireEvent.click(upBtns[1])

      expect(mockReorderPlanItemsAtomicMutate).toHaveBeenCalledTimes(1)
      const firstCall = mockReorderPlanItemsAtomicMutate.mock.calls[0][0]
      expect(firstCall.items).toEqual([
        { item_id: 'item-2', sequence: 1 },
        { item_id: 'item-1', sequence: 2 },
        { item_id: 'item-3', sequence: 3 }
      ])

      await new Promise(r => setTimeout(r, 0))

      // Clicking a different button (like ArrowDown on item-2 at idx 1, which swaps it with item-3) BEFORE retry succeeds
      // should block and toast
      const downBtns = screen.getAllByTitle('تحريك للأسفل')
      fireEvent.click(downBtns[1]) // item-2 idx 1 down
      expect(toast.error).toHaveBeenCalledWith('يرجى إعادة محاولة الترتيب السابق أولاً، أو إلغاء نية الترتيب المعلقة.')

      // Click same up button (retry)
      fireEvent.click(upBtns[1])
      expect(mockReorderPlanItemsAtomicMutate).toHaveBeenCalledTimes(2)
      const secondCall = mockReorderPlanItemsAtomicMutate.mock.calls[1][0]
      expect(secondCall.operationId).toBe(firstCall.operationId)
    })

    it('atomic clone preserves customer_branch_id, maps purpose_type null, blocks empty plans and navigates using result.data.plan_id', async () => {
      mockPlanStatus = 'confirmed'
      mockCreatePlanAtomicMutate.mockImplementationOnce((_args: unknown, options: { onSuccess: (res: VisitRpcResult<CreateVisitPlanAtomicResult>) => void; onSettled: () => void }) => {
        setTimeout(() => {
          options.onSuccess({
            ok: true,
            operation_id: 'op-123',
            operation: 'create_visit_plan_atomic',
            replayed: false,
            data: { plan_id: 'new-cloned-plan-id' }
          } as VisitRpcResult<CreateVisitPlanAtomicResult>)
          options.onSettled()
        }, 0)
      })

      const { container } = render(<VisitPlanDetail />)
      fireEvent.click(screen.getByRole('button', { name: 'استنساخ المسار' }))

      const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
      fireEvent.change(dateInput, { target: { value: '2026-07-10' } })

      const confirmBtn = screen.getByRole('button', { name: 'تأكيد العملية' })
      fireEvent.click(confirmBtn)

      expect(mockCreatePlanAtomicMutate).toHaveBeenCalledTimes(1)
      const firstCallArgs = mockCreatePlanAtomicMutate.mock.calls[0][0]
      expect(firstCallArgs.planDate).toBe('2026-07-10')
      expect(firstCallArgs.employeeId).toBe('emp-123')
      expect(firstCallArgs.items[0].customer_branch_id).toBe('branch-123')
      expect(firstCallArgs.items[0].purpose_type).toBeNull()
      expect(firstCallArgs.items[0].sequence).toBe(1)
      expect(firstCallArgs.items[0]).not.toHaveProperty('expected_lat')
      expect(firstCallArgs.items[0]).not.toHaveProperty('expected_lng')

      expect(firstCallArgs.items[1].customer_branch_id).toBeNull()
      expect(firstCallArgs.items[1].purpose_type).toBeNull()
      expect(firstCallArgs.items[1].sequence).toBe(2)
      expect(firstCallArgs.items[1]).not.toHaveProperty('expected_lat')
      expect(firstCallArgs.items[1]).not.toHaveProperty('expected_lng')

      await new Promise(r => setTimeout(r, 0))
      expect(mockNavigate).toHaveBeenCalledWith('/activities/visit-plans/new-cloned-plan-id')
    })

    it('update permission without create permission hides delete button in editMode', () => {
      // Mock useAuthStore to return true for UPDATE but false for CREATE
      mockPermissions([PERMISSIONS.VISIT_PLANS_UPDATE])

      mockPlanStatus = 'draft'
      render(<VisitPlanDetail />)
      
      const editTriggerBtn = screen.queryByRole('button', { name: 'تعديل الخطة' })
      if (editTriggerBtn) {
        fireEvent.click(editTriggerBtn)
        const deleteBtn = screen.queryByRole('button', { name: 'حذف البند' })
        expect(deleteBtn).toBeNull() // Hides delete button
      }
    })

    it('update permission inside confirmed hides add item and reorder button', () => {
      mockPermissions([PERMISSIONS.VISIT_PLANS_UPDATE])

      mockPlanStatus = 'confirmed'
      render(<VisitPlanDetail />)

      const addBtn = screen.queryByRole('button', { name: 'إضافة بند' })
      expect(addBtn).toBeNull()

      const editTriggerBtn = screen.queryByRole('button', { name: 'تعديل الخطة' })
      expect(editTriggerBtn).toBeNull()
    })

    it('update_own ownership logic verification and fail closed behavior', () => {
      // Mock auth store to return UPDATE_OWN permission only
      mockPermissions([PERMISSIONS.VISIT_PLANS_UPDATE_OWN])

      // 1. owned plan: employee_id = emp-123, currentEmployee.id = emp-123
      mockPlanStatus = 'draft'
      mockPlanEmployeeId = 'emp-123'
      mockCurrentEmployee = { id: 'emp-123' }

      render(<VisitPlanDetail />)
      let editTriggerBtn = screen.queryByRole('button', { name: 'تعديل الخطة' })
      expect(editTriggerBtn).not.toBeNull() // Owned plan allows update_own in draft

      // Cleanup DOM
      cleanup()
      vi.clearAllMocks()

      // 2. unowned plan: employee_id = emp-999, currentEmployee.id = emp-123
      mockPlanEmployeeId = 'emp-999'
      mockCurrentEmployee = { id: 'emp-123' }

      render(<VisitPlanDetail />)
      editTriggerBtn = screen.queryByRole('button', { name: 'تعديل الخطة' })
      expect(editTriggerBtn).toBeNull() // Unowned plan blocks update_own

      // Cleanup DOM
      cleanup()
      vi.clearAllMocks()

      // 3. fail closed: currentEmployee is null
      mockPlanEmployeeId = 'emp-123'
      mockCurrentEmployee = null

      render(<VisitPlanDetail />)
      editTriggerBtn = screen.queryByRole('button', { name: 'تعديل الخطة' })
      expect(editTriggerBtn).toBeNull() // Missing currentEmployee fails closed
    })

    it('draft status + create & update permission displays add, delete, and reorder controls', () => {
      mockPermissions([PERMISSIONS.VISIT_PLANS_CREATE, PERMISSIONS.VISIT_PLANS_UPDATE])

      mockPlanStatus = 'draft'
      mockPlanEmployeeId = 'emp-123'
      mockCurrentEmployee = { id: 'emp-123' }

      render(<VisitPlanDetail />)

      const addBtn = screen.getByRole('button', { name: 'إضافة بند' })
      expect(addBtn).not.toBeNull()

      const editTriggerBtn = screen.getByRole('button', { name: 'تعديل الخطة' })
      fireEvent.click(editTriggerBtn)

      const deleteBtns = screen.getAllByTitle('حذف البند')
      expect(deleteBtns.length).toBeGreaterThan(0)

      const upBtns = screen.getAllByTitle('تحريك للأعلى')
      expect(upBtns[1].hasAttribute('disabled')).toBe(false)
    })

    it('CREATE permission only + draft status allows adding and deleting but blocks reordering', () => {
      mockPermissions([PERMISSIONS.VISIT_PLANS_CREATE])

      mockPlanStatus = 'draft'
      mockPlanEmployeeId = 'emp-123'
      mockCurrentEmployee = { id: 'emp-123' }

      render(<VisitPlanDetail />)

      // 1. Add button must show
      const addBtn = screen.getByRole('button', { name: 'إضافة بند' })
      expect(addBtn).not.toBeNull()

      // 2. Can enter editMode
      const editTriggerBtn = screen.getByRole('button', { name: 'تعديل الخطة' })
      expect(editTriggerBtn).not.toBeNull()
      fireEvent.click(editTriggerBtn)

      // 3. Delete buttons must show
      const deleteBtns = screen.getAllByTitle('حذف البند')
      expect(deleteBtns.length).toBeGreaterThan(0)

      // 4. Reorder arrows must NOT show
      const upBtns = screen.queryAllByTitle('تحريك للأعلى')
      expect(upBtns.length).toBe(0)
      const downBtns = screen.queryAllByTitle('تحريك للأسفل')
      expect(downBtns.length).toBe(0)
    })

    it('UPDATE permission only + draft status allows reordering but blocks adding and deleting', () => {
      mockPermissions([PERMISSIONS.VISIT_PLANS_UPDATE])

      mockPlanStatus = 'draft'
      mockPlanEmployeeId = 'emp-123'
      mockCurrentEmployee = { id: 'emp-123' }

      render(<VisitPlanDetail />)

      // 1. Add button must NOT show
      const addBtn = screen.queryByRole('button', { name: 'إضافة بند' })
      expect(addBtn).toBeNull()

      // 2. Can enter editMode
      const editTriggerBtn = screen.getByRole('button', { name: 'تعديل الخطة' })
      expect(editTriggerBtn).not.toBeNull()
      fireEvent.click(editTriggerBtn)

      // 3. Delete buttons must NOT show
      const deleteBtn = screen.queryByTitle('حذف البند')
      expect(deleteBtn).toBeNull()

      // 4. Reorder arrows must show
      const upBtns = screen.getAllByTitle('تحريك للأعلى')
      expect(upBtns.length).toBeGreaterThan(0)
    })

    it('non-draft plan hides adding, deleting, and reordering controls even with full permissions', () => {
      mockPermissions(['*'])

      mockPlanStatus = 'confirmed'
      mockPlanEmployeeId = 'emp-123'
      mockCurrentEmployee = { id: 'emp-123' }

      render(<VisitPlanDetail />)

      // 1. Add button must NOT show
      const addBtn = screen.queryByRole('button', { name: 'إضافة بند' })
      expect(addBtn).toBeNull()

      // 2. Edit trigger button must NOT show
      const editTriggerBtn = screen.queryByRole('button', { name: 'تعديل الخطة' })
      expect(editTriggerBtn).toBeNull()
    })

    it('closing and reopening Clone Modal resets cloneDate to tomorrow()', async () => {
      mockPlanStatus = 'confirmed'
      const { container } = render(<VisitPlanDetail />)
      fireEvent.click(screen.getByRole('button', { name: 'استنساخ المسار' }))

      const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
      fireEvent.change(dateInput, { target: { value: '2026-07-20' } })
      expect(dateInput.value).toBe('2026-07-20')

      const cloneModal = screen.getByRole('dialog', { name: /استنساخ مسار/ })
      const cancelBtn = within(cloneModal).getByRole('button', { name: 'إلغاء' })
      fireEvent.click(cancelBtn)

      await waitFor(() => expect(screen.queryByRole('dialog', { name: /استنساخ مسار/ })).toBeNull())

      // Reopen
      fireEvent.click(screen.getByRole('button', { name: 'استنساخ المسار' }))
      const newCloneModal = await screen.findByRole('dialog', { name: /استنساخ مسار/ })
      const newDateInput = newCloneModal.querySelector('input[type="date"]') as HTMLInputElement
      expect(newDateInput.value).toBe(tomorrow())
    })

    it('closing and reopening Bulk Close Modal resets reason to default انتهاء الدوام الزمني', async () => {
      mockPlanStatus = 'in_progress'
      const { container } = render(<VisitPlanDetail />)
      fireEvent.click(screen.getByRole('button', { name: 'إنهاء اليومية المتبقية' }))

      const bulkModal = screen.getByRole('dialog', { name: /إنهاء يومية/ })
      const reasonInput = within(bulkModal).getByRole('textbox') as HTMLInputElement
      expect(reasonInput.value).toBe('انتهاء الدوام الزمني')

      fireEvent.change(reasonInput, { target: { value: 'تغيير طارئ' } })
      expect(reasonInput.value).toBe('تغيير طارئ')

      const cancelBtn = within(bulkModal).getByRole('button', { name: 'إلغاء' })
      fireEvent.click(cancelBtn)

      await waitFor(() => expect(screen.queryByRole('dialog', { name: /إنهاء يومية/ })).toBeNull())

      // Reopen
      fireEvent.click(screen.getByRole('button', { name: 'إنهاء اليومية المتبقية' }))
      const newBulkModal = await screen.findByRole('dialog', { name: /إنهاء يومية/ })
      const newReasonInput = within(newBulkModal).getByRole('textbox') as HTMLInputElement
      expect(newReasonInput.value).toBe('انتهاء الدوام الزمني')
    })

    it('reordering first item up is disabled and last item down is disabled in the UI', () => {
      mockPermissions(['*'])

      mockPlanStatus = 'draft'
      render(<VisitPlanDetail />)

      const editTriggerBtn = screen.getByRole('button', { name: 'تعديل الخطة' })
      fireEvent.click(editTriggerBtn)

      const upBtns = screen.getAllByTitle('تحريك للأعلى')
      expect(upBtns[0].hasAttribute('disabled')).toBe(true) // First item up is disabled

      const downBtns = screen.getAllByTitle('تحريك للأسفل')
      expect(downBtns[downBtns.length - 1].hasAttribute('disabled')).toBe(true) // Last item down is disabled
    })

    it('blocks rescheduling if rescheduleDate is not set', async () => {
      const { container } = render(<VisitPlanDetail />)
      fireEvent.click(screen.getAllByRole('button', { name: 'إعادة جدولة' })[0])

      const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
      fireEvent.change(dateInput, { target: { value: '' } }) // Clear date

      const confirmBtn = screen.getByRole('button', { name: 'تأكيد إعادة الجدولة' })
      expect(confirmBtn.hasAttribute('disabled')).toBe(true) // Should be disabled if targetDate is empty
    })

    it('disables skip reason buttons while skip mutation is loading', async () => {
      mockSkipVisitAtomicMutate.mockImplementationOnce(() => {
        // Keeps mutating state active
      })

      render(<VisitPlanDetail />)
      fireEvent.click(screen.getAllByRole('button', { name: 'تخطي' })[0])

      const reasonBtn = screen.getByRole('button', { name: 'محل مغلق' })
      fireEvent.click(reasonBtn)

      const confirmBtn = screen.getByRole('button', { name: 'تخطي البند' })
      fireEvent.click(confirmBtn)

      expect(reasonBtn.hasAttribute('disabled')).toBe(true)
    })

    it('blocks reordering during active reorder mutation to prevent concurrent shifts', async () => {
      mockPlanStatus = 'draft'
      mockReorderPlanItemsAtomicMutate.mockImplementationOnce(() => {
        // Mock loading state
      })

      const { rerender } = render(<VisitPlanDetail />)
      fireEvent.click(screen.getByRole('button', { name: 'تعديل الخطة' }))

      const upBtns = screen.getAllByTitle('تحريك للأعلى')
      fireEvent.click(upBtns[1]) // Trigger reorder mutation

      // Force rerender to pick up the ref change in the test DOM
      rerender(<VisitPlanDetail />)

      // During active mutation, all reorder buttons should be disabled
      expect(screen.getAllByTitle('تحريك للأعلى')[1].hasAttribute('disabled')).toBe(true)
    })

    it('does not display Add Item controls if canAddItem is false', () => {
      mockPermissions(perm => perm !== PERMISSIONS.VISIT_PLANS_CREATE)

      mockPlanStatus = 'draft'
      render(<VisitPlanDetail />)

      const addBtn = screen.queryByRole('button', { name: 'إضافة بند' })
      expect(addBtn).toBeNull()
    })

    it('reopen of Skip Modal after closing resets skipReason and skipCustom', async () => {
      render(<VisitPlanDetail />)
      fireEvent.click(screen.getAllByRole('button', { name: 'تخطي' })[0])

      const skipModal = screen.getByRole('dialog', { name: /تخطي:/ })
      const reasonBtn = within(skipModal).getByRole('button', { name: 'محل مغلق' })
      fireEvent.click(reasonBtn)

      const cancelBtn = within(skipModal).getByRole('button', { name: 'إلغاء' })
      fireEvent.click(cancelBtn)

      await waitFor(() => expect(screen.queryByRole('dialog', { name: /تخطي:/ })).toBeNull())

      // Reopen
      fireEvent.click(screen.getAllByRole('button', { name: 'تخطي' })[0])
      const newSkipModal = await screen.findByRole('dialog', { name: /تخطي:/ })
      const input = newSkipModal.querySelector('input')
      expect(input).toBeNull() // Not showing custom input because reason is reset and not 'أخرى'
    })

    it('Atomic=true + close_administrative -> زر إنهاء اليومية ظاهر', () => {
      mockIsAtomic = true
      mockPermissions([PERMISSIONS.VISIT_PLANS_CLOSE_ADMINISTRATIVE])
      mockPlanStatus = 'in_progress'
      render(<VisitPlanDetail />)
      expect(screen.queryByRole('button', { name: 'إنهاء اليومية المتبقية' })).not.toBeNull()
    })

    it('Atomic=true + confirm فقط -> الزر غير ظاهر', () => {
      mockIsAtomic = true
      mockPermissions([PERMISSIONS.VISIT_PLANS_CONFIRM])
      mockPlanStatus = 'in_progress'
      render(<VisitPlanDetail />)
      expect(screen.queryByRole('button', { name: 'إنهاء اليومية المتبقية' })).toBeNull()
    })

    it('Atomic=false + confirm -> يحافظ على Legacy behavior (الزر ظاهر)', () => {
      mockIsAtomic = false
      mockPermissions([PERMISSIONS.VISIT_PLANS_CONFIRM])
      mockPlanStatus = 'in_progress'
      render(<VisitPlanDetail />)
      expect(screen.queryByRole('button', { name: 'إنهاء اليومية المتبقية' })).not.toBeNull()
    })

    it('Atomic execution requires update_own + activities.create (زر بدء الزيارة ظاهر)', () => {
      mockIsAtomic = true
      mockPermissions([PERMISSIONS.VISIT_PLANS_UPDATE_OWN, PERMISSIONS.ACTIVITIES_CREATE])
      mockPlanStatus = 'in_progress'
      render(<VisitPlanDetail />)
      expect(screen.queryAllByRole('button', { name: 'بدء الزيارة' }).length).toBeGreaterThan(0)
    })

    it('نقص واحدة يمنع زر التنفيذ (update_own missing)', () => {
      mockIsAtomic = true
      mockPermissions([PERMISSIONS.ACTIVITIES_CREATE])
      mockPlanStatus = 'in_progress'
      render(<VisitPlanDetail />)
      expect(screen.queryAllByRole('button', { name: 'بدء الزيارة' }).length).toBe(0)
    })

    it('نقص واحدة يمنع زر التنفيذ (activities.create missing)', () => {
      mockIsAtomic = true
      mockPermissions([PERMISSIONS.VISIT_PLANS_UPDATE_OWN])
      mockPlanStatus = 'in_progress'
      render(<VisitPlanDetail />)
      expect(screen.queryAllByRole('button', { name: 'بدء الزيارة' }).length).toBe(0)
    })
  })
})
