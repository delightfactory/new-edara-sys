import type { ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, within } from '@testing-library/react'
import ChurnRiskPage, { CustomTooltip } from './ChurnRiskPage'

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
  total: 5,
  vip: 5,
  loyal: 4,
  engaged: 3,
  at_risk: 2,
  dormant: 1,
  avg_rfm_score: 300,
}

const longCustomerName = 'شركة العميل ذات الاسم العربي الطويل جداً لاختبار الالتفاف داخل البطاقة بدون تجاوز'

const riskRows = [
  {
    customer_id: 'customer-1',
    customer_name: longCustomerName,
    risk_label: 'AT_RISK',
    rfm_score: 532,
    recency_days: 45,
    frequency_l90d: 3,
    monetary_l90d: 1234,
  },
  {
    customer_id: 'deadbeef-1234-5678-9012',
    customer_name: null,
    risk_label: 'DORMANT',
    rfm_score: 111,
    recency_days: null,
    frequency_l90d: 1,
    monetary_l90d: 500,
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
  const title = screen.getByText('تفاصيل العملاء — مرتب: معرض للخطر أولاً')
  return title.parentElement?.parentElement as HTMLElement
}

function setDefaultMocks() {
  mocks.useSystemTrustState.mockReturnValue({ data: [], isLoading: false, error: null })
  mocks.useTrustForComponent.mockReturnValue(riskTrust)
  mocks.useCustomerRiskSummary.mockReturnValue({ data: populatedStats, isLoading: false })
  mocks.useCustomerRiskList.mockReturnValue({ data: [], isLoading: false })
}

describe('ChurnRisk report-header filter controls', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    setViewport(1440)
    setDefaultMocks()
  })

  it('uses shared V2 Field controls with accessible names and preserves initial hook filters', () => {
    render(<ChurnRiskPage />)

    const riskControl = screen.getByRole('combobox', { name: 'تصنيف الخطر' }) as HTMLSelectElement
    const dateControl = screen.getByLabelText('بتاريخ:') as HTMLInputElement

    expect(riskControl.closest('.ds-field')).not.toBeNull()
    expect(riskControl.classList.contains('form-select')).toBe(true)
    expect(dateControl.closest('.ds-field')).not.toBeNull()
    expect(dateControl.classList.contains('form-input')).toBe(true)
    expect(dateControl.type).toBe('date')
    expect(dateControl.max).toBe(dateControl.value)
    expect(mocks.useCustomerRiskSummary).toHaveBeenLastCalledWith({ asOfDate: dateControl.value, riskLabel: undefined })
    expect(mocks.useCustomerRiskList).toHaveBeenLastCalledWith({ asOfDate: dateControl.value, riskLabel: undefined })
  })

  it('preserves exact risk options and propagates risk/date changes to both customer-risk hooks', () => {
    render(<ChurnRiskPage />)

    const riskControl = screen.getByRole('combobox', { name: 'تصنيف الخطر' }) as HTMLSelectElement
    const dateControl = screen.getByLabelText('بتاريخ:') as HTMLInputElement

    expect(Array.from(riskControl.options).map(option => [option.value, option.textContent])).toEqual([
      ['', 'كل التصنيفات'],
      ['VIP', 'VIP'],
      ['LOYAL', 'مخلص'],
      ['ENGAGED', 'متفاعل'],
      ['AT_RISK', 'معرض للخطر'],
      ['DORMANT', 'خامد'],
    ])

    fireEvent.change(riskControl, { target: { value: 'AT_RISK' } })
    expect(riskControl.value).toBe('AT_RISK')
    expect(mocks.useCustomerRiskSummary).toHaveBeenLastCalledWith({ asOfDate: dateControl.value, riskLabel: 'AT_RISK' })
    expect(mocks.useCustomerRiskList).toHaveBeenLastCalledWith({ asOfDate: dateControl.value, riskLabel: 'AT_RISK' })

    fireEvent.change(dateControl, { target: { value: '2025-01-01' } })
    expect(dateControl.value).toBe('2025-01-01')
    expect(mocks.useCustomerRiskSummary).toHaveBeenLastCalledWith({ asOfDate: '2025-01-01', riskLabel: 'AT_RISK' })
    expect(mocks.useCustomerRiskList).toHaveBeenLastCalledWith({ asOfDate: '2025-01-01', riskLabel: 'AT_RISK' })

    fireEvent.change(riskControl, { target: { value: '' } })
    expect(riskControl.value).toBe('')
    expect(mocks.useCustomerRiskSummary).toHaveBeenLastCalledWith({ asOfDate: '2025-01-01', riskLabel: undefined })
    expect(mocks.useCustomerRiskList).toHaveBeenLastCalledWith({ asOfDate: '2025-01-01', riskLabel: undefined })
  })
})

