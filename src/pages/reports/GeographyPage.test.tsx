import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import GeographyPage from './GeographyPage'

const mocks = vi.hoisted(() => ({
  useSystemTrustState: vi.fn(),
  useTrustForComponent: vi.fn(),
  useGeographySummary: vi.fn(),
  useGeographyTable: vi.fn(),
}))

vi.mock('@/hooks/useSystemTrustState', () => ({
  useSystemTrustState: mocks.useSystemTrustState,
  useTrustForComponent: mocks.useTrustForComponent,
}))

vi.mock('@/hooks/useGeographyPerformance', () => ({
  useGeographySummary: mocks.useGeographySummary,
  useGeographyTable: mocks.useGeographyTable,
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

describe('Geography analysis-level selector convergence', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.useSystemTrustState.mockReturnValue({ data: [], isLoading: false, error: null })
    mocks.useTrustForComponent.mockReturnValue(null)
    mocks.useGeographySummary.mockReturnValue({
      data: { total_revenue: 1200, covered_areas: 3 },
      isLoading: false,
    })
    mocks.useGeographyTable.mockReturnValue({ data: [], isLoading: false })
  })

  it('uses the shared Select field contract with the exact accessible Arabic options', () => {
    render(<GeographyPage />)

    const select = screen.getByRole('combobox', { name: 'مستوى التحليل الجغرافي' }) as HTMLSelectElement
    const options = within(select).getAllByRole('option') as HTMLOptionElement[]

    expect(select.classList.contains('form-select')).toBe(true)
    expect(select.closest('.ds-field')).not.toBeNull()
    expect(select.getAttribute('style')).toBeNull()
    expect(options.map(option => [option.value, option.textContent])).toEqual([
      ['governorate', 'محافظة'],
      ['city', 'مدينة'],
      ['area', 'منطقة'],
    ])
    expect(select.value).toBe('governorate')
    expect(screen.getByTestId('report-filter-bar')).toBeTruthy()
  })

  it('keeps GeoLevel controlled by the page and forwards the unchanged filter shape after selection', () => {
    render(<GeographyPage />)

    const select = screen.getByRole('combobox', { name: 'مستوى التحليل الجغرافي' }) as HTMLSelectElement
    fireEvent.change(select, { target: { value: 'city' } })

    expect(select.value).toBe('city')
    expect(mocks.useGeographySummary).toHaveBeenLastCalledWith(expect.objectContaining({
      dateFrom: expect.any(String),
      dateTo: expect.any(String),
      level: 'city',
    }))
    expect(mocks.useGeographyTable).toHaveBeenLastCalledWith(expect.objectContaining({
      dateFrom: expect.any(String),
      dateTo: expect.any(String),
      level: 'city',
    }))
    expect(screen.getByText('مدينة مغطاة')).toBeTruthy()
    expect(screen.getByText('التوزيع حسب مدينة')).toBeTruthy()
  })
})
