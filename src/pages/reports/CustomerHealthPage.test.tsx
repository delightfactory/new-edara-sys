import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, render, screen, within } from '@testing-library/react'
import CustomerHealthPage from './CustomerHealthPage'

const mocks = vi.hoisted(() => ({
  useSystemTrustState: vi.fn(),
  useTrustForComponent: vi.fn(),
  useCustomerHealthSummary: vi.fn(),
}))

vi.mock('@/hooks/useSystemTrustState', () => ({
  useSystemTrustState: mocks.useSystemTrustState,
  useTrustForComponent: mocks.useTrustForComponent,
}))

vi.mock('@/hooks/useCustomerHealth', () => ({
  useCustomerHealthSummary: mocks.useCustomerHealthSummary,
}))

vi.mock('@/components/reports/MetricCard', () => ({
  default: ({ label }: { label: string }) => <div data-testid="metric-card">{label}</div>,
}))

vi.mock('@/components/reports/SkeletonCard', () => ({
  default: ({ height }: { height: number }) => <div data-testid="skeleton-card" data-height={height} />,
}))

vi.mock('@/components/reports/SystemHealthBar', () => ({
  default: () => <div data-testid="system-health-bar" />,
}))

vi.mock('@/components/reports/TrustStateBadge', () => ({
  default: () => <span data-testid="trust-state-badge" />,
}))

vi.mock('@/components/reports/FreshnessIndicator', () => ({
  default: () => <span data-testid="freshness-indicator" />,
}))

const longCustomerName = 'شركة العميل ذات الاسم العربي الطويل جداً لاختبار الالتفاف داخل البطاقة بدون تجاوز'

const rows = [
  {
    customer_id: 'customer-1',
    customer_name: longCustomerName,
    as_of_date: '2026-09-20',
    recency_days: 12,
    frequency_l90d: 3,
    monetary_l90d: 1234,
    is_dormant: false,
  },
  {
    customer_id: 'deadbeef-1234-5678-9012',
    customer_name: undefined,
    as_of_date: '2026-09-20',
    recency_days: null,
    frequency_l90d: 1,
    monetary_l90d: 500,
    is_dormant: true,
  },
]

const stats = {
  total: 75,
  dormant: 1,
  active: 1,
  avg_monetary: 867,
  avg_recency: 12,
}

function setViewport(width: number) {
  Object.defineProperty(window, 'innerWidth', {
    configurable: true,
    writable: true,
    value: width,
  })
  act(() => window.dispatchEvent(new Event('resize')))
}

function getDetailSection() {
  const title = screen.getByText('تفاصيل العملاء — أعلى 50 حسب القيمة')
  return title.parentElement?.parentElement as HTMLElement
}

