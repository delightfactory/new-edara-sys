import type { ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, render, screen, within } from '@testing-library/react'
import ProductPerformancePage from './ProductPerformancePage'

const mocks = vi.hoisted(() => ({
  useSystemTrustState: vi.fn(),
  useTrustForComponent: vi.fn(),
  useProductPerformanceSummary: vi.fn(),
  useProductPerformanceTable: vi.fn(),
  rpc: vi.fn(),
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

vi.mock('@/hooks/useProductPerformance', () => ({
  useProductPerformanceSummary: mocks.useProductPerformanceSummary,
  useProductPerformanceTable: mocks.useProductPerformanceTable,
}))

vi.mock('@/lib/supabase/client', () => ({
  supabase: { rpc: mocks.rpc },
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

const rows = [
  {
    product_id: 'product-1',
    product_name: 'منتج طويل للاختبار بدون قص النص الأساسي',
    category_name: 'تصنيف تجريبي طويل',
    net_revenue: 1234,
    net_qty: 12,
    return_rate_pct: 12,
    distinct_customers: 7,
    revenue_share_pct: 40,
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

function getDetailSection() {
  return screen.getByText('تفاصيل المنتجات — أعلى 50 حسب الإيراد').parentElement as HTMLElement
}

function getChartPanel() {
  const heading = screen.getByRole('heading', { level: 2, name: 'أعلى 15 منتجاً بالإيراد' })
  return heading.closest('.ds-chart-panel') as HTMLElement
}

function getMetricGrid() {
  return document.querySelector('[data-metric-grid]') as HTMLElement
}

describe('Product Performance responsive detail collection', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.rpc.mockReturnValue({ then: () => undefined })
    mocks.useSystemTrustState.mockReturnValue({ data: [], isLoading: false, error: null })
    mocks.useTrustForComponent.mockReturnValue({ status: 'OK', last_completed_at: '2026-09-19T00:00:00Z', is_stale: false })
    mocks.useProductPerformanceSummary.mockReturnValue({
      data: { total_revenue: 1234, total_products: 1, top_product_revenue: 1234 },
      isLoading: false,
    })
    mocks.useProductPerformanceTable.mockReturnValue({ data: rows, isLoading: false })
  })

  it('uses the shared four-column MetricGrid for the KPI summary with exact ready-card order', () => {
    render(<ProductPerformancePage />)

    const grid = getMetricGrid()
    expect(document.querySelectorAll('[data-metric-grid]')).toHaveLength(1)
    expect(grid.getAttribute('data-columns')).toBe('4')
    expect(grid.classList.contains('ds-metric-grid--cols-4')).toBe(true)
    expect(within(grid).getAllByTestId('metric-card').map(card => card.textContent)).toEqual([
      'إجمالى الإيراد',
      'منتجات نشطة',
      'أعلى منتج',
      'متوسط نسبة المرتجع',
    ])
    expect(document.querySelector('.report-grid')).toBeNull()
  })

  it('preserves four 160px summary skeletons when either side of the combined loading gate is active', () => {
    mocks.useProductPerformanceSummary.mockReturnValue({ data: undefined, isLoading: true })
    const { rerender } = render(<ProductPerformancePage />)

    let grid = getMetricGrid()
    let skeletons = within(grid).getAllByTestId('skeleton-card')
    expect(skeletons).toHaveLength(4)
    skeletons.forEach(skeleton => expect(skeleton.getAttribute('data-height')).toBe('160'))

    mocks.useProductPerformanceSummary.mockReturnValue({
      data: { total_revenue: 1234, total_products: 1, top_product_revenue: 1234 },
      isLoading: false,
    })
    mocks.useProductPerformanceTable.mockReturnValue({ data: rows, isLoading: true })
    rerender(<ProductPerformancePage />)

    grid = getMetricGrid()
    skeletons = within(grid).getAllByTestId('skeleton-card')
    expect(skeletons).toHaveLength(4)
    skeletons.forEach(skeleton => expect(skeleton.getAttribute('data-height')).toBe('160'))
  })

  it('uses the shared ChartPanel with semantic hierarchy, exact copy, and the existing trust action', () => {
    render(<ProductPerformancePage />)

    const panel = getChartPanel()
    expect(document.querySelectorAll('.ds-chart-panel')).toHaveLength(1)
    expect(within(panel).getByText('مرتب تنازلياً حسب صافى الإيراد')).toBeTruthy()
    expect(within(panel).getByTestId('trust-state-badge')).toBeTruthy()
    expect(within(panel).getByTestId('freshness-indicator')).toBeTruthy()
  })

  it('preserves the salesTrust action presence rule when trust is unavailable', () => {
    mocks.useTrustForComponent.mockReturnValue(null)
    render(<ProductPerformancePage />)

    const panel = getChartPanel()
    expect(within(panel).queryByTestId('trust-state-badge')).toBeNull()
    expect(within(panel).queryByTestId('freshness-indicator')).toBeNull()
  })

  it('preserves the exact 240px chart loading gate and converges empty presentation onto compact StatePanel', () => {
    mocks.useProductPerformanceTable.mockReturnValue({ data: rows, isLoading: true })
    const { rerender } = render(<ProductPerformancePage />)

    let panel = getChartPanel()
    expect(within(panel).getByTestId('skeleton-card').getAttribute('data-height')).toBe('240')
    expect(panel.querySelector('.ds-state-panel')).toBeNull()

    mocks.useProductPerformanceTable.mockReturnValue({ data: [], isLoading: false })
    rerender(<ProductPerformancePage />)

    panel = getChartPanel()
    const emptyCopy = within(panel).getByText('لا توجد بيانات')
    const statePanel = emptyCopy.closest('.ds-state-panel') as HTMLElement
    expect(statePanel).toBeTruthy()
    expect(statePanel.getAttribute('data-state-kind')).toBe('empty')
    expect(statePanel.classList.contains('ds-state-panel--compact')).toBe(true)
    expect(statePanel.parentElement?.style.height).toBe('240px')
    expect(statePanel.querySelector('.ds-state-panel__action')).toBeNull()
  })

  it('preserves the 240px responsive BarChart data, axes, grid, tooltip, and revenue-series contract', () => {
    render(<ProductPerformancePage />)

    expect(mocks.responsiveContainer).toHaveBeenCalledTimes(1)
    expect(mocks.responsiveContainer.mock.calls[0][0]).toMatchObject({ width: '100%', height: 240 })

    const expectedChartData = [{
      name: rows[0].product_name.slice(0, 20) + '…',
      revenue: 1234,
    }]
    expect(mocks.barChart.mock.calls[0][0]).toMatchObject({
      data: expectedChartData,
      margin: { top: 4, left: -10, right: 4, bottom: 60 },
    })
    expect(mocks.cartesianGrid.mock.calls[0][0]).toMatchObject({
      strokeDasharray: '3 3',
      stroke: 'var(--border-primary)',
      vertical: false,
    })
    expect(mocks.xAxis.mock.calls[0][0]).toMatchObject({
      dataKey: 'name',
      tickLine: false,
      axisLine: false,
      angle: -30,
      textAnchor: 'end',
      interval: 0,
    })
    expect(mocks.yAxis.mock.calls[0][0]).toMatchObject({
      tickLine: false,
      axisLine: false,
    })
    expect(mocks.yAxis.mock.calls[0][0].tickFormatter(1234)).toBe('1,234')
    expect(mocks.tooltip.mock.calls[0][0].content).toBeTruthy()
    expect(mocks.bar.mock.calls[0][0]).toMatchObject({
      dataKey: 'revenue',
      name: 'الإيراد',
      fill: '#2563eb',
      radius: [3, 3, 0, 0],
      maxBarSize: 32,
    })
  })

  it('preserves the semantic seven-column desktop table and mounts no detail-card renderer', () => {
    setViewport(1440)
    render(<ProductPerformancePage />)

    const section = getDetailSection()
    const table = within(section).getByRole('table')
    const headers = within(table).getAllByRole('columnheader')

    expect(headers.map(header => header.textContent)).toEqual([
      'المنتج',
      'التصنيف',
      'الإيراد',
      'الكمية',
      'نسبة المرتجع',
      'عملاء',
      'الحصة%',
    ])
    headers.forEach(header => expect(header.getAttribute('scope')).toBe('col'))
    expect(within(table).getByText(rows[0].product_name)).toBeTruthy()
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
  })

  it('mounts only the one-column detail-card composition on Mobile with all seven source fields represented', () => {
    setViewport(390)
    render(<ProductPerformancePage />)

    const section = getDetailSection()
    expect(within(section).queryByRole('table')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--mobile')).not.toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--tablet')).toBeNull()
    expect(within(section).getByText(rows[0].product_name)).toBeTruthy()
    expect(within(section).getByText(rows[0].category_name)).toBeTruthy()

    ;['الإيراد', 'الكمية', 'نسبة المرتجع', 'عملاء', 'الحصة%'].forEach(label => {
      expect(within(section).getByText(label)).toBeTruthy()
    })

    expect(within(section).getByText('1,234 ج.م')).toBeTruthy()
    expect(within(section).getByText('12%').style.color).toBe('var(--color-danger)')
    expect(section.querySelector('.ds-key-value-list--cols-1')).not.toBeNull()
  })

  it('uses the same detail-card anatomy deliberately on Tablet with denser labeled metadata', () => {
    setViewport(900)
    render(<ProductPerformancePage />)

    const section = getDetailSection()
    expect(within(section).queryByRole('table')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--tablet')).not.toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--mobile')).toBeNull()
    expect(section.querySelector('.ds-key-value-list--cols-2')).not.toBeNull()
    expect(within(section).getByText(rows[0].product_name)).toBeTruthy()
  })

  it('preserves five 44px detail loading rows before empty evaluation', () => {
    setViewport(390)
    mocks.useProductPerformanceTable.mockReturnValue({ data: [], isLoading: true })
    render(<ProductPerformancePage />)

    const section = getDetailSection()
    const skeletons = within(section).getAllByTestId('skeleton-card')
    expect(skeletons).toHaveLength(5)
    skeletons.forEach(skeleton => expect(skeleton.getAttribute('data-height')).toBe('44'))
    expect(section.querySelector('.ds-state-panel')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
    expect(within(section).queryByRole('table')).toBeNull()
  })

  it('uses one passive shared detail StatePanel on Mobile, Tablet, and Desktop without mounting ready renderers', () => {
    mocks.useProductPerformanceTable.mockReturnValue({ data: [], isLoading: false })
    render(<ProductPerformancePage />)

    for (const width of [390, 900, 1440]) {
      setViewport(width)
      const section = getDetailSection()
      const collection = section.querySelector('.ds-responsive-collection[data-collection-state="empty"]') as HTMLElement
      const statePanel = collection.querySelector('.ds-state-panel[data-state-kind="empty"]') as HTMLElement

      expect(collection).toBeTruthy()
      expect(statePanel).toBeTruthy()
      expect(within(statePanel).getByText('لا توجد بيانات')).toBeTruthy()
      expect(statePanel.querySelector('.ds-state-panel__action')).toBeNull()
      expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
      expect(within(section).queryByRole('table')).toBeNull()
    }
  })
})
