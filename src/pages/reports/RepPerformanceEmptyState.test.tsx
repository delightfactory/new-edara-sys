import { type ReactNode } from 'react'
import { act, render, screen, within } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import RepPerformancePage from './RepPerformancePage'

const mocks = vi.hoisted(() => ({
  useSystemTrustState: vi.fn(),
  useTrustForComponent: vi.fn(),
  useRepPerformanceSummary: vi.fn(),
  useRepPerformanceTable: vi.fn(),
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
  default: () => <div data-testid="metric-card" />,
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
  ResponsiveContainer: ({ children }: { children: ReactNode }) => <div data-testid="responsive-container">{children}</div>,
  BarChart: ({ children }: { children: ReactNode }) => <div data-testid="bar-chart">{children}</div>,
  Bar: () => null,
  XAxis: () => null,
  YAxis: () => null,
  Tooltip: () => null,
  CartesianGrid: () => null,
}))

const detailRows = [{
  rep_id: 'rep-1',
  rank: 1,
  rep_name: 'مندوب 1',
  branch_name: 'فرع طنطا',
  net_revenue: 10_000,
  returns_value: 500,
  return_rate_pct: 5,
  distinct_customers: 20,
}]

function setViewport(width: number) {
  Object.defineProperty(window, 'innerWidth', {
    configurable: true,
    writable: true,
    value: width,
  })
  act(() => window.dispatchEvent(new Event('resize')))
}

function getChartPanel() {
  const heading = screen.getByRole('heading', { level: 2, name: 'مقارنة المندوبين — أعلى 15' })
  return heading.closest('.ds-chart-panel') as HTMLElement
}

function getDetailSection() {
  return screen.getByText('تفصيل الأداء — جميع المندوبين').parentElement as HTMLElement
}

describe('Rep Performance shared empty-state convergence', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    setViewport(1440)
    mocks.useSystemTrustState.mockReturnValue({ data: [], isLoading: false, error: null })
    mocks.useTrustForComponent.mockReturnValue({
      status: 'OK',
      last_completed_at: '2026-09-23T00:00:00Z',
      is_stale: false,
    })
    mocks.useRepPerformanceSummary.mockReturnValue({
      data: {
        total_revenue: 10_000,
        total_reps: 1,
        avg_revenue_per_rep: 10_000,
        total_returns_value: 500,
      },
      isLoading: false,
    })
    mocks.useRepPerformanceTable.mockReturnValue({ data: detailRows, isLoading: false })
  })

  it('keeps chart and detail loading precedence before shared empty-state evaluation', () => {
    mocks.useRepPerformanceTable.mockReturnValue({ data: detailRows, isLoading: true })
    render(<RepPerformancePage />)

    const panel = getChartPanel()
    expect(within(panel).getByTestId('skeleton-card').getAttribute('data-height')).toBe('300')
    expect(panel.querySelector('.ds-state-panel')).toBeNull()
    expect(within(panel).queryByTestId('bar-chart')).toBeNull()

    const detail = getDetailSection()
    const loading = detail.querySelector('[data-collection-state="loading"]') as HTMLElement
    expect(loading).not.toBeNull()
    const skeletons = within(loading).getAllByTestId('skeleton-card')
    expect(skeletons).toHaveLength(5)
    skeletons.forEach(skeleton => expect(skeleton.getAttribute('data-height')).toBe('44'))
    expect(detail.querySelector('.ds-state-panel')).toBeNull()
    expect(detail.querySelector('.ds-responsive-card-grid')).toBeNull()
    expect(within(detail).queryByRole('table')).toBeNull()
  })

  it('uses compact shared StatePanel for the chart while preserving exact copy and 300px footprint', () => {
    mocks.useRepPerformanceTable.mockReturnValue({ data: [], isLoading: false })
    render(<RepPerformancePage />)

    const panel = getChartPanel()
    const state = panel.querySelector('.ds-state-panel[data-state-kind="empty"]') as HTMLElement
    expect(state).not.toBeNull()
    expect(state.classList.contains('ds-state-panel--compact')).toBe(true)
    expect(within(state).getByText('لا توجد بيانات فى النطاق الزمني المحدد')).toBeTruthy()
    expect(state.parentElement?.style.height).toBe('300px')
    expect(state.querySelector('.ds-state-panel__action')).toBeNull()
    expect(state.getAttribute('aria-live')).toBeNull()
    expect(within(panel).queryByTestId('bar-chart')).toBeNull()
  })

  it.each([390, 900, 1440])('uses one passive shared detail empty renderer at %ipx without mounting a ready renderer', width => {
    setViewport(width)
    mocks.useRepPerformanceTable.mockReturnValue({ data: [], isLoading: false })
    render(<RepPerformancePage />)

    const detail = getDetailSection()
    const collectionEmpty = detail.querySelector('[data-collection-state="empty"]') as HTMLElement
    expect(collectionEmpty).not.toBeNull()

    const states = collectionEmpty.querySelectorAll('.ds-state-panel[data-state-kind="empty"]')
    expect(states).toHaveLength(1)
    const state = states[0] as HTMLElement
    expect(within(state).getByText('لا توجد بيانات فى النطاق الزمني المحدد')).toBeTruthy()
    expect(state.classList.contains('ds-state-panel--compact')).toBe(false)
    expect(state.querySelector('.ds-state-panel__action')).toBeNull()
    expect(state.getAttribute('aria-live')).toBeNull()
    expect(detail.querySelector('.ds-responsive-card-grid')).toBeNull()
    expect(within(detail).queryByRole('table')).toBeNull()
  })
})
