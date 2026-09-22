import type { ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import ReceivablesPage from './ReceivablesPage'

const mocks = vi.hoisted(() => ({
  useSystemTrustState: vi.fn(),
  useTrustForComponent: vi.fn(),
  useARDailyTotals: vi.fn(),
  useARSummary: vi.fn(),
}))

vi.mock('@/hooks/useSystemTrustState', () => ({
  useSystemTrustState: mocks.useSystemTrustState,
  useTrustForComponent: mocks.useTrustForComponent,
}))

vi.mock('@/hooks/useARCollections', () => ({
  useARDailyTotals: mocks.useARDailyTotals,
  useARSummary: mocks.useARSummary,
}))

vi.mock('@/components/reports/MetricCard', () => ({
  default: ({ label, subtitle, value, status, lastCompletedAt, isStale, domain }: {
    label: string
    subtitle?: string
    value?: string | number | null
    status?: string | null
    lastCompletedAt?: string | null
    isStale?: boolean
    domain?: string
  }) => (
    <div
      data-testid="metric-card"
      data-label={label}
      data-subtitle={subtitle ?? ''}
      data-value={value == null ? '' : String(value)}
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
  default: ({ status }: { status: string }) => <span data-testid="trust-state-badge">{status}</span>,
}))

vi.mock('@/components/reports/FreshnessIndicator', () => ({
  default: () => <span data-testid="freshness-indicator">freshness</span>,
}))

vi.mock('recharts', () => ({
  ResponsiveContainer: ({ children, height }: { children: ReactNode; height: number }) => (
    <div data-testid="responsive-container" data-height={height}>{children}</div>
  ),
  BarChart: ({ children, data, margin }: { children: ReactNode; data: unknown; margin: Record<string, number> }) => (
    <div data-testid="bar-chart" data-data={JSON.stringify(data)} data-margin={JSON.stringify(margin)}>{children}</div>
  ),
  Bar: ({ dataKey, name, fill, radius, maxBarSize }: {
    dataKey: string
    name: string
    fill: string
    radius: number[]
    maxBarSize: number
  }) => (
    <span
      data-testid={`bar-${dataKey}`}
      data-name={name}
      data-fill={fill}
      data-radius={JSON.stringify(radius)}
      data-max-bar-size={maxBarSize}
    />
  ),
  XAxis: () => null,
  YAxis: () => null,
  Tooltip: () => null,
  CartesianGrid: () => null,
}))

const arTrust = {
  status: 'OK',
  last_completed_at: '2026-09-19T00:00:00Z',
  is_stale: false,
}

describe('Receivables report composition', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.useSystemTrustState.mockReturnValue({ data: [], isLoading: false, error: null })
    mocks.useTrustForComponent.mockReturnValue(arTrust)
    mocks.useARDailyTotals.mockReturnValue({ data: [], isLoading: false })
    mocks.useARSummary.mockReturnValue({
      data: {
        total_net_cohort: 100,
        total_receipt_amount: 120,
        total_refunds: 20,
      },
      isLoading: false,
    })
  })

  it('uses the shared three-column MetricGrid and preserves exact AR summary card order and content', () => {
    const { container } = render(<ReceivablesPage />)

    const grid = container.querySelector('[data-metric-grid]') as HTMLElement
    expect(grid).not.toBeNull()
    expect(grid.getAttribute('data-columns')).toBe('3')
    expect(grid.classList.contains('ds-metric-grid--cols-3')).toBe(true)
    expect(container.querySelector('.report-grid')).toBeNull()

    const cards = within(grid).getAllByTestId('metric-card')
    expect(cards).toHaveLength(3)
    expect(cards.map(card => card.getAttribute('data-label'))).toEqual([
      'صافي التحصيل (Cohort)',
      'إجمالي الإيصالات',
      'إجمالي المردودات النقدية',
    ])
    expect(cards.map(card => card.getAttribute('data-subtitle'))).toEqual([
      'منسوب لتاريخ البيع الأصلي',
      'قيمة ما حُصِّل فعلياً',
      'مسترد من عمليات مرتجع',
    ])
    expect(cards.map(card => card.getAttribute('data-value'))).toEqual(['100 ج.م', '120 ج.م', '20 ج.م'])

    cards.forEach(card => {
      expect(card.getAttribute('data-status')).toBe('OK')
      expect(card.getAttribute('data-last-completed-at')).toBe('2026-09-19T00:00:00Z')
      expect(card.getAttribute('data-stale')).toBe('false')
      expect(card.getAttribute('data-domain')).toBe('ar')
    })
  })

  it('keeps exactly three 160px summary loading skeletons without changing the AR chart state', () => {
    mocks.useARSummary.mockReturnValue({ data: undefined, isLoading: true })

    const { container } = render(<ReceivablesPage />)

    const grid = container.querySelector('[data-metric-grid]') as HTMLElement
    const skeletons = within(grid).getAllByTestId('skeleton-card')
    expect(skeletons).toHaveLength(3)
    expect(skeletons.map(skeleton => skeleton.getAttribute('data-height'))).toEqual(['160', '160', '160'])
    expect(within(grid).queryAllByTestId('metric-card')).toHaveLength(0)

    const panel = screen.getByRole('heading', { level: 2, name: 'تحصيلات AR مجمّعة بتاريخ البيع الأصلي' }).closest('.ds-chart-panel') as HTMLElement
    expect(within(panel).queryByTestId('skeleton-card')).toBeNull()
    expect(within(panel).getByText('لا توجد بيانات تحصيل في هذه الفترة')).not.toBeNull()
  })

  it('uses the shared ChartPanel with the exact title, description, trust action and empty state', () => {
    const { container } = render(<ReceivablesPage />)

    const heading = screen.getByRole('heading', { level: 2, name: 'تحصيلات AR مجمّعة بتاريخ البيع الأصلي' })
    const panel = heading.closest('.ds-chart-panel') as HTMLElement

    expect(panel).not.toBeNull()
    expect(container.querySelectorAll('.ds-chart-panel')).toHaveLength(1)
    expect(within(panel).getByText('مجمّع في قاعدة البيانات — إيصالات، مردودات، صافي')).not.toBeNull()
    expect(within(panel).getByTestId('trust-state-badge').textContent).toBe('OK')
    expect(within(panel).getByTestId('freshness-indicator')).not.toBeNull()

    const empty = within(panel).getByText('لا توجد بيانات تحصيل في هذه الفترة')
    expect(empty.style.height).toBe('260px')
  })

  it('keeps the existing blocked AR state and 260px body contract inside the shared panel', () => {
    mocks.useTrustForComponent.mockReturnValue({ ...arTrust, status: 'BLOCKED' })

    render(<ReceivablesPage />)

    const panel = screen.getByRole('heading', { level: 2, name: 'تحصيلات AR مجمّعة بتاريخ البيع الأصلي' }).closest('.ds-chart-panel') as HTMLElement
    const blockedTitle = within(panel).getByText('بيانات AR محجوبة')

    expect(blockedTitle.parentElement?.style.height).toBe('260px')
    expect(within(panel).getByText('يحتاج إلى اكتمال تشغيل محرك AR أولاً')).not.toBeNull()
  })

  it('keeps the loading skeleton at 260px', () => {
    mocks.useARDailyTotals.mockReturnValue({ data: [], isLoading: true })

    render(<ReceivablesPage />)

    const panel = screen.getByRole('heading', { level: 2, name: 'تحصيلات AR مجمّعة بتاريخ البيع الأصلي' }).closest('.ds-chart-panel') as HTMLElement
    expect(within(panel).getByTestId('skeleton-card').getAttribute('data-height')).toBe('260')
  })

  it('preserves the AR chart data mapping, 260px container, margins and all three series contracts', () => {
    mocks.useARDailyTotals.mockReturnValue({
      data: [{
        sale_date: '2026-09-18',
        receipt_amount: 120,
        refund_amount: 20,
        net_cohort: 100,
      }],
      isLoading: false,
    })

    render(<ReceivablesPage />)

    const panel = screen.getByRole('heading', { level: 2, name: 'تحصيلات AR مجمّعة بتاريخ البيع الأصلي' }).closest('.ds-chart-panel') as HTMLElement
    const container = within(panel).getByTestId('responsive-container')
    const chart = within(panel).getByTestId('bar-chart')

    expect(container.getAttribute('data-height')).toBe('260')
    expect(JSON.parse(chart.getAttribute('data-data') ?? '[]')).toEqual([
      { date: '2026-09-18', receipts: 120, refunds: 20, net: 100 },
    ])
    expect(JSON.parse(chart.getAttribute('data-margin') ?? '{}')).toEqual({ top: 4, left: -10, right: 4, bottom: 0 })

    expect(within(panel).getByTestId('bar-receipts')).toMatchObject({
      dataset: expect.objectContaining({ name: 'إيصالات', fill: '#2563eb', radius: '[3,3,0,0]', maxBarSize: '20' }),
    })
    expect(within(panel).getByTestId('bar-refunds')).toMatchObject({
      dataset: expect.objectContaining({ name: 'مردودات', fill: '#dc2626', radius: '[3,3,0,0]', maxBarSize: '20' }),
    })
    expect(within(panel).getByTestId('bar-net')).toMatchObject({
      dataset: expect.objectContaining({ name: 'صافي', fill: '#16a34a', radius: '[3,3,0,0]', maxBarSize: '20' }),
    })
  })
})
