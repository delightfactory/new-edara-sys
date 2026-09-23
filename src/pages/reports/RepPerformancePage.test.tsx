import type { ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, render, screen, within } from '@testing-library/react'
import RepPerformancePage from './RepPerformancePage'

const mocks = vi.hoisted(() => ({
  useSystemTrustState: vi.fn(),
  useTrustForComponent: vi.fn(),
  useRepPerformanceSummary: vi.fn(),
  useRepPerformanceTable: vi.fn(),
  metricCard: vi.fn(),
  responsiveContainer: vi.fn(),
  barChart: vi.fn(),
  bar: vi.fn(),
  xAxis: vi.fn(),
  yAxis: vi.fn(),
  tooltip: vi.fn(),
  cartesianGrid: vi.fn(),
}))

vi.mock('@/hooks/useSystemTrustState', () => ({
  useSystemTrustState: mocks.useSystemTrustState,
  useTrustForComponent: mocks.useTrustForComponent,
}))

vi.mock('@/hooks/useRepPerformance', () => ({
  useRepPerformanceSummary: mocks.useRepPerformanceSummary,
  useRepPerformanceTable: mocks.useRepPerformanceTable,
}))

vi.mock('@/components/reports/MetricCard', () => ({
  default: ({ label, value, status, lastCompletedAt, isStale, domain }: {
    label: string
    value: ReactNode
    status: string | null
    lastCompletedAt?: string
    isStale?: boolean
    domain: string
  }) => {
    mocks.metricCard({ label, value, status, lastCompletedAt, isStale, domain })
    return (
      <div
        data-testid="metric-card"
        data-domain={domain}
        data-status={status ?? ''}
        data-last-completed-at={lastCompletedAt ?? ''}
        data-stale={String(Boolean(isStale))}
      >
        <span data-testid="metric-label">{label}</span>
        <span data-testid="metric-value">{value}</span>
      </div>
    )
  },
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

vi.mock('recharts', () => ({
  ResponsiveContainer: ({ children, ...props }: { children: ReactNode } & Record<string, unknown>) => {
    mocks.responsiveContainer(props)
    return <div data-testid="responsive-container">{children}</div>
  },
  BarChart: ({ children, ...props }: { children: ReactNode } & Record<string, unknown>) => {
    mocks.barChart(props)
    return <div data-testid="bar-chart">{children}</div>
  },
  Bar: (props: Record<string, unknown>) => {
    mocks.bar(props)
    return null
  },
  XAxis: (props: Record<string, unknown>) => {
    mocks.xAxis(props)
    return null
  },
  YAxis: (props: Record<string, unknown>) => {
    mocks.yAxis(props)
    return null
  },
  Tooltip: (props: Record<string, unknown>) => {
    mocks.tooltip(props)
    return null
  },
  CartesianGrid: (props: Record<string, unknown>) => {
    mocks.cartesianGrid(props)
    return null
  },
}))

const rows = Array.from({ length: 16 }, (_, index) => ({
  rep_id: `rep-${index + 1}`,
  rank: index + 1,
  rep_name: `مندوب ${index + 1}`,
  branch_name: `فرع ${index + 1}`,
  net_revenue: 10_000 - (index * 100),
  returns_value: 500 + (index * 10),
  return_rate_pct: index,
  distinct_customers: 20 + index,
}))

const longRepName = 'مندوب مبيعات باسم عربي طويل جداً لاختبار التفاف هوية المندوب داخل بطاقة الأداء بدون تجاوز أفقي'
const longBranchName = 'فرع طنطا الرئيسي باسم عربي طويل جداً لاختبار التفاف سياق الفرع داخل البطاقة'
const detailRows = [
  {
    rep_id: 'detail-1',
    rank: 1,
    rep_name: longRepName,
    branch_name: longBranchName,
    net_revenue: 12_500,
    returns_value: 0,
    return_rate_pct: 4,
    distinct_customers: 21,
  },
  {
    rep_id: 'detail-2',
    rank: 2,
    rep_name: 'مندوب متوسط الأداء',
    branch_name: 'فرع المحلة',
    net_revenue: 9_500,
    returns_value: 250,
    return_rate_pct: 7,
    distinct_customers: 14,
  },
  {
    rep_id: 'detail-3',
    rank: 3,
    rep_name: 'مندوب آخر الترتيب',
    branch_name: 'فرع كفر الزيات',
    net_revenue: 7_000,
    returns_value: 500,
    return_rate_pct: 12,
    distinct_customers: 9,
  },
]

function getChartPanel() {
  const heading = screen.getByRole('heading', { level: 2, name: 'مقارنة المندوبين — أعلى 15' })
  return heading.closest('.ds-chart-panel') as HTMLElement
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
  return screen.getByText('تفصيل الأداء — جميع المندوبين').parentElement as HTMLElement
}

describe('Rep Performance summary MetricGrid convergence', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.useSystemTrustState.mockReturnValue({ data: [], isLoading: false, error: null })
    mocks.useTrustForComponent.mockReturnValue({ status: 'OK', last_completed_at: '2026-09-22T00:00:00Z', is_stale: false })
    mocks.useRepPerformanceSummary.mockReturnValue({
      data: {
        total_revenue: 100_000,
        total_reps: 16,
        avg_revenue_per_rep: 6_250,
        total_returns_value: 8_000,
      },
      isLoading: false,
    })
    mocks.useRepPerformanceTable.mockReturnValue({ data: rows, isLoading: false })
  })

  it('uses the shared four-column MetricGrid with exact KPI order, values, and caller-owned trust/domain wiring', () => {
    render(<RepPerformancePage />)

    const grid = document.querySelector('[data-metric-grid]') as HTMLElement
    expect(grid).not.toBeNull()
    expect(grid.getAttribute('data-columns')).toBe('4')
    expect(grid.classList.contains('ds-metric-grid--cols-4')).toBe(true)
    expect(document.querySelector('.report-grid')).toBeNull()

    const cards = within(grid).getAllByTestId('metric-card')
    expect(cards).toHaveLength(4)
    expect(cards.map(card => within(card).getByTestId('metric-label').textContent)).toEqual([
      'إجمالى الإيراد الصافى',
      'مندوبون نشطون',
      'متوسط إيراد المندوب',
      'إجمالى المرتجعات',
    ])
    expect(cards.map(card => within(card).getByTestId('metric-value').textContent)).toEqual([
      '100,000 ج.م',
      '16',
      '6,250 ج.م',
      '8,000 ج.م',
    ])
    cards.forEach(card => {
      expect(card.getAttribute('data-domain')).toBe('sales')
      expect(card.getAttribute('data-status')).toBe('OK')
      expect(card.getAttribute('data-last-completed-at')).toBe('2026-09-22T00:00:00Z')
      expect(card.getAttribute('data-stale')).toBe('false')
    })
    expect(screen.getByTestId('system-health-bar')).toBeTruthy()
    expect(screen.getByTestId('report-filter-bar')).toBeTruthy()
  })

  it('preserves the combined summaryLoading/tableLoading gate with exactly four 160px summary skeletons', () => {
    mocks.useRepPerformanceSummary.mockReturnValue({ data: null, isLoading: true })
    const { rerender } = render(<RepPerformancePage />)

    let grid = document.querySelector('[data-metric-grid]') as HTMLElement
    let skeletons = within(grid).getAllByTestId('skeleton-card')
    expect(skeletons).toHaveLength(4)
    skeletons.forEach(skeleton => expect(skeleton.getAttribute('data-height')).toBe('160'))
    expect(within(grid).queryByTestId('metric-card')).toBeNull()

    mocks.useRepPerformanceSummary.mockReturnValue({
      data: {
        total_revenue: 100_000,
        total_reps: 16,
        avg_revenue_per_rep: 6_250,
        total_returns_value: 8_000,
      },
      isLoading: false,
    })
    mocks.useRepPerformanceTable.mockReturnValue({ data: rows, isLoading: true })
    rerender(<RepPerformancePage />)

    grid = document.querySelector('[data-metric-grid]') as HTMLElement
    skeletons = within(grid).getAllByTestId('skeleton-card')
    expect(skeletons).toHaveLength(4)
    skeletons.forEach(skeleton => expect(skeleton.getAttribute('data-height')).toBe('160'))
    expect(within(grid).queryByTestId('metric-card')).toBeNull()
  })
})

