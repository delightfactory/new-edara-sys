import type { ReactNode } from 'react'
import { act, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import ProductPerformancePage from './ProductPerformancePage'

const mocks = vi.hoisted(() => ({
  useSystemTrustState: vi.fn(),
  useTrustForComponent: vi.fn(),
  useProductPerformanceSummary: vi.fn(),
  useProductPerformanceTable: vi.fn(),
  rpc: vi.fn(),
}))

vi.mock('@/hooks/useSystemTrustState', () => ({
  useSystemTrustState: mocks.useSystemTrustState,
  useTrustForComponent: mocks.useTrustForComponent,
}))

vi.mock('@/hooks/useProductPerformance', () => ({
  useProductPerformanceSummary: mocks.useProductPerformanceSummary,
  useProductPerformanceTable: mocks.useProductPerformanceTable,
}))

vi.mock('@/lib/supabase/client', () => ({
  supabase: { rpc: mocks.rpc },
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

vi.mock('@/components/reports/ReportFilterBar', () => ({
  default: () => <div data-testid="report-filter-bar" />,
}))

vi.mock('@/components/reports/TrustStateBadge', () => ({
  default: () => <span data-testid="trust-state-badge" />,
}))

vi.mock('@/components/reports/FreshnessIndicator', () => ({
  default: () => <span data-testid="freshness-indicator" />,
}))

vi.mock('recharts', () => ({
  ResponsiveContainer: ({ children }: { children: ReactNode }) => <div>{children}</div>,
  BarChart: ({ children }: { children: ReactNode }) => <div>{children}</div>,
  Bar: () => null,
  XAxis: () => null,
  YAxis: () => null,
  Tooltip: () => null,
  CartesianGrid: () => null,
}))

const rows = [
  {
    product_id: 'product-1',
    product_name: 'منتج طويل للاختبار بدون قص النص الأساسي',
    category_name: 'تصنيف تجريبي طويل',
    net_revenue: 1234,
    net_qty: 12,
    return_rate_pct: 12,
    distinct_customers: 7,
    revenue_share_pct: 40,
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
  return screen.getByText('تفاصيل المنتجات — أعلى 50 حسب الإيراد').parentElement as HTMLElement
}

describe('Product Performance responsive detail collection', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.rpc.mockReturnValue({ then: () => undefined })
    mocks.useSystemTrustState.mockReturnValue({ data: [], isLoading: false, error: null })
    mocks.useTrustForComponent.mockReturnValue({ status: 'OK', last_completed_at: '2026-09-19T00:00:00Z', is_stale: false })
    mocks.useProductPerformanceSummary.mockReturnValue({
      data: { total_revenue: 1234, total_products: 1, top_product_revenue: 1234 },
      isLoading: false,
    })
    mocks.useProductPerformanceTable.mockReturnValue({ data: rows, isLoading: false })
  })

  it('preserves the semantic seven-column desktop table and mounts no detail-card renderer', () => {
    setViewport(1440)
    render(<ProductPerformancePage />)

    const section = getDetailSection()
    const table = within(section).getByRole('table')
    const headers = within(table).getAllByRole('columnheader')

    expect(headers.map(header => header.textContent)).toEqual([
      'المنتج',
      'التصنيف',
      'الإيراد',
      'الكمية',
      'نسبة المرتجع',
      'عملاء',
      'الحصة%',
    ])
    headers.forEach(header => expect(header.getAttribute('scope')).toBe('col'))
    expect(within(table).getByText(rows[0].product_name)).toBeTruthy()
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
  })

  it('mounts only the one-column detail-card composition on Mobile with all seven source fields represented', () => {
    setViewport(390)
    render(<ProductPerformancePage />)

    const section = getDetailSection()
    expect(within(section).queryByRole('table')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--mobile')).not.toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--tablet')).toBeNull()
    expect(within(section).getByText(rows[0].product_name)).toBeTruthy()
    expect(within(section).getByText(rows[0].category_name)).toBeTruthy()

    ;['الإيراد', 'الكمية', 'نسبة المرتجع', 'عملاء', 'الحصة%'].forEach(label => {
      expect(within(section).getByText(label)).toBeTruthy()
    })

    expect(within(section).getByText('1,234 ج.م')).toBeTruthy()
    expect(within(section).getByText('12%').style.color).toBe('var(--color-danger)')
    expect(section.querySelector('.ds-key-value-list--cols-1')).not.toBeNull()
  })

  it('uses the same detail-card anatomy deliberately on Tablet with denser labeled metadata', () => {
    setViewport(900)
    render(<ProductPerformancePage />)

    const section = getDetailSection()
    expect(within(section).queryByRole('table')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--tablet')).not.toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--mobile')).toBeNull()
    expect(section.querySelector('.ds-key-value-list--cols-2')).not.toBeNull()
    expect(within(section).getByText(rows[0].product_name)).toBeTruthy()
  })

  it('preserves the custom five-row loading state and exact empty copy without mounting any renderer', () => {
    setViewport(390)
    mocks.useProductPerformanceTable.mockReturnValue({ data: [], isLoading: true })
    const { rerender } = render(<ProductPerformancePage />)

    let section = getDetailSection()
    expect(within(section).getAllByTestId('skeleton-card')).toHaveLength(5)
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
    expect(within(section).queryByRole('table')).toBeNull()

    mocks.useProductPerformanceTable.mockReturnValue({ data: [], isLoading: false })
    rerender(<ProductPerformancePage />)

    section = getDetailSection()
    expect(within(section).getByText('لا توجد بيانات')).toBeTruthy()
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
    expect(within(section).queryByRole('table')).toBeNull()
  })
})
