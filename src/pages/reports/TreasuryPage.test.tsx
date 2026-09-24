import type { ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import TreasuryPage, { CustomTooltip } from './TreasuryPage'

const mocks = vi.hoisted(() => ({
  useSystemTrustState: vi.fn(),
  useTrustForComponent: vi.fn(),
  useTreasuryDailyTotals: vi.fn(),
  useTreasurySummary: vi.fn(),
}))

vi.mock('@/hooks/useSystemTrustState', () => ({
  useSystemTrustState: mocks.useSystemTrustState,
  useTrustForComponent: mocks.useTrustForComponent,
}))

vi.mock('@/hooks/useTreasuryCashflow', () => ({
  useTreasuryDailyTotals: mocks.useTreasuryDailyTotals,
  useTreasurySummary: mocks.useTreasurySummary,
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
  ResponsiveContainer: ({ children, width, height }: { children: ReactNode; width: string; height: number }) => (
    <div data-testid="responsive-container" data-width={width} data-height={height}>{children}</div>
  ),
  AreaChart: ({ children, data, margin }: { children: ReactNode; data: unknown; margin: Record<string, number> }) => (
    <svg data-testid="area-chart" data-data={JSON.stringify(data)} data-margin={JSON.stringify(margin)}>{children}</svg>
  ),
  Area: ({ dataKey, name, stroke, strokeWidth, fill, dot }: {
    dataKey: string
    name: string
    stroke: string
    strokeWidth: number
    fill: string
    dot: boolean
  }) => (
    <g
      data-testid={`area-${dataKey}`}
      data-name={name}
      data-stroke={stroke}
      data-stroke-width={strokeWidth}
      data-fill={fill}
      data-dot={String(dot)}
    />
  ),
  XAxis: ({ dataKey, tickLine, axisLine }: { dataKey: string; tickLine: boolean; axisLine: boolean }) => (
    <g data-testid="x-axis" data-key={dataKey} data-tick-line={String(tickLine)} data-axis-line={String(axisLine)} />
  ),
  YAxis: ({ tickFormatter, tickLine, axisLine }: { tickFormatter: (value: number) => string; tickLine: boolean; axisLine: boolean }) => (
    <g data-testid="y-axis" data-formatted={tickFormatter(1234)} data-tick-line={String(tickLine)} data-axis-line={String(axisLine)} />
  ),
  Tooltip: ({ content }: { content?: ReactNode }) => (
    <g data-testid="chart-tooltip" data-has-content={String(Boolean(content))} />
  ),
  CartesianGrid: ({ strokeDasharray, stroke, vertical }: { strokeDasharray: string; stroke: string; vertical: boolean }) => (
    <g data-testid="cartesian-grid" data-dash={strokeDasharray} data-stroke={stroke} data-vertical={String(vertical)} />
  ),
  ReferenceLine: ({ y, stroke, strokeDasharray }: { y: number; stroke: string; strokeDasharray: string }) => (
    <g data-testid="reference-line" data-y={y} data-stroke={stroke} data-dash={strokeDasharray} />
  ),
}))

const treasuryTrust = {
  status: 'OK',
  last_completed_at: '2026-09-20T00:00:00Z',
  is_stale: false,
}

function setViewport(width: number) {
  Object.defineProperty(window, 'innerWidth', {
    configurable: true,
    writable: true,
    value: width,
  })
}

const readyDailyRow = {
  treasury_date: '2026-09-20',
  gross_inflow: 120,
  gross_outflow: 20,
  net_cashflow: 100,
}

const cssColorByHex: Record<string, string> = {
  '#16a34a': 'rgb(22, 163, 74)',
  '#dc2626': 'rgb(220, 38, 38)',
  '#2563eb': 'rgb(37, 99, 235)',
}

describe('Treasury daily cashflow chart composition', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.useSystemTrustState.mockReturnValue({ data: [], isLoading: false, error: null })
    mocks.useTrustForComponent.mockReturnValue(treasuryTrust)
    mocks.useTreasuryDailyTotals.mockReturnValue({ data: [], isLoading: false })
    mocks.useTreasurySummary.mockReturnValue({
      data: {
        net_cashflow: 100,
        total_inflow: 120,
        total_outflow: 20,
      },
      isLoading: false,
    })
  })

  it('uses the shared static info AlertPanel for the Treasury semantic-contract notice without changing disclosure meaning or hierarchy', () => {
    const { container } = render(<TreasuryPage />)

    const alert = container.querySelector('.ds-alert-panel') as HTMLElement
    expect(alert).not.toBeNull()
    expect(alert.getAttribute('data-tone')).toBe('info')
    expect(alert.getAttribute('role')).toBeNull()
    expect(alert.getAttribute('aria-live')).toBeNull()
    expect(alert.querySelector('.ds-alert-panel__action')).toBeNull()
    expect(alert.querySelector('.ds-alert-panel__icon')?.getAttribute('aria-hidden')).toBe('true')

    expect(alert.textContent).toContain('مطابق لسجلات الخزينة')
    expect(alert.textContent).toContain('وليس تدقيقاً خارجياً مستقلاً')
    expect(within(alert).getByText('vault_transactions / custody_transactions', { selector: 'code' })).not.toBeNull()
    expect(within(alert).getByText('net_cashflow', { selector: 'code' })).not.toBeNull()

    expect(alert.previousElementSibling?.querySelector('h1')?.textContent).toBe('التدفق النقدي الخزيني')
    expect(alert.previousElementSibling?.querySelector('[data-testid="report-filter-bar"]')).not.toBeNull()
    expect(alert.nextElementSibling?.getAttribute('data-testid')).toBe('system-health-bar')
  })

  it('uses the shared three-column MetricGrid and preserves exact Treasury summary card order and contracts', () => {
    const { container } = render(<TreasuryPage />)

    const grid = container.querySelector('[data-metric-grid]') as HTMLElement
    expect(grid).not.toBeNull()
    expect(grid.getAttribute('data-columns')).toBe('3')
    expect(grid.classList.contains('ds-metric-grid--cols-3')).toBe(true)
    expect(container.querySelector('.report-grid')).toBeNull()

    const cards = within(grid).getAllByTestId('metric-card')
    expect(cards).toHaveLength(3)
    expect(cards.map(card => card.getAttribute('data-label'))).toEqual([
      'صافي التدفق الخزيني',
      'إجمالي التحصيل الداخل',
      'إجمالي المسترد',
    ])
    expect(cards.map(card => card.getAttribute('data-subtitle'))).toEqual([
      'net_cashflow — مطابق لسجلات الخزينة والعُهد',
      'نقد وعُهد مدفوعة فعلياً',
      'مردودات نقدية للعملاء',
    ])
    expect(cards.map(card => card.getAttribute('data-value'))).toEqual(['100 ج.م', '120 ج.م', '20 ج.م'])
    expect(cards.map(card => card.getAttribute('data-domain'))).toEqual(['treasury', 'treasury', 'treasury'])
    expect(cards.map(card => card.getAttribute('data-has-icon'))).toEqual(['true', 'true', 'true'])

    cards.forEach(card => {
      expect(card.getAttribute('data-status')).toBe('OK')
      expect(card.getAttribute('data-last-completed-at')).toBe('2026-09-20T00:00:00Z')
      expect(card.getAttribute('data-stale')).toBe('false')
    })
  })

  it('keeps exactly three 160px summary loading skeletons isolated from the existing chart state', () => {
    mocks.useTreasurySummary.mockReturnValue({ data: undefined, isLoading: true })

    const { container } = render(<TreasuryPage />)

    const grid = container.querySelector('[data-metric-grid]') as HTMLElement
    const skeletons = within(grid).getAllByTestId('skeleton-card')
    expect(skeletons).toHaveLength(3)
    expect(skeletons.map(skeleton => skeleton.getAttribute('data-height'))).toEqual(['160', '160', '160'])
    expect(within(grid).queryAllByTestId('metric-card')).toHaveLength(0)

    const panel = screen.getByRole('heading', { level: 2, name: 'التدفق النقدي اليومي' }).closest('.ds-chart-panel') as HTMLElement
    expect(within(panel).queryByTestId('skeleton-card')).toBeNull()
    expect(within(panel).getByText('لا توجد تدفقات خزينية في هذه الفترة')).not.toBeNull()
  })

  it('adopts the shared ChartPanel with semantic h1 to h2 hierarchy and exact trust context', () => {
    const { container } = render(<TreasuryPage />)

    expect(screen.getByRole('heading', { level: 1, name: 'التدفق النقدي الخزيني' })).not.toBeNull()

    const heading = screen.getByRole('heading', { level: 2, name: 'التدفق النقدي اليومي' })
    const panel = heading.closest('.ds-chart-panel') as HTMLElement

    expect(panel).not.toBeNull()
    expect(container.querySelectorAll('.ds-chart-panel')).toHaveLength(1)
    expect(within(panel).getByText('net_cashflow — مجمّع يومياً في قاعدة البيانات')).not.toBeNull()
    expect(within(panel).getByTestId('trust-state-badge').textContent).toBe('OK')
    expect(within(panel).getByTestId('freshness-indicator')).not.toBeNull()
  })

  it('keeps blocked state first with exact copy and 280px body even when daily data is loading', () => {
    mocks.useTrustForComponent.mockReturnValue({ ...treasuryTrust, status: 'BLOCKED' })
    mocks.useTreasuryDailyTotals.mockReturnValue({
      data: [readyDailyRow],
      isLoading: true,
    })

    render(<TreasuryPage />)

    const panel = screen.getByRole('heading', { level: 2, name: 'التدفق النقدي اليومي' }).closest('.ds-chart-panel') as HTMLElement
    const blockedTitle = within(panel).getByText('التدفق النقدي محجوب')

    expect(blockedTitle.parentElement?.style.height).toBe('280px')
    expect(within(panel).getByText('يظهر عند اكتمال المطابقة مع سجلات الخزائن والعُهد')).not.toBeNull()
    expect(within(panel).queryByTestId('skeleton-card')).toBeNull()
    expect(within(panel).queryByTestId('area-chart')).toBeNull()
    expect(within(panel).queryByTestId('chart-tooltip')).toBeNull()
  })

  it('keeps loading ahead of empty with the exact 280px skeleton contract', () => {
    mocks.useTreasuryDailyTotals.mockReturnValue({ data: [], isLoading: true })

    render(<TreasuryPage />)

    const panel = screen.getByRole('heading', { level: 2, name: 'التدفق النقدي اليومي' }).closest('.ds-chart-panel') as HTMLElement
    expect(within(panel).getByTestId('skeleton-card').getAttribute('data-height')).toBe('280')
    expect(within(panel).queryByText('لا توجد تدفقات خزينية في هذه الفترة')).toBeNull()
    expect(within(panel).queryByTestId('chart-tooltip')).toBeNull()
  })

  it('keeps the exact empty copy and 280px height after loading resolves', () => {
    render(<TreasuryPage />)

    const panel = screen.getByRole('heading', { level: 2, name: 'التدفق النقدي اليومي' }).closest('.ds-chart-panel') as HTMLElement
    const empty = within(panel).getByText('لا توجد تدفقات خزينية في هذه الفترة')

    expect(empty.style.height).toBe('280px')
    expect(within(panel).queryByTestId('chart-tooltip')).toBeNull()
  })

  it('keeps the Treasury tooltip inactive and empty-payload guard unchanged', () => {
    const view = render(<CustomTooltip active={false} label="2026-09-20" payload={[
      { name: 'داخل', value: 120, color: '#16a34a' },
    ]} />)

    expect(view.container.firstChild).toBeNull()

    view.rerender(<CustomTooltip active label="2026-09-20" payload={[]} />)
    expect(view.container.firstChild).toBeNull()
  })

  it('delegates Treasury tooltip presentation to shared ChartTooltip while preserving label, row order, colors, currency formatting, and LTR values', () => {
    const payload = [
      { name: 'داخل', value: 1234, color: '#16a34a' },
      { name: 'مستردّ', value: 200, color: '#dc2626' },
      { name: 'صافي', value: 1034, color: '#2563eb' },
    ]

    for (const width of [390, 900, 1440]) {
      setViewport(width)
      const view = render(<CustomTooltip active label="2026-09-20" payload={payload} />)
      const tooltip = view.container.querySelector('.ds-chart-tooltip') as HTMLElement
      const rows = Array.from(tooltip.querySelectorAll('.ds-chart-tooltip__row')) as HTMLElement[]
      const values = rows.map(row => row.querySelector('.ds-chart-tooltip__value') as HTMLElement)

      expect(tooltip).not.toBeNull()
      expect(tooltip.getAttribute('dir')).toBe('rtl')
      expect(within(tooltip).getByText('2026-09-20')).not.toBeNull()
      expect(rows.map(row => row.querySelector('.ds-chart-tooltip__item-label')?.textContent)).toEqual(payload.map(item => item.name))
      expect(rows.map(row => row.style.color)).toEqual(payload.map(item => cssColorByHex[item.color]))
      expect(values.map(value => value.textContent)).toEqual(['1,234 ج.م', '200 ج.م', '1,034 ج.م'])
      expect(values.map(value => value.getAttribute('dir'))).toEqual(['ltr', 'ltr', 'ltr'])
      expect(tooltip.querySelector('button, a, input, select, textarea, [tabindex]:not([tabindex="-1"])')).toBeNull()
      expect(tooltip.getAttribute('aria-live')).toBeNull()
      expect(tooltip.getAttribute('role')).toBeNull()

      view.unmount()
    }
  })

  it('keeps shared tooltip content wired into the ready Treasury chart at Mobile, Tablet, and Desktop widths', () => {
    mocks.useTreasuryDailyTotals.mockReturnValue({ data: [readyDailyRow], isLoading: false })

    for (const width of [390, 900, 1440]) {
      setViewport(width)
      const view = render(<TreasuryPage />)
      const panel = screen.getByRole('heading', { level: 2, name: 'التدفق النقدي اليومي' }).closest('.ds-chart-panel') as HTMLElement
      const tooltip = within(panel).getByTestId('chart-tooltip')

      expect(tooltip.getAttribute('data-has-content')).toBe('true')
      expect(within(panel).getByTestId('responsive-container').getAttribute('data-height')).toBe('280')
      expect(within(panel).getByTestId('area-chart')).not.toBeNull()
      expect(within(panel).queryByText('لا توجد تدفقات خزينية في هذه الفترة')).toBeNull()

      view.unmount()
    }
  })

  it('preserves caller ordering, chart mapping, 100% containment, margins and core axes/grid/reference contracts', () => {
    mocks.useTreasuryDailyTotals.mockReturnValue({
      data: [
        { treasury_date: '2026-09-19', gross_inflow: 80, gross_outflow: 10, net_cashflow: 70 },
        readyDailyRow,
      ],
      isLoading: false,
    })

    render(<TreasuryPage />)

    const panel = screen.getByRole('heading', { level: 2, name: 'التدفق النقدي اليومي' }).closest('.ds-chart-panel') as HTMLElement
    const responsive = within(panel).getByTestId('responsive-container')
    const chart = within(panel).getByTestId('area-chart')

    expect(responsive.dataset).toMatchObject({ width: '100%', height: '280' })
    expect(JSON.parse(chart.getAttribute('data-data') ?? '[]')).toEqual([
      { date: '2026-09-19', inflow: 80, outflow: 10, net: 70 },
      { date: '2026-09-20', inflow: 120, outflow: 20, net: 100 },
    ])
    expect(JSON.parse(chart.getAttribute('data-margin') ?? '{}')).toEqual({ top: 4, left: -10, right: 4, bottom: 0 })
    expect(within(panel).getByTestId('cartesian-grid').dataset).toMatchObject({ dash: '3 3', stroke: 'var(--border-primary)', vertical: 'false' })
    expect(within(panel).getByTestId('x-axis').dataset).toMatchObject({ key: 'date', tickLine: 'false', axisLine: 'false' })
    expect(within(panel).getByTestId('y-axis').dataset).toMatchObject({ formatted: '1,234', tickLine: 'false', axisLine: 'false' })
    expect(within(panel).getByTestId('reference-line').dataset).toMatchObject({ y: '0', stroke: 'var(--border-primary)', dash: '4 4' })
    expect(within(panel).getByTestId('chart-tooltip').getAttribute('data-has-content')).toBe('true')
  })

  it('preserves all three area-series and gradient color/opacity contracts', () => {
    mocks.useTreasuryDailyTotals.mockReturnValue({
      data: [readyDailyRow],
      isLoading: false,
    })

    const { container } = render(<TreasuryPage />)
    const panel = screen.getByRole('heading', { level: 2, name: 'التدفق النقدي اليومي' }).closest('.ds-chart-panel') as HTMLElement

    expect(within(panel).getByTestId('area-inflow').dataset).toMatchObject({
      name: 'داخل', stroke: '#16a34a', strokeWidth: '2', fill: 'url(#inflowGrad)', dot: 'false',
    })
    expect(within(panel).getByTestId('area-outflow').dataset).toMatchObject({
      name: 'مستردّ', stroke: '#dc2626', strokeWidth: '1.5', fill: 'url(#outflowGrad)', dot: 'false',
    })
    expect(within(panel).getByTestId('area-net').dataset).toMatchObject({
      name: 'صافي', stroke: '#2563eb', strokeWidth: '2.5', fill: 'url(#netGrad)', dot: 'false',
    })

    const inflowStops = Array.from(container.querySelectorAll('#inflowGrad stop'))
    const outflowStops = Array.from(container.querySelectorAll('#outflowGrad stop'))
    const netStops = Array.from(container.querySelectorAll('#netGrad stop'))

    expect(inflowStops.map(stop => [stop.getAttribute('offset'), stop.getAttribute('stop-color'), stop.getAttribute('stop-opacity')])).toEqual([
      ['5%', '#16a34a', '0.25'], ['95%', '#16a34a', '0.02'],
    ])
    expect(outflowStops.map(stop => [stop.getAttribute('offset'), stop.getAttribute('stop-color'), stop.getAttribute('stop-opacity')])).toEqual([
      ['5%', '#dc2626', '0.2'], ['95%', '#dc2626', '0.02'],
    ])
    expect(netStops.map(stop => [stop.getAttribute('offset'), stop.getAttribute('stop-color'), stop.getAttribute('stop-opacity')])).toEqual([
      ['5%', '#2563eb', '0.3'], ['95%', '#2563eb', '0.02'],
    ])
  })
})