describe('Rep Performance comparison ChartPanel convergence', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.useSystemTrustState.mockReturnValue({ data: [], isLoading: false, error: null })
    mocks.useTrustForComponent.mockReturnValue({ status: 'OK', last_completed_at: '2026-09-20T00:00:00Z', is_stale: false })
    mocks.useRepPerformanceSummary.mockReturnValue({
      data: {
        total_revenue: 100_000,
        total_reps: 16,
        avg_revenue_per_rep: 6_250,
        total_returns_value: 8_000,
      },
      isLoading: false,
    })
    mocks.useRepPerformanceTable.mockReturnValue({ data: rows, isLoading: false })
  })

  it('uses the shared ChartPanel with h1-to-h2 hierarchy, exact copy, and existing trust actions', () => {
    render(<RepPerformancePage />)

    expect(screen.getByRole('heading', { level: 1, name: 'أداء المندوبين' })).toBeTruthy()
    const panel = getChartPanel()
    expect(document.querySelectorAll('.ds-chart-panel')).toHaveLength(1)
    expect(within(panel).getByText('صافى الإيراد مقابل المرتجعات')).toBeTruthy()
    expect(within(panel).getByTestId('trust-state-badge')).toBeTruthy()
    expect(within(panel).getByTestId('freshness-indicator')).toBeTruthy()
  })

  it('preserves the salesTrust action presence rule when trust is unavailable', () => {
    mocks.useTrustForComponent.mockReturnValue(null)
    render(<RepPerformancePage />)

    const panel = getChartPanel()
    expect(within(panel).queryByTestId('trust-state-badge')).toBeNull()
    expect(within(panel).queryByTestId('freshness-indicator')).toBeNull()
  })

  it('preserves the exact 300px chart loading state and converges the empty branch onto shared StatePanel', () => {
    mocks.useRepPerformanceTable.mockReturnValue({ data: rows, isLoading: true })
    const { rerender } = render(<RepPerformancePage />)

    let panel = getChartPanel()
    expect(within(panel).getByTestId('skeleton-card').getAttribute('data-height')).toBe('300')
    expect(panel.querySelector('.ds-state-panel')).toBeNull()
    expect(within(panel).queryByTestId('bar-chart')).toBeNull()

    mocks.useRepPerformanceTable.mockReturnValue({ data: [], isLoading: false })
    rerender(<RepPerformancePage />)

    panel = getChartPanel()
    const state = panel.querySelector('.ds-state-panel[data-state-kind="empty"]') as HTMLElement
    expect(state).not.toBeNull()
    expect(state.classList.contains('ds-state-panel--compact')).toBe(true)
    expect(within(state).getByText('لا توجد بيانات فى النطاق الزمني المحدد')).toBeTruthy()
    expect(state.parentElement?.style.height).toBe('300px')
    expect(state.querySelector('.ds-state-panel__action')).toBeNull()
    expect(state.getAttribute('aria-live')).toBeNull()
    expect(within(panel).queryByTestId('bar-chart')).toBeNull()
  })

  it('preserves top-15 order/mapping and the dynamic responsive chart height', () => {
    render(<RepPerformancePage />)

    expect(mocks.responsiveContainer).toHaveBeenCalledTimes(1)
    expect(mocks.responsiveContainer.mock.calls[0][0]).toMatchObject({ width: '100%', height: 600 })

    const chartProps = mocks.barChart.mock.calls[0][0]
    expect(chartProps.layout).toBe('vertical')
    expect(chartProps.margin).toEqual({ top: 4, left: 10, right: 20, bottom: 0 })
    expect(chartProps.data).toHaveLength(15)
    expect(chartProps.data[0]).toEqual({
      name: rows[0].rep_name,
      revenue: rows[0].net_revenue,
      returns: rows[0].returns_value,
    })
    expect(chartProps.data[14]).toEqual({
      name: rows[14].rep_name,
      revenue: rows[14].net_revenue,
      returns: rows[14].returns_value,
    })
    expect(chartProps.data.find((row: { name: string }) => row.name === rows[15].rep_name)).toBeUndefined()
  })

  it('preserves grid, axes, tooltip and both revenue/returns series contracts', () => {
    render(<RepPerformancePage />)

    expect(mocks.cartesianGrid.mock.calls[0][0]).toMatchObject({
      strokeDasharray: '3 3',
      stroke: 'var(--border-primary)',
      horizontal: false,
    })
    expect(mocks.xAxis.mock.calls[0][0]).toMatchObject({
      type: 'number',
      tickLine: false,
      axisLine: false,
    })
    expect(mocks.xAxis.mock.calls[0][0].tickFormatter(1234)).toBe('1,234')
    expect(mocks.yAxis.mock.calls[0][0]).toMatchObject({
      type: 'category',
      dataKey: 'name',
      width: 120,
      tickLine: false,
      axisLine: false,
    })
    expect(mocks.tooltip.mock.calls[0][0].content).toBeTruthy()
    expect(mocks.bar.mock.calls).toHaveLength(2)
    expect(mocks.bar.mock.calls[0][0]).toMatchObject({
      dataKey: 'revenue',
      name: 'الإيراد الصافى',
      fill: '#2563eb',
      radius: [0, 3, 3, 0],
      maxBarSize: 20,
    })
    expect(mocks.bar.mock.calls[1][0]).toMatchObject({
      dataKey: 'returns',
      name: 'المرتجعات',
      fill: '#dc2626',
      radius: [0, 3, 3, 0],
      maxBarSize: 10,
    })
  })
})

