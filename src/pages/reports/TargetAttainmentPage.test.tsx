import { act, render, screen, within } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import TargetAttainmentPage from './TargetAttainmentPage'

const mocks = vi.hoisted(() => ({
  useSystemTrustState: vi.fn(),
  useTrustForComponent: vi.fn(),
  useTargetAttainmentSummary: vi.fn(),
  useTargetAttainmentTable: vi.fn(),
}))

vi.mock('@/hooks/useSystemTrustState', () => ({
  useSystemTrustState: mocks.useSystemTrustState,
  useTrustForComponent: mocks.useTrustForComponent,
}))

vi.mock('@/hooks/useTargetAttainment', () => ({
  useTargetAttainmentSummary: mocks.useTargetAttainmentSummary,
  useTargetAttainmentTable: mocks.useTargetAttainmentTable,
}))

vi.mock('@/components/reports/MetricCard', () => ({
  default: ({ label }: { label: string }) => <div data-testid="metric-card">{label}</div>,
}))

vi.mock('@/components/reports/SkeletonCard', () => ({
  default: ({ height }: { height: number }) => <div data-testid="skeleton-card" data-height={height} />,
}))

vi.mock('@/components/reports/SystemHealthBar', () => ({
  default: () => <div data-testid="system-health-bar" />,
}))

vi.mock('@/components/reports/TrustStateBadge', () => ({
  default: () => <span data-testid="trust-state-badge" />,
}))

vi.mock('@/components/reports/FreshnessIndicator', () => ({
  default: () => <span data-testid="freshness-indicator" />,
}))

vi.mock('recharts', () => ({
  ResponsiveContainer: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  BarChart: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  Bar: ({ children }: { children?: React.ReactNode }) => <div>{children}</div>,
  XAxis: () => null,
  YAxis: () => null,
  Tooltip: () => null,
  CartesianGrid: () => null,
  ReferenceLine: () => null,
  Cell: () => null,
}))

const longTargetName = 'هدف مبيعات سنوي باسم عربي طويل جداً لاختبار التفاف اسم الهدف داخل البطاقة بدون تجاوز أفقي'
const longTypeCode = 'نوع هدف تجاري طويل لاختبار الالتفاف'
const longRepName = 'مسؤول مبيعات باسم عربي طويل جداً لاختبار التفاف اسم المسؤول داخل البطاقة'
const longBranchName = 'فرع طنطا الرئيسي باسم عربي طويل جداً لاختبار التفاف اسم الفرع داخل البطاقة'

