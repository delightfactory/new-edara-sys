import type { ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'

const testState = vi.hoisted(() => ({
  device: 'desktop' as 'mobile' | 'tablet' | 'desktop',
  useCustomers: vi.fn(),
}))

const customer = {
  id: 'customer-1',
  name: 'عميل اختبار',
  code: 'C-001',
  mobile: '01000000000',
  phone: null,
  type: 'retail',
  payment_terms: 'cash',
  credit_limit: 0,
  credit_days: 0,
  current_balance: 0,
  is_active: true,
  latitude: null,
  longitude: null,
} as any

vi.mock('@/hooks/useDeviceMode', () => ({
  useDeviceMode: () => testState.device,
}))

vi.mock('@/hooks/useQueryHooks', () => ({
  useCustomers: (params: unknown) => testState.useCustomers(params),
  useGovernorates: () => ({ data: [] }),
  useProfiles: () => ({ data: [] }),
  useCities: () => ({ data: [] }),
  useInvalidate: () => vi.fn(),
}))

vi.mock('@/hooks/useFilterState', () => ({
  useFilterState: () => ({
    filters: {
      search: '',
      type: '',
      governorateId: '',
      cityId: '',
      repId: '',
      status: '',
    },
    setFilter: vi.fn(),
    setFilters: vi.fn(),
    reset: vi.fn(),
    activeCount: 0,
    filterKey: 'base',
  }),
}))

vi.mock('@/hooks/useIntersectionObserver', () => ({
  useMobileInfiniteList: ({ data }: { data: unknown[] }) => ({
    accumulated: data,
    sentinelRef: { current: null },
  }),
}))

vi.mock('@/stores/auth-store', () => ({
  useAuthStore: (selector: (state: unknown) => unknown) => selector({
    can: () => true,
  }),
}))

vi.mock('@/components/shared/FilterBar', () => {
  const FilterBar = Object.assign(
    ({ children }: { children?: ReactNode }) => <div data-testid="filters">{children}</div>,
    {
      Search: () => <div data-testid="filter-search" />,
      Select: () => <div data-testid="filter-select" />,
    },
  )
  return { default: FilterBar }
})

vi.mock('@/components/shared/DataTable', () => ({
  default: ({ data }: { data: Array<{ name: string }> }) => (
    <div data-testid="desktop-table">{data.map(item => item.name).join(',')}</div>
  ),
}))

vi.mock('@/components/ui/DataCard', () => ({
  default: ({ title }: { title: ReactNode }) => <div data-testid="mobile-card">{title}</div>,
}))

vi.mock('@/components/ui/ResponsiveModal', () => ({
  default: () => null,
}))

vi.mock('@/components/shared/CustomerCreditChip', () => ({
  default: () => <span>credit</span>,
}))

vi.mock('@/lib/services/customers', () => ({
  toggleCustomerActive: vi.fn(),
}))

import CustomersPage from './CustomersPage'

function renderPage() {
  return render(
    <MemoryRouter>
      <CustomersPage />
    </MemoryRouter>,
  )
}

describe('Customers responsive collection migration', () => {
  beforeEach(() => {
    testState.device = 'desktop'
    testState.useCustomers.mockReset()
    testState.useCustomers.mockReturnValue({
      data: {
        data: [customer],
        count: 1,
        totalPages: 1,
      },
      isLoading: false,
    })
  })

  it('mounts only the paged table presentation on desktop', () => {
    renderPage()

    expect(screen.getByTestId('desktop-table')).toBeTruthy()
    expect(screen.queryByTestId('mobile-card')).toBeNull()
    expect(testState.useCustomers).toHaveBeenCalledTimes(2)
  })

  it('mounts only mobile cards on mobile while keeping the existing data hooks', () => {
    testState.device = 'mobile'
    renderPage()

    expect(screen.getByTestId('mobile-card')).toBeTruthy()
    expect(screen.queryByTestId('desktop-table')).toBeNull()
    expect(testState.useCustomers).toHaveBeenCalledTimes(2)
  })
})
