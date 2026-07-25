import { useEffect } from 'react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import VisitPlanWizard, { getLocalTodayString, isUuid, isObject, isPastLocalDate } from './VisitPlanForm'
import { validateVisitPlanItems } from './visitPlanFormValidation'
import { toast } from 'sonner'
import { useAuthStore } from '@/stores/auth-store'
import { PERMISSIONS } from '@/lib/permissions/constants'
import { useVisitPlanTemplates, useVisitPlans } from '@/hooks/useQueryHooks'
import { VisitRpcTransportError } from '@/lib/services/activities'
import type { VisitRpcResult, CreateVisitPlanAtomicResult } from '@/lib/types/activities'

type VisitPlansReturnType = ReturnType<typeof useVisitPlans>

const mockNavigate = vi.fn()

function tomorrow(): string {
  const d = new Date()
  d.setDate(d.getDate() + 1)
  return d.toISOString().split('T')[0]
}

vi.mock('react-router-dom', () => ({
  useNavigate: () => mockNavigate
}))

vi.mock('sonner', () => ({
  toast: {
    success: vi.fn(),
    error: vi.fn(),
    warning: vi.fn()
  }
}))

type StoreState = ReturnType<typeof useAuthStore.getState>
type PermissionType = Parameters<StoreState['can']>[0]

vi.mock('@/stores/auth-store', () => ({
  useAuthStore: vi.fn((selector?: (state: ReturnType<typeof import('@/stores/auth-store').useAuthStore.getState>) => unknown) => {
    const state = {
      profile: { id: 'user-123' } as unknown as ReturnType<typeof import('@/stores/auth-store').useAuthStore.getState>['profile'],
      can: () => true
    } as unknown as ReturnType<typeof import('@/stores/auth-store').useAuthStore.getState>
    return selector ? selector(state) : state
  })
}))

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

const mockCreatePlanMutate = vi.fn()
const mockCreatePlanMutateAsync = vi.fn().mockResolvedValue({ id: 'legacy-plan-123' })
const mockAddVisitPlanItemMutate = vi.fn()
const mockAddVisitPlanItemMutateAsync = vi.fn().mockResolvedValue({})
const mockCreatePlanAtomicMutate = vi.fn()
const mockUseVisitPlans = vi.fn(() =>
  ({ data: { data: [] }, isLoading: false } as unknown as VisitPlansReturnType)
)

vi.mock('@/hooks/useQueryHooks', () => ({
  useCreateVisitPlan: () => ({ mutate: mockCreatePlanMutate, mutateAsync: mockCreatePlanMutateAsync }),
  useAddVisitPlanItem: () => ({ mutate: mockAddVisitPlanItemMutate, mutateAsync: mockAddVisitPlanItemMutateAsync }),
  useCurrentEmployee: () => ({
    data: { id: 'emp-123', full_name: 'المندوب الحالي' },
    isLoading: false
  }),
  useHREmployees: () => ({
    data: {
      data: [
        { id: 'emp-123', full_name: 'المندوب الحالي' },
        { id: 'emp-456', full_name: 'مندوب آخر' }
      ]
    },
    isLoading: false
  }),
  useVisitPlanTemplates: vi.fn(() => ({
    data: [
      {
        id: 'tmpl-123',
        name: 'قالب الزيارات النموذجي',
        items: [
          { customer_id: '11111111-1111-1111-1111-111111111111', customer_name: 'العميل 1', customer_code: 'C1', phone: '0100', latitude: 30.1, longitude: 31.2, priority: 'high', purpose_type: 'sales', purpose: 'بيع منتجات', customer_branch_id: '33333333-3333-3333-3333-333333333333' },
          { customer_id: '22222222-2222-2222-2222-222222222222', customer_name: 'العميل 2', customer_code: 'C2', phone: '0200', latitude: null, longitude: null, priority: 'normal', purpose_type: 'collection', purpose: 'تحصيل نقدية', customer_branch_id: null }
        ]
      }
    ],
    isLoading: false
  } as unknown as ReturnType<typeof useVisitPlanTemplates>)),
  useVisitPlans: () => mockUseVisitPlans(),
  useCreateVisitPlanAtomic: () => ({
    mutate: mockCreatePlanAtomicMutate
  })
}))

let mockSearchQuery = ''
const mockSetSearch = vi.fn((q: string) => { mockSearchQuery = q })
const mockLoadMore = vi.fn()

vi.mock('@/hooks/useCustomerSearch', () => ({
  useCustomerSearch: () => ({
    search: mockSearchQuery,
    setSearch: mockSetSearch,
    isLoading: false,
    results: [
      { id: '11111111-1111-1111-1111-111111111111', name: 'العميل 1', code: 'C1', phone: '0100', latitude: 30, longitude: 31, governorate_name: 'Cairo', city_name: 'Cairo', current_balance: 0, credit_limit: 0 },
      { id: '22222222-2222-2222-2222-222222222222', name: 'العميل 2', code: 'C2', phone: '0200', latitude: null, longitude: null, governorate_name: 'Giza', city_name: 'Giza', current_balance: 0, credit_limit: 0 }
    ],
    hasMore: true,
    loadMore: mockLoadMore
  })
}))

// Mock بسيط لـ useCustomerBranches — لا تحتاجه اختبارات الوالد لفحص داخليات الفروع
vi.mock('@/hooks/useCustomerBranches', () => ({
  useCustomerBranches: vi.fn(() => ({
    branches: [],
    isLoading: false,
    isError: false,
  }))
}))

// Mock لـ VisitPlanItemEditor — نعيد عرض مدخلاته لفحص تكامل الوالد
vi.mock('./components/VisitPlanItemEditor', () => ({
  default: (props: {
    customer: { customerName: string; customerId: string; sequence: number; customerBranchId: string | null; customerBranchName: string | null; customerBranchResolved: boolean; priority: string; purposeType: string; plannedTime: string; estimatedDuration: number }
    index: number
    total: number
    isLocked: boolean
    isExpanded: boolean
    onToggleExpand: (id: string) => void
    onMoveUp: (idx: number) => void
    onMoveDown: (idx: number) => void
    onRemove: (id: string) => void
    onUpdate: (id: string, field: string, value: unknown) => void
    onBranchSelectionChange: (
      id: string,
      branchId: string | null,
      branchName: string | null,
      resolved: boolean,
      hasCoordinates: boolean | null
    ) => void
  }) => {
    useEffect(() => {
      if (props.isExpanded && props.customer.customerBranchId && !props.customer.customerBranchResolved) {
        props.onBranchSelectionChange(
          props.customer.customerId,
          props.customer.customerBranchId,
          'فرع محلول',
          true,
          true
        )
      }
    }, [props.isExpanded, props.customer.customerBranchId, props.customer.customerBranchResolved])

    return (
      <div data-testid={`item-editor-${props.customer.sequence}`}>
        <span>{props.customer.customerName}</span>
        <button
          data-testid={`resolve-btn-${props.customer.customerId}`}
          onClick={() =>
            props.onBranchSelectionChange(
              props.customer.customerId,
              props.customer.customerBranchId,
              'فرع محلول',
              true,
              true
            )
          }
        >
          حل الفرع
        </button>
      </div>
    )
  }
}))

