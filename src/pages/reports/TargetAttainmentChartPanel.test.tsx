import type { ReactNode } from 'react'
import { render, screen, within } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import TargetAttainmentPage from './TargetAttainmentPage'

const mocks = vi.hoisted(() => ({
  useSystemTrustState: vi.fn(),
  useTrustForComponent: vi.fn(),
  useTargetAttainmentSummary: vi.fn(),
  useTargetAttainmentTable: vi.fn(),
}))

vi.mock('@/hooks/useSystemTrustState', () => ({
  useSystemTrustState: mocks.useSystemTrustState,
  useTrustForComponent: mocks.useTrustForComponent,
}))

vi.mock('@/hooks/useTargetAttainment', () => ({
  useTargetAttainmentSummary: mocks.useTargetAttainmentSummary,
  useTargetAttainmentTable: mocks.useTargetAttainmentTable,
}))

vi.mock('@/components/reports/MetricCard', () => ({
  default: ({ label }: { label: string }) => <div>{label}</div>,
}))

vi.mock('@/components/reports/SkeletonCard', () => ({
  default: () => <div data-testid="skeleton-card" />,
}))

vi.mock('@/components/reports/SystemHealthBar', () => ({
  default: () => <div data-testid="system-health-bar" />,
}))

vi.mock('@/components/reports/TrustStateBadge', () => ({
  default: ({ status, domain, size }: { status: string; domain: string; size: string }) => (
    <span data-testid="trust-state-badge" data-status={status} data-domain={domain} data-size={size} />
  ),
}))

vi.mock('@/components/reports/FreshnessIndicator', () => ({
  default: ({ lastCompletedAt, isStale }: { lastCompletedAt?: string; isStale?: boolean }) => (
    <span
      data-testid="freshness-indicator"
      data-last-completed-at={lastCompletedAt}
      data-is-stale={String(Boolean(isStale))}
    />
  ),
}))

vi.mock('@/components/patterns/ResponsiveCollection', () => ({
  default: () => <div data-testid="responsive-collection" />,
}))

vi.mock('recharts', () => ({
  ResponsiveContainer: ({ children, width, height }: { children: ReactNode; width: string | number; height: number }) => (
    <div data-testid="chart-responsive-container" data-width={String(width)} data-height={String(height)}>{children}</div>
  ),
  BarChart: ({ children, data, layout }: { children: ReactNode; data: unknown; layout: string }) => (
    <div data-testid="bar-chart" data-layout={layout} data-chart-data={JSON.stringify(data)}>{children}</div>
  ),
  Bar: ({ children, dataKey, name, radius, maxBarSize }: { children?: ReactNode; dataKey: string; name: string; radius: number[]; maxBarSize: number }) => (
    <div
      data-testid="bar"
      data-key={dataKey}
      data-name={name}
      data-radius={JSON.stringify(radius)}
      data-max-bar-size={String(maxBarSize)}
    >
      {children}
    </div>
  ),
  XAxis: () => null,
  YAxis: () => null,
  Tooltip: () => null,
  CartesianGrid: () => null,
  ReferenceLine: ({ x, stroke, strokeDasharray, strokeWidth }: { x: number; stroke: string; strokeDasharray: string; strokeWidth: number }) => (
    <div
      data-testid="reference-line"
      data-x={String(x)}
      data-stroke={stroke}
      data-stroke-dasharray={strokeDasharray}
      data-stroke-width={String(strokeWidth)}
    />
  ),
  Cell: ({ fill }: { fill: string }) => <span data-testid="bar-cell" data-fill={fill} />,
}))

const individualRows = [110.4, 100, 95, 85, 79, 50].map((achievementPct, index) => ({
  target_id: `individual-${index + 1}`,
  target_name: `هدف مندوب ${index + 1}`,
  type_code: 'sales',
  rep_name: `مندوب ${index + 1}`,
  branch_name: 'فرع طنطا',
  target_value: 100_000,
  achieved_value: achievementPct * 1_000,
  achievement_pct: achievementPct,
  trend: 'on_track',
  scope: 'individual',
}))

const branchOnlyRow = {
  ...individualRows[0],
  target_id: 'branch-only',
  rep_name: 'مندوب فرع',
  scope: 'branch',
}

