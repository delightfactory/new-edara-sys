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
  default: ({ label }: { label: string }) => <div data-testid="metric-card">{label}</div>,
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

vi.mock('@/components/reports/TrustStateBadge', () => ({
  default: ({ status }: { status: string }) => <span data-testid="trust-state-badge">{status}</span>,
}))

vi.mock('@/components/reports/FreshnessIndicator', () => ({
  default: () => <span data-testid="freshness-indicator">freshness</span>,
}))

vi.mock('recharts', () => ({
  ResponsiveContainer: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  AreaChart: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  Area: () => null,
  XAxis: () => null,
  YAxis: () => null,
  Tooltip: () => null,
  CartesianGrid: () => null,
  BarChart: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  Bar: () => null,
}))

const trustByComponent: Record<string, { status: string; last_completed_at: string; is_stale: boolean }> = {
  fact_sales_daily_grain: { status: 'OK', last_completed_at: '2026-09-19T00:00:00Z', is_stale: false },
  'fact_sales_daily_grain.revenue': { status: 'OK', last_completed_at: '2026-09-19T00:00:00Z', is_stale: false },
  'fact_sales_daily_grain.tax': { status: 'OK', last_completed_at: '2026-09-19T00:00:00Z', is_stale: false },
  'fact_sales_daily_grain.ar_creation': { status: 'OK', last_completed_at: '2026-09-19T00:00:00Z', is_stale: false },
}

describe('Sales report revenue chart composition', () => {
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

  it('uses exactly one shared ChartPanel for the first chart while preserving its title, description, trust action and empty state', () => {
    const { container } = render(<SalesPage />)

    const heading = screen.getByRole('heading', { level: 3, name: 'تطور الإيراد اليومي' })
    const panel = heading.closest('.ds-chart-panel') as HTMLElement

    expect(panel).not.toBeNull()
    expect(container.querySelectorAll('.ds-chart-panel')).toHaveLength(1)
    expect(within(panel).getByText('صافي إيراد + قيمة مرتجعات — مجمّع يومياً في قاعدة البيانات')).not.toBeNull()
    expect(within(panel).getByTestId('trust-state-badge').textContent).toBe('OK')
    expect(within(panel).getByTestId('freshness-indicator')).not.toBeNull()
    expect(within(panel).getByText('لا توجد بيانات في النطاق الزمني المحدد')).not.toBeNull()
    expect(screen.getByText('توزيع الإيرادات اليومي (إيراد + ضريبة)').closest('.ds-chart-panel')).toBeNull()
  })

  it('keeps the existing blocked chart state inside the shared panel', () => {
    mocks.useTrustForComponent.mockImplementation((_rows: unknown, component: string) => {
      if (component === 'fact_sales_daily_grain.revenue') {
        return { ...trustByComponent[component], status: 'BLOCKED' }
      }
      return trustByComponent[component] ?? null
    })

    render(<SalesPage />)

    const panel = screen.getByRole('heading', { level: 3, name: 'تطور الإيراد اليومي' }).closest('.ds-chart-panel') as HTMLElement
    expect(within(panel).getByText('المخطط محجوب')).not.toBeNull()
    expect(within(panel).getByText('لا يمكن عرض بيانات الإيراد حتى اكتمال المطابقة المحاسبية')).not.toBeNull()
  })
})
