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
  useTargetCustomerCandidates: (params: { search?: string } | null) => {
    const showSecondCustomer = params?.search?.includes('الثاني')
    const customer = showSecondCustomer ? {
      customer_id: 'customer-2', customer_name: 'العميل الثاني', customer_code: 'C-2',
      customer_type: 'wholesale', assigned_rep_id: null, assigned_rep_name: null,
      governorate_name: null, city_name: 'القاهرة', area_name: null,
      last_purchase_date: '2026-07-22', dormant_days: 10,
      baseline_value: 1500, baseline_category_count: 3,
      eligible: true, eligibility_reason: 'eligible', total_count: 1,
    } : {
      customer_id: 'customer-1', customer_name: 'عميل اختبار', customer_code: 'C-1',
      customer_type: 'retail', assigned_rep_id: null, assigned_rep_name: null,
      governorate_name: null, city_name: null, area_name: null,
      last_purchase_date: '2026-07-20', dormant_days: 12,
      baseline_value: 1000, baseline_category_count: 2,
      eligible: true, eligibility_reason: 'eligible', total_count: 1,
    }
    return {
      data: { data: [customer], totalCount: 1, page: 1, pageSize: 100 },
      isFetching: false,
      error: null,
    }
  },
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

    // واجهة الاختيار الذكي تبدأ مركزة على البحث وتكشف الفلاتر عند الحاجة فقط.
    const smartSearch = screen.getByRole('textbox', { name: 'بحث ذكي عن العملاء' })
    fireEvent.change(smartSearch, { target: { value: 'عميل اختبار' } })
    expect(screen.getByRole('button', { name: 'مسح البحث' })).not.toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'مسح البحث' }))
    expect((smartSearch as HTMLInputElement).value).toBe('')

    const filtersButton = screen.getByRole('button', { name: /فلاتر متقدمة/ })
    expect(filtersButton.getAttribute('aria-expanded')).toBe('false')
    fireEvent.click(filtersButton)
    expect(filtersButton.getAttribute('aria-expanded')).toBe('true')
    expect(screen.getByText('تضييق النتائج')).not.toBeNull()

    fireEvent.click(screen.getByRole('button', { name: 'اختيار النتائج المعروضة (1)' }))
    const selectedCustomers = screen.getByRole('complementary', { name: 'العملاء المختارون' })
    expect(selectedCustomers.textContent).toContain('عميل اختبار')

    // تغيير النتائج لا يمسح المجموعة الأولى؛ المجموعة الجديدة تُدمج معها بلا استبدال.
    fireEvent.change(smartSearch, { target: { value: 'العميل الثاني' } })
    expect(screen.getByRole('checkbox', { name: 'اختيار العميل الثاني' })).not.toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'اختيار النتائج المعروضة (1)' }))
    expect(selectedCustomers.textContent).toContain('عميل اختبار')
    expect(selectedCustomers.textContent).toContain('العميل الثاني')
    expect(selectedCustomers.textContent).toContain('2 عميل')

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
