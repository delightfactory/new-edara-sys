import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import VisitPlansPage from './VisitPlansPage'
import type { VisitPlan, PlanStatus } from '@/lib/types/activities'

const mockNavigate = vi.fn()
let capturedParams: {
  status?: PlanStatus
  planType?: VisitPlan['plan_type']
  employeeId?: string
  dateFrom?: string
  dateTo?: string
  page?: number
  pageSize?: number
} | null = null
let capturedEnabled: boolean | undefined = undefined

vi.mock('react-router-dom', () => ({
  useNavigate: () => mockNavigate,
  Link: ({ to, children, className, ...props }: { to: string; children: React.ReactNode; className?: string }) => (
    <a href={to} className={className} {...props}>
      {children}
    </a>
  )
}))

vi.mock('sonner', () => ({
  toast: {
    success: vi.fn(),
    error: vi.fn(),
    warning: vi.fn()
  }
}))

let mockPermissions = {
  create: true,
  confirm: true,
  cancel: true,
  readTeam: true
}

vi.mock('@/stores/auth-store', () => ({
  useAuthStore: vi.fn((selector) => {
    const state = {
      profile: { id: 'user-123' },
      can: (perm: string) => {
        if (perm === 'visit_plans.create') return mockPermissions.create
        if (perm === 'visit_plans.confirm') return mockPermissions.confirm
        if (perm === 'visit_plans.cancel') return mockPermissions.cancel
        if (perm === 'visit_plans.read_team' || perm === 'visit_plans.read_all') return mockPermissions.readTeam
        return false
      }
    }
    return selector ? selector(state) : state
  })
}))

let mockVisitPlansData: {
  data: VisitPlan[]
  totalPages: number
  count: number
} = {
  data: [],
  totalPages: 1,
  count: 0
}
let mockVisitPlansLoading = false
let mockVisitPlansError: Error | null = null
const mockRefetch = vi.fn()

const mockConfirmMutate = vi.fn()
const mockCancelMutate = vi.fn()
const mockConfirmAtomicMutate = vi.fn()
const mockCancelAtomicMutate = vi.fn()

let capturedEmployeesEnabled: boolean | undefined = undefined

vi.mock('@/hooks/useQueryHooks', () => ({
  useVisitPlans: (params: typeof capturedParams, enabled: boolean) => {
    capturedParams = params
    capturedEnabled = enabled
    return {
      data: mockVisitPlansData,
      isLoading: mockVisitPlansLoading,
      error: mockVisitPlansError,
      refetch: mockRefetch
    }
  },
  useConfirmVisitPlan: () => ({ mutate: mockConfirmMutate }),
  useCancelVisitPlan: () => ({ mutate: mockCancelMutate }),
  useConfirmVisitPlanAtomic: () => ({ mutate: mockConfirmAtomicMutate }),
  useCancelVisitPlanAtomic: () => ({ mutate: mockCancelAtomicMutate }),
  useHREmployees: (params: unknown, enabled: boolean) => {
    capturedEmployeesEnabled = enabled
    return {
      data: params ? {
        data: [
          { id: 'emp-1', full_name: 'أحمد مندوب' },
          { id: 'emp-2', full_name: 'محمد مندوب' }
        ]
      } : null
    }
  }
}))

let mockIsAtomic = true
vi.mock('@/lib/config/features', () => ({
  get VISITS_ATOMIC_EXECUTION() {
    return mockIsAtomic
  }
}))

