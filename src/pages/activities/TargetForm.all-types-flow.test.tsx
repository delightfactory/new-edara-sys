import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import TargetForm from './TargetForm'

const targetTypes = [
  { id: 'sales', code: 'sales_value', name: 'قيمة المبيعات', unit: 'currency', category: 'financial' },
  { id: 'collection', code: 'collection', name: 'التحصيلات', unit: 'currency', category: 'financial' },
  { id: 'qty', code: 'product_qty', name: 'كمية منتج', unit: 'quantity', category: 'product' },
  { id: 'visits', code: 'visits_count', name: 'عدد الزيارات', unit: 'count', category: 'activity' },
  { id: 'calls', code: 'calls_count', name: 'عدد المكالمات', unit: 'count', category: 'activity' },
  { id: 'new', code: 'new_customers', name: 'عملاء جدد', unit: 'count', category: 'customer' },
  { id: 'reactivation', code: 'reactivation', name: 'إعادة تنشيط', unit: 'count', category: 'customer' },
  { id: 'upgrade', code: 'upgrade_value', name: 'رفع مشتريات', unit: 'count', category: 'customer' },
  { id: 'spread', code: 'category_spread', name: 'توسيع تصنيفات', unit: 'count', category: 'customer' },
]

vi.mock('react-router-dom', () => ({ useNavigate: () => vi.fn() }))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), warning: vi.fn() } }))
vi.mock('@/stores/auth-store', () => ({
  useAuthStore: (selector: (state: unknown) => unknown) => selector({
    profile: { id: 'user-1' },
    can: () => true,
  }),
}))
vi.mock('@/components/shared/PageHeader', () => ({ default: () => null }))
vi.mock('@/components/targets/TierLadderDisplay', () => ({ default: () => null }))
vi.mock('@/components/ui/AsyncCombobox', () => ({
  default: ({ label, placeholder, onChange }: any) => (
    <div>
      <span>{label}</span>
      <button type="button" onClick={() => onChange('product-1', { value: 'product-1', label: 'منتج اختبار' })}>
        {placeholder}
      </button>
    </div>
  ),
}))
vi.mock('@/hooks/useQueryHooks', () => ({
  useCreateTargetWithRewards: () => ({ mutateAsync: vi.fn() }),
  useTargetTypes: () => ({ data: targetTypes }),
  useCurrentEmployee: () => ({ data: null }),
  useBranches: () => ({ data: [] }),
  useHRDepartments: () => ({ data: [] }),
  useHREmployees: () => ({ data: { data: [] } }),
  useCategories: () => ({ data: [{ id: 'category-1', name: 'تصنيف اختبار' }] }),
  useGovernorates: () => ({ data: [{ id: 'gov-1', name: 'القاهرة' }] }),
  useCities: () => ({ data: [] }),
  useAreas: () => ({ data: [] }),
  useCustomers: () => ({ data: { data: [] }, isFetching: false }),
  useReactivationTargetCandidates: () => ({ data: [], isFetching: false, error: null }),
}))

function selectType(name: string) {
  fireEvent.click(screen.getByText(name))
}

describe('TargetForm UI flow for all active target types', () => {
  it.each([
    ['التحصيلات'], ['عدد الزيارات'], ['عدد المكالمات'], ['عملاء جدد'],
  ])('does not expose unsupported filters for %s', name => {
    render(<TargetForm />)
    selectType(name)
    expect(screen.queryByText(/فلاتر تخصصية/)).toBeNull()
  })

  it('shows searchable product selection and hierarchical geography for sales', () => {
    render(<TargetForm />)
    selectType('قيمة المبيعات')
    expect(screen.getByRole('button', { name: 'ابحث باسم المنتج أو الكود أو الباركود...' })).not.toBeNull()
    expect(screen.getByText('المحافظة', { exact: false })).not.toBeNull()
    expect(screen.getByText(/الفلتر الجغرافي مدعوم حسابياً لهدف المبيعات فقط/)).not.toBeNull()
  })

  it('requires a product or category before a quantity target can continue', () => {
    render(<TargetForm />)
    selectType('كمية منتج')
    fireEvent.change(screen.getByPlaceholderText('مثال: هدف كمية منتج - شهري 2026'), { target: { value: 'هدف كمية' } })

    const next = screen.getByRole('button', { name: 'التالي' })
    expect((next as HTMLButtonElement).disabled).toBe(true)
    fireEvent.click(screen.getByRole('button', { name: 'ابحث باسم المنتج أو الكود أو الباركود...' }))
    expect((next as HTMLButtonElement).disabled).toBe(false)
  })

  it.each([
    ['إعادة تنشيط', 'مثال: 90', 'مثال: 5000'],
    ['رفع مشتريات', 'مثال: 20 (يعني 20%)', null],
    ['توسيع تصنيفات', 'مثال: 4', null],
  ])('shows the complete recently-added controls for %s', (name, firstPlaceholder, secondPlaceholder) => {
    render(<TargetForm />)
    selectType(name)
    expect(screen.getByPlaceholderText(firstPlaceholder)).not.toBeNull()
    if (secondPlaceholder) expect(screen.getByPlaceholderText(secondPlaceholder)).not.toBeNull()
  })
})
