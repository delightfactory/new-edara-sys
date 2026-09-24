import type { ReactNode } from 'react'
import { act, render } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { ReengagementRow } from '@/hooks/useCustomerReengagement'
import CustomerReengagementPage from './CustomerReengagementPage'

const mocks = vi.hoisted(() => ({
  setTitle: vi.fn(),
  useReengagementList: vi.fn(),
  useReengagementSummary: vi.fn(),
  can: vi.fn(),
}))

vi.mock('@/components/layout/PageTitleContext', () => ({
  usePageTitle: () => ({ setTitle: mocks.setTitle }),
}))

vi.mock('@/hooks/useCustomerReengagement', () => ({
  useReengagementList: mocks.useReengagementList,
  useReengagementSummary: mocks.useReengagementSummary,
}))

vi.mock('@/hooks/useFilterState', () => ({
  useFilterState: () => ({
    filters: {
      dateFrom: '',
      dateTo: '',
      repId: '',
      governorateId: '',
      cityId: '',
      priority: '',
      customerType: '',
      activeOnly: true,
    },
    setFilter: vi.fn(),
    setFilters: vi.fn(),
    reset: vi.fn(),
    activeCount: 0,
  }),
}))

vi.mock('@/hooks/useQueryHooks', () => ({
  useGovernorates: () => ({ data: [] }),
  useCities: () => ({ data: [] }),
  useProfiles: () => ({ data: [] }),
}))

vi.mock('@/stores/auth-store', () => ({
  useAuthStore: (selector: (state: { can: (permission: string) => boolean }) => unknown) => selector({ can: mocks.can }),
}))

vi.mock('@/components/shared/PageHeader', () => ({
  default: ({ title }: { title: string }) => <div data-testid="page-header">{title}</div>,
}))

vi.mock('@/components/shared/FilterBar', () => {
  const EmptyControl = () => null
  const FilterBar = Object.assign(
    ({ children }: { children?: ReactNode }) => <div data-testid="filter-bar">{children}</div>,
    {
      Select: EmptyControl,
      DateRange: EmptyControl,
      Toggle: EmptyControl,
    },
  )
  return { default: FilterBar }
})

vi.mock('@/features/output/hooks/useDocumentOutput', () => ({
  useDocumentOutput: () => ({
    triggerPreview: vi.fn(),
    triggerPdfDownload: vi.fn(),
    busy: false,
    error: null,
    clearError: vi.fn(),
  }),
}))

vi.mock('@/lib/utils/export', () => ({
  downloadAsCSV: vi.fn(),
}))

const summary = {
  total_customers: 1234,
  champion_lost_count: 12,
  declining_high_count: 34,
  mid_lost_count: 56,
  mid_at_risk_count: 78,
  other_count: 90,
  total_outstanding: 98765,
  avg_historical_revenue: 5000,
  avg_recency_days: 42,
}

const rows: ReengagementRow[] = [
  {
    customer_id: 'customer-1',
    customer_name: 'عميل ألف',
    customer_code: 'C-001',
    customer_type: 'retail',
    governorate_name: 'الغربية',
    city_name: 'طنطا',
    rep_name: 'أحمد',
    rep_id: 'rep-1',
    priority_label: 'CHAMPION_LOST',
    priority_rank: 1,
    value_tier: 'HIGH',
    status_label: 'LOST',
    historical_revenue: 125000,
    revenue_last_90d: 0,
    revenue_prev_90d: 42000,
    recency_days: 120,
    last_order_date: '2026-05-20',
    outstanding_balance: 3500,
    order_count: 18,
    is_active: true,
  },
  {
    customer_id: 'customer-2',
    customer_name: 'عميل باء',
    customer_code: 'C-002',
    customer_type: 'wholesale',
    governorate_name: 'القاهرة',
    city_name: 'مدينة نصر',
    rep_name: 'محمد',
    rep_id: 'rep-2',
    priority_label: 'MID_AT_RISK',
    priority_rank: 4,
    value_tier: 'MED',
    status_label: 'AT_RISK',
    historical_revenue: 64000,
    revenue_last_90d: 7000,
    revenue_prev_90d: 19000,
    recency_days: 58,
    last_order_date: '2026-07-27',
    outstanding_balance: -900,
    order_count: 9,
    is_active: true,
  },
]

function setViewport(width: number) {
  Object.defineProperty(window, 'innerWidth', {
    configurable: true,
    writable: true,
    value: width,
  })
  act(() => window.dispatchEvent(new Event('resize')))
}

function renderPage(width = 1440) {
  setViewport(width)
  return render(
    <MemoryRouter>
      <CustomerReengagementPage />
    </MemoryRouter>,
  )
}