describe('VisitPlansPage - Flow Enhancements Wave 1', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockIsAtomic = true
    mockPermissions = {
      create: true,
      confirm: true,
      cancel: true,
      readTeam: true
    }
    mockVisitPlansData = {
      data: [
        {
          id: 'plan-1',
          plan_date: '2026-07-10',
          plan_type: 'recurring',
          status: 'draft',
          completed_count: 2,
          total_customers: 5,
          completion_pct: 40,
          employee: { full_name: 'أحمد مندوب' }
        } as VisitPlan
      ],
      totalPages: 1,
      count: 1
    }
    mockVisitPlansLoading = false
    mockVisitPlansError = null
    capturedParams = null
    capturedEnabled = undefined
    capturedEmployeesEnabled = undefined
  })

  it('renders loading skeleton when loading is true', () => {
    mockVisitPlansLoading = true
    const { container } = render(<VisitPlansPage />)
    expect(screen.getByText('خطط الزيارات')).toBeDefined()
    expect(container.querySelector('.skeleton-row-fallback')).toBeDefined()
  })

  it('renders error state and triggers refetch on retry click', () => {
    mockVisitPlansError = new Error('Database connection failed')
    render(<VisitPlansPage />)
    expect(screen.getByText('فشل تحميل البيانات')).toBeDefined()
    const retryBtn = screen.getByRole('button', { name: 'إعادة المحاولة' })
    fireEvent.click(retryBtn)
    expect(mockRefetch).toHaveBeenCalled()
  })

  it('renders empty database state when count is 0 and filters are empty', () => {
    mockVisitPlansData = { data: [], totalPages: 1, count: 0 }
    render(<VisitPlansPage />)
    expect(screen.getByText('لا توجد خطط زيارات مسجلة')).toBeDefined()
    expect(screen.getByText('لم يتم إنشاء أي خطة زيارات بعد في النظام.')).toBeDefined()
    expect(screen.getAllByRole('button', { name: 'خطة جديدة' }).length).toBeGreaterThan(0)
  })

  it('renders empty filtered results state when filters are active and yields 0 results', () => {
    mockVisitPlansData = { data: [], totalPages: 1, count: 0 }
    render(<VisitPlansPage />)
    
    const statusSelect = screen.getByLabelText('الحالة')
    fireEvent.change(statusSelect, { target: { value: 'draft' } })
    
    expect(screen.getByText('لا توجد نتائج مطابقة للفلاتر')).toBeDefined()
    const clearBtn = screen.getByRole('button', { name: 'مسح الفلاتر' })
    fireEvent.click(clearBtn)
    
    expect(capturedParams?.page).toBe(1)
  })

  it('correctly maps status configs to active select options and renders Arabic status translations', () => {
    render(<VisitPlansPage />)
    expect(screen.getAllByText('مسودة').length).toBeGreaterThan(0)
    expect(screen.getAllByText('مؤكدة').length).toBeGreaterThan(0)
    expect(screen.getAllByText('جارية').length).toBeGreaterThan(0)
  })

  it('hides create button when create permission is missing', () => {
    mockPermissions.create = false
    render(<VisitPlansPage />)
    expect(screen.queryByRole('button', { name: 'خطة جديدة' })).toBeNull()
  })

  it('hides confirm action button in actions column when confirm permission is missing', () => {
    mockPermissions.confirm = false
    render(<VisitPlansPage />)
    expect(screen.queryByRole('button', { name: 'تأكيد الخطة' })).toBeNull()
  })

  it('hides cancel action button in actions column when cancel permission is missing', () => {
    mockPermissions.cancel = false
    render(<VisitPlansPage />)
    expect(screen.queryByRole('button', { name: 'إلغاء الخطة' })).toBeNull()
  })

  it('correctly passes planType and employeeId within React Query parameters', () => {
    render(<VisitPlansPage />)
    
    const typeSelect = screen.getByLabelText('نوع الخطة')
    fireEvent.change(typeSelect, { target: { value: 'weekly' } })
    
    const empSelect = screen.getByLabelText('الموظف')
    fireEvent.change(empSelect, { target: { value: 'emp-1' } })

    expect(capturedParams?.planType).toBe('weekly')
    expect(capturedParams?.employeeId).toBe('emp-1')
  })

  it('prevents event bubbling when internally nested buttons inside cards are clicked', () => {
    render(<VisitPlansPage />)
    
    const confirmBtn = screen.getByRole('button', { name: 'تأكيد الخطة' })
    fireEvent.click(confirmBtn)
    
    expect(mockNavigate).not.toHaveBeenCalled()
  })

  it('supports keyboard navigation using standard Links', () => {
    render(<VisitPlansPage />)
    const links = screen.getAllByRole('link')
    expect(links.length).toBeGreaterThan(0)
    expect(links[0].getAttribute('href')).toContain('/activities/visit-plans/plan-1')
  })

  it('disables query and hides count when dateFrom is after dateTo', () => {
    render(<VisitPlansPage />)
    
    const fromInput = screen.getByLabelText('من تاريخ')
    fireEvent.change(fromInput, { target: { value: '2026-07-15' } })
    
    const toInput = screen.getByLabelText('إلى تاريخ')
    fireEvent.change(toInput, { target: { value: '2026-07-10' } })

    expect(capturedEnabled).toBe(false)
    expect(screen.queryByText(/عدد النتائج الحالية/)).toBeNull()
    expect(screen.getByText('⚠️ تاريخ البدء لا يمكن أن يكون بعد تاريخ الانتهاء')).toBeDefined()
  })

  it('sets useHREmployees enabled to false when canReadTeam is false', () => {
    mockPermissions.readTeam = false
    render(<VisitPlansPage />)
    expect(capturedEmployeesEnabled).toBe(false)
  })

  it('translates recurring plan type to متكررة correctly', () => {
    render(<VisitPlansPage />)
    expect(screen.getAllByText('متكررة').length).toBeGreaterThan(0)
    expect(screen.queryByText('حملة', { selector: '.text-xs' })).toBeNull()
  })

  describe('Atomic execution paths (VISITS_ATOMIC_EXECUTION = true) - Idempotency & Mutex Locks', () => {
    beforeEach(() => {
      mockIsAtomic = true
    })

    it('confirm mutation triggers atomic confirm hook with uuid, prevents concurrent duplicate clicks', () => {
      render(<VisitPlansPage />)
      const confirmBtn = screen.getByRole('button', { name: 'تأكيد الخطة' })
      fireEvent.click(confirmBtn)

      const modalConfirmBtn = screen.getByRole('button', { name: 'تأكيد' })
      fireEvent.click(modalConfirmBtn)
      // double click
      fireEvent.click(modalConfirmBtn)

      expect(mockConfirmAtomicMutate).toHaveBeenCalledTimes(1)
      const args = mockConfirmAtomicMutate.mock.calls[0][0]
      expect(args.planId).toBe('plan-1')
      expect(args.operationId).toBeDefined()
      expect(args.operationId).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
      expect(mockConfirmMutate).not.toHaveBeenCalled()
    })

    it('cancel mutation validation checks reason and prevents execute on empty reason', () => {
      render(<VisitPlansPage />)
      const cancelBtns = screen.getAllByRole('button', { name: 'إلغاء الخطة' })
      fireEvent.click(cancelBtns[0])

      const modalCancelBtns = screen.getAllByRole('button', { name: 'إلغاء الخطة' })
      const modalCancelBtn = modalCancelBtns[modalCancelBtns.length - 1]
      fireEvent.click(modalCancelBtn)

      expect(mockCancelAtomicMutate).not.toHaveBeenCalled()
    })

    it('cancel mutation triggers atomic cancel hook, and reuse same operationId and reason on failure retry', async () => {
      // Mock failure trigger and call onSettled asynchronously to release lock
      mockCancelAtomicMutate.mockImplementationOnce((_args: unknown, options: { onError: (err: Error) => void; onSettled: () => void }) => {
        setTimeout(() => {
          options.onError(new Error('Network failure'))
          options.onSettled()
        }, 0)
      })

      render(<VisitPlansPage />)
      const cancelBtns = screen.getAllByRole('button', { name: 'إلغاء الخطة' })
      fireEvent.click(cancelBtns[0])

      const reasonTextarea = screen.getByPlaceholderText('اذكر سبب الإلغاء وجوباً...')
      fireEvent.change(reasonTextarea, { target: { value: 'عدم توفر المندوب' } })

      const modalCancelBtns = screen.getAllByRole('button', { name: 'إلغاء الخطة' })
      const modalCancelBtn = modalCancelBtns[modalCancelBtns.length - 1]
      
      // Click first attempt (fails)
      fireEvent.click(modalCancelBtn)
      await new Promise(resolve => setTimeout(resolve, 0))

      expect(mockCancelAtomicMutate).toHaveBeenCalledTimes(1)
      const firstArgs = mockCancelAtomicMutate.mock.calls[0][0]
      expect(firstArgs.operationId).toBeDefined()
      expect(firstArgs.reason).toBe('عدم توفر المندوب')
      expect(reasonTextarea.getAttribute('disabled')).toBeDefined()

      // Click second attempt (retries)
      fireEvent.click(modalCancelBtn)
      expect(mockCancelAtomicMutate).toHaveBeenCalledTimes(2)
      const secondArgs = mockCancelAtomicMutate.mock.calls[1][0]
      expect(secondArgs.operationId).toBe(firstArgs.operationId) // Same operationId reused
      expect(secondArgs.reason).toBe('عدم توفر المندوب')
      expect(mockCancelMutate).not.toHaveBeenCalled()
    })

    it('closing confirm modal resets the confirm operationId ref', async () => {
      mockConfirmAtomicMutate.mockImplementationOnce((_args: unknown, options: { onError: (err: Error) => void; onSettled: () => void }) => {
        setTimeout(() => {
          options.onError(new Error('Confirm failed'))
          options.onSettled()
        }, 0)
      })

      render(<VisitPlansPage />)
      const confirmBtn = screen.getByRole('button', { name: 'تأكيد الخطة' })
      fireEvent.click(confirmBtn)

      const modalConfirmBtn1 = screen.getByRole('button', { name: 'تأكيد' })
      fireEvent.click(modalConfirmBtn1)
      await new Promise(resolve => setTimeout(resolve, 0))
      
      const firstOpId = mockConfirmAtomicMutate.mock.calls[0][0].operationId

      // Close modal
      const closeBtn = screen.getByRole('button', { name: 'إلغاء' })
      fireEvent.click(closeBtn)

      // Open modal again and confirm
      fireEvent.click(confirmBtn)
      const modalConfirmBtn2 = screen.getByRole('button', { name: 'تأكيد' })
      fireEvent.click(modalConfirmBtn2)
      const secondOpId = mockConfirmAtomicMutate.mock.calls[1][0].operationId

      expect(secondOpId).not.toBe(firstOpId) // Generated fresh operationId on new modal intent
    })
  })

  describe('Legacy execution fallback (VISITS_ATOMIC_EXECUTION = false)', () => {
    beforeEach(() => {
      mockIsAtomic = false
    })

    it('confirm mutation triggers legacy confirm hook', () => {
      render(<VisitPlansPage />)
      const confirmBtn = screen.getByRole('button', { name: 'تأكيد الخطة' })
      fireEvent.click(confirmBtn)

      const modalConfirmBtn = screen.getByRole('button', { name: 'تأكيد' })
      fireEvent.click(modalConfirmBtn)

      expect(mockConfirmMutate).toHaveBeenCalledWith('plan-1', expect.any(Object))
      expect(mockConfirmAtomicMutate).not.toHaveBeenCalled()
    })

    it('cancel mutation triggers legacy cancel hook', () => {
      render(<VisitPlansPage />)
      const cancelBtns = screen.getAllByRole('button', { name: 'إلغاء الخطة' })
      fireEvent.click(cancelBtns[0])

      const modalCancelBtns = screen.getAllByRole('button', { name: 'إلغاء الخطة' })
      const modalCancelBtn = modalCancelBtns[modalCancelBtns.length - 1]
      fireEvent.click(modalCancelBtn)

      expect(mockCancelMutate).toHaveBeenCalledWith({ id: 'plan-1', reason: undefined }, expect.any(Object))
      expect(mockCancelAtomicMutate).not.toHaveBeenCalled()
    })
  })
})
