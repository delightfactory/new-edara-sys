import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, within } from '@testing-library/react'
import CustomerReengagementPage from './CustomerReengagementPage'

const mocks = vi.hoisted(() => ({
  setTitle: vi.fn(),
  useReengagementList: vi.fn(),
  useReengagementSummary: vi.fn(),
}))

vi.mock('@/components/layout/PageTitleContext', () => ({
  usePageTitle: () => ({ setTitle: mocks.setTitle }),
}))

vi.mock('@/hooks/useCustomerReengagement', () => ({
  useReengagementList: mocks.useReengagementList,
  useReengagementSummary: mocks.useReengagementSummary,
}))

vi.mock('@/hooks/useFilterState', () => ({
  useFilterState: () => ({
    filters: {
      dateFrom: '',
      dateTo: '',
      repId: '',
      governorateId: '',
      cityId: '',
      priority: '',
      customerType: '',
      activeOnly: true,
    },
    setFilter: vi.fn(),
    setFilters: vi.fn(),
    reset: vi.fn(),
    activeCount: 0,
  }),
}))

vi.mock('@/hooks/useQueryHooks', () => ({
  useGovernorates: () => ({ data: [] }),
  useCities: () => ({ data: [] }),
  useProfiles: () => ({ data: [] }),
}))

vi.mock('@/stores/auth-store', () => ({
  useAuthStore: (selector: (state: { can: () => boolean }) => unknown) => selector({ can: () => false }),
}))

vi.mock('@/components/shared/PageHeader', () => ({
  default: ({ title }: { title: string }) => <div data-testid="page-header">{title}</div>,
}))

vi.mock('@/components/shared/FilterBar', () => {
  const FilterBar = ({ children }: { children?: unknown }) => <div data-testid="filter-bar">{children as never}</div>
  FilterBar.Select = () => null
  FilterBar.DateRange = () => null
  FilterBar.Toggle = () => null
  return { default: FilterBar }
})

vi.mock('@/features/output/hooks/useDocumentOutput', () => ({
  useDocumentOutput: () => ({
    triggerPreview: vi.fn(),
    triggerPdfDownload: vi.fn(),
    busy: false,
    error: null,
    clearError: vi.fn(),
  }),
}))

vi.mock('@/lib/utils/export', () => ({
  downloadAsCSV: vi.fn(),
}))

const summary = {
  total_customers: 1234,
  champion_lost_count: 12,
  declining_high_count: 34,
  mid_lost_count: 56,
  mid_at_risk_count: 78,
  other_count: 90,
  total_outstanding: 98765,
  avg_historical_revenue: 5000,
  avg_recency_days: 42,
}

function getMetricCards() {
  const grid = document.querySelector('[data-metric-grid]') as HTMLElement
  expect(grid).not.toBeNull()
  expect(grid.getAttribute('data-columns')).toBe('3')
  return { grid, cards: Array.from(grid.querySelectorAll('.ds-stat-card')) as HTMLElement[] }
}

function cardPart(card: HTMLElement, selector: string) {
  return card.querySelector(selector)?.textContent
}

describe('Customer Re-engagement KPI summary convergence', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.useReengagementList.mockReturnValue({
      data: [],
      isLoading: false,
      error: null,
    })
    mocks.useReengagementSummary.mockReturnValue({
      data: summary,
      isLoading: false,
    })
  })

  it('uses the shared three-column metric grammar while preserving exact KPI order, copy, values, icons, and tones', () => {
    render(<CustomerReengagementPage />)

    const { grid, cards } = getMetricCards()
    expect(grid.classList.contains('ds-metric-grid--cols-3')).toBe(true)
    expect(cards).toHaveLength(5)

    expect(cards.map(card => cardPart(card, '.ds-stat-card__label'))).toEqual([
      'Champion Lost',
      'تراجع عالي',
      'متوسط خامد',
      'إجمالي العملاء',
      'صافي الأرصدة',
    ])
    expect(cards.map(card => cardPart(card, '.ds-stat-card__context'))).toEqual([
      'عملاء مميزون خمدوا',
      'عملاء في خطر',
      'فرصة متوسطة',
      'في قاعدة البيانات',
      'إجمالي مديونية',
    ])
    expect(cards.map(card => cardPart(card, '.ds-stat-card__value'))).toEqual([
      '12',
      '34',
      '56',
      '1,234',
      '98,765 ج.م',
    ])
    expect(cards.map(card => cardPart(card, '.ds-stat-card__icon'))).toEqual(['🔴', '🟠', '🟡', '👥', '💰'])
    expect(cards.map(card => card.getAttribute('data-tone'))).toEqual([
      'danger',
      'warning',
      'warning',
      'info',
      'info',
    ])

    expect(document.querySelector('.rp-kpi-grid')).toBeNull()
    expect(document.querySelector('.rp-kpi-card')).toBeNull()
  })

  it('preserves the credit-balance sign semantics while mapping its presentation to success', () => {
    mocks.useReengagementSummary.mockReturnValue({
      data: { ...summary, total_outstanding: -4321 },
      isLoading: false,
    })

    render(<CustomerReengagementPage />)

    const { cards } = getMetricCards()
    const balanceCard = cards[4]
    expect(cardPart(balanceCard, '.ds-stat-card__context')).toBe('رصيد دائن صاف')
    expect(cardPart(balanceCard, '.ds-stat-card__value')).toBe('4,321 ج.م')
    expect(cardPart(balanceCard, '.ds-stat-card__icon')).toBe('🟢')
    expect(balanceCard.getAttribute('data-tone')).toBe('success')
  })

  it('keeps all five metric identities and contexts visible while loading only the value layer', () => {
    mocks.useReengagementSummary.mockReturnValue({
      data: summary,
      isLoading: true,
    })

    render(<CustomerReengagementPage />)

    const { grid, cards } = getMetricCards()
    expect(cards).toHaveLength(5)
    expect(cards.map(card => cardPart(card, '.ds-stat-card__label'))).toEqual([
      'Champion Lost',
      'تراجع عالي',
      'متوسط خامد',
      'إجمالي العملاء',
      'صافي الأرصدة',
    ])
    expect(cards.map(card => cardPart(card, '.ds-stat-card__context'))).toEqual([
      'عملاء مميزون خمدوا',
      'عملاء في خطر',
      'فرصة متوسطة',
      'في قاعدة البيانات',
      'إجمالي مديونية',
    ])

    const skeletons = within(grid).getAllByRole('generic').filter(node => node.classList.contains('rp-kpi-skeleton'))
    expect(skeletons).toHaveLength(5)
    skeletons.forEach(skeleton => expect(skeleton.getAttribute('aria-hidden')).toBe('true'))
    cards.forEach(card => expect(card.querySelector('.ds-stat-card__value .rp-kpi-skeleton')).not.toBeNull())
  })
})
