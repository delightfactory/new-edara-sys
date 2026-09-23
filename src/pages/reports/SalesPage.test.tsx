import type { ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import SalesPage from './SalesPage'

const mocks = vi.hoisted(() => ({
  useSystemTrustState: vi.fn(),
  useTrustForComponent: vi.fn(),
  useSalesDailyTotals: vi.fn(),
  useSalesSummary: vi.fn(),
}))

vi.mock('@/hooks/useSystemTrustState', () => ({
  useSystemTrustState: mocks.useSystemTrustState,
  useTrustForComponent: mocks.useTrustForComponent,
}))

vi.mock('@/hooks/useSalesGrain', () => ({
  useSalesDailyTotals: mocks.useSalesDailyTotals,
  useSalesSummary: mocks.useSalesSummary,
}))

vi.mock('@/components/reports/MetricCard', () => ({
  default: ({ label, subtitle, value, status, lastCompletedAt, isStale, domain, icon }: {
    label: string
    subtitle?: string
    value?: string | number | null
    status?: string | null
    lastCompletedAt?: string | null
    isStale?: boolean
    domain?: string
    icon?: ReactNode
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
      data-has-icon={String(Boolean(icon))}
    >
      {label}
    </div>
  ),
}))

vi.mock('@/components/reports/SkeletonCard', () => ({
  default: ({ height }: { height?: number }) => <div data-testid="skeleton-card" data-height={height} />,
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
  ResponsiveContainer: ({ children, width, height }: { children: ReactNode; width?: string | number; height?: string | number }) => (
    <div data-testid="responsive-container" data-width={String(width)} data-height={String(height)}>{children}</div>
  ),
  AreaChart: ({ children, data, margin }: { children: ReactNode; data: unknown; margin: unknown }) => (
    <div data-testid="area-chart" data-chart-data={JSON.stringify(data)} data-margin={JSON.stringify(margin)}>{children}</div>
  ),
  Area: ({ type, dataKey, name, stroke, strokeWidth, fill, dot }: {
    type: string
    dataKey: string
    name: string
    stroke: string
    strokeWidth: number
    fill: string
    dot: boolean
  }) => (
    <div
      data-testid={`area-${dataKey}`}
      data-type={type}
      data-name={name}
      data-stroke={stroke}
      data-stroke-width={String(strokeWidth)}
      data-fill={fill}
      data-dot={String(dot)}
    />
  ),
  XAxis: () => null,
  YAxis: () => null,
  Tooltip: () => null,
  CartesianGrid: () => null,
  BarChart: ({ children, data, margin }: { children: ReactNode; data: unknown; margin: unknown }) => (
    <div data-testid="bar-chart" data-chart-data={JSON.stringify(data)} data-margin={JSON.stringify(margin)}>{children}</div>
  ),
  Bar: ({ dataKey, name, fill, radius, maxBarSize }: { dataKey: string; name: string; fill: string; radius: number[]; maxBarSize: number }) => (
    <div
      data-testid={`bar-${dataKey}`}
      data-name={name}
      data-fill={fill}
      data-radius={JSON.stringify(radius)}
      data-max-bar-size={String(maxBarSize)}
    />
  ),
}))

const trustByComponent: Record<string, { status: string; last_completed_at: string; is_stale: boolean }> = {
  fact_sales_daily_grain: { status: 'OK', last_completed_at: '2026-09-19T00:00:00Z', is_stale: false },
  'fact_sales_daily_grain.revenue': { status: 'OK', last_completed_at: '2026-09-19T00:00:00Z', is_stale: false },
  'fact_sales_daily_grain.tax': { status: 'OK', last_completed_at: '2026-09-19T00:00:00Z', is_stale: false },
  'fact_sales_daily_grain.ar_creation': { status: 'OK', last_completed_at: '2026-09-19T00:00:00Z', is_stale: false },
}

function setViewport(width: number) {
  Object.defineProperty(window, 'innerWidth', {
    configurable: true,
    writable: true,
    value: width,
  })
}

function getFirstPanel() {
  return screen.getByRole('heading', { level: 2, name: 'تطور الإيراد اليومي' }).closest('.ds-chart-panel') as HTMLElement
}

function getSecondPanel() {
  return screen.getByRole('heading', { level: 2, name: 'توزيع الإيرادات اليومي (إيراد + ضريبة)' }).closest('.ds-chart-panel') as HTMLElement
}

describe('Sales report composition', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.useSystemTrustState.mockReturnValue({ data: [], isLoading: false, error: null })
    mocks.useTrustForComponent.mockImplementation((_rows: unknown, component: string) => trustByComponent[component] ?? null)
    mocks.useSalesDailyTotals.mockReturnValue({ data: [], isLoading: false })
    mocks.useSalesSummary.mockReturnValue({
      data: {
        total_revenue: 100,
        total_tax: 14,
        total_returns_value: 5,
        total_ar_credit: 40,
      },
      isLoading: false,
    })
  })

  it('uses the shared four-column MetricGrid and preserves exact Sales summary card order and content', () => {
    const { container } = render(<SalesPage />)

    const grid = container.querySelector('[data-metric-grid]') as HTMLElement
    expect(grid).not.toBeNull()
    expect(grid.getAttribute('data-columns')).toBe('4')
    expect(grid.classList.contains('ds-metric-grid--cols-4')).toBe(true)
    expect(container.querySelector('.report-grid')).toBeNull()

    const cards = within(grid).getAllByTestId('metric-card')
    expect(cards).toHaveLength(4)
    expect(cards.map(card => card.getAttribute('data-label'))).toEqual([
      'صافي الإيراد',
      'إجمالي الضريبة المحصلة',
      'قيمة المرتجعات',
      'ذمم عملاء منشأة',
    ])
    expect(cards.map(card => card.getAttribute('data-subtitle'))).toEqual([
      'ضريبة مستبعدة · مرتجعات مستبعدة',
      'ضريبة القيمة المضافة (2200)',
      'صافي قيمة ما تم رده',
      'قيمة الجزء الآجل من الفواتير',
    ])
    expect(cards.map(card => card.getAttribute('data-value'))).toEqual(['100 ج.م', '14 ج.م', '5 ج.م', '40 ج.م'])
    expect(cards.map(card => card.getAttribute('data-domain'))).toEqual(['sales', 'sales', 'sales', 'ar'])
    expect(cards.map(card => card.getAttribute('data-has-icon'))).toEqual(['true', 'true', 'true', 'false'])

    cards.forEach(card => {
      expect(card.getAttribute('data-status')).toBe('OK')
      expect(card.getAttribute('data-last-completed-at')).toBe('2026-09-19T00:00:00Z')
      expect(card.getAttribute('data-stale')).toBe('false')
    })
  })

  it('keeps exactly four 160px summary loading skeletons without changing either Sales chart state', () => {
    mocks.useSalesSummary.mockReturnValue({ data: undefined, isLoading: true })

    const { container } = render(<SalesPage />)

    const grid = container.querySelector('[data-metric-grid]') as HTMLElement
    const skeletons = within(grid).getAllByTestId('skeleton-card')
    expect(skeletons).toHaveLength(4)
    expect(skeletons.map(skeleton => skeleton.getAttribute('data-height'))).toEqual(['160', '160', '160', '160'])
    expect(within(grid).queryAllByTestId('metric-card')).toHaveLength(0)

    const firstPanel = getFirstPanel()
    const secondPanel = getSecondPanel()
    expect(within(firstPanel).queryByTestId('skeleton-card')).toBeNull()
    expect(within(firstPanel).getByText('لا توجد بيانات في النطاق الزمني المحدد')).not.toBeNull()
    expect(within(secondPanel).queryByTestId('skeleton-card')).toBeNull()
    expect(within(secondPanel).getByTestId('bar-chart')).not.toBeNull()
  })

  it('uses shared ChartPanel for both analytical sections while preserving the first panel contract', () => {
    const { container } = render(<SalesPage />)

    const firstPanel = getFirstPanel()
    const secondPanel = getSecondPanel()

    expect(firstPanel).not.toBeNull()
    expect(secondPanel).not.toBeNull()
    expect(container.querySelectorAll('.ds-chart-panel')).toHaveLength(2)

    expect(within(firstPanel).getByText('صافي إيراد + قيمة مرتجعات — مجمّع يومياً في قاعدة البيانات')).not.toBeNull()
    expect(within(firstPanel).getByTestId('trust-state-badge').textContent).toBe('OK')
    expect(within(firstPanel).getByTestId('freshness-indicator')).not.toBeNull()
    expect(within(firstPanel).getByText('لا توجد بيانات في النطاق الزمني المحدد')).not.toBeNull()

    expect(within(secondPanel).queryByTestId('trust-state-badge')).toBeNull()
    expect(within(secondPanel).queryByTestId('freshness-indicator')).toBeNull()
    expect(within(secondPanel).queryByText('صافي إيراد + قيمة مرتجعات — مجمّع يومياً في قاعدة البيانات')).toBeNull()
  })

  it('uses one compact passive shared empty StatePanel with exact copy and 240px geometry at Mobile, Tablet, and Desktop widths', () => {
    for (const width of [390, 900, 1440]) {
      setViewport(width)
      const view = render(<SalesPage />)
      const firstPanel = getFirstPanel()
      const emptyCopy = within(firstPanel).getByText('لا توجد بيانات في النطاق الزمني المحدد')
      const statePanel = emptyCopy.closest('.ds-state-panel') as HTMLElement

      expect(statePanel).not.toBeNull()
      expect(statePanel.getAttribute('data-state-kind')).toBe('empty')
      expect(statePanel.classList.contains('ds-state-panel--compact')).toBe(true)
      expect(statePanel.parentElement?.style.height).toBe('240px')
      expect(statePanel.parentElement?.style.width).toBe('')
      expect(statePanel.querySelector('.ds-state-panel__action')).toBeNull()
      expect(statePanel.getAttribute('aria-live')).toBeNull()
      expect(statePanel.querySelector('button, a, input, select, textarea, [tabindex]:not([tabindex="-1"])')).toBeNull()
      expect(within(firstPanel).queryByTestId('area-chart')).toBeNull()

      view.unmount()
    }
  })

  it('keeps the first chart blocked state first with exact copy and no empty/loading/ready renderer leakage', () => {
    mocks.useTrustForComponent.mockImplementation((_rows: unknown, component: string) => {
      if (component === 'fact_sales_daily_grain.revenue') {
        return { ...trustByComponent[component], status: 'BLOCKED' }
      }
      return trustByComponent[component] ?? null
    })

    render(<SalesPage />)

    const firstPanel = getFirstPanel()
    const secondPanel = getSecondPanel()
    const blockedTitle = within(firstPanel).getByText('المخطط محجوب')

    expect(blockedTitle.parentElement?.style.height).toBe('240px')
    expect(within(firstPanel).getByText('لا يمكن عرض بيانات الإيراد حتى اكتمال المطابقة المحاسبية')).not.toBeNull()
    expect(firstPanel.querySelector('.ds-state-panel')).toBeNull()
    expect(within(firstPanel).queryByTestId('skeleton-card')).toBeNull()
    expect(within(firstPanel).queryByTestId('area-chart')).toBeNull()
    expect(within(secondPanel).queryByText('المخطط محجوب')).toBeNull()
    expect(within(secondPanel).getByTestId('bar-chart')).not.toBeNull()
  })

  it('preserves the 240px first-chart loading body ahead of empty/ready and the 200px second-chart loading body', () => {
    mocks.useSalesDailyTotals.mockReturnValue({ data: [], isLoading: true })

    render(<SalesPage />)

    const firstPanel = getFirstPanel()
    const secondPanel = getSecondPanel()

    expect(within(firstPanel).getByTestId('skeleton-card').getAttribute('data-height')).toBe('240')
    expect(firstPanel.querySelector('.ds-state-panel')).toBeNull()
    expect(within(firstPanel).queryByTestId('area-chart')).toBeNull()
    expect(within(secondPanel).getByTestId('skeleton-card').getAttribute('data-height')).toBe('200')
  })

  it('preserves the first chart data mapping, 240px container, margins and exact revenue/returns series contract', () => {
    mocks.useSalesDailyTotals.mockReturnValue({
      data: [{
        sale_date: '2026-09-19',
        net_revenue: 1250,
        returns_value: 75,
        tax_amount: 175,
      }],
      isLoading: false,
    })

    render(<SalesPage />)

    const firstPanel = getFirstPanel()
    const responsive = within(firstPanel).getByTestId('responsive-container')
    const areaChart = within(firstPanel).getByTestId('area-chart')
    const revenueArea = within(firstPanel).getByTestId('area-revenue')
    const returnsArea = within(firstPanel).getByTestId('area-returns')

    expect(firstPanel.querySelector('.ds-state-panel')).toBeNull()
    expect(within(firstPanel).queryByTestId('skeleton-card')).toBeNull()
    expect(responsive.getAttribute('data-width')).toBe('100%')
    expect(responsive.getAttribute('data-height')).toBe('240')
    expect(areaChart.getAttribute('data-margin')).toBe(JSON.stringify({ top: 4, left: -10, right: 4, bottom: 0 }))
    expect(JSON.parse(areaChart.getAttribute('data-chart-data') ?? '[]')).toEqual([
      { date: '2026-09-19', revenue: 1250, returns: 75, tax: 175 },
    ])

    expect(revenueArea.dataset).toMatchObject({
      type: 'monotone',
      name: 'الإيراد الصافي',
      stroke: '#2563eb',
      strokeWidth: '2',
      fill: 'url(#revGrad)',
      dot: 'false',
    })
    expect(returnsArea.dataset).toMatchObject({
      type: 'monotone',
      name: 'المرتجعات',
      stroke: '#dc2626',
      strokeWidth: '1.5',
      fill: 'url(#retGrad)',
      dot: 'false',
    })
  })

  it('preserves the second chart data mapping, 200px container, margins and exact revenue/tax series contract', () => {
    mocks.useSalesDailyTotals.mockReturnValue({
      data: [{
        sale_date: '2026-09-19',
        net_revenue: 1250,
        returns_value: 75,
        tax_amount: 175,
      }],
      isLoading: false,
    })

    render(<SalesPage />)

    const secondPanel = getSecondPanel()
    const responsive = within(secondPanel).getByTestId('responsive-container')
    const barChart = within(secondPanel).getByTestId('bar-chart')
    const revenueBar = within(secondPanel).getByTestId('bar-revenue')
    const taxBar = within(secondPanel).getByTestId('bar-tax')

    expect(responsive.getAttribute('data-width')).toBe('100%')
    expect(responsive.getAttribute('data-height')).toBe('200')
    expect(barChart.getAttribute('data-margin')).toBe(JSON.stringify({ top: 4, left: -10, right: 4, bottom: 0 }))
    expect(JSON.parse(barChart.getAttribute('data-chart-data') ?? '[]')).toEqual([
      { date: '2026-09-19', revenue: 1250, returns: 75, tax: 175 },
    ])

    expect(revenueBar.getAttribute('data-name')).toBe('الإيراد')
    expect(revenueBar.getAttribute('data-fill')).toBe('#2563eb')
    expect(revenueBar.getAttribute('data-radius')).toBe(JSON.stringify([3, 3, 0, 0]))
    expect(revenueBar.getAttribute('data-max-bar-size')).toBe('24')

    expect(taxBar.getAttribute('data-name')).toBe('الضريبة')
    expect(taxBar.getAttribute('data-fill')).toBe('#0284c7')
    expect(taxBar.getAttribute('data-radius')).toBe(JSON.stringify([3, 3, 0, 0]))
    expect(taxBar.getAttribute('data-max-bar-size')).toBe('24')
  })
})