describe('ChurnRisk pie chart composition', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    setViewport(1440)
    setDefaultMocks()
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

describe('ChurnRisk responsive detail collection', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    setViewport(1440)
    setDefaultMocks()
    mocks.useCustomerRiskList.mockReturnValue({ data: riskRows, isLoading: false })
  })

  it('preserves the compact semantic six-column Desktop table with exact row facts and no card renderer mounted', () => {
    render(<ChurnRiskPage />)

    const section = getDetailSection()
    const table = within(section).getByRole('table')
    const headers = within(table).getAllByRole('columnheader')

    expect(headers.map(header => header.textContent)).toEqual([
      'العميل',
      'التصنيف',
      'RFM Score',
      'أيام منذ آخر شراء',
      'تكرار (90 يوم)',
      'قيمة (90 يوم)',
    ])
    headers.forEach(header => expect(header.getAttribute('scope')).toBe('col'))
    expect(within(table).getByText(longCustomerName)).toBeTruthy()
    expect(within(table).getByText('معرض للخطر')).toBeTruthy()
    expect(within(table).getByText('532')).toBeTruthy()
    expect(within(table).getByText('45 يوم')).toBeTruthy()
    expect(within(table).getByText('3×')).toBeTruthy()
    expect(within(table).getByText('1,234 ج.م')).toBeTruthy()
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
  })

  it('mounts only one-column Mobile cards with exact RFM facts, fallback identity, wrapping and LTR numeric treatment', () => {
    setViewport(390)
    render(<ChurnRiskPage />)

    const section = getDetailSection()
    expect(within(section).queryByRole('table')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--mobile')).not.toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--tablet')).toBeNull()
    expect(section.querySelector('.ds-key-value-list--cols-1')).not.toBeNull()

    const longName = within(section).getByText(longCustomerName)
    expect(longName.style.overflowWrap).toBe('anywhere')
    expect(within(section).getByText('deadbeef…')).toBeTruthy()
    expect(within(section).queryByText('deadbeef-1234-5678-9012')).toBeNull()

    ;['التصنيف', 'RFM Score', 'أيام منذ آخر شراء', 'تكرار (90 يوم)', 'قيمة (90 يوم)'].forEach(label => {
      expect(within(section).getAllByText(label).length).toBeGreaterThan(0)
    })

    expect(within(section).getByText('معرض للخطر')).toBeTruthy()
    expect(within(section).getByText('خامد')).toBeTruthy()
    expect(within(section).getByText('532').getAttribute('dir')).toBe('ltr')
    expect(within(section).getByText('45 يوم').style.direction).toBe('ltr')
    expect(within(section).getByText('3×').getAttribute('dir')).toBe('ltr')
    expect(within(section).getByText('1,234 ج.م').getAttribute('dir')).toBe('ltr')
    expect(within(section).getByText('لا توجد مبيعات')).toBeTruthy()
  })

  it('uses the deliberate two-column Tablet card composition and mounts no Desktop table or Mobile renderer', () => {
    setViewport(900)
    render(<ChurnRiskPage />)

    const section = getDetailSection()
    expect(within(section).queryByRole('table')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--tablet')).not.toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--mobile')).toBeNull()
    expect(section.querySelector('.ds-key-value-list--cols-2')).not.toBeNull()
    expect(within(section).getByText(longCustomerName)).toBeTruthy()
  })

  it('keeps the blocked state higher priority than collection loading, empty, or ready renderers', () => {
    setViewport(390)
    mocks.useTrustForComponent.mockReturnValue({
      status: 'BLOCKED',
      last_completed_at: null,
      is_stale: true,
    })
    mocks.useCustomerRiskList.mockReturnValue({ data: riskRows, isLoading: true })

    render(<ChurnRiskPage />)

    const section = getDetailSection()
    expect(within(section).getByText('بيانات الخطر محجوبة')).toBeTruthy()
    expect(within(section).getByText('snapshot_customer_risk يحتاج تشغيل ناجح أولاً')).toBeTruthy()
    expect(section.querySelector('.ds-responsive-collection')).toBeNull()
    expect(section.querySelector('.ds-state-panel[data-state-kind="empty"]')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
    expect(within(section).queryByRole('table')).toBeNull()
  })

  it('keeps the five-row 44px loading state ahead of empty and ready renderers', () => {
    setViewport(390)
    mocks.useCustomerRiskList.mockReturnValue({ data: [], isLoading: true })

    render(<ChurnRiskPage />)

    const section = getDetailSection()
    const loadingCollection = section.querySelector('[data-collection-state="loading"]') as HTMLElement
    expect(loadingCollection).not.toBeNull()
    const loadingRows = within(loadingCollection).getAllByTestId('skeleton-card')
    expect(loadingRows).toHaveLength(5)
    loadingRows.forEach(row => expect(row.getAttribute('data-height')).toBe('44'))
    expect(section.querySelector('.ds-state-panel[data-state-kind="empty"]')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
    expect(within(section).queryByRole('table')).toBeNull()
  })

  it.each([
    [390, 'mobile'],
    [900, 'tablet'],
    [1440, 'desktop'],
  ])('uses the shared compact passive empty state without ready-renderer leakage at %ipx', (width, device) => {
    setViewport(width)
    mocks.useCustomerRiskList.mockReturnValue({ data: [], isLoading: false })

    render(<ChurnRiskPage />)

    const section = getDetailSection()
    const emptyCollection = section.querySelector('[data-collection-state="empty"]') as HTMLElement
    const statePanel = emptyCollection.querySelector('.ds-state-panel[data-state-kind="empty"]') as HTMLElement

    expect(emptyCollection).not.toBeNull()
    expect(emptyCollection.getAttribute('data-device')).toBe(device)
    expect(statePanel).not.toBeNull()
    expect(statePanel.classList.contains('ds-state-panel--compact')).toBe(true)
    expect(within(statePanel).getByText('لا توجد بيانات — شغّل watermark sweep أولاً')).toBeTruthy()
    expect(statePanel.getAttribute('aria-live')).toBeNull()
    expect(statePanel.querySelector('.ds-state-panel__action')).toBeNull()
    expect(within(statePanel).queryByRole('button')).toBeNull()
    expect(within(statePanel).queryByRole('link')).toBeNull()
    expect(statePanel.querySelector('[tabindex]')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
    expect(within(section).queryByRole('table')).toBeNull()
  })

  it('preserves the detail-section trust and freshness actions', () => {
    setViewport(390)
    render(<ChurnRiskPage />)

    const section = getDetailSection()
    expect(within(section).getByTestId('trust-state-badge').textContent).toBe('OK')
    expect(within(section).getByTestId('freshness-indicator')).toBeTruthy()
  })
})