function getMetricCards() {
  const grid = document.querySelector('[data-metric-grid]') as HTMLElement
  expect(grid).not.toBeNull()
  expect(grid.getAttribute('data-columns')).toBe('3')
  return { grid, cards: Array.from(grid.querySelectorAll('.ds-stat-card')) as HTMLElement[] }
}

function cardPart(card: HTMLElement, selector: string) {
  return card.querySelector(selector)?.textContent
}

function useReadyRows() {
  mocks.useReengagementList.mockReturnValue({
    data: rows,
    isLoading: false,
    error: null,
  })
}

function collectionRoot() {
  const collection = document.querySelector('.ds-responsive-collection') as HTMLElement
  expect(collection).not.toBeNull()
  return collection
}

function customerNames(selector: string) {
  return Array.from(document.querySelectorAll(selector)).map(node => node.textContent)
}

describe('Customer Re-engagement KPI summary convergence', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.can.mockReturnValue(false)
    mocks.useReengagementList.mockReturnValue({
      data: [],
      isLoading: false,
      error: null,
    })
    mocks.useReengagementSummary.mockReturnValue({
      data: summary,
      isLoading: false,
    })
  })

  it('uses the shared three-column metric grammar while preserving exact KPI order, copy, values, icons, and tones', () => {
    renderPage()

    const { grid, cards } = getMetricCards()
    expect(grid.classList.contains('ds-metric-grid--cols-3')).toBe(true)
    expect(cards).toHaveLength(5)

    expect(cards.map(card => cardPart(card, '.ds-stat-card__label'))).toEqual([
      'Champion Lost',
      'تراجع عالي',
      'متوسط خامد',
      'إجمالي العملاء',
      'صافي الأرصدة',
    ])
    expect(cards.map(card => cardPart(card, '.ds-stat-card__context'))).toEqual([
      'عملاء مميزون خمدوا',
      'عملاء في خطر',
      'فرصة متوسطة',
      'في قاعدة البيانات',
      'إجمالي مديونية',
    ])
    expect(cards.map(card => cardPart(card, '.ds-stat-card__value'))).toEqual([
      '12',
      '34',
      '56',
      '1,234',
      '98,765 ج.م',
    ])
    expect(cards.map(card => cardPart(card, '.ds-stat-card__icon'))).toEqual(['🔴', '🟠', '🟡', '👥', '💰'])
    expect(cards.map(card => card.getAttribute('data-tone'))).toEqual([
      'danger',
      'warning',
      'warning',
      'info',
      'info',
    ])

    expect(document.querySelector('.rp-kpi-grid')).toBeNull()
    expect(document.querySelector('.rp-kpi-card')).toBeNull()
  })

  it('preserves the credit-balance sign semantics while mapping its presentation to success', () => {
    mocks.useReengagementSummary.mockReturnValue({
      data: { ...summary, total_outstanding: -4321 },
      isLoading: false,
    })

    renderPage()

    const { cards } = getMetricCards()
    const balanceCard = cards[4]
    expect(cardPart(balanceCard, '.ds-stat-card__context')).toBe('رصيد دائن صاف')
    expect(cardPart(balanceCard, '.ds-stat-card__value')).toBe('4,321 ج.م')
    expect(cardPart(balanceCard, '.ds-stat-card__icon')).toBe('🟢')
    expect(balanceCard.getAttribute('data-tone')).toBe('success')
  })

  it('keeps all five metric identities and contexts visible while loading only the value layer', () => {
    mocks.useReengagementSummary.mockReturnValue({
      data: summary,
      isLoading: true,
    })

    renderPage()

    const { grid, cards } = getMetricCards()
    expect(cards).toHaveLength(5)
    expect(cards.map(card => cardPart(card, '.ds-stat-card__label'))).toEqual([
      'Champion Lost',
      'تراجع عالي',
      'متوسط خامد',
      'إجمالي العملاء',
      'صافي الأرصدة',
    ])
    expect(cards.map(card => cardPart(card, '.ds-stat-card__context'))).toEqual([
      'عملاء مميزون خمدوا',
      'عملاء في خطر',
      'فرصة متوسطة',
      'في قاعدة البيانات',
      'إجمالي مديونية',
    ])

    const skeletons = Array.from(grid.querySelectorAll('.rp-kpi-skeleton')) as HTMLElement[]
    expect(skeletons).toHaveLength(5)
    skeletons.forEach(skeleton => expect(skeleton.getAttribute('aria-hidden')).toBe('true'))
    cards.forEach(card => expect(card.querySelector('.ds-stat-card__value .rp-kpi-skeleton')).not.toBeNull())
  })
})