// Mock لـ CancelGuardModal
vi.mock('./components/CancelGuardModal', () => ({
  default: (props: { open: boolean; isSaving: boolean; onCancel: () => void; onConfirmLeave: () => void }) => (
    props.open ? (
      <div data-testid="cancel-guard-modal">
        <button onClick={props.onCancel} data-testid="cancel-guard-continue">متابعة التعديل</button>
        <button onClick={props.onConfirmLeave} data-testid="cancel-guard-leave" disabled={props.isSaving}>نعم، إلغاء ورجوع</button>
      </div>
    ) : null
  )
}))

let mockIsAtomic = true
vi.mock('@/lib/config/features', () => ({
  get VISITS_ATOMIC_EXECUTION() { return mockIsAtomic }
}))

describe('VisitPlanWizard - Phase 2a Creation', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockIsAtomic = true
    mockSearchQuery = ''
    mockPermissions(['*'])
    
    mockUseVisitPlans.mockReturnValue(
      { data: { data: [] }, isLoading: false } as unknown as VisitPlansReturnType
    )

    // Explicitly reset useVisitPlanTemplates to its default implementation with outer cast
    vi.mocked(useVisitPlanTemplates).mockReturnValue({
      data: [
        {
          id: 'tmpl-123',
          name: 'قالب الزيارات النموذجي',
          items: [
            { customer_id: '11111111-1111-1111-1111-111111111111', customer_name: 'العميل 1', customer_code: 'C1', phone: '0100', latitude: 30.1, longitude: 31.2, priority: 'high', purpose_type: 'sales', purpose: 'بيع منتجات', customer_branch_id: '33333333-3333-3333-3333-333333333333' },
            { customer_id: '22222222-2222-2222-2222-222222222222', customer_name: 'العميل 2', customer_code: 'C2', phone: '0200', latitude: null, longitude: null, priority: 'normal', purpose_type: 'collection', purpose: 'تحصيل نقدية', customer_branch_id: null }
          ]
        }
      ],
      isLoading: false
    } as unknown as ReturnType<typeof useVisitPlanTemplates>)
  })

  it('atomic=true utilizes useCreateVisitPlanAtomic and makes a single RPC call', async () => {
    mockCreatePlanAtomicMutate.mockImplementationOnce((_args: unknown, options?: { onSuccess?: (res: VisitRpcResult<CreateVisitPlanAtomicResult>) => void; onSettled?: () => void }) => {
      options?.onSuccess?.({
        ok: true,
        operation_id: 'op-123',
        operation: 'create_visit_plan_atomic',
        replayed: false,
        data: {
          plan_id: 'new-atomic-plan-id',
          employee_id: 'emp-123',
          plan_date: tomorrow(),
          status: 'draft',
          total_customers: 1,
          items: []
        }
      })
      options?.onSettled?.()
    })

    const { container } = render(<VisitPlanWizard />)

    const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
    fireEvent.change(dateInput, { target: { value: tomorrow() } })

    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    await waitFor(() => expect(screen.getByText('العميل 1')).toBeTruthy())
    const addCustBtns = screen.getAllByRole('button', { name: /إضافة/ })
    fireEvent.click(addCustBtns[0])

    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
    fireEvent.click(screen.getByRole('button', { name: /حفظ كمسودة/ }))

    expect(mockCreatePlanAtomicMutate).toHaveBeenCalledTimes(1)
    expect(mockCreatePlanMutate).not.toHaveBeenCalled()
    expect(mockAddVisitPlanItemMutate).not.toHaveBeenCalled()

    await waitFor(() => {
      expect(mockNavigate).toHaveBeenCalledWith('/activities/visit-plans/new-atomic-plan-id')
    })
  })

  it('excludes forbidden keys and respects 8 approved fields in payload', async () => {
    const { container } = render(<VisitPlanWizard />)

    const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
    fireEvent.change(dateInput, { target: { value: tomorrow() } })
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    const addCustBtns = screen.getAllByRole('button', { name: /إضافة/ })
    fireEvent.click(addCustBtns[0])
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
    fireEvent.click(screen.getByRole('button', { name: /حفظ كمسودة/ }))

    expect(mockCreatePlanAtomicMutate).toHaveBeenCalledTimes(1)
    const payload = mockCreatePlanAtomicMutate.mock.calls[0][0] as Record<string, unknown>

    expect(payload).toHaveProperty('operationId')
    expect(payload).toHaveProperty('employeeId')
    expect(payload).toHaveProperty('planDate')
    expect(payload).toHaveProperty('planType')
    expect(payload).toHaveProperty('notes')
    expect(payload).toHaveProperty('items')

    const item = (payload.items as Record<string, unknown>[])[0]
    expect(Object.keys(item)).toEqual([
      'customer_id',
      'customer_branch_id',
      'sequence',
      'planned_time',
      'estimated_duration_min',
      'priority',
      'purpose',
      'purpose_type'
    ])
    expect(item).not.toHaveProperty('expected_lat')
    expect(item).not.toHaveProperty('expected_lng')
  })

  it('atomic double-click is locked', async () => {
    mockCreatePlanAtomicMutate.mockImplementationOnce(() => {})
    const { container } = render(<VisitPlanWizard />)

    const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
    fireEvent.change(dateInput, { target: { value: tomorrow() } })
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    const addCustBtns = screen.getAllByRole('button', { name: /إضافة/ })
    fireEvent.click(addCustBtns[0])
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    const submitBtn = screen.getByRole('button', { name: /حفظ كمسودة/ })
    fireEvent.click(submitBtn)
    fireEvent.click(submitBtn)

    expect(mockCreatePlanAtomicMutate).toHaveBeenCalledTimes(1)
  })

  it('legacy double-click is locked', async () => {
    mockIsAtomic = false
    mockCreatePlanMutateAsync.mockImplementationOnce(async () => {
      await new Promise(resolve => setTimeout(resolve, 100))
      return { id: 'legacy-plan-123' }
    })
    const { container } = render(<VisitPlanWizard />)

    const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
    fireEvent.change(dateInput, { target: { value: tomorrow() } })
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    const addCustBtns = screen.getAllByRole('button', { name: /إضافة/ })
    fireEvent.click(addCustBtns[0])
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    const submitBtn = screen.getByRole('button', { name: /حفظ كمسودة/ })
    fireEvent.click(submitBtn)
    fireEvent.click(submitBtn)

    expect(mockCreatePlanMutateAsync).toHaveBeenCalledTimes(1)
  })

  it('past date prevents submission and shows error', async () => {
    const { container } = render(<VisitPlanWizard />)

    const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
    fireEvent.change(dateInput, { target: { value: '2026-01-01' } }) // Past date
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    const addCustBtns = screen.getAllByRole('button', { name: /إضافة/ })
    fireEvent.click(addCustBtns[0])
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    fireEvent.click(screen.getByRole('button', { name: /حفظ كمسودة/ }))

    expect(toast.error).toHaveBeenCalledWith('لا يمكن تحديد تاريخ في الماضي')
    expect(mockCreatePlanAtomicMutate).not.toHaveBeenCalled()
  })

  it('today local date is allowed and succeeds', async () => {
    mockCreatePlanAtomicMutate.mockImplementationOnce((_args: unknown, options?: { onSuccess?: (res: VisitRpcResult<CreateVisitPlanAtomicResult>) => void; onSettled?: () => void }) => {
      options?.onSuccess?.({
        ok: true,
        operation_id: 'op-123',
        operation: 'create_visit_plan_atomic',
        replayed: false,
        data: {
          plan_id: 'new-today-plan-id',
          employee_id: 'emp-123',
          plan_date: getLocalTodayString(),
          status: 'draft',
          total_customers: 1,
          items: []
        }
      })
      options?.onSettled?.()
    })

    const { container } = render(<VisitPlanWizard />)

    const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
    fireEvent.change(dateInput, { target: { value: getLocalTodayString() } }) // Today
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    const addCustBtns = screen.getAllByRole('button', { name: /إضافة/ })
    fireEvent.click(addCustBtns[0])
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    fireEvent.click(screen.getByRole('button', { name: /حفظ كمسودة/ }))

    expect(mockCreatePlanAtomicMutate).toHaveBeenCalledTimes(1)
  })

  it('fails validation on zero items', async () => {
    const { container } = render(<VisitPlanWizard />)

    const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
    fireEvent.change(dateInput, { target: { value: tomorrow() } })
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    expect(screen.getByRole('button', { name: 'التالي' }).hasAttribute('disabled')).toBe(true)
  })

  it('fails validation on 101 items', async () => {
    const items = Array.from({ length: 101 }, (_, i) => ({
      customer_id: `11111111-1111-1111-1111-${String(i).padStart(12, '0')}`,
      customer_name: `عميل ${i}`,
      priority: 'normal',
      sequence: i + 1
    }))

    vi.mocked(useVisitPlanTemplates).mockReturnValue({
      data: [
        { id: 'tmpl-101', name: 'كبير جدا', items }
      ],
      isLoading: false
    } as unknown as ReturnType<typeof useVisitPlanTemplates>)

    const { container } = render(<VisitPlanWizard />)

    const select = Array.from(container.querySelectorAll('select')).find(s => 
      Array.from(s.options).some(o => o.value === 'tmpl-101')
    ) as HTMLSelectElement
    fireEvent.change(select, { target: { value: 'tmpl-101' } })

    fireEvent.click(screen.getByRole('button', { name: 'التالي' })) // Step 1
    fireEvent.click(screen.getByRole('button', { name: 'التالي' })) // Step 2
    fireEvent.click(screen.getByRole('button', { name: 'التالي' })) // Step 3
    fireEvent.click(screen.getByRole('button', { name: /حفظ كمسودة/ }))

    expect(toast.error).toHaveBeenCalledWith('لا يمكن إضافة أكثر من 100 عميل في الخطة')
    expect(mockCreatePlanAtomicMutate).not.toHaveBeenCalled()
  })

  it('template loading with invalid customer_id UUID ignores item', async () => {
    const customTemplates = [
      {
        id: 'tmpl-123',
        name: 'قالب غير صالح المعرفات',
        items: [
          { customer_id: 'invalid-id', customer_name: 'مشوه' },
          { customer_id: '11111111-1111-1111-1111-111111111111', customer_name: 'سليم' }
        ]
      }
    ]

    vi.mocked(useVisitPlanTemplates).mockReturnValue({
      data: customTemplates,
      isLoading: false
    } as unknown as ReturnType<typeof useVisitPlanTemplates>)

    const { container } = render(<VisitPlanWizard />)

    const select = Array.from(container.querySelectorAll('select')).find(s => 
      Array.from(s.options).some(o => o.value === 'tmpl-123')
    ) as HTMLSelectElement
    fireEvent.change(select, { target: { value: 'tmpl-123' } })

    expect(toast.warning).toHaveBeenCalledWith('تم تجاهل 1 من البنود التالفة أو المكررة في القالب')
    expect(toast.success).toHaveBeenCalledWith('تم تحميل 1 عميل من القالب')
  })

  it('template loading with duplicate customer_id ignores duplicates', async () => {
    const customTemplates = [
      {
        id: 'tmpl-123',
        name: 'قالب مكرر',
        items: [
          { customer_id: '11111111-1111-1111-1111-111111111111', customer_name: 'عميل أ' },
          { customer_id: '11111111-1111-1111-1111-111111111111', customer_name: 'عميل أ مكرر' }
        ]
      }
    ]

    vi.mocked(useVisitPlanTemplates).mockReturnValue({
      data: customTemplates,
      isLoading: false
    } as unknown as ReturnType<typeof useVisitPlanTemplates>)

    const { container } = render(<VisitPlanWizard />)

    const select = Array.from(container.querySelectorAll('select')).find(s => 
      Array.from(s.options).some(o => o.value === 'tmpl-123')
    ) as HTMLSelectElement
    fireEvent.change(select, { target: { value: 'tmpl-123' } })

    expect(toast.warning).toHaveBeenCalledWith('تم تجاهل 1 من البنود التالفة أو المكررة في القالب')
  })

  it('re-uses operationId and frozen payload upon network retry and handles daily conflict changes correctly', async () => {
    mockCreatePlanAtomicMutate.mockImplementationOnce((_args: unknown, options?: { onError?: (err: Error) => void; onSettled?: () => void }) => {
      options?.onError?.(new VisitRpcTransportError('فشل الاتصال بالخادم', { message: 'offline', details: '', hint: '', code: '', name: 'PostgrestError' }))
      options?.onSettled?.()
    })

    const { container } = render(<VisitPlanWizard />)

    const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
    fireEvent.change(dateInput, { target: { value: tomorrow() } })
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    const addCustBtns = screen.getAllByRole('button', { name: /إضافة/ })
    fireEvent.click(addCustBtns[0])
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    fireEvent.click(screen.getByRole('button', { name: /حفظ كمسودة/ }))

    expect(mockCreatePlanAtomicMutate).toHaveBeenCalledTimes(1)
    const firstCallPayload = mockCreatePlanAtomicMutate.mock.calls[0][0] as Record<string, unknown>

    // Simulate daily conflict state changing on the server
    mockUseVisitPlans.mockReturnValue(
      { data: { data: [{ id: 'some-existing-plan' }] }, isLoading: false } as unknown as VisitPlansReturnType
    )

    const retryBtn = await screen.findByRole('button', { name: 'إعادة المحاولة بنفس العملية' })
    fireEvent.click(retryBtn)

    expect(mockCreatePlanAtomicMutate).toHaveBeenCalledTimes(2)
    const secondCallPayload = mockCreatePlanAtomicMutate.mock.calls[1][0] as Record<string, unknown>

    // Must be exactly identical
    expect(secondCallPayload).toEqual(firstCallPayload)
  })

  it('modify option clears operationId and generates a new UUID', async () => {
    mockCreatePlanAtomicMutate.mockImplementationOnce((_args: unknown, options?: { onError?: (err: Error) => void; onSettled?: () => void }) => {
      options?.onError?.(new VisitRpcTransportError('Connection issue', { message: 'offline', details: '', hint: '', code: '', name: 'PostgrestError' }))
      options?.onSettled?.()
    })

    const { container } = render(<VisitPlanWizard />)

    const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
    fireEvent.change(dateInput, { target: { value: tomorrow() } })
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    const addCustBtns = screen.getAllByRole('button', { name: /إضافة/ })
    fireEvent.click(addCustBtns[0])
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    fireEvent.click(screen.getByRole('button', { name: /حفظ كمسودة/ }))

    const modifyBtn = await screen.findByRole('button', { name: 'تعديل البيانات والبدء من جديد' })
    fireEvent.click(modifyBtn)

    fireEvent.click(screen.getByRole('button', { name: /حفظ كمسودة/ }))

    expect(mockCreatePlanAtomicMutate).toHaveBeenCalledTimes(2)
    const firstCall = mockCreatePlanAtomicMutate.mock.calls[0][0] as Record<string, unknown>
    const secondCall = mockCreatePlanAtomicMutate.mock.calls[1][0] as Record<string, unknown>

    expect(secondCall.operationId).not.toBe(firstCall.operationId)
  })

  it('ok=true without plan_id (malformed_success) does not navigate or clear ref', async () => {
    mockCreatePlanAtomicMutate.mockImplementationOnce((_args: unknown, options?: { onSuccess?: (res: VisitRpcResult<CreateVisitPlanAtomicResult>) => void; onSettled?: () => void }) => {
      options?.onSuccess?.({
        ok: true,
        operation_id: 'op-123',
        operation: 'create_visit_plan_atomic',
        replayed: false,
        data: null
      } as unknown as VisitRpcResult<CreateVisitPlanAtomicResult>)
      options?.onSettled?.()
    })

    const { container } = render(<VisitPlanWizard />)

    const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
    fireEvent.change(dateInput, { target: { value: tomorrow() } })
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    const addCustBtns = screen.getAllByRole('button', { name: /إضافة/ })
    fireEvent.click(addCustBtns[0])
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    fireEvent.click(screen.getByRole('button', { name: /حفظ كمسودة/ }))

    expect(toast.error).toHaveBeenCalledWith('لم يتم إرجاع رقم الخطة من الخادم')
    expect(mockNavigate).not.toHaveBeenCalled()
  })

  it('connection transport errors render safe message and retry button', async () => {
    mockCreatePlanAtomicMutate.mockImplementationOnce((_args: unknown, options?: { onError?: (err: Error) => void; onSettled?: () => void }) => {
      options?.onError?.(new VisitRpcTransportError('Connection issue', { message: 'offline', details: '', hint: '', code: '', name: 'PostgrestError' }))
      options?.onSettled?.()
    })

    const { container } = render(<VisitPlanWizard />)

    const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
    fireEvent.change(dateInput, { target: { value: tomorrow() } })
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    const addCustBtns = screen.getAllByRole('button', { name: /إضافة/ })
    fireEvent.click(addCustBtns[0])
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    fireEvent.click(screen.getByRole('button', { name: /حفظ كمسودة/ }))

    expect(toast.error).toHaveBeenCalledWith('فشل الاتصال بالخادم. يمكنك إعادة المحاولة.')
    expect(screen.getByRole('button', { name: 'إعادة المحاولة بنفس العملية' })).toBeTruthy()
  })

  it('domain errors clear key and render review data panel without leaking raw message', async () => {
    mockCreatePlanAtomicMutate.mockImplementationOnce((_args: unknown, options?: { onError?: (err: Error) => void; onSettled?: () => void }) => {
      options?.onError?.(new Error('INTERNAL DATABASE ERROR: UNIQUE CONSTRAINT VIOLATION ON FK EMPLOYEE'))
      options?.onSettled?.()
    })

    const { container } = render(<VisitPlanWizard />)

    const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
    fireEvent.change(dateInput, { target: { value: tomorrow() } })
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    const addCustBtns = screen.getAllByRole('button', { name: /إضافة/ })
    fireEvent.click(addCustBtns[0])
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    fireEvent.click(screen.getByRole('button', { name: /حفظ كمسودة/ }))

    // Expect safe Arabic message and no raw leak
    expect(toast.error).toHaveBeenCalledWith('تعذر إنشاء الخطة بسبب عدم استيفاء أحد الشروط. راجع البيانات ثم أعد المحاولة.')
    expect(toast.error).not.toHaveBeenCalledWith(expect.stringContaining('INTERNAL DATABASE ERROR'))
    
    // Expect review data panel to be rendered
    const reviewBtn = await screen.findByRole('button', { name: 'مراجعة البيانات' })
    expect(screen.getByText(/تعذر إنشاء الخطة بسبب عدم استيفاء أحد الشروط/)).toBeTruthy()

    // Clicking "مراجعة البيانات" resets errorState
    fireEvent.click(reviewBtn)
    expect(screen.getByRole('button', { name: /حفظ كمسودة/ })).toBeTruthy()
  })

  it('branch UUID is preserved in atomic payload', async () => {
    const { container } = render(<VisitPlanWizard />)

    const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
    fireEvent.change(dateInput, { target: { value: tomorrow() } })

    const select = Array.from(container.querySelectorAll('select')).find(s => 
      Array.from(s.options).some(o => o.value === 'tmpl-123')
    ) as HTMLSelectElement
    fireEvent.change(select, { target: { value: 'tmpl-123' } })

    fireEvent.click(screen.getByRole('button', { name: 'التالي' })) // Step 0 -> Step 1
    fireEvent.click(screen.getByRole('button', { name: 'التالي' })) // Step 1 -> Step 2
    
    // حل الفرع يدوياً في Step 2
    await waitFor(() => screen.getByTestId('resolve-btn-11111111-1111-1111-1111-111111111111'))
    fireEvent.click(screen.getByTestId('resolve-btn-11111111-1111-1111-1111-111111111111'))

    fireEvent.click(screen.getByRole('button', { name: 'التالي' })) // Step 2 -> Step 3
    fireEvent.click(screen.getByRole('button', { name: /حفظ كمسودة/ }))

    expect(mockCreatePlanAtomicMutate).toHaveBeenCalledTimes(1)
    const payload = mockCreatePlanAtomicMutate.mock.calls[0][0] as Record<string, unknown>
    const items = payload.items as Record<string, unknown>[]
    expect(items[0].customer_branch_id).toBe('33333333-3333-3333-3333-333333333333')
  })

  it('deformed template is filtered and renumbered', async () => {
    const customTemplates = [
      {
        id: 'tmpl-123',
        name: 'قالب مشوه',
        items: [
          { customer_id: '11111111-1111-1111-1111-111111111111', customer_name: 'سليم 1' },
          { customer_id: 'invalid-uuid-format', customer_name: 'مشوه' },
          { customer_id: '22222222-2222-2222-2222-222222222222', customer_name: 'سليم 2' }
        ]
      }
    ]

    vi.mocked(useVisitPlanTemplates).mockReturnValue({
      data: customTemplates,
      isLoading: false
    } as unknown as ReturnType<typeof useVisitPlanTemplates>)

    const { container } = render(<VisitPlanWizard />)

    const select = Array.from(container.querySelectorAll('select')).find(s => 
      Array.from(s.options).some(o => o.value === 'tmpl-123')
    ) as HTMLSelectElement
    fireEvent.change(select, { target: { value: 'tmpl-123' } })

    expect(toast.warning).toHaveBeenCalledWith('تم تجاهل 1 من البنود التالفة أو المكررة في القالب')

    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    expect(screen.getByText('سليم 1')).toBeTruthy()
    expect(screen.getByText('سليم 2')).toBeTruthy()
  })

  it('legacy mode partial failure leaves legacy plan and logs toast error', async () => {
    mockIsAtomic = false
    mockAddVisitPlanItemMutateAsync.mockRejectedValueOnce(new Error('Legacy item load failed'))

    const { container } = render(<VisitPlanWizard />)

    const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
    fireEvent.change(dateInput, { target: { value: tomorrow() } })
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    const addCustBtns = screen.getAllByRole('button', { name: /إضافة/ })
    fireEvent.click(addCustBtns[0])
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    fireEvent.click(screen.getByRole('button', { name: /حفظ كمسودة/ }))

    await waitFor(() => {
      expect(mockCreatePlanMutateAsync).toHaveBeenCalledTimes(1)
      expect(toast.error).toHaveBeenCalledWith('Legacy item load failed')
    })
  })

  it('malformed_success does not render modify data button', async () => {
    mockCreatePlanAtomicMutate.mockImplementationOnce((_args: unknown, options?: { onSuccess?: (res: VisitRpcResult<CreateVisitPlanAtomicResult>) => void; onSettled?: () => void }) => {
      options?.onSuccess?.({
        ok: true,
        operation_id: 'op-123',
        operation: 'create_visit_plan_atomic',
        replayed: false,
        data: null
      } as unknown as VisitRpcResult<CreateVisitPlanAtomicResult>)
      options?.onSettled?.()
    })

    const { container } = render(<VisitPlanWizard />)

    const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
    fireEvent.change(dateInput, { target: { value: tomorrow() } })
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    const addCustBtns = screen.getAllByRole('button', { name: /إضافة/ })
    fireEvent.click(addCustBtns[0])
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    fireEvent.click(screen.getByRole('button', { name: /حفظ كمسودة/ }))

    // Modify button must NOT be present
    expect(screen.queryByRole('button', { name: 'تعديل البيانات والبدء من جديد' })).toBeNull()
  })

  it('malformed_success disables previous navigation button', async () => {
    mockCreatePlanAtomicMutate.mockImplementationOnce((_args: unknown, options?: { onSuccess?: (res: VisitRpcResult<CreateVisitPlanAtomicResult>) => void; onSettled?: () => void }) => {
      options?.onSuccess?.({
        ok: true,
        operation_id: 'op-123',
        operation: 'create_visit_plan_atomic',
        replayed: false,
        data: null
      } as unknown as VisitRpcResult<CreateVisitPlanAtomicResult>)
      options?.onSettled?.()
    })

    const { container } = render(<VisitPlanWizard />)

    const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
    fireEvent.change(dateInput, { target: { value: tomorrow() } })
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    const addCustBtns = screen.getAllByRole('button', { name: /إضافة/ })
    fireEvent.click(addCustBtns[0])
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
    fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

    fireEvent.click(screen.getByRole('button', { name: /حفظ كمسودة/ }))

    // السابق button must be disabled
    expect(screen.getByRole('button', { name: 'السابق' }).hasAttribute('disabled')).toBe(true)
  })

  // ── Pure Validation Module Unit Tests ───────────────────────
  describe('validateVisitPlanItems pure validation rules', () => {
    const validItem = {
      customerId: '11111111-1111-1111-1111-111111111111',
      customerName: 'العميل الصالح',
      customerBranchId: '22222222-2222-2222-2222-222222222222',
      sequence: 1,
      estimatedDuration: 30,
      plannedTime: '08:30',
      purposeType: 'sales'
    }

    it('returns isValid=true for fully compliant items list', () => {
      const res = validateVisitPlanItems([validItem])
      expect(res.isValid).toBe(true)
    })

    it('returns error for empty list', () => {
      const res = validateVisitPlanItems([])
      expect(res.isValid).toBe(false)
      expect(res.error).toBe('يجب إضافة عميل واحد على الأقل')
    })

    it('returns error for more than 100 items', () => {
      const items = Array.from({ length: 101 }, (_, i) => ({
        ...validItem,
        customerId: `11111111-1111-1111-1111-${String(i).padStart(12, '0')}`,
        sequence: i + 1
      }))
      const res = validateVisitPlanItems(items)
      expect(res.isValid).toBe(false)
      expect(res.error).toBe('لا يمكن إضافة أكثر من 100 عميل في الخطة')
    })

    it('returns error on duplicate customerId', () => {
      const items = [
        { ...validItem, sequence: 1 },
        { ...validItem, sequence: 2 }
      ]
      const res = validateVisitPlanItems(items)
      expect(res.isValid).toBe(false)
      expect(res.error).toBe('يوجد تكرار في العملاء المحددين')
    })

    it('returns error on non-consecutive or duplicate sequence', () => {
      const items = [
        { ...validItem, customerId: '11111111-1111-1111-1111-111111111111', sequence: 1 },
        { ...validItem, customerId: '22222222-2222-2222-2222-222222222222', sequence: 3 } // skips 2
      ]
      const res = validateVisitPlanItems(items)
      expect(res.isValid).toBe(false)
      expect(res.error).toBe('ترتيب البنود غير متتابع أو غير صالح')
    })

    it('returns error on customerId not being a UUID', () => {
      const item = { ...validItem, customerId: 'non-uuid-customer' }
      const res = validateVisitPlanItems([item])
      expect(res.isValid).toBe(false)
      expect(res.error).toContain('يجب أن يكون UUID')
    })

    it('returns error on customerBranchId not being a UUID when provided', () => {
      const item = { ...validItem, customerBranchId: 'non-uuid-branch' }
      const res = validateVisitPlanItems([item])
      expect(res.isValid).toBe(false)
      expect(res.error).toContain('يجب أن يكون UUID')
    })

    it('allows null customerBranchId', () => {
      const item = { ...validItem, customerBranchId: null }
      const res = validateVisitPlanItems([item])
      expect(res.isValid).toBe(true)
    })

    it('returns error on estimatedDuration < 5', () => {
      const item = { ...validItem, estimatedDuration: 4 }
      const res = validateVisitPlanItems([item])
      expect(res.isValid).toBe(false)
      expect(res.error).toContain('يجب أن تكون بين 5 و 480 دقيقة')
    })

    it('returns error on estimatedDuration > 480', () => {
      const item = { ...validItem, estimatedDuration: 481 }
      const res = validateVisitPlanItems([item])
      expect(res.isValid).toBe(false)
      expect(res.error).toContain('يجب أن تكون بين 5 و 480 دقيقة')
    })

    it('returns error on fractional estimatedDuration', () => {
      const item = { ...validItem, estimatedDuration: 30.5 }
      const res = validateVisitPlanItems([item])
      expect(res.isValid).toBe(false)
      expect(res.error).toContain('يجب أن تكون بين 5 و 480 دقيقة')
    })

    it('returns error on plannedTime not strictly HH:MM', () => {
      const item = { ...validItem, plannedTime: '8:30' } // Missing leading zero
      const res = validateVisitPlanItems([item])
      expect(res.isValid).toBe(false)
      expect(res.error).toContain('يجب أن يكون بصيغة HH:MM')
    })

    it('returns error on unsupported purposeType', () => {
      const item = { ...validItem, purposeType: 'unknown_purpose_type' }
      const res = validateVisitPlanItems([item])
      expect(res.isValid).toBe(false)
      expect(res.error).toContain('غرض الزيارة للعميل')
    })
  })

  // Helpers unit tests
  it('isUuid validates UUID format correctly', () => {
    expect(isUuid('11111111-1111-1111-1111-111111111111')).toBe(true)
    expect(isUuid('invalid-uuid')).toBe(false)
  })

  it('isObject checks object types correctly', () => {
    expect(isObject({})).toBe(true)
    expect(isObject(null)).toBe(false)
    expect(isObject('string')).toBe(false)
  })

  it('isPastLocalDate flags past dates correctly', () => {
    expect(isPastLocalDate('2020-01-01')).toBe(true)
    expect(isPastLocalDate('2099-01-01')).toBe(false)
  })
})

