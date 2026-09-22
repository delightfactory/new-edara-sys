import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, within } from '@testing-library/react'
import GeographyPage from './GeographyPage'

const mocks = vi.hoisted(() => ({
  useSystemTrustState: vi.fn(),
  useTrustForComponent: vi.fn(),
  useGeographySummary: vi.fn(),
  useGeographyTable: vi.fn(),
}))

vi.mock('@/hooks/useSystemTrustState', () => ({
  useSystemTrustState: mocks.useSystemTrustState,
  useTrustForComponent: mocks.useTrustForComponent,
}))

vi.mock('@/hooks/useGeographyPerformance', () => ({
  useGeographySummary: mocks.useGeographySummary,
  useGeographyTable: mocks.useGeographyTable,
}))

vi.mock('@/components/reports/MetricCard', () => ({
  default: ({
    label,
    subtitle,
    value,
    status,
    lastCompletedAt,
    isStale,
    domain,
  }: {
    label: string
    subtitle?: string
    value?: string | number | null
    status?: string | null
    lastCompletedAt?: string
    isStale?: boolean
    domain?: string
  }) => (
    <div
      data-testid="metric-card"
      data-subtitle={subtitle}
      data-value={value ?? ''}
      data-status={status ?? ''}
      data-last-completed-at={lastCompletedAt ?? ''}
      data-stale={String(Boolean(isStale))}
      data-domain={domain ?? ''}
    >
      {label}
    </div>
  ),
}))

vi.mock('@/components/reports/SkeletonCard', () => ({
  default: ({ height }: { height: number }) => <div data-testid="skeleton-card" data-height={height} />,
}))

vi.mock('@/components/reports/SystemHealthBar', () => ({
  default: () => <div data-testid="system-health-bar" />,
}))

vi.mock('@/components/reports/ReportFilterBar', () => ({
  default: () => <div data-testid="report-filter-bar" />,
}))

vi.mock('@/components/reports/TrustStateBadge', () => ({
  default: () => <span data-testid="trust-state-badge" />,
}))

vi.mock('@/components/reports/FreshnessIndicator', () => ({
  default: () => <span data-testid="freshness-indicator" />,
}))

const longGeoName = 'منطقة جغرافية عربية ذات اسم طويل جداً لاختبار الالتفاف داخل بطاقة التقرير بدون تجاوز أفقي'
const longParentName = 'مدينة أم ذات اسم عربي طويل جداً لاختبار التفاف سياق المستوى الأعلى داخل البطاقة'