describe('Rep Performance responsive detail collection', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    setViewport(1440)
    mocks.useSystemTrustState.mockReturnValue({ data: [], isLoading: false, error: null })
    mocks.useTrustForComponent.mockReturnValue({ status: 'OK', last_completed_at: '2026-09-21T00:00:00Z', is_stale: false })
    mocks.useRepPerformanceSummary.mockReturnValue({
      data: {
        total_revenue: 29_000,
        total_reps: 3,
        avg_revenue_per_rep: 9_667,
        total_returns_value: 750,
      },
      isLoading: false,
    })
    mocks.useRepPerformanceTable.mockReturnValue({ data: detailRows, isLoading: false })
  })

  it('preserves the dense Desktop table, seven facts/order, semantic headers, and exact ranking/return tones', () => {
    render(<RepPerformancePage />)

    const section = getDetailSection()
    const table = within(section).getByRole('table')
    const headers = within(table).getAllByRole('columnheader')
    expect(headers.map(header => header.textContent)).toEqual([
      '#',
      'المندوب',
      'الفرع',
      'صافى الإيراد',
      'المرتجعات',
      'نسبة المرتجع',
      'عملاء',
    ])
    headers.forEach(header => expect(header.getAttribute('scope')).toBe('col'))
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()

    const dataRows = within(table).getAllByRole('row').slice(1)
    expect(dataRows).toHaveLength(3)
    expect(within(dataRows[0]).getAllByRole('cell').map(cell => cell.textContent)).toEqual([
      '1',
      longRepName,
      longBranchName,
      '12,500 ج.م',
      '0 ج.م',
      '4%',
      '21',
    ])
    expect(within(dataRows[1]).getByText('مندوب متوسط الأداء')).toBeTruthy()
    expect(within(dataRows[2]).getByText('مندوب آخر الترتيب')).toBeTruthy()

    expect(within(table).getByText(longRepName).style.color).toBe('var(--color-success)')
    expect(within(table).getByText('مندوب آخر الترتيب').style.color).toBe('var(--color-danger)')
    expect(within(table).getByText('0 ج.م').style.color).toBe('var(--text-muted)')
    expect(within(table).getByText('250 ج.م').style.color).toBe('var(--color-danger)')
    expect(within(table).getByText('4%').style.color).toBe('var(--color-success)')
    expect(within(table).getByText('7%').style.color).toBe('var(--color-warning)')
    expect(within(table).getByText('12%').style.color).toBe('var(--color-danger)')
    expect(within(dataRows[0]).getByText('12,500 ج.م').style.direction).toBe('ltr')
  })

  it('mounts only one-column Mobile cards with complete row truth, safe Arabic wrapping, LTR values, and preserved tones', () => {
    setViewport(390)
    render(<RepPerformancePage />)

    const section = getDetailSection()
    expect(within(section).queryByRole('table')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--mobile')).not.toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--tablet')).toBeNull()
    expect(section.querySelector('.ds-key-value-list--cols-1')).not.toBeNull()

    const firstIdentity = within(section).getByText(longRepName)
    const firstCard = firstIdentity.closest('.ds-card') as HTMLElement
    const firstRank = within(firstCard).getByText('#1')
    const firstRevenue = within(firstCard).getByText('12,500 ج.م')
    expect(firstIdentity.style.overflowWrap).toBe('anywhere')
    expect(firstIdentity.style.color).toBe('var(--color-success)')
    expect(within(firstCard).getByText(longBranchName).style.overflowWrap).toBe('anywhere')
    expect(firstRank.getAttribute('dir')).toBe('ltr')
    expect(firstRank.style.color).toBe('var(--color-success)')
    expect(firstRevenue.getAttribute('dir')).toBe('ltr')
    expect(firstRevenue.style.color).toBe('')
    expect(within(firstCard).getByText('0 ج.م').getAttribute('dir')).toBe('ltr')
    expect(within(firstCard).getByText('4%').getAttribute('dir')).toBe('ltr')
    expect(within(firstCard).getByText('21').getAttribute('dir')).toBe('ltr')
    expect(within(firstCard).getByText('0 ج.م').style.color).toBe('var(--text-muted)')
    expect(within(firstCard).getByText('4%').style.color).toBe('var(--color-success)')

    const warningCard = within(section).getByText('مندوب متوسط الأداء').closest('.ds-card') as HTMLElement
    expect(within(warningCard).getByText('250 ج.م').style.color).toBe('var(--color-danger)')
    expect(within(warningCard).getByText('7%').style.color).toBe('var(--color-warning)')

    const lastIdentity = within(section).getByText('مندوب آخر الترتيب')
    const lastCard = lastIdentity.closest('.ds-card') as HTMLElement
    const lastRank = within(lastCard).getByText('#3')
    const lastRevenue = within(lastCard).getByText('7,000 ج.م')
    expect(lastIdentity.style.color).toBe('var(--color-danger)')
    expect(lastRank.style.color).toBe('var(--color-danger)')
    expect(lastRevenue.getAttribute('dir')).toBe('ltr')
    expect(lastRevenue.style.color).toBe('')
    expect(within(lastCard).getByText('12%').style.color).toBe('var(--color-danger)')
  })

  it('uses deliberate two-column Tablet cards while keeping all seven facts and no Desktop/Mobile renderer', () => {
    setViewport(900)
    render(<RepPerformancePage />)

    const section = getDetailSection()
    expect(within(section).queryByRole('table')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--tablet')).not.toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--mobile')).toBeNull()
    expect(section.querySelector('.ds-key-value-list--cols-2')).not.toBeNull()

    const firstCard = within(section).getByText(longRepName).closest('.ds-card') as HTMLElement
    ;[longBranchName, '#1', '12,500 ج.م', '0 ج.م', '4%', '21'].forEach(value => {
      expect(within(firstCard).getByText(value)).toBeTruthy()
    })
  })

  it('preserves five-row loading precedence and uses one passive shared empty renderer across device modes', () => {
    setViewport(390)
    mocks.useRepPerformanceTable.mockReturnValue({ data: detailRows, isLoading: true })
    const { rerender } = render(<RepPerformancePage />)

    let section = getDetailSection()
    const loadingCollection = section.querySelector('[data-collection-state="loading"]') as HTMLElement
    expect(loadingCollection).not.toBeNull()
    const loadingSkeletons = within(loadingCollection).getAllByTestId('skeleton-card')
    expect(loadingSkeletons).toHaveLength(5)
    loadingSkeletons.forEach(skeleton => expect(skeleton.getAttribute('data-height')).toBe('44'))
    expect(section.querySelector('.ds-state-panel')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
    expect(within(section).queryByRole('table')).toBeNull()

    mocks.useRepPerformanceTable.mockReturnValue({ data: [], isLoading: false })
    rerender(<RepPerformancePage />)

    ;[390, 900, 1440].forEach(width => {
      setViewport(width)
      section = getDetailSection()
      const emptyCollection = section.querySelector('[data-collection-state="empty"]') as HTMLElement
      expect(emptyCollection).not.toBeNull()
      const states = emptyCollection.querySelectorAll('.ds-state-panel[data-state-kind="empty"]')
      expect(states).toHaveLength(1)
      const state = states[0] as HTMLElement
      expect(within(state).getByText('لا توجد بيانات فى النطاق الزمني المحدد')).toBeTruthy()
      expect(state.classList.contains('ds-state-panel--compact')).toBe(false)
      expect(state.querySelector('.ds-state-panel__action')).toBeNull()
      expect(state.getAttribute('aria-live')).toBeNull()
      expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
      expect(within(section).queryByRole('table')).toBeNull()
    })
  })
})