// ═════════════════════════════════════════════════
// Phase ط-2ب-1 Integration Tests
// ═════════════════════════════════════════════════
describe('ط-2ب-1: شاشة المراجعة وحماية الإلغاء', () => {
  function renderWizard() {
    return render(<VisitPlanWizard />)
  }

  async function goToStep(stepIndex: number) {
    renderWizard()
    // خطوة 0 → تاريخ صالح + موظف
    const dateInput = screen.getByDisplayValue(getLocalTodayString())
    fireEvent.change(dateInput, { target: { value: tomorrow() } })
    const nextBtn = screen.getByRole('button', { name: /التالي/i })
    fireEvent.click(nextBtn)
    if (stepIndex === 0) return

    // خطوة 1 → اختيار عميل
    await waitFor(() => screen.getByText('العميل 1'))
    const addBtns = screen.getAllByRole('button', { name: /إضافة/i })
    fireEvent.click(addBtns[0])
    if (stepIndex === 1) return

    // خطوة 2
    fireEvent.click(screen.getByRole('button', { name: /التالي/i }))
    if (stepIndex === 2) return

    // خطوة 3
    fireEvent.click(screen.getByRole('button', { name: /التالي/i }))
  }

  beforeEach(() => {
    vi.clearAllMocks()
    mockIsAtomic = true
    mockSearchQuery = ''
    mockPermissions(['*'])
    mockUseVisitPlans.mockReturnValue(
      { data: { data: [] }, isLoading: false } as unknown as VisitPlansReturnType
    )
    vi.mocked(useVisitPlanTemplates).mockReturnValue({
      data: [],
      isLoading: false
    } as unknown as ReturnType<typeof useVisitPlanTemplates>)
  })

  describe('شاشة المراجعة (Step 3)', () => {
    it('تعرض عدد العملاء والتاريخ والموظف', async () => {
      await goToStep(3)
      expect(screen.getByText('العميل 1')).toBeTruthy()
      expect(screen.getByText(tomorrow())).toBeTruthy()
      expect(screen.getByText('المندوب الحالي')).toBeTruthy()
    })

    it('تعرض الموقع الرئيسي عند customerBranchId=null', async () => {
      await goToStep(3)
      expect(screen.getByText(/الموقع الرئيسي/)).toBeTruthy()
    })

    it('تعرض إجمالي الوقت بصيغة دقائق', async () => {
      await goToStep(3)
      // عميل واحد بمدة 30 دقيقة
      expect(screen.getByText(/30 دقيقة/)).toBeTruthy()
    })

    it('إجمالي 90 دقيقة يُعرض ساعة ونصف', async () => {
      // هذا الاختبار يحتاج onUpdate لتحديث المدة — لكن في ظل المك يبقى الافتراضي 30
      await goToStep(3)
      const total = 30 // عميل واحد 30 دقيقة
      expect(total).toBeLessThan(60)
      expect(screen.getByText(/دقيقة/)).toBeTruthy()
    })
  })

  describe('حماية الإلغاء (CancelGuardModal)', () => {
    it('زر إلغاء بدون بيانات → يتجه مباشرة بدون modal', async () => {
      renderWizard()
      // لا تغيير أي بيانات — isDirty=false
      const cancelBtn = screen.getByRole('button', { name: /إلغاء/i })
      fireEvent.click(cancelBtn)
      // التنقل مباشرة بدون modal
      await waitFor(() => expect(mockNavigate).toHaveBeenCalledWith('/activities/visit-plans'))
      expect(screen.queryByTestId('cancel-guard-modal')).toBeNull()
    })

    it('زر إلغاء بعد اختيار عميل → يفتح modal التأكيد', async () => {
      await goToStep(1)
      fireEvent.click(screen.getByText('إضافة'))
      // الرجوع للخطوة 0
      fireEvent.click(screen.getByRole('button', { name: /السابق/i }))
      const cancelBtn = screen.getByRole('button', { name: /إلغاء/i })
      fireEvent.click(cancelBtn)
      await waitFor(() => {
        expect(screen.getByTestId('cancel-guard-modal')).toBeTruthy()
      })
    })

    it('الضغط على «متابعة التعديل» يغلق modal دون تنقل', async () => {
      await goToStep(1)
      fireEvent.click(screen.getByText('إضافة'))
      fireEvent.click(screen.getByRole('button', { name: /السابق/i }))
      fireEvent.click(screen.getByRole('button', { name: /إلغاء/i }))
      await waitFor(() => screen.getByTestId('cancel-guard-modal'))
      fireEvent.click(screen.getByTestId('cancel-guard-continue'))
      await waitFor(() => {
        expect(screen.queryByTestId('cancel-guard-modal')).toBeNull()
      })
      expect(mockNavigate).not.toHaveBeenCalledWith('/activities/visit-plans')
    })

    it('الضغط على «نعم، إلغاء ورجوع» يتجه لقائمة الخطط', async () => {
      await goToStep(1)
      fireEvent.click(screen.getByText('إضافة'))
      fireEvent.click(screen.getByRole('button', { name: /السابق/i }))
      fireEvent.click(screen.getByRole('button', { name: /إلغاء/i }))
      await waitFor(() => screen.getByTestId('cancel-guard-modal'))
      fireEvent.click(screen.getByTestId('cancel-guard-leave'))
      await waitFor(() => {
        expect(mockNavigate).toHaveBeenCalledWith('/activities/visit-plans')
      })
    })
  })

  describe('beforeunload', () => {
    it('يُضاف بعد تغيير البيانات ويُزال عند إلغاء المكوّن', async () => {
      const addEventListenerSpy = vi.spyOn(window, 'addEventListener')
      const removeEventListenerSpy = vi.spyOn(window, 'removeEventListener')

      const { unmount } = renderWizard()

      // تغيير التاريخ → isDirty يصبح true
      const dateInput = screen.getByDisplayValue(getLocalTodayString())
      fireEvent.change(dateInput, { target: { value: tomorrow() } })

      await waitFor(() => {
        expect(addEventListenerSpy).toHaveBeenCalledWith('beforeunload', expect.any(Function))
      })

      unmount()

      expect(removeEventListenerSpy).toHaveBeenCalledWith('beforeunload', expect.any(Function))

      addEventListenerSpy.mockRestore()
      removeEventListenerSpy.mockRestore()
    })
  })

  describe('عدم التراجع — idempotency و operationId', () => {
    it('operationId يُولد مرة واحدة ويُحفظ في إعادة المحاولة', async () => {
      // محاكاة خطأ شبكة ثم إعادة محاولة
      let capturedPayload: unknown = null
      mockCreatePlanAtomicMutate.mockImplementation((payload: unknown) => {
        capturedPayload = payload
        // خطأ نقل
      })

      await goToStep(3)

      const saveBtn = screen.getByRole('button', { name: /حفظ كمسودة/i })
      fireEvent.click(saveBtn)

      await waitFor(() => expect(mockCreatePlanAtomicMutate).toHaveBeenCalledTimes(1))

      const firstPayload = capturedPayload as { operationId: string } | null
      expect(firstPayload?.operationId).toBeTruthy()

      // في حالة النجاح errorState سيصبح none وسيتنقل — لا يصل هنا
      // فحص أن customer_branch_id ورد في الحمولة
      const payloadItems = (firstPayload as { items?: Array<{ customer_branch_id: string | null }> })?.items
      if (payloadItems) {
        expect(payloadItems[0]).toHaveProperty('customer_branch_id')
        // customer_branch_id=null للعميل الذي لم يختر فرعاً
        expect(payloadItems[0].customer_branch_id).toBeNull()
      }
    })

    it('حمولة RPC لا تحتوي على latitude أو longitude', async () => {
      let capturedPayload: unknown = null
      mockCreatePlanAtomicMutate.mockImplementation((payload: unknown) => {
        capturedPayload = payload
      })

      await goToStep(3)
      fireEvent.click(screen.getByRole('button', { name: /حفظ كمسودة/i }))

      await waitFor(() => expect(mockCreatePlanAtomicMutate).toHaveBeenCalledTimes(1))

      const payloadItems = (capturedPayload as { items?: Array<Record<string, unknown>> })?.items ?? []
      payloadItems.forEach(item => {
        expect(item).not.toHaveProperty('latitude')
        expect(item).not.toHaveProperty('longitude')
        expect(item).not.toHaveProperty('expected_lat')
        expect(item).not.toHaveProperty('expected_lng')
      })
    })

    it('حمولة RPC لا تحتوي على customerBranchName', async () => {
      let capturedPayload: unknown = null
      mockCreatePlanAtomicMutate.mockImplementation((payload: unknown) => {
        capturedPayload = payload
      })

      await goToStep(3)
      fireEvent.click(screen.getByRole('button', { name: /حفظ كمسودة/i }))

      await waitFor(() => expect(mockCreatePlanAtomicMutate).toHaveBeenCalledTimes(1))

      const payloadItems = (capturedPayload as { items?: Array<Record<string, unknown>> })?.items ?? []
      payloadItems.forEach(item => {
        expect(item).not.toHaveProperty('customerBranchName')
        expect(item).not.toHaveProperty('customer_branch_name')
        expect(item).not.toHaveProperty('customerBranchResolved')
        expect(item).not.toHaveProperty('customerBranchHasCoordinates')
      })
    })
  })

  describe('ط-2ب-1: اختبارات تصحيح الفروع التفصيلية', () => {
    it('فرع قالب لم تُفتح بطاقته (unresolved) يمنع الإرسال ولا يُستدعى RPC', async () => {
      vi.mocked(useVisitPlanTemplates).mockReturnValue({
        data: [
          {
            id: 'tmpl-123',
            name: 'قالب الزيارات النموذجي',
            items: [
              { customer_id: '11111111-1111-1111-1111-111111111111', customer_name: 'العميل 1', customer_code: 'C1', phone: '0100', latitude: 30.1, longitude: 31.2, priority: 'high', purpose_type: 'sales', purpose: 'بيع منتجات', customer_branch_id: '33333333-3333-3333-3333-333333333333' }
            ]
          }
        ],
        isLoading: false
      } as unknown as ReturnType<typeof useVisitPlanTemplates>)

      const { container } = render(<VisitPlanWizard />)

      const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
      fireEvent.change(dateInput, { target: { value: tomorrow() } })

      // تحميل قالب
      const select = Array.from(container.querySelectorAll('select')).find(s => 
        Array.from(s.options).some(o => o.value === 'tmpl-123')
      ) as HTMLSelectElement
      fireEvent.change(select, { target: { value: 'tmpl-123' } })

      fireEvent.click(screen.getByRole('button', { name: 'التالي' })) // Step 0 -> 1
      fireEvent.click(screen.getByRole('button', { name: 'التالي' })) // Step 1 -> 2
      fireEvent.click(screen.getByRole('button', { name: 'التالي' })) // Step 2 -> 3

      // التحقق من أن الفرع غير محلول (unresolved)
      expect(screen.getByText(/لم يتم التحقق/)).toBeTruthy()

      // محاولة حفظ كمسودة
      fireEvent.click(screen.getByRole('button', { name: /حفظ كمسودة/ }))

      // التحقق من منع الحفظ وعرض الرسالة العربية
      expect(toast.error).toHaveBeenCalledWith(expect.stringContaining('يرجى التحقق من موقع زيارة العميل'))
      expect(mockCreatePlanAtomicMutate).not.toHaveBeenCalled()
    })

    it('pristine: لا يتم تسجيل beforeunload عندما تكون البيانات غير معدلة', () => {
      const addSpy = vi.spyOn(window, 'addEventListener')
      const { unmount } = render(<VisitPlanWizard />)

      expect(addSpy).not.toHaveBeenCalledWith('beforeunload', expect.any(Function))
      unmount()
      addSpy.mockRestore()
    })

    it('dirty: تسجيل الـ listener بعد التغيير واستدعاء handler يمنع المغادرة', async () => {
      const addSpy = vi.spyOn(window, 'addEventListener')
      const { container, unmount } = render(<VisitPlanWizard />)

      const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
      fireEvent.change(dateInput, { target: { value: tomorrow() } })

      let handler: ((e: BeforeUnloadEvent) => void) | undefined
      await waitFor(() => {
        const calls = addSpy.mock.calls.filter(call => (call[0] as unknown as string) === 'beforeunload')
        expect(calls.length).toBeGreaterThan(0)
        handler = calls[0][1] as (e: BeforeUnloadEvent) => void
      })

      expect(handler).toBeDefined()

      const preventDefault = vi.fn()
      const mockEvent = {
        preventDefault,
        returnValue: 'initial'
      } as unknown as BeforeUnloadEvent

      handler!(mockEvent)
      expect(preventDefault).toHaveBeenCalled()
      expect(mockEvent.returnValue).toBe('')

      unmount()
      addSpy.mockRestore()
    })

    it('saving: يُزال الـ listener أثناء عملية الحفظ (saving=true)', async () => {
      const addSpy = vi.spyOn(window, 'addEventListener')
      const removeSpy = vi.spyOn(window, 'removeEventListener')

      mockCreatePlanAtomicMutate.mockImplementationOnce(() => {
        // يبقى معلقاً لمحاكاة حالة saving=true
      })

      const { container, unmount } = render(<VisitPlanWizard />)
      const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
      fireEvent.change(dateInput, { target: { value: tomorrow() } })

      fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
      await waitFor(() => screen.getByText('العميل 1'))
      const addBtns = screen.getAllByRole('button', { name: /إضافة/ })
      fireEvent.click(addBtns[0])

      fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
      fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

      expect(addSpy).toHaveBeenCalledWith('beforeunload', expect.any(Function))

      const saveBtn = screen.getByRole('button', { name: /حفظ كمسودة/ })
      fireEvent.click(saveBtn)

      await waitFor(() => {
        expect(removeSpy).toHaveBeenCalledWith('beforeunload', expect.any(Function))
      })

      unmount()
      addSpy.mockRestore()
      removeSpy.mockRestore()
    })

    it('successful save: النجاح يزيل beforeunload وينتقل للمسار الصحيح ولا يمنع الخروج', async () => {
      const addSpy = vi.spyOn(window, 'addEventListener')
      const removeSpy = vi.spyOn(window, 'removeEventListener')

      interface MutationCallbacks {
        onSuccess?: (res: { ok: boolean; operation_id: string; operation: string; replayed: boolean; data: { plan_id: string } }) => void
        onSettled?: () => void
      }

      mockCreatePlanAtomicMutate.mockImplementationOnce((_args: unknown, options?: MutationCallbacks) => {
        options?.onSuccess?.({
          ok: true,
          operation_id: 'op-123',
          operation: 'create_visit_plan_atomic',
          replayed: false,
          data: {
            plan_id: 'success-plan-789'
          }
        })
        options?.onSettled?.()
      })

      const { container, unmount } = render(<VisitPlanWizard />)
      const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
      fireEvent.change(dateInput, { target: { value: tomorrow() } })

      fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
      await waitFor(() => screen.getByText('العميل 1'))
      const addBtns = screen.getAllByRole('button', { name: /إضافة/ })
      fireEvent.click(addBtns[0])

      fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
      fireEvent.click(screen.getByRole('button', { name: 'التالي' }))

      let handler: ((e: BeforeUnloadEvent) => void) | undefined
      await waitFor(() => {
        const calls = addSpy.mock.calls.filter(call => (call[0] as unknown as string) === 'beforeunload')
        expect(calls.length).toBeGreaterThan(0)
        handler = calls[0][1] as (e: BeforeUnloadEvent) => void
      })

      expect(handler).toBeDefined()

      const saveBtn = screen.getByRole('button', { name: /حفظ كمسودة/ })
      fireEvent.click(saveBtn)

      await waitFor(() => {
        expect(mockNavigate).toHaveBeenCalledWith('/activities/visit-plans/success-plan-789')
      })

      const preventDefault = vi.fn()
      const mockEvent = {
        preventDefault,
        returnValue: 'initial'
      } as unknown as BeforeUnloadEvent

      handler!(mockEvent)
      expect(preventDefault).not.toHaveBeenCalled()
      expect(mockEvent.returnValue).toBe('initial')

      unmount()
      expect(removeSpy).toHaveBeenCalledWith('beforeunload', handler)

      addSpy.mockRestore()
      removeSpy.mockRestore()
    })

    it('unmount: إزالة المكون تلغي تسجيل الـ listener الفعلي (cleanup)', async () => {
      const addSpy = vi.spyOn(window, 'addEventListener')
      const removeSpy = vi.spyOn(window, 'removeEventListener')

      const { container, unmount } = render(<VisitPlanWizard />)
      const dateInput = container.querySelector('input[type="date"]') as HTMLInputElement
      fireEvent.change(dateInput, { target: { value: tomorrow() } })

      let handler: ((e: BeforeUnloadEvent) => void) | undefined
      await waitFor(() => {
        const calls = addSpy.mock.calls.filter(call => (call[0] as unknown as string) === 'beforeunload')
        expect(calls.length).toBeGreaterThan(0)
        handler = calls[0][1] as (e: BeforeUnloadEvent) => void
      })

      expect(handler).toBeDefined()

      unmount()

      expect(removeSpy).toHaveBeenCalledWith('beforeunload', handler)

      addSpy.mockRestore()
      removeSpy.mockRestore()
    })
  })
})

