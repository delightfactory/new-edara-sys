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
  default: ({
    label,
    value,
    subtitle,
    status,
    lastCompletedAt,
    isStale,
    domain,
    secondary,
  }: {
    label: string
    value: string | number | null
    subtitle?: string
    status?: string | null
    lastCompletedAt?: string | null
    isStale?: boolean | null
    domain?: string
    secondary?: { label: string; value: string }
  }) => (
    <article
      data-testid="report-metric-card"
      data-label={label}
      data-subtitle={subtitle}
      data-status={status ?? undefined}
      data-last-completed-at={lastCompletedAt ?? undefined}
      data-is-stale={isStale == null ? undefined : String(isStale)}
      data-domain={domain}
      data-secondary-label={secondary?.label}
      data-secondary-value={secondary?.value}
    >
      {value ?? '—'}
    </article>
  ),
}))

vi.mock('@/components/reports/SkeletonCard', () => ({
  default: ({ height }: { height?: number }) => (
    <div data-testid="skeleton-card" data-height={height == null ? undefined : String(height)} />
  ),
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

  it('uses the shared SectionHeader anatomy for both report sections while preserving h2 hierarchy and the customer-details link', () => {
    const { container, getByRole } = renderPage()

    const sectionHeaders = container.querySelectorAll('.ds-section-header')
    expect(sectionHeaders).toHaveLength(2)

    const summaryHeading = getByRole('heading', { level: 2, name: 'المؤشرات الرئيسية' })
    expect(summaryHeading).toHaveClass('ds-section-header__title')
    expect(summaryHeading.closest('.ds-section-header')).toBe(sectionHeaders[0])

    const customerHeading = getByRole('heading', { level: 2, name: 'صحة قاعدة العملاء' })
    expect(customerHeading).toHaveClass('ds-section-header__title')
    const customerHeader = customerHeading.closest('.ds-section-header') as HTMLElement
    expect(customerHeader).toBe(sectionHeaders[1])

    const detailsLink = within(customerHeader).getByRole('link', { name: 'عرض التفاصيل ←' })
    expect(detailsLink).toHaveAttribute('href', '/reports/customers')
    expect(detailsLink.closest('.ds-section-header__action')).not.toBeNull()
  })

  it('uses the shared four-column MetricGrid while preserving the existing four report MetricCard children in order', () => {
    const { container } = renderPage()

    const metricGrids = container.querySelectorAll('[data-metric-grid]')
    expect(metricGrids).toHaveLength(2)

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

  it('uses a second shared two-column MetricGrid for customer health while preserving card order and values', () => {
    const { container } = renderPage()

    const metricGrids = container.querySelectorAll('[data-metric-grid]')
    expect(metricGrids).toHaveLength(2)

    const customerGrid = metricGrids[1] as HTMLElement
    expect(customerGrid.className).toContain('ds-metric-grid')
    expect(customerGrid.className).toContain('ds-metric-grid--cols-2')
    expect(customerGrid.getAttribute('data-columns')).toBe('2')
    expect(customerGrid.className).not.toContain('report-grid')

    const cards = within(customerGrid).getAllByTestId('report-metric-card')
    expect(cards).toHaveLength(2)
    expect(cards.map(card => card.getAttribute('data-label'))).toEqual([
      'إجمالي العملاء النشطين',
      'متوسط قيمة العميل',
    ])
    expect(cards.map(card => card.textContent)).toEqual(['12', '250 ج.م'])
    expect(cards[0]).toHaveAttribute('data-secondary-label', 'خامدون')
    expect(cards[0]).toHaveAttribute('data-secondary-value', '3')
    expect(cards[1]).toHaveAttribute('data-subtitle', 'آخر 90 يوماً')
    expect(cards[1]).toHaveAttribute('data-secondary-label', 'متوسط أيام الخمود')
    expect(cards[1]).toHaveAttribute('data-secondary-value', '18 يوم')
  })

  it('preserves customer trust, freshness, stale state and domain wiring on both customer-health cards', () => {
    mocks.useTrustForComponent.mockImplementation((_rows, component: string) => (
      component === 'snapshot_customer_health'
        ? { status: 'SUCCESS', last_completed_at: '2026-09-21T12:00:00Z', is_stale: true }
        : null
    ))

    const { container } = renderPage()
    const customerGrid = container.querySelectorAll('[data-metric-grid]')[1] as HTMLElement
    const cards = within(customerGrid).getAllByTestId('report-metric-card')

    cards.forEach(card => {
      expect(card).toHaveAttribute('data-status', 'SUCCESS')
      expect(card).toHaveAttribute('data-last-completed-at', '2026-09-21T12:00:00Z')
      expect(card).toHaveAttribute('data-is-stale', 'true')
      expect(card).toHaveAttribute('data-domain', 'customers')
    })
  })

  it('keeps the existing four-card loading state inside the shared summary grid', () => {
    mocks.useSalesSummary.mockReturnValue({ data: null, isLoading: true })

    const { container } = renderPage()
    const grid = container.querySelector('[data-metric-grid]') as HTMLElement

    expect(within(grid).getAllByTestId('skeleton-card')).toHaveLength(4)
    expect(within(grid).queryByTestId('report-metric-card')).toBeNull()
  })

  it('keeps the customer-health loading branch as one 120px skeleton without mounting the customer grid', () => {
    mocks.useCustomerHealthSummary.mockReturnValue({ data: null, isLoading: true })

    const { container, getAllByTestId } = renderPage()
    const metricGrids = container.querySelectorAll('[data-metric-grid]')
    expect(metricGrids).toHaveLength(1)

    const skeletons = getAllByTestId('skeleton-card')
    expect(skeletons).toHaveLength(1)
    expect(skeletons[0]).toHaveAttribute('data-height', '120')

    const readyCards = within(metricGrids[0] as HTMLElement).getAllByTestId('report-metric-card')
    expect(readyCards.map(card => card.getAttribute('data-label'))).not.toContain('إجمالي العملاء النشطين')
    expect(readyCards.map(card => card.getAttribute('data-label'))).not.toContain('متوسط قيمة العميل')
  })
})