const geographyRows = [
  {
    geo_id: 'geo-1',
    geo_name: longGeoName,
    parent_name: longParentName,
    net_revenue: 2500,
    customer_count: 5,
    transaction_count: 8,
    revenue_share_pct: 62,
  },
  {
    geo_id: 'geo-2',
    geo_name: 'منطقة بلا مبيعات',
    parent_name: null,
    net_revenue: 0,
    customer_count: 0,
    transaction_count: 0,
    revenue_share_pct: 0,
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

function getDistributionSection() {
  const title = screen.getByText(/التوزيع حسب (محافظة|مدينة|منطقة)/)
  return title.parentElement?.parentElement as HTMLElement
}

describe('Geography responsive detail collection', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    setViewport(1440)
    mocks.useSystemTrustState.mockReturnValue({ data: [], isLoading: false, error: null })
    mocks.useTrustForComponent.mockReturnValue({
      status: 'OK',
      last_completed_at: '2026-09-21T00:00:00Z',
      is_stale: false,
    })
    mocks.useGeographySummary.mockReturnValue({
      data: { total_revenue: 2500, covered_areas: 2 },
      isLoading: false,
    })
    mocks.useGeographyTable.mockReturnValue({ data: geographyRows, isLoading: false })
  })

  it('uses one shared two-column MetricGrid for the summary with exact card order and caller-owned metric truth', () => {
    const { container } = render(<GeographyPage />)

    const metricGrids = container.querySelectorAll('[data-metric-grid]')
    expect(metricGrids).toHaveLength(1)

    const metricGrid = metricGrids[0] as HTMLElement
    expect(metricGrid.getAttribute('data-columns')).toBe('2')
    expect(container.querySelector('.report-grid')).toBeNull()

    const cards = within(metricGrid).getAllByTestId('metric-card')
    expect(cards.map(card => card.textContent)).toEqual([
      'إجمالى الإيراد',
      'محافظة مغطاة',
    ])
    expect(cards[0].getAttribute('data-subtitle')).toBe('من جميع المناطق الجغرافية')
    expect(cards[0].getAttribute('data-value')).toBe('2,500 ج.م')
    expect(cards[1].getAttribute('data-subtitle')).toBe('بها مبيعات فى الفترة')
    expect(cards[1].getAttribute('data-value')).toBe('2')
    cards.forEach(card => {
      expect(card.getAttribute('data-status')).toBe('OK')
      expect(card.getAttribute('data-last-completed-at')).toBe('2026-09-21T00:00:00Z')
      expect(card.getAttribute('data-stale')).toBe('false')
      expect(card.getAttribute('data-domain')).toBe('sales')
    })
  })

  it('preserves the shared Select contract and exact controlled geography filter shape', () => {
    render(<GeographyPage />)

    const select = screen.getByRole('combobox', { name: 'مستوى التحليل الجغرافي' }) as HTMLSelectElement
    const options = within(select).getAllByRole('option') as HTMLOptionElement[]

    expect(select.classList.contains('form-select')).toBe(true)
    expect(select.closest('.ds-field')).not.toBeNull()
    expect(select.getAttribute('style')).toBeNull()
    expect(options.map(option => [option.value, option.textContent])).toEqual([
      ['governorate', 'محافظة'],
      ['city', 'مدينة'],
      ['area', 'منطقة'],
    ])
    expect(select.value).toBe('governorate')
    expect(screen.getByTestId('report-filter-bar')).toBeTruthy()

    fireEvent.change(select, { target: { value: 'city' } })

    expect(select.value).toBe('city')
    expect(mocks.useGeographySummary).toHaveBeenLastCalledWith(expect.objectContaining({
      dateFrom: expect.any(String),
      dateTo: expect.any(String),
      level: 'city',
    }))
    expect(mocks.useGeographyTable).toHaveBeenLastCalledWith(expect.objectContaining({
      dateFrom: expect.any(String),
      dateTo: expect.any(String),
      level: 'city',
    }))
    expect(screen.getByText('مدينة مغطاة')).toBeTruthy()
    expect(screen.getByText('التوزيع حسب مدينة')).toBeTruthy()
  })

  it('preserves the dense governorate Desktop table, semantic headers, row facts, and no card renderer', () => {
    render(<GeographyPage />)

    const section = getDistributionSection()
    const table = within(section).getByRole('table')
    const headers = within(table).getAllByRole('columnheader')

    expect(headers.map(header => header.textContent)).toEqual([
      'محافظة',
      'صافى الإيراد',
      'عملاء',
      'صفقات',
      'الحصة%',
    ])
    headers.forEach(header => expect(header.getAttribute('scope')).toBe('col'))
    expect(within(table).getByText(longGeoName)).toBeTruthy()
    expect(within(table).getByText('2,500 ج.م')).toBeTruthy()
    expect(within(table).getByText('5')).toBeTruthy()
    expect(within(table).getByText('8')).toBeTruthy()
    expect(within(table).getByText('62%')).toBeTruthy()
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
    expect(within(section).getByTestId('trust-state-badge')).toBeTruthy()
    expect(within(section).getByTestId('freshness-indicator')).toBeTruthy()
  })

  it('keeps the conditional parent column and fallback in the Desktop city renderer', () => {
    render(<GeographyPage />)

    fireEvent.change(screen.getByRole('combobox', { name: 'مستوى التحليل الجغرافي' }), { target: { value: 'city' } })

    const section = getDistributionSection()
    const table = within(section).getByRole('table')
    const headers = within(table).getAllByRole('columnheader')

    expect(headers.map(header => header.textContent)).toEqual([
      'مدينة',
      'الأم',
      'صافى الإيراد',
      'عملاء',
      'صفقات',
      'الحصة%',
    ])
    headers.forEach(header => expect(header.getAttribute('scope')).toBe('col'))
    expect(within(table).getByText(longParentName)).toBeTruthy()
    expect(within(table).getByText('—')).toBeTruthy()
  })

  it('mounts only one-column Mobile cards with complete row truth, wrapping, conditional parent omission, and LTR numeric values', () => {
    setViewport(390)
    render(<GeographyPage />)

    const section = getDistributionSection()
    expect(within(section).queryByRole('table')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--mobile')).not.toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--tablet')).toBeNull()
    expect(section.querySelector('.ds-key-value-list--cols-1')).not.toBeNull()
    expect(within(section).queryByText('الأم')).toBeNull()

    const longName = within(section).getByText(longGeoName)
    expect(longName.style.overflowWrap).toBe('anywhere')

    ;['صافى الإيراد', 'عملاء', 'صفقات', 'الحصة%'].forEach(label => {
      expect(within(section).getAllByText(label).length).toBeGreaterThan(0)
    })

    expect(within(section).getByText('2,500 ج.م').getAttribute('dir')).toBe('ltr')
    expect(within(section).getByText('5').getAttribute('dir')).toBe('ltr')
    expect(within(section).getByText('8').getAttribute('dir')).toBe('ltr')
    expect(within(section).getByText('62%').getAttribute('dir')).toBe('ltr')
  })

  it('uses deliberate two-column Tablet cards and preserves conditional parent truth with wrapping and fallback', () => {
    setViewport(900)
    render(<GeographyPage />)

    fireEvent.change(screen.getByRole('combobox', { name: 'مستوى التحليل الجغرافي' }), { target: { value: 'city' } })

    const section = getDistributionSection()
    expect(within(section).queryByRole('table')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--tablet')).not.toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--mobile')).toBeNull()
    expect(section.querySelector('.ds-key-value-list--cols-2')).not.toBeNull()
    expect(within(section).getAllByText('الأم')).toHaveLength(2)

    const parent = within(section).getByText(longParentName)
    expect(parent.style.overflowWrap).toBe('anywhere')
    expect(within(section).getByText('—')).toBeTruthy()
  })

  it('preserves the exact two-card summary loading grid plus five-row detail loading state and exact empty copy', () => {
    setViewport(390)
    mocks.useGeographyTable.mockReturnValue({ data: geographyRows, isLoading: true })
    const { container, rerender } = render(<GeographyPage />)

    const summaryGrid = container.querySelector('[data-metric-grid]') as HTMLElement
    const summarySkeletons = within(summaryGrid).getAllByTestId('skeleton-card')
    expect(summaryGrid.getAttribute('data-columns')).toBe('2')
    expect(summarySkeletons).toHaveLength(2)
    summarySkeletons.forEach(skeleton => expect(skeleton.getAttribute('data-height')).toBe('160'))

    let section = getDistributionSection()
    const loadingCollection = section.querySelector('[data-collection-state="loading"]') as HTMLElement
    expect(loadingCollection).not.toBeNull()
    const loadingSkeletons = within(loadingCollection).getAllByTestId('skeleton-card')
    expect(loadingSkeletons).toHaveLength(5)
    loadingSkeletons.forEach(skeleton => expect(skeleton.getAttribute('data-height')).toBe('44'))
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
    expect(within(section).queryByRole('table')).toBeNull()

    mocks.useGeographyTable.mockReturnValue({ data: [], isLoading: false })
    rerender(<GeographyPage />)

    section = getDistributionSection()
    expect(section.querySelector('[data-collection-state="empty"]')).not.toBeNull()
    expect(within(section).getByText('لا توجد بيانات — شغّل watermark sweep أولاً')).toBeTruthy()
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
    expect(within(section).queryByRole('table')).toBeNull()
  })
})
