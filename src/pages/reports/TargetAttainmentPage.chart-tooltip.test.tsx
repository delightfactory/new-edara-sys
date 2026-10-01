import type { ReactNode } from 'react'
import { act, render, screen, within } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import TargetAttainmentPage, { CustomTooltip } from './TargetAttainmentPage'

const mocks = vi.hoisted(() => ({
  useSystemTrustState: vi.fn(),
  useTrustForComponent: vi.fn(),
  useTargetAttainmentSummary: vi.fn(),
  useTargetAttainmentTable: vi.fn(),
  responsiveContainer: vi.fn(),
  barChart: vi.fn(),
  bar: vi.fn(),
  xAxis: vi.fn(),
  yAxis: vi.fn(),
  tooltip: vi.fn(),
  cartesianGrid: vi.fn(),
  referenceLine: vi.fn(),
  cell: vi.fn(),
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
  default: () => <span data-testid="trust-state-badge" />,
}))

vi.mock('@/components/reports/FreshnessIndicator', () => ({
  default: () => <span data-testid="freshness-indicator" />,
}))

vi.mock('@/components/patterns/ResponsiveCollection', () => ({
  default: () => <div data-testid="responsive-collection" />,
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
  Bar: ({ children, ...props }: { children?: ReactNode } & Record<string, unknown>) => {
    mocks.bar(props)
    return <div data-testid="bar">{children}</div>
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
  ReferenceLine: (props: Record<string, unknown>) => {
    mocks.referenceLine(props)
    return null
  },
  Cell: (props: Record<string, unknown>) => {
    mocks.cell(props)
    return null
  },
}))

const longRepName = 'اسم مندوب عربي طويل جداً للتحقق من احتواء النص داخل أداة الرسم بدون إنشاء معالجة خاصة بالصفحة'

const chartRows = [
  { target_id: '1', target_name: 'هدف 1', type_code: 'sales', rep_name: longRepName, branch_name: 'طنطا', target_value: 100, achieved_value: 105, achievement_pct: 104.6, trend: 'exceeded', scope: 'individual' },
  { target_id: '2', target_name: 'هدف 2', type_code: 'sales', rep_name: 'مندوب 2', branch_name: 'طنطا', target_value: 100, achieved_value: 81, achievement_pct: 80.6, trend: 'on_track', scope: 'individual' },
  { target_id: '3', target_name: 'هدف 3', type_code: 'sales', rep_name: 'مندوب 3', branch_name: 'طنطا', target_value: 100, achieved_value: 79, achievement_pct: 79.4, trend: 'behind', scope: 'individual' },
  { target_id: '4', target_name: 'هدف 4', type_code: 'sales', rep_name: 'مندوب 4', branch_name: 'طنطا', target_value: 100, achieved_value: 100, achievement_pct: 100, trend: 'achieved', scope: 'individual' },
  { target_id: '5', target_name: 'هدف 5', type_code: 'sales', rep_name: 'مندوب 5', branch_name: 'طنطا', target_value: 100, achieved_value: 80, achievement_pct: 80, trend: 'on_track', scope: 'individual' },
  { target_id: '6', target_name: 'هدف 6', type_code: 'sales', rep_name: 'مندوب 6', branch_name: 'طنطا', target_value: 100, achieved_value: 0, achievement_pct: null, trend: 'behind', scope: 'individual' },
  { target_id: '7', target_name: 'هدف فرع', type_code: 'sales', rep_name: 'مندوب فرع', branch_name: 'المحلة', target_value: 100, achieved_value: 95, achievement_pct: 95, trend: 'on_track', scope: 'branch' },
  { target_id: '8', target_name: 'هدف بلا مندوب', type_code: 'sales', rep_name: null, branch_name: 'طنطا', target_value: 100, achieved_value: 90, achievement_pct: 90, trend: 'on_track', scope: 'individual' },
]

function setViewport(width: number) {
  Object.defineProperty(window, 'innerWidth', { configurable: true, writable: true, value: width })
  act(() => window.dispatchEvent(new Event('resize')))
}

function setDefaultMocks() {
  mocks.useSystemTrustState.mockReturnValue({ data: [], isLoading: false, error: null })
  mocks.useTrustForComponent.mockReturnValue({
    status: 'OK',
    last_completed_at: '2026-09-21T00:00:00Z',
    is_stale: false,
  })
  mocks.useTargetAttainmentSummary.mockReturnValue({
    data: { achieved: 2, on_track: 2, behind: 2, at_risk: 0, total_targets: 8, avg_achievement_pct: 74 },
    isLoading: false,
  })
  mocks.useTargetAttainmentTable.mockReturnValue({ data: chartRows, isLoading: false })
}

function getChartPanel() {
  return screen.getByRole('heading', { level: 2, name: 'نسبة الإنجاز — المندوبون الفرديون' }).closest('.ds-chart-panel') as HTMLElement
}

describe('Target Attainment shared chart tooltip adoption', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    setViewport(1440)
    setDefaultMocks()
  })

  it('keeps inactive and empty-payload adapter guards', () => {
    const view = render(<CustomTooltip active={false} label="مندوب اختباري" payload={[{ value: 105 }]} />)
    expect(view.container.firstChild).toBeNull()

    view.rerender(<CustomTooltip active label="مندوب اختباري" payload={[]} />)
    expect(view.container.firstChild).toBeNull()
  })

  it('uses shared RTL passive anatomy at Mobile, Tablet and Desktop while preserving caller-owned percentage semantics', () => {
    for (const width of [390, 900, 1440]) {
      setViewport(width)
      const view = render(<CustomTooltip active label={longRepName} payload={[{ value: 105 }]} />)
      const tooltip = view.container.querySelector('.ds-chart-tooltip') as HTMLElement
      const row = tooltip.querySelector('.ds-chart-tooltip__row') as HTMLElement
      const value = row.querySelector('.ds-chart-tooltip__value') as HTMLElement

      expect(tooltip.getAttribute('dir')).toBe('rtl')
      expect(tooltip.querySelector('.ds-chart-tooltip__label')?.textContent).toBe(longRepName)
      expect(row.querySelector('.ds-chart-tooltip__item-label')?.textContent).toBe('الإنجاز')
      expect(row.style.color).toBe('rgb(16, 185, 129)')
      expect(value.textContent).toBe('105%')
      expect(value.getAttribute('dir')).toBe('ltr')
      expect(tooltip.querySelector('button, a, input, select, textarea')).toBeNull()
      expect(tooltip.getAttribute('aria-live')).toBeNull()
      expect(tooltip.getAttribute('role')).toBeNull()

      view.unmount()
    }
  })

  it('preserves individual-only filtering, rounded mapping, dynamic geometry, axes, reference line, bar contract and threshold colors', () => {
    render(<TargetAttainmentPage />)

    const panel = getChartPanel()
    expect(within(panel).getByText('الخط المنقط عند 100% هو الهدف')).toBeTruthy()
    expect(within(panel).getByTestId('trust-state-badge')).toBeTruthy()
    expect(within(panel).getByTestId('freshness-indicator')).toBeTruthy()

    expect(mocks.responsiveContainer.mock.calls[0][0]).toMatchObject({ width: '100%', height: 240 })
    expect(mocks.barChart.mock.calls[0][0]).toMatchObject({
      layout: 'vertical',
      margin: { top: 4, left: 10, right: 40, bottom: 0 },
      data: [
        { name: longRepName, pct: 105 },
        { name: 'مندوب 2', pct: 81 },
        { name: 'مندوب 3', pct: 79 },
        { name: 'مندوب 4', pct: 100 },
        { name: 'مندوب 5', pct: 80 },
        { name: 'مندوب 6', pct: 0 },
      ],
    })

    expect(mocks.cartesianGrid.mock.calls[0][0]).toMatchObject({
      strokeDasharray: '3 3',
      stroke: 'var(--border-primary)',
      horizontal: false,
    })
    const xAxis = mocks.xAxis.mock.calls[0][0]
    expect(xAxis).toMatchObject({ type: 'number', tickLine: false, axisLine: false, domain: [0, 'dataMax + 10'] })
    expect(xAxis.tickFormatter(81)).toBe('81%')
    expect(mocks.yAxis.mock.calls[0][0]).toMatchObject({
      type: 'category',
      dataKey: 'name',
      width: 120,
      tickLine: false,
      axisLine: false,
    })
    expect(mocks.referenceLine.mock.calls[0][0]).toMatchObject({
      x: 100,
      stroke: 'var(--color-warning)',
      strokeDasharray: '4 4',
      strokeWidth: 2,
    })
    expect(mocks.tooltip.mock.calls[0][0].content).toBeTruthy()
    expect(mocks.bar.mock.calls[0][0]).toMatchObject({
      dataKey: 'pct',
      name: 'الإنجاز%',
      radius: [0, 3, 3, 0],
      maxBarSize: 20,
    })
    expect(mocks.cell.mock.calls.map(call => call[0].fill)).toEqual([
      '#10b981', '#f59e0b', '#ef4444', '#10b981', '#f59e0b', '#ef4444',
    ])
  })

  it('keeps shared tooltip wiring stable across 390, 900 and 1440 widths', () => {
    for (const width of [390, 900, 1440]) {
      setViewport(width)
      const view = render(<TargetAttainmentPage />)

      expect(mocks.tooltip.mock.calls[mocks.tooltip.mock.calls.length - 1][0].content).toBeTruthy()
      expect(mocks.responsiveContainer.mock.calls[mocks.responsiveContainer.mock.calls.length - 1][0]).toMatchObject({
        width: '100%',
        height: 240,
      })
      expect(getChartPanel()).not.toBeNull()

      view.unmount()
    }
  })

  it('keeps the chart absent when chartData is empty', () => {
    mocks.useTargetAttainmentTable.mockReturnValue({
      data: [{ ...chartRows[6] }, { ...chartRows[7] }],
      isLoading: false,
    })
    const view = render(<TargetAttainmentPage />)

    expect(view.container.querySelector('.ds-chart-panel')).toBeNull()
    expect(mocks.tooltip).not.toHaveBeenCalled()
  })

  it('preserves trust and freshness action presence rules', () => {
    mocks.useTrustForComponent.mockReturnValue(undefined)
    render(<TargetAttainmentPage />)

    const panel = getChartPanel()
    expect(within(panel).queryByTestId('trust-state-badge')).toBeNull()
    expect(within(panel).queryByTestId('freshness-indicator')).toBeNull()
  })
})
