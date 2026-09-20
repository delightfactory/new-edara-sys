import type { ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import ChurnRiskPage from './ChurnRiskPage'

const mocks = vi.hoisted(() => ({
  useSystemTrustState: vi.fn(),
  useTrustForComponent: vi.fn(),
  useCustomerRiskSummary: vi.fn(),
  useCustomerRiskList: vi.fn(),
}))

vi.mock('@/hooks/useSystemTrustState', () => ({
  useSystemTrustState: mocks.useSystemTrustState,
  useTrustForComponent: mocks.useTrustForComponent,
}))

vi.mock('@/hooks/useCustomerRisk', () => ({
  useCustomerRiskSummary: mocks.useCustomerRiskSummary,
  useCustomerRiskList: mocks.useCustomerRiskList,
}))

vi.mock('@/components/reports/SkeletonCard', () => ({
  default: ({ height }: { height: number }) => <div data-testid="skeleton-card" data-height={height} />,
}))

vi.mock('@/components/reports/SystemHealthBar', () => ({
  default: () => <div data-testid="system-health-bar" />,
}))

vi.mock('@/components/reports/TrustStateBadge', () => ({
  default: ({ status }: { status: string }) => <span data-testid="trust-state-badge">{status}</span>,
}))

vi.mock('@/components/reports/FreshnessIndicator', () => ({
  default: () => <span data-testid="freshness-indicator">freshness</span>,
}))

vi.mock('recharts', () => ({
  ResponsiveContainer: ({ children, width, height }: { children: ReactNode; width: string; height: number }) => (
    <div data-testid="responsive-container" data-width={width} data-height={height}>{children}</div>
  ),
  PieChart: ({ children }: { children: ReactNode }) => <div data-testid="pie-chart">{children}</div>,
  Pie: ({
    children,
    data,
    dataKey,
    nameKey,
    cx,
    cy,
    innerRadius,
    outerRadius,
    paddingAngle,
  }: {
    children: ReactNode
    data: unknown
    dataKey: string
    nameKey: string
    cx: string
    cy: string
    innerRadius: number
    outerRadius: number
    paddingAngle: number
  }) => (
    <div
      data-testid="pie"
      data-data={JSON.stringify(data)}
      data-data-key={dataKey}
      data-name-key={nameKey}
      data-cx={cx}
      data-cy={cy}
      data-inner-radius={innerRadius}
      data-outer-radius={outerRadius}
      data-padding-angle={paddingAngle}
    >
      {children}
    </div>
  ),
  Cell: ({ fill }: { fill: string }) => <span data-testid="pie-cell" data-fill={fill} />,
  Tooltip: ({ formatter }: { formatter?: (value: number) => unknown }) => (
    <span data-testid="tooltip" data-format={JSON.stringify(formatter?.(7))} />
  ),
  Legend: () => <span data-testid="legend" />,
}))

const riskTrust = {
  status: 'OK',
  last_completed_at: '2026-09-20T00:00:00Z',
  is_stale: false,
}

const populatedStats = {
  vip: 5,
  loyal: 4,
  engaged: 3,
  at_risk: 2,
  dormant: 1,
}

describe('ChurnRisk pie chart composition', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.useSystemTrustState.mockReturnValue({ data: [], isLoading: false, error: null })
    mocks.useTrustForComponent.mockReturnValue(riskTrust)
    mocks.useCustomerRiskSummary.mockReturnValue({ data: populatedStats, isLoading: false })
    mocks.useCustomerRiskList.mockReturnValue({ data: [], isLoading: false })
  })

  it('uses the shared ChartPanel with the exact h2 title and existing trust action', () => {
    const { container } = render(<ChurnRiskPage />)

    const heading = screen.getByRole('heading', { level: 2, name: 'توزيع تصنيف العملاء' })
    const panel = heading.closest('.ds-chart-panel') as HTMLElement

    expect(panel).not.toBeNull()
    expect(container.querySelectorAll('.ds-chart-panel')).toHaveLength(1)
    expect(within(panel).getByTestId('trust-state-badge').textContent).toBe('OK')
    expect(within(panel).getByTestId('freshness-indicator')).not.toBeNull()
  })

  it('keeps the chart completely absent while stats are loading or when no pie segment has data', () => {
    mocks.useCustomerRiskSummary.mockReturnValue({ data: populatedStats, isLoading: true })
    const loadingRender = render(<ChurnRiskPage />)

    expect(loadingRender.container.querySelector('.ds-chart-panel')).toBeNull()
    expect(screen.queryByRole('heading', { level: 2, name: 'توزيع تصنيف العملاء' })).toBeNull()

    loadingRender.unmount()
    mocks.useCustomerRiskSummary.mockReturnValue({
      data: { vip: 0, loyal: 0, engaged: 0, at_risk: 0, dormant: 0 },
      isLoading: false,
    })
    const emptyRender = render(<ChurnRiskPage />)

    expect(emptyRender.container.querySelector('.ds-chart-panel')).toBeNull()
    expect(screen.queryByRole('heading', { level: 2, name: 'توزيع تصنيف العملاء' })).toBeNull()
  })

  it('keeps trust and freshness controls absent when riskTrust is unavailable', () => {
    mocks.useTrustForComponent.mockReturnValue(undefined)

    render(<ChurnRiskPage />)

    const panel = screen.getByRole('heading', { level: 2, name: 'توزيع تصنيف العملاء' }).closest('.ds-chart-panel') as HTMLElement
    expect(within(panel).queryByTestId('trust-state-badge')).toBeNull()
    expect(within(panel).queryByTestId('freshness-indicator')).toBeNull()
  })

  it('preserves the 260px pie container, filtered data, geometry, colors, tooltip and legend contracts', () => {
    render(<ChurnRiskPage />)

    const panel = screen.getByRole('heading', { level: 2, name: 'توزيع تصنيف العملاء' }).closest('.ds-chart-panel') as HTMLElement
    const responsive = within(panel).getByTestId('responsive-container')
    const pie = within(panel).getByTestId('pie')
    const cells = within(panel).getAllByTestId('pie-cell')

    expect(responsive.dataset).toMatchObject({ width: '100%', height: '260' })
    expect(JSON.parse(pie.getAttribute('data-data') ?? '[]')).toEqual([
      { name: 'VIP', value: 5 },
      { name: 'مخلص', value: 4 },
      { name: 'متفاعل', value: 3 },
      { name: 'معرض للخطر', value: 2 },
      { name: 'خامد', value: 1 },
    ])
    expect(pie.dataset).toMatchObject({
      dataKey: 'value',
      nameKey: 'name',
      cx: '50%',
      cy: '50%',
      innerRadius: '60',
      outerRadius: '100',
      paddingAngle: '2',
    })
    expect(cells.map(cell => cell.getAttribute('data-fill'))).toEqual([
      '#f59e0b', '#10b981', '#3b82f6', '#f97316', '#ef4444',
    ])
    expect(within(panel).getByTestId('tooltip').getAttribute('data-format')).toBe(JSON.stringify(['7', 'عملاء']))
    expect(within(panel).getByTestId('legend')).not.toBeNull()
  })
})