const detailRows = [
  {
    target_id: 'target-1',
    target_name: longTargetName,
    type_code: longTypeCode,
    rep_name: longRepName,
    branch_name: longBranchName,
    target_value: 100_000,
    achieved_value: 105_000,
    achievement_pct: 105,
    trend: 'exceeded',
    scope: 'branch',
  },
  {
    target_id: 'target-2',
    target_name: 'هدف إعادة تنشيط العملاء',
    type_code: 'customer_reactivation',
    rep_name: null,
    branch_name: null,
    target_value: 80_000,
    achieved_value: 68_000,
    achievement_pct: 85,
    trend: 'at_risk',
    scope: 'branch',
  },
  {
    target_id: 'target-3',
    target_name: 'هدف التغطية الجغرافية',
    type_code: 'coverage',
    rep_name: 'مندوب دلتا',
    branch_name: 'فرع المحلة',
    target_value: 50_000,
    achieved_value: 39_500,
    achievement_pct: 79,
    trend: 'غير_معروف',
    scope: 'branch',
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
  return screen.getByText('تفاصيل الأهداف').parentElement?.parentElement as HTMLElement
}

function getCardByTarget(targetName: string) {
  return screen.getByText(targetName).closest('.ds-card') as HTMLElement
}

describe('Target Attainment responsive detail collection', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    setViewport(1440)
    mocks.useSystemTrustState.mockReturnValue({
      data: [{ component_name: 'snapshot_target_attainment' }],
      isLoading: false,
      error: null,
    })
    mocks.useTrustForComponent.mockReturnValue({
      status: 'OK',
      last_completed_at: '2026-09-21T00:00:00Z',
      is_stale: false,
    })
    mocks.useTargetAttainmentSummary.mockReturnValue({
      data: {
        achieved: 1,
        on_track: 1,
        behind: 1,
        at_risk: 0,
        total_targets: 3,
        avg_achievement_pct: 90,
      },
      isLoading: false,
    })
    mocks.useTargetAttainmentTable.mockReturnValue({ data: detailRows, isLoading: false })
  })

  it('preserves the dense Desktop table, exact eight-column order, row order, fallbacks, semantic headers and achievement/trend truth', () => {
    render(<TargetAttainmentPage />)

    const section = getDetailSection()
    const table = within(section).getByRole('table')
    const headers = within(table).getAllByRole('columnheader')
    expect(headers.map(header => header.textContent)).toEqual([
      'الهدف',
      'النوع',
      'المسؤول',
      'الفرع',
      'المستهدف',
      'المحقق',
      'إنجاز%',
      'الاتجاه',
    ])
    headers.forEach(header => expect(header.getAttribute('scope')).toBe('col'))
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()

    const dataRows = within(table).getAllByRole('row').slice(1)
    expect(dataRows).toHaveLength(3)
    expect(within(dataRows[0]).getAllByRole('cell').map(cell => cell.textContent)).toEqual([
      longTargetName,
      longTypeCode,
      longRepName,
      longBranchName,
      '100,000 ج.م',
      '105,000 ج.م',
      '105%',
      'تجاوز الهدف',
    ])
    expect(within(dataRows[1]).getAllByRole('cell').map(cell => cell.textContent)).toEqual([
      'هدف إعادة تنشيط العملاء',
      'customer_reactivation',
      '—',
      '—',
      '80,000 ج.م',
      '68,000 ج.م',
      '85%',
      'معرض للخطر',
    ])
    expect(within(dataRows[2]).getByText('غير_معروف')).toBeTruthy()
    expect(within(dataRows[0]).getByText('105%').style.color).toBe('var(--color-success)')
    expect(within(dataRows[1]).getByText('85%').style.color).toBe('var(--color-warning)')
    expect(within(dataRows[2]).getByText('79%').style.color).toBe('var(--color-danger)')
    expect(within(dataRows[0]).getByText('100,000 ج.م').style.direction).toBe('ltr')
    expect(within(dataRows[0]).getByText('105,000 ج.م').style.direction).toBe('ltr')
    expect(within(dataRows[0]).getByText('105%').style.direction).toBe('ltr')
    expect(within(section).getByTestId('trust-state-badge')).toBeTruthy()
    expect(within(section).getByTestId('freshness-indicator')).toBeTruthy()
  })

  it('mounts only one-column Mobile passive cards with all eight facts, safe Arabic wrapping, LTR numeric values and preserved semantics', () => {
    setViewport(390)
    render(<TargetAttainmentPage />)

    const section = getDetailSection()
    expect(within(section).queryByRole('table')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--mobile')).not.toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--tablet')).toBeNull()
    expect(section.querySelector('.ds-key-value-list--cols-1')).not.toBeNull()

    const firstCard = getCardByTarget(longTargetName)
    expect(within(firstCard).getByText(longTargetName).style.overflowWrap).toBe('anywhere')
    expect(within(firstCard).getByText(longTypeCode).style.overflowWrap).toBe('anywhere')
    expect(within(firstCard).getByText(longRepName).style.overflowWrap).toBe('anywhere')
    expect(within(firstCard).getByText(longBranchName).style.overflowWrap).toBe('anywhere')
    ;['الهدف', 'النوع', 'المسؤول', 'الفرع', 'المستهدف', 'المحقق', 'إنجاز%', 'الاتجاه'].forEach(label => {
      expect(within(firstCard).getByText(label)).toBeTruthy()
    })
    expect(within(firstCard).getByText('100,000 ج.م').getAttribute('dir')).toBe('ltr')
    expect(within(firstCard).getByText('105,000 ج.م').getAttribute('dir')).toBe('ltr')
    expect(within(firstCard).getByText('105%').getAttribute('dir')).toBe('ltr')
    expect(within(firstCard).getByText('105%').style.color).toBe('var(--color-success)')
    expect(within(firstCard).getByText('تجاوز الهدف')).toBeTruthy()
    expect(within(firstCard).queryByRole('button')).toBeNull()
    expect(within(firstCard).queryByRole('link')).toBeNull()

    const fallbackCard = getCardByTarget('هدف إعادة تنشيط العملاء')
    expect(within(fallbackCard).getAllByText('—')).toHaveLength(2)
    expect(within(fallbackCard).getByText('85%').style.color).toBe('var(--color-warning)')
    expect(within(fallbackCard).getByText('معرض للخطر')).toBeTruthy()

    const unknownTrendCard = getCardByTarget('هدف التغطية الجغرافية')
    expect(within(unknownTrendCard).getByText('79%').style.color).toBe('var(--color-danger)')
    expect(within(unknownTrendCard).getByText('غير_معروف')).toBeTruthy()
  })

  it('uses deliberate two-column Tablet cards, preserves row ordering, and mounts no Desktop/Mobile renderer', () => {
    setViewport(900)
    render(<TargetAttainmentPage />)

    const section = getDetailSection()
    expect(within(section).queryByRole('table')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--tablet')).not.toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--mobile')).toBeNull()
    expect(section.querySelector('.ds-key-value-list--cols-2')).not.toBeNull()

    const cards = Array.from(section.querySelectorAll('.ds-card'))
    expect(cards).toHaveLength(3)
    expect(within(cards[0] as HTMLElement).getByText(longTargetName)).toBeTruthy()
    expect(within(cards[1] as HTMLElement).getByText('هدف إعادة تنشيط العملاء')).toBeTruthy()
    expect(within(cards[2] as HTMLElement).getByText('هدف التغطية الجغرافية')).toBeTruthy()
    expect(within(cards[0] as HTMLElement).getByText('105%').style.color).toBe('var(--color-success)')
    expect(within(cards[1] as HTMLElement).getByText('85%').style.color).toBe('var(--color-warning)')
    expect(within(cards[2] as HTMLElement).getByText('79%').style.color).toBe('var(--color-danger)')
  })

  it('preserves BLOCKED -> loading -> empty -> ready precedence, exact blocked/empty copy and five 44px skeleton rows', () => {
    setViewport(390)
    mocks.useTrustForComponent.mockReturnValue({
      status: 'BLOCKED',
      last_completed_at: '2026-09-21T00:00:00Z',
      is_stale: false,
    })
    mocks.useTargetAttainmentTable.mockReturnValue({ data: detailRows, isLoading: true })
    const { rerender } = render(<TargetAttainmentPage />)

    let section = getDetailSection()
    expect(within(section).getByText('بيانات الأهداف محجوبة')).toBeTruthy()
    expect(within(section).getByText('snapshot_target_attainment يحتاج تشغيل ناجح أولاً')).toBeTruthy()
    expect(within(section).queryByTestId('skeleton-card')).toBeNull()
    expect(section.querySelector('.ds-responsive-collection')).toBeNull()

    mocks.useTrustForComponent.mockReturnValue({
      status: 'OK',
      last_completed_at: '2026-09-21T00:00:00Z',
      is_stale: false,
    })
    rerender(<TargetAttainmentPage />)

    section = getDetailSection()
    const loadingCollection = section.querySelector('[data-collection-state="loading"]') as HTMLElement
    expect(loadingCollection).not.toBeNull()
    const loadingSkeletons = within(loadingCollection).getAllByTestId('skeleton-card')
    expect(loadingSkeletons).toHaveLength(5)
    loadingSkeletons.forEach(skeleton => expect(skeleton.getAttribute('data-height')).toBe('44'))
    expect(within(section).queryByRole('table')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()

    mocks.useTargetAttainmentTable.mockReturnValue({ data: [], isLoading: false })
    rerender(<TargetAttainmentPage />)

    section = getDetailSection()
    expect(section.querySelector('[data-collection-state="empty"]')).not.toBeNull()
    expect(within(section).getByText('لا توجد بيانات — شغّل watermark sweep أولاً')).toBeTruthy()
    expect(within(section).queryByRole('table')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
  })
})