describe('Customer Health responsive detail collection', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    setViewport(1440)
    mocks.useSystemTrustState.mockReturnValue({
      data: [{ component_name: 'snapshot_customer_health', status: 'OK' }],
      isLoading: false,
      error: null,
    })
    mocks.useTrustForComponent.mockReturnValue({
      status: 'OK',
      last_completed_at: '2026-09-20T00:00:00Z',
      is_stale: false,
    })
    mocks.useCustomerHealthSummary.mockReturnValue({
      data: { stats, rows },
      isLoading: false,
    })
  })

  it('uses the shared three-column MetricGrid for the summary and preserves exact card order', () => {
    render(<CustomerHealthPage />)

    const grid = document.querySelector('[data-metric-grid]') as HTMLElement
    expect(grid).not.toBeNull()
    expect(grid.getAttribute('data-columns')).toBe('3')
    expect(grid.classList.contains('ds-metric-grid--cols-3')).toBe(true)
    expect(within(grid).getAllByTestId('metric-card').map(card => card.textContent)).toEqual([
      'نشطون',
      'خامدون',
      'متوسط القيمة (90 يوم)',
    ])
    expect(document.querySelector('.report-grid')).toBeNull()
  })

  it('keeps exactly three 150px summary skeletons inside MetricGrid while detail loading stays five 44px rows', () => {
    mocks.useCustomerHealthSummary.mockReturnValue({
      data: { stats, rows },
      isLoading: true,
    })

    render(<CustomerHealthPage />)

    const grid = document.querySelector('[data-metric-grid]') as HTMLElement
    const summarySkeletons = within(grid).getAllByTestId('skeleton-card')
    expect(summarySkeletons).toHaveLength(3)
    summarySkeletons.forEach(skeleton => expect(skeleton.getAttribute('data-height')).toBe('150'))

    const detailSection = getDetailSection()
    const loadingCollection = detailSection.querySelector('[data-collection-state="loading"]') as HTMLElement
    const detailSkeletons = within(loadingCollection).getAllByTestId('skeleton-card')
    expect(detailSkeletons).toHaveLength(5)
    detailSkeletons.forEach(skeleton => expect(skeleton.getAttribute('data-height')).toBe('44'))
  })

  it('preserves the compact semantic five-column Desktop table with no card renderer mounted', () => {
    render(<CustomerHealthPage />)

    const section = getDetailSection()
    const table = within(section).getByRole('table')
    const headers = within(table).getAllByRole('columnheader')

    expect(headers.map(header => header.textContent)).toEqual([
      'العميل',
      'أيام منذ آخر بيع',
      'تكرار (90 يوم)',
      'قيمة (90 يوم)',
      'الحالة',
    ])
    headers.forEach(header => expect(header.getAttribute('scope')).toBe('col'))
    expect(within(table).getByText(longCustomerName)).toBeTruthy()
    expect(within(table).getByText('12 يوم')).toBeTruthy()
    expect(within(table).getByText('3×')).toBeTruthy()
    expect(within(table).getByText('1,234 ج.م')).toBeTruthy()
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
  })

  it('mounts only the one-column Mobile cards with all row facts, wrapping, fallback identity, and LTR numeric values', () => {
    setViewport(390)
    render(<CustomerHealthPage />)

    const section = getDetailSection()
    expect(within(section).queryByRole('table')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--mobile')).not.toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--tablet')).toBeNull()
    expect(section.querySelector('.ds-key-value-list--cols-1')).not.toBeNull()

    const longName = within(section).getByText(longCustomerName)
    expect(longName.style.overflowWrap).toBe('anywhere')
    expect(within(section).getByText('deadbeef…')).toBeTruthy()

    ;['أيام منذ آخر بيع', 'تكرار (90 يوم)', 'قيمة (90 يوم)', 'الحالة'].forEach(label => {
      expect(within(section).getAllByText(label).length).toBeGreaterThan(0)
    })

    expect(within(section).getByText('12 يوم')).toBeTruthy()
    expect(within(section).getByText('3×').getAttribute('dir')).toBe('ltr')
    expect(within(section).getByText('1,234 ج.م').getAttribute('dir')).toBe('ltr')
    expect(within(section).getByText('نشط')).toBeTruthy()
    expect(within(section).getByText('خامد')).toBeTruthy()
    expect(within(section).getByText('لا توجد مبيعات')).toBeTruthy()
  })

  it('uses the deliberate two-column Tablet card composition and mounts no Desktop table', () => {
    setViewport(900)
    render(<CustomerHealthPage />)

    const section = getDetailSection()
    expect(within(section).queryByRole('table')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--tablet')).not.toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--mobile')).toBeNull()
    expect(section.querySelector('.ds-key-value-list--cols-2')).not.toBeNull()
    expect(within(section).getByText(longCustomerName)).toBeTruthy()
  })

  it('keeps the blocked state higher priority than collection loading, empty, or ready renderers', () => {
    setViewport(390)
    mocks.useTrustForComponent.mockReturnValue({
      status: 'BLOCKED',
      last_completed_at: null,
      is_stale: true,
    })
    mocks.useCustomerHealthSummary.mockReturnValue({
      data: { stats, rows },
      isLoading: true,
    })

    render(<CustomerHealthPage />)

    const section = getDetailSection()
    expect(within(section).getByText('بيانات العملاء محجوبة')).toBeTruthy()
    expect(within(section).getByText('snapshot_customer_health يحتاج إلى تشغيل ناجح أولاً')).toBeTruthy()
    expect(section.querySelector('.ds-responsive-collection')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
    expect(within(section).queryByRole('table')).toBeNull()
  })

  it('preserves the custom five-row loading state and exact empty copy without mounting a ready renderer', () => {
    setViewport(390)
    mocks.useCustomerHealthSummary.mockReturnValue({
      data: { stats, rows: [] },
      isLoading: true,
    })
    const { rerender } = render(<CustomerHealthPage />)

    let section = getDetailSection()
    const loadingCollection = section.querySelector('[data-collection-state="loading"]') as HTMLElement
    expect(loadingCollection).not.toBeNull()
    expect(within(loadingCollection).getAllByTestId('skeleton-card')).toHaveLength(5)
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
    expect(within(section).queryByRole('table')).toBeNull()
    expect(within(section).queryByText(/يعرض أعلى 50 عميلاً حسب القيمة/)).toBeNull()

    mocks.useCustomerHealthSummary.mockReturnValue({
      data: { stats, rows: [] },
      isLoading: false,
    })
    rerender(<CustomerHealthPage />)

    section = getDetailSection()
    expect(section.querySelector('[data-collection-state="empty"]')).not.toBeNull()
    expect(within(section).getByText('لا توجد بيانات snapshot لهذا التاريخ — شغّل watermark sweep أولاً')).toBeTruthy()
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
    expect(within(section).queryByRole('table')).toBeNull()
    expect(within(section).queryByText(/يعرض أعلى 50 عميلاً حسب القيمة/)).toBeNull()
  })

  it('preserves trust actions and renders the >50 informational footer exactly once only with ready data', () => {
    setViewport(390)
    const { rerender } = render(<CustomerHealthPage />)

    let section = getDetailSection()
    expect(within(section).getByTestId('trust-state-badge')).toBeTruthy()
    expect(within(section).getByTestId('freshness-indicator')).toBeTruthy()
    expect(within(section).getAllByText('يعرض أعلى 50 عميلاً حسب القيمة — 75 إجمالاً (مُجمَّعة في قاعدة البيانات)')).toHaveLength(1)

    mocks.useCustomerHealthSummary.mockReturnValue({
      data: { stats: { ...stats, total: 50 }, rows },
      isLoading: false,
    })
    rerender(<CustomerHealthPage />)

    section = getDetailSection()
    expect(within(section).queryByText(/يعرض أعلى 50 عميلاً حسب القيمة/)).toBeNull()
  })
})
