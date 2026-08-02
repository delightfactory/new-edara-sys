import { fireEvent, render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import GoalCommandCenter from './GoalCommandCenter'

const navigateMock = vi.fn()
const useTargetsMock = vi.fn()
const useContributionsMock = vi.fn()
const refetchTargetsMock = vi.fn()
const refetchContributionsMock = vi.fn()

vi.mock('react-router-dom', () => ({ useNavigate: () => navigateMock }))
vi.mock('@/stores/auth-store', () => ({
  useAuthStore: (selector: (state: unknown) => unknown) => selector({
    can: (permission: string) => permission === 'targets.read_all',
  }),
}))
vi.mock('@/hooks/useQueryHooks', () => ({
  useTargets: (...args: unknown[]) => useTargetsMock(...args),
  useTargetEmployeeContributions: (...args: unknown[]) => useContributionsMock(...args),
}))

const departmentTarget = {
  id: 'target-sales',
  type_id: 'type-sales',
  type_code: 'sales_value',
  name: 'هدف مبيعات قسم المبيعات',
  description: null,
  scope: 'department',
  scope_id: 'sales-dept',
  period: 'monthly',
  period_start: '2026-08-01',
  period_end: '2026-08-31',
  target_value: 700000,
  min_value: null,
  stretch_value: null,
  product_id: null,
  category_id: null,
  governorate_id: null,
  city_id: null,
  area_id: null,
  dormancy_days: null,
  filter_criteria: {},
  parent_target_id: null,
  auto_split: false,
  split_basis: null,
  is_paused: false,
  paused_at: null,
  paused_reason: null,
  assigned_by: 'user-1',
  is_active: true,
  notes: null,
  reward_type: null,
  reward_base_value: null,
  reward_pool_basis: null,
  auto_payout: false,
  payout_month_offset: 0,
  created_at: '2026-08-01T00:00:00Z',
  updated_at: '2026-08-01T00:00:00Z',
  target_type: { id: 'type-sales', name: 'قيمة المبيعات', code: 'sales_value', unit: 'currency', category: 'sales' },
  latest_progress: {
    id: 'progress-1', target_id: 'target-sales', snapshot_date: '2026-08-02',
    achieved_value: 175000, achievement_pct: 25, trend: 'on_track',
    last_calc_at: '2026-08-02T10:00:00Z', calc_details: { expected_pct: 6.45 },
  },
}

describe('GoalCommandCenter', () => {
  beforeEach(() => {
    vi.useRealTimers()
    navigateMock.mockReset()
    refetchTargetsMock.mockReset()
    refetchContributionsMock.mockReset()
    useTargetsMock.mockReturnValue({
      data: { data: [departmentTarget] }, isLoading: false, isError: false,
      refetch: refetchTargetsMock,
    })
    useContributionsMock.mockReturnValue({
      data: [{
        employee_id: 'employee-1', employee_name: 'أحمد محمد', achieved_value: 175000,
        contribution_share_pct: 100, target_share_pct: 25, contribution_rank: 1,
      }],
      isLoading: false,
      isError: false,
      refetch: refetchContributionsMock,
    })
  })

  it('requests only genuinely current, active and unpaused targets', () => {
    render(<GoalCommandCenter />)

    expect(useTargetsMock).toHaveBeenCalledWith(
      expect.objectContaining({ is_active: true, is_paused: false, active_on: expect.any(String) }),
      { page: 1, pageSize: 30 },
    )
    expect(screen.getByText('هدف مبيعات قسم المبيعات')).not.toBeNull()
    expect(screen.getByText('25%')).not.toBeNull()
  })

  it('shows exact team contribution and opens the goal details', () => {
    render(<GoalCommandCenter />)

    expect(screen.getByText('مساهمة الفريق')).not.toBeNull()
    expect(screen.getByText('أحمد محمد')).not.toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'فتح تفاصيل هدف هدف مبيعات قسم المبيعات' }))
    expect(navigateMock).toHaveBeenCalledWith('/activities/targets/target-sales')
  })

  it('renders a useful empty state when the user has no current goals', () => {
    useTargetsMock.mockReturnValue({
      data: { data: [] }, isLoading: false, isError: false, refetch: refetchTargetsMock,
    })
    render(<GoalCommandCenter />)

    expect(screen.getByText('لا توجد أهداف جارية مخصّصة لك أو لفريقك اليوم.')).not.toBeNull()
  })

  it('never disguises a target query failure as an empty target list', () => {
    useTargetsMock.mockReturnValue({
      data: undefined, isLoading: false, isError: true, refetch: refetchTargetsMock,
    })
    render(<GoalCommandCenter />)

    expect(screen.getByText('تعذّر تحميل الأهداف')).not.toBeNull()
    expect(screen.queryByText('لا توجد أهداف جارية مخصّصة لك أو لفريقك اليوم.')).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: /إعادة المحاولة/ }))
    expect(refetchTargetsMock).toHaveBeenCalledTimes(1)
  })

  it('shows contribution failures separately and supports retry', () => {
    useContributionsMock.mockReturnValue({
      data: undefined, isLoading: false, isError: true, refetch: refetchContributionsMock,
    })
    render(<GoalCommandCenter />)

    expect(screen.getByText('تعذّر تحميل مساهمات الفريق.')).not.toBeNull()
    fireEvent.click(screen.getByRole('button', { name: /إعادة المحاولة/ }))
    expect(refetchContributionsMock).toHaveBeenCalledTimes(1)
  })

  it('matches the canonical inclusive day calculation when no snapshot exists', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-08-02T12:00:00+03:00'))
    useTargetsMock.mockReturnValue({
      data: { data: [{ ...departmentTarget, latest_progress: null }] },
      isLoading: false, isError: false, refetch: refetchTargetsMock,
    })
    render(<GoalCommandCenter />)

    expect(screen.getByText('المفترض اليوم 6.45%')).not.toBeNull()
  })

  it('uses a semantic overlay action instead of wrapping headings inside a button', () => {
    const { container } = render(<GoalCommandCenter />)

    expect(container.querySelector('article.gcc-hero')).not.toBeNull()
    expect(container.querySelector('button.gcc-hero-action h3')).toBeNull()
  })
})