describe('Target Attainment individual-rep chart panel convergence', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.useSystemTrustState.mockReturnValue({
      data: [{ component_name: 'snapshot_target_attainment' }],
      isLoading: false,
      error: null,
    })
    mocks.useTrustForComponent.mockReturnValue({
      status: 'OK',
      last_completed_at: '2026-09-23T02:00:00Z',
      is_stale: false,
    })
    mocks.useTargetAttainmentSummary.mockReturnValue({
      data: {
        achieved: 2,
        on_track: 2,
        behind: 1,
        at_risk: 1,
        total_targets: 6,
        avg_achievement_pct: 87,
      },
      isLoading: false,
    })
    mocks.useTargetAttainmentTable.mockReturnValue({ data: individualRows, isLoading: false })
  })

  it('uses the shared ChartPanel while preserving title, description, trust/freshness inputs and chart/reference semantics', () => {
    render(<TargetAttainmentPage />)

    const title = screen.getByRole('heading', { name: 'نسبة الإنجاز — المندوبون الفرديون', level: 2 })
    const panel = title.closest('.ds-chart-panel') as HTMLElement
    expect(panel).not.toBeNull()
    expect(within(panel).getByText('الخط المنقط عند 100% هو الهدف')).toBeTruthy()

    const trust = within(panel).getByTestId('trust-state-badge')
    expect(trust.getAttribute('data-status')).toBe('OK')
    expect(trust.getAttribute('data-domain')).toBe('sales')
    expect(trust.getAttribute('data-size')).toBe('sm')

    const freshness = within(panel).getByTestId('freshness-indicator')
    expect(freshness.getAttribute('data-last-completed-at')).toBe('2026-09-23T02:00:00Z')
    expect(freshness.getAttribute('data-is-stale')).toBe('false')

    const container = within(panel).getByTestId('chart-responsive-container')
    expect(container.getAttribute('data-width')).toBe('100%')
    expect(container.getAttribute('data-height')).toBe('240')

    const chart = within(panel).getByTestId('bar-chart')
    expect(chart.getAttribute('data-layout')).toBe('vertical')
    expect(JSON.parse(chart.getAttribute('data-chart-data') ?? '[]')).toEqual([
      { name: 'مندوب 1', pct: 110 },
      { name: 'مندوب 2', pct: 100 },
      { name: 'مندوب 3', pct: 95 },
      { name: 'مندوب 4', pct: 85 },
      { name: 'مندوب 5', pct: 79 },
      { name: 'مندوب 6', pct: 50 },
    ])

    const referenceLine = within(panel).getByTestId('reference-line')
    expect(referenceLine.getAttribute('data-x')).toBe('100')
    expect(referenceLine.getAttribute('data-stroke')).toBe('var(--color-warning)')
    expect(referenceLine.getAttribute('data-stroke-dasharray')).toBe('4 4')
    expect(referenceLine.getAttribute('data-stroke-width')).toBe('2')

    const bar = within(panel).getByTestId('bar')
    expect(bar.getAttribute('data-key')).toBe('pct')
    expect(bar.getAttribute('data-name')).toBe('الإنجاز%')
    expect(bar.getAttribute('data-radius')).toBe('[0,3,3,0]')
    expect(bar.getAttribute('data-max-bar-size')).toBe('20')
    expect(within(panel).getAllByTestId('bar-cell').map(cell => cell.getAttribute('data-fill'))).toEqual([
      '#10b981',
      '#10b981',
      '#f59e0b',
      '#f59e0b',
      '#ef4444',
      '#ef4444',
    ])
  })

  it('keeps the chart panel absent when there is no individual-rep chart data', () => {
    mocks.useTargetAttainmentTable.mockReturnValue({ data: [branchOnlyRow], isLoading: false })

    render(<TargetAttainmentPage />)

    expect(screen.queryByRole('heading', { name: 'نسبة الإنجاز — المندوبون الفرديون' })).toBeNull()
    expect(document.querySelector('.ds-chart-panel')).toBeNull()
    expect(screen.queryByTestId('bar-chart')).toBeNull()
  })
})