describe('Customer Re-engagement responsive collection convergence', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.can.mockReturnValue(false)
    mocks.useReengagementList.mockReturnValue({
      data: [],
      isLoading: false,
      error: null,
    })
    mocks.useReengagementSummary.mockReturnValue({
      data: summary,
      isLoading: false,
    })
  })

  it('mounts only the Mobile card renderer at 390px and preserves row order', () => {
    useReadyRows()
    renderPage(390)

    const collection = collectionRoot()
    expect(collection.getAttribute('data-device')).toBe('mobile')
    expect(collection.getAttribute('data-collection-state')).toBe('ready')
    expect(document.querySelector('.rp-mobile-cards')).not.toBeNull()
    expect(document.querySelector('.rp-tablet-cards')).toBeNull()
    expect(document.querySelector('.rp-desktop-table')).toBeNull()
    expect(customerNames('.rp-mcard-name')).toEqual(['عميل ألف', 'عميل باء'])
  })

  it('mounts only the explicit two-column touch-first card renderer at 900px', () => {
    useReadyRows()
    renderPage(900)

    const collection = collectionRoot()
    const tabletGrid = document.querySelector('.rp-tablet-cards') as HTMLElement
    expect(collection.getAttribute('data-device')).toBe('tablet')
    expect(collection.getAttribute('data-collection-state')).toBe('ready')
    expect(tabletGrid).not.toBeNull()
    expect(tabletGrid.classList.contains('ds-responsive-card-grid')).toBe(true)
    expect(tabletGrid.classList.contains('ds-responsive-card-grid--tablet')).toBe(true)
    expect(document.querySelector('.rp-mobile-cards')).toBeNull()
    expect(document.querySelector('.rp-desktop-table')).toBeNull()
    expect(customerNames('.rp-mcard-name')).toEqual(['عميل ألف', 'عميل باء'])
  })

  it('mounts only the dense Desktop table at 1440px and preserves row order', () => {
    useReadyRows()
    renderPage(1440)

    const collection = collectionRoot()
    expect(collection.getAttribute('data-device')).toBe('desktop')
    expect(collection.getAttribute('data-collection-state')).toBe('ready')
    expect(document.querySelector('.rp-desktop-table')).not.toBeNull()
    expect(document.querySelector('.rp-mobile-cards')).toBeNull()
    expect(document.querySelector('.rp-tablet-cards')).toBeNull()
    expect(customerNames('.rp-customer-name')).toEqual(['عميل ألف', 'عميل باء'])
  })

  it('keeps loading ahead of ready composition with exactly eight existing skeleton rows', () => {
    mocks.useReengagementList.mockReturnValue({
      data: rows,
      isLoading: true,
      error: null,
    })

    renderPage(900)

    const collection = collectionRoot()
    expect(collection.getAttribute('data-device')).toBe('tablet')
    expect(collection.getAttribute('data-collection-state')).toBe('loading')
    expect(collection.querySelectorAll('.skeleton-row')).toHaveLength(8)
    expect(collection.querySelector('.rp-desktop-table')).toBeNull()
    expect(collection.querySelector('.rp-tablet-cards')).toBeNull()
    expect(collection.querySelector('.rp-mobile-cards')).toBeNull()
  })

  it('preserves the exact filtered-empty copy before any ready renderer mounts', () => {
    renderPage(390)

    const collection = collectionRoot()
    expect(collection.getAttribute('data-device')).toBe('mobile')
    expect(collection.getAttribute('data-collection-state')).toBe('empty')
    expect(collection.querySelector('.rp-empty-title')?.textContent).toBe('لا يوجد عملاء يطابقون الفلاتر المحددة')
    expect(collection.querySelector('.rp-empty-hint')?.textContent).toBe('جرّب تغيير الفلاتر أو إلغاء تفعيل «النشطون فقط»')
    expect(collection.querySelector('.rp-desktop-table')).toBeNull()
    expect(collection.querySelector('.rp-tablet-cards')).toBeNull()
    expect(collection.querySelector('.rp-mobile-cards')).toBeNull()
  })

  it('keeps Customer 360 native-link routes permission-gated across Mobile, Tablet, and Desktop', () => {
    useReadyRows()
    mocks.can.mockImplementation((permission: string) => permission === 'customers.read')

    for (const width of [390, 900, 1440]) {
      const view = renderPage(width)
      const links = Array.from(document.querySelectorAll('a[href^="/customers/"]')) as HTMLAnchorElement[]
      expect(links.map(link => link.getAttribute('href'))).toEqual([
        '/customers/customer-1',
        '/customers/customer-2',
      ])
      links.forEach(link => expect(link.tagName).toBe('A'))
      view.unmount()
    }

    mocks.can.mockReturnValue(false)
    for (const width of [390, 900, 1440]) {
      const view = renderPage(width)
      expect(document.querySelectorAll('a[href^="/customers/"]')).toHaveLength(0)
      view.unmount()
    }
  })
})
