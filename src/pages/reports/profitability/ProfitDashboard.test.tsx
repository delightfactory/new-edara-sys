import { render, screen, within } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import ProfitDashboard from './ProfitDashboard'

const mocks = vi.hoisted(() => ({
  useProfitSummary: vi.fn(),
  useSystemTrustState: vi.fn(),
  useTrustForComponent: vi.fn(),
  metricCard: vi.fn(),
  setTitle: vi.fn(),
}))

vi.mock('@/hooks/useProfitability', () => ({
  useProfitSummary: mocks.useProfitSummary,
}))

vi.mock('@/hooks/useSystemTrustState', () => ({
  useSystemTrustState: mocks.useSystemTrustState,
  useTrustForComponent: mocks.useTrustForComponent,
}))

vi.mock('@/components/reports/MetricCard', () => ({
  default: (props: Record<string, unknown>) => {
    mocks.metricCard(props)
    return <div data-testid="metric-card">{String(props.label)}</div>
  },
}))

vi.mock('@/components/reports/ReportFilterBar', () => ({
  default: () => <div data-testid="report-filter-bar" />,
}))

vi.mock('@/components/layout/PageTitleContext', () => ({
  usePageTitle: () => ({ setTitle: mocks.setTitle }),
}))

function getMetricGrid() {
  return document.querySelector('[data-metric-grid]') as HTMLElement
}

describe('ProfitDashboard summary composition', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.useProfitSummary.mockReturnValue({
      data: {
        net_revenue: 1200,
        cogs: 600,
        gross_profit: 600,
        operating_expenses: 200,
        payroll_expenses: 100,
        net_profit: 300,
      },
      isLoading: false,
    })
    mocks.useSystemTrustState.mockReturnValue({ data: [{ domain: 'profit_overview' }] })
    mocks.useTrustForComponent.mockReturnValue({
      status: 'OK',
      last_completed_at: '2026-09-22T00:00:00Z',
      is_stale: false,
    })
  })

  it('uses the shared four-column MetricGrid with the exact existing KPI order and trust contract', () => {
    render(<ProfitDashboard />)

    const grid = getMetricGrid()
    expect(document.querySelectorAll('[data-metric-grid]')).toHaveLength(1)
    expect(grid.getAttribute('data-columns')).toBe('4')
    expect(grid.classList.contains('ds-metric-grid--cols-4')).toBe(true)
    expect(within(grid).getAllByTestId('metric-card').map(card => card.textContent)).toEqual([
      'صافي الإيراد بعد المرتجعات',
      'المبيعات (تكلفة البضاعة)',
      'إجمالي الربح (التشغيلي)',
      'المصروفات التشغيلية والرواتب',
    ])
    expect(document.querySelector('.report-grid')).toBeNull()

    const cardProps = mocks.metricCard.mock.calls.map(([props]) => props)
    expect(cardProps.map(props => props.value)).toEqual([1200, 600, 600, 300])
    cardProps.forEach(props => {
      expect(props.status).toBe('OK')
      expect(props.lastCompletedAt).toBe('2026-09-22T00:00:00Z')
      expect(props.isStale).toBe(false)
      expect(props.domain).toBe('profit_overview')
      expect(props.icon).toBeTruthy()
    })
    expect(cardProps[2].secondary).toEqual({ label: 'هامش الربح', value: '50.0%' })
  })

  it('preserves the existing loading representation instead of introducing a new summary state', () => {
    mocks.useProfitSummary.mockReturnValue({ data: undefined, isLoading: true })
    render(<ProfitDashboard />)

    const grid = getMetricGrid()
    expect(within(grid).getAllByTestId('metric-card')).toHaveLength(4)
    expect(mocks.metricCard.mock.calls.map(([props]) => props.value)).toEqual(['...', '...', '...', '...'])

    const netProfitPanel = screen.getByText('صافي الربح النهائي').parentElement as HTMLElement
    expect(within(netProfitPanel).getByText('...')).toBeTruthy()
    expect(within(netProfitPanel).getByText('ج.م')).toBeTruthy()
  })

  it('preserves the surrounding filter and final-profit surface outside the converged summary grid', () => {
    render(<ProfitDashboard />)

    expect(screen.getByTestId('report-filter-bar')).toBeTruthy()
    expect(screen.getByRole('heading', { level: 2, name: 'نظرة عامة على الربحية' })).toBeTruthy()
    expect(screen.getByText('300')).toBeTruthy()
    expect(screen.getByText('هامش صافي الربح:')).toBeTruthy()
    expect(screen.getByText('25.0%')).toBeTruthy()
  })
})
