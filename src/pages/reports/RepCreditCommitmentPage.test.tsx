import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import RepCreditCommitmentPage from './RepCreditCommitmentPage'

const mocks = vi.hoisted(() => ({
  useQuery: vi.fn(),
}))

vi.mock('@tanstack/react-query', () => ({
  useQuery: mocks.useQuery,
}))

vi.mock('@/features/output/components/DocumentActions', () => ({
  DocumentActions: () => <div data-testid="document-actions" />,
}))

vi.mock('@/components/shared/CustomerCreditChip', () => ({
  computeCreditState: () => ({ type: 'credit', usedPct: 0 }),
}))

const rows = [
  {
    rep_id: 'rep-1',
    rep_name: 'أحمد',
    is_unassigned: false,
    sort_order: 0,
    portfolio_balance: 1000,
    customers_count: 3,
    customers_with_balance: 2,
    overdue_customers_count: 1,
    created_debt: 600,
    confirmed_collections: 250,
  },
  {
    rep_id: null,
    rep_name: 'غير مسند',
    is_unassigned: true,
    sort_order: 1,
    portfolio_balance: 300,
    customers_count: 1,
    customers_with_balance: 1,
    overdue_customers_count: 0,
    created_debt: 0,
    confirmed_collections: 0,
  },
]

describe('Rep Credit Commitment summary composition', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    Object.defineProperty(window, 'innerWidth', {
      configurable: true,
      writable: true,
      value: 1280,
    })
    mocks.useQuery.mockReturnValue({
      data: { rows },
      isLoading: false,
      error: null,
    })
  })

  it('uses the shared four-column MetricGrid and preserves exact filtered KPI order and values', () => {
    const { container } = render(<RepCreditCommitmentPage />)

    const grid = container.querySelector('[data-metric-grid]') as HTMLElement
    expect(grid).not.toBeNull()
    expect(grid.getAttribute('data-columns')).toBe('4')
    expect(grid.classList.contains('ds-metric-grid--cols-4')).toBe(true)
    expect(grid.children).toHaveLength(4)

    const cards = Array.from(grid.children) as HTMLElement[]
    expect(cards.map(card => card.querySelector('span')?.textContent)).toEqual([
      'مسؤولو المحافظ',
      'إجمالي محافظ المتابعة',
      'إجمالي المديونية المنشأة',
      'إجمالي التحصيلات المؤكدة',
    ])

    expect(within(cards[0]).getByText('1')).not.toBeNull()
    expect(within(cards[0]).getByText('لديهم عملاء بأرصدة فعلية')).not.toBeNull()
    expect(within(cards[1]).getByText('1,300.00')).not.toBeNull()
    expect(within(cards[1]).getByText('يشمل الأرصدة الافتتاحية')).not.toBeNull()
    expect(within(cards[2]).getByText('600.00')).not.toBeNull()
    expect(within(cards[2]).getByText('فواتير مسلَّمة صافيها > 0')).not.toBeNull()
    expect(within(cards[3]).getByText('250.00')).not.toBeNull()
    expect(within(cards[3]).getByText('إيصالات confirmed فقط')).not.toBeNull()

    const warningHeading = screen.getByText('أرصدة بدون مسؤول متابعة:')
    const warningContent = warningHeading.parentElement as HTMLElement
    expect(grid.contains(warningHeading)).toBe(false)
    expect(within(warningContent).getByText('300.00')).not.toBeNull()
    expect(within(warningContent).getByText(/عملاء غير مسندين لأي مسؤول/)).not.toBeNull()
  })

  it('keeps exactly four 6rem loading placeholders in the shared grid without replacing table loading', () => {
    mocks.useQuery.mockReturnValue({
      data: undefined,
      isLoading: true,
      error: null,
    })

    const { container } = render(<RepCreditCommitmentPage />)

    const grid = container.querySelector('[data-metric-grid]') as HTMLElement
    expect(grid).not.toBeNull()
    expect(grid.getAttribute('data-columns')).toBe('4')
    expect(grid.children).toHaveLength(4)

    Array.from(grid.children).forEach(child => {
      const placeholder = child as HTMLElement
      expect(placeholder.style.height).toBe('6rem')
      expect(placeholder.style.background).toBe('var(--bg-surface-2)')
      expect(placeholder.style.animation).toBe('shimmer 1.5s infinite')
    })

    expect(screen.getByRole('table')).not.toBeNull()
    expect(screen.queryByText('مسؤولو المحافظ')).toBeNull()
  })

  it('keeps the summary grid absent for the existing empty filtered state', () => {
    mocks.useQuery.mockReturnValue({
      data: { rows: [] },
      isLoading: false,
      error: null,
    })

    const { container } = render(<RepCreditCommitmentPage />)

    expect(container.querySelector('[data-metric-grid]')).toBeNull()
    expect(screen.getByText('لا توجد بيانات مطابقة للفلتر')).not.toBeNull()
  })
})
