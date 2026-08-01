import { act, fireEvent, render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import TargetForm from './TargetForm'

const createTargetMock = vi.fn()

vi.mock('react-router-dom', () => ({ useNavigate: () => vi.fn() }))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), warning: vi.fn() } }))
vi.mock('@/stores/auth-store', () => ({
  useAuthStore: (selector: (state: unknown) => unknown) => selector({
    profile: { id: 'user-1' },
    can: () => true,
  }),
}))
vi.mock('@/hooks/useDebounce', () => ({ useDebounce: (value: string) => value }))
vi.mock('@/components/shared/PageHeader', () => ({ default: () => null }))
vi.mock('@/components/targets/TierLadderDisplay', () => ({ default: () => null }))
vi.mock('@/hooks/useQueryHooks', () => ({
  useCreateTargetWithRewards: () => ({ mutateAsync: createTargetMock }),
  useTargetTypes: () => ({ data: [{
    id: 'type-category-spread', code: 'category_spread', name: 'توسيع تصنيفات',
    unit: 'count', category: 'sales', description: 'اختبار',
  }] }),
  useCurrentEmployee: () => ({ data: null }),
  useBranches: () => ({ data: [] }),
  useHRDepartments: () => ({ data: [] }),
  useHREmployees: () => ({ data: { data: [] } }),
  useCategories: () => ({ data: [] }),
  useGovernorates: () => ({ data: [] }),
  useCities: () => ({ data: [] }),
  useAreas: () => ({ data: [] }),
  useCustomers: () => ({
    data: { data: [{ id: 'customer-1', name: 'عميل اختبار', code: 'C-1' }] },
    isFetching: false,
  }),
  useReactivationTargetCandidates: () => ({ data: [], isFetching: false, error: null }),
}))

function clickNext() {
  fireEvent.click(screen.getByRole('button', { name: 'التالي' }))
}

describe('TargetForm review flow', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    createTargetMock.mockReset().mockResolvedValue('target-1')
    Element.prototype.scrollIntoView = vi.fn()
  })

  it('shows review after customer selection and never creates through form submit', () => {
    const { container } = render(<TargetForm />)

    fireEvent.click(screen.getByRole('button', { name: /توسيع تصنيفات/ }))
    fireEvent.change(screen.getByPlaceholderText('مثال: هدف توسيع تصنيفات - شهري 2026'), { target: { value: 'هدف اختبار' } })
    fireEvent.change(screen.getByPlaceholderText('مثال: 4'), { target: { value: '2' } })
    clickNext()

    // نطاق الشركة صالح دون scope_id.
    clickNext()
    const targetInputs = screen.getAllByRole('spinbutton')
    fireEvent.change(targetInputs[0], { target: { value: '1' } })
    clickNext()

    // بدون مكافأة: ينتقل مباشرة إلى اختيار العملاء.
    clickNext()
    fireEvent.change(screen.getByPlaceholderText('اكتب اسم العميل أو الكود...'), { target: { value: 'عم' } })
    fireEvent.click(screen.getByRole('option', { name: /عميل اختبار/ }))
    fireEvent.click(screen.getByRole('button', { name: 'إضافة' }))

    clickNext()
    expect(screen.getByText('✅ مراجعة شاملة قبل الإنشاء')).not.toBeNull()
    expect(createTargetMock).not.toHaveBeenCalled()

    // حتى submit صريح/Enter لا ينشئ شيئاً؛ الإنشاء له زر مستقل بعد عرض المراجعة.
    fireEvent.submit(container.querySelector('form')!)
    expect(createTargetMock).not.toHaveBeenCalled()

    act(() => vi.advanceTimersByTime(500))
    fireEvent.click(screen.getByRole('button', { name: 'إنشاء الهدف 🎯' }))
    expect(createTargetMock).toHaveBeenCalledTimes(1)
  })
})
