import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render } from '@testing-library/react'
import ChurnRiskPage from './ChurnRiskPage'

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
  default: () => <span data-testid="trust-state-badge" />,
}))

vi.mock('@/components/reports/FreshnessIndicator', () => ({
  default: () => <span data-testid="freshness-indicator" />,
}))

vi.mock('@/components/patterns/ChartPanel', () => ({
  default: ({ children }: { children: React.ReactNode }) => <section data-testid="chart-panel">{children}</section>,
}))

vi.mock('@/components/patterns/ResponsiveCollection', () => ({
  default: () => <div data-testid="responsive-collection" />,
}))

vi.mock('recharts', () => ({
  ResponsiveContainer: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  PieChart: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  Pie: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  Cell: () => <span />,
  Tooltip: () => <span />,
  Legend: () => <span />,
}))

const populatedStats = {
  total: 1500,
  vip: 1234,
  loyal: 210,
  engaged: 42,
  at_risk: 13,
  dormant: 1,
  avg_rfm_score: 300,
}

function setDefaultMocks() {
  mocks.useSystemTrustState.mockReturnValue({ data: [], isLoading: false, error: null })
  mocks.useTrustForComponent.mockReturnValue(undefined)
  mocks.useCustomerRiskSummary.mockReturnValue({ data: populatedStats, isLoading: false })
  mocks.useCustomerRiskList.mockReturnValue({ data: [], isLoading: false })
}

function getMetricGrid(container: HTMLElement) {
  return container.querySelector('.ds-metric-grid[data-columns="3"]') as HTMLElement
}

describe('ChurnRisk KPI summary convergence', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    setDefaultMocks()
  })

  it('renders the five shared StatCards in exact risk order with semantic tones and unchanged formatted values', () => {
    const { container } = render(<ChurnRiskPage />)

    const grid = getMetricGrid(container)
    expect(grid).not.toBeNull()

    const cards = Array.from(grid.querySelectorAll('.ds-stat-card')) as HTMLElement[]
    expect(cards).toHaveLength(5)
    expect(cards.map(card => card.querySelector('.ds-stat-card__label')?.textContent)).toEqual([
      'VIP',
      'مخلص',
      'متفاعل',
      'معرض للخطر',
      'خامد',
    ])
    expect(cards.map(card => card.querySelector('.ds-stat-card__value')?.textContent)).toEqual([
      '1,234',
      '210',
      '42',
      '13',
      '1',
    ])
    expect(cards.map(card => card.getAttribute('data-tone'))).toEqual([
      'neutral',
      'success',
      'info',
      'warning',
      'danger',
    ])
    expect(grid.querySelectorAll('[data-testid="skeleton-card"]')).toHaveLength(0)
  })

  it('preserves the ready-state fallback when summary data is unavailable', () => {
    mocks.useCustomerRiskSummary.mockReturnValue({ data: undefined, isLoading: false })

    const { container } = render(<ChurnRiskPage />)

    const grid = getMetricGrid(container)
    const cards = Array.from(grid.querySelectorAll('.ds-stat-card')) as HTMLElement[]
    expect(cards).toHaveLength(5)
    expect(cards.map(card => card.querySelector('.ds-stat-card__value')?.textContent)).toEqual([
      '—',
      '—',
      '—',
      '—',
      '—',
    ])
  })

  it('keeps the exact statsLoading gate with five 120px skeletons inside the shared grid and no ready StatCards', () => {
    mocks.useCustomerRiskSummary.mockReturnValue({ data: populatedStats, isLoading: true })

    const { container, getAllByTestId } = render(<ChurnRiskPage />)

    const grid = getMetricGrid(container)
    expect(grid).not.toBeNull()
    expect(grid.querySelectorAll('.ds-stat-card')).toHaveLength(0)

    const skeletons = getAllByTestId('skeleton-card')
    expect(skeletons).toHaveLength(5)
    skeletons.forEach(skeleton => expect(skeleton.getAttribute('data-height')).toBe('120'))
  })
})
