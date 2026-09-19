import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import OverviewPage from './OverviewPage'

const mocks = vi.hoisted(() => ({
  useSystemTrustState: vi.fn(),
  useTrustForComponent: vi.fn(),
  useSalesSummary: vi.fn(),
  useTreasurySummary: vi.fn(),
  useARSummary: vi.fn(),
  useCustomerHealthSummary: vi.fn(),
}))

vi.mock('@/hooks/useSystemTrustState', () => ({
  useSystemTrustState: mocks.useSystemTrustState,
  useTrustForComponent: mocks.useTrustForComponent,
}))

vi.mock('@/hooks/useSalesGrain', () => ({
  useSalesSummary: mocks.useSalesSummary,
}))

vi.mock('@/hooks/useTreasuryCashflow', () => ({
  useTreasurySummary: mocks.useTreasurySummary,
}))

vi.mock('@/hooks/useARCollections', () => ({
  useARSummary: mocks.useARSummary,
}))

vi.mock('@/hooks/useCustomerHealth', () => ({
  useCustomerHealthSummary: mocks.useCustomerHealthSummary,
}))

vi.mock('@/components/reports/MetricCard', () => ({
  default: ({ label, value }: { label: string; value: string | number | null }) => (
    <article data-testid="report-metric-card" data-label={label}>
      {value ?? '—'}
    </article>
  ),
}))

vi.mock('@/components/reports/SkeletonCard', () => ({
  default: () => <div data-testid="skeleton-card" />,
}))

vi.mock('@/components/reports/SystemHealthBar', () => ({
  default: () => <div data-testid="system-health-bar" />,
}))

vi.mock('@/components/reports/ReportFilterBar', () => ({
  default: () => <div data-testid="report-filter-bar" />,
}))

function renderPage() {
  return render(
    <MemoryRouter>
      <OverviewPage />
    </MemoryRouter>,
  )
}

describe('Reports Overview summary metric composition', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.useSystemTrustState.mockReturnValue({ data: [], isLoading: false, error: null })
    mocks.useTrustForComponent.mockReturnValue(null)
    mocks.useSalesSummary.mockReturnValue({
      data: {
        total_revenue: 100,
        total_tax: 14,
        total_gross_revenue: 114,
        total_returns_value: 5,
      },
      isLoading: false,
    })
    mocks.useTreasurySummary.mockReturnValue({
      data: { net_cashflow: 80, total_inflow: 90 },
      isLoading: false,
    })
    mocks.useARSummary.mockReturnValue({
      data: { total_net_cohort: 70, total_receipt_amount: 75 },
      isLoading: false,
    })
    mocks.useCustomerHealthSummary.mockReturnValue({
      data: {
        stats: {
          active: 12,
          dormant: 3,
          avg_monetary: 250,
          avg_recency: 18,
        },
      },
      isLoading: false,
    })
  })

  it('uses the shared four-column MetricGrid while preserving the existing four report MetricCard children in order', () => {
    const { container } = renderPage()

    const metricGrids = container.querySelectorAll('[data-metric-grid]')
    expect(metricGrids).toHaveLength(1)

    const grid = metricGrids[0] as HTMLElement
    expect(grid.className).toContain('ds-metric-grid')
    expect(grid.className).toContain('ds-metric-grid--cols-4')
    expect(grid.getAttribute('data-columns')).toBe('4')
    expect(grid.className).not.toContain('report-grid')

    const cards = within(grid).getAllByTestId('report-metric-card')
    expect(cards).toHaveLength(4)
    expect(cards.map(card => card.getAttribute('data-label'))).toEqual([
      'صافي الإيراد',
      'إجمالي المبيعات',
      'صافي التحصيل الخزيني',
      'تحصيل AR المنسوب',
    ])
    expect(cards.map(card => card.textContent)).toEqual([
      '100 ج.م',
      '114 ج.م',
      '80 ج.م',
      '70 ج.م',
    ])
  })

  it('keeps the existing four-card loading state inside the shared summary grid', () => {
    mocks.useSalesSummary.mockReturnValue({ data: null, isLoading: true })

    const { container } = renderPage()
    const grid = container.querySelector('[data-metric-grid]') as HTMLElement

    expect(within(grid).getAllByTestId('skeleton-card')).toHaveLength(4)
    expect(within(grid).queryByTestId('report-metric-card')).toBeNull()
  })
})
