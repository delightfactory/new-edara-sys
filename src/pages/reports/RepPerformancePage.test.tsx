import type { ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import RepPerformancePage from './RepPerformancePage'

const mocks = vi.hoisted(() => ({
  useSystemTrustState: vi.fn(),
  useTrustForComponent: vi.fn(),
  useRepPerformanceSummary: vi.fn(),
  useRepPerformanceTable: vi.fn(),
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

function getChartPanel() {
  const heading = screen.getByRole('heading', { level: 2, name: 'مقارنة المندوبين — أعلى 15' })
  return heading.closest('.ds-chart-panel') as HTMLElement
}

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

  it('preserves the exact 300px chart loading and empty states', () => {
    mocks.useRepPerformanceTable.mockReturnValue({ data: rows, isLoading: true })
    const { rerender } = render(<RepPerformancePage />)

    let panel = getChartPanel()
    expect(within(panel).getByTestId('skeleton-card').getAttribute('data-height')).toBe('300')
    expect(within(panel).queryByTestId('bar-chart')).toBeNull()

    mocks.useRepPerformanceTable.mockReturnValue({ data: [], isLoading: false })
    rerender(<RepPerformancePage />)

    panel = getChartPanel()
    const empty = within(panel).getByText('لا توجد بيانات فى النطاق الزمني المحدد')
    expect(empty.style.height).toBe('300px')
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
