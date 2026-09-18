import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import SupervisorWorkPage from './SupervisorWorkPage'

const mocks = vi.hoisted(() => ({
  navigate: vi.fn(),
  useSupervisorOverview: vi.fn(),
}))

vi.mock('react-router-dom', () => ({
  useNavigate: () => mocks.navigate,
}))

vi.mock('@/features/work/supervisor', () => ({
  useSupervisorOverview: mocks.useSupervisorOverview,
}))

const rows = [
  {
    work_item_id: 'work-1',
    work_number: 101,
    title: 'مراجعة طلب العميل',
    status: 'open',
    current_assignee_user_id: 'user-1',
    assignee_name: 'أحمد',
    owner_name: 'أحمد',
    is_overdue: true,
    is_blocked: false,
    is_at_risk: false,
    is_stale: false,
    is_follow_up_due: false,
    is_escalated: false,
    next_action_text: null,
    due_at: null,
    next_action_at: null,
  },
  {
    work_item_id: 'work-2',
    work_number: 102,
    title: 'اعتماد متابعة المخزون',
    status: 'waiting',
    current_assignee_user_id: 'user-1',
    assignee_name: 'أحمد',
    owner_name: 'مدير الفريق',
    is_overdue: false,
    is_blocked: true,
    is_at_risk: true,
    is_stale: false,
    is_follow_up_due: false,
    is_escalated: false,
    next_action_text: null,
    due_at: null,
    next_action_at: null,
  },
  {
    work_item_id: 'work-3',
    work_number: 103,
    title: 'تجهيز مستندات المتابعة',
    status: 'in_progress',
    current_assignee_user_id: 'user-2',
    assignee_name: 'محمد',
    owner_name: 'محمد',
    is_overdue: false,
    is_blocked: true,
    is_at_risk: false,
    is_stale: false,
    is_follow_up_due: false,
    is_escalated: false,
    next_action_text: null,
    due_at: null,
    next_action_at: null,
  },
  {
    work_item_id: 'work-4',
    work_number: 104,
    title: 'متابعة تنفيذ الإجراء',
    status: 'pending_approval',
    current_assignee_user_id: 'user-2',
    assignee_name: 'محمد',
    owner_name: 'محمد',
    is_overdue: false,
    is_blocked: false,
    is_at_risk: false,
    is_stale: false,
    is_follow_up_due: false,
    is_escalated: false,
    next_action_text: null,
    due_at: null,
    next_action_at: null,
  },
]

describe('SupervisorWorkPage V2 operational summary metrics', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.useSupervisorOverview.mockReturnValue({
      data: rows,
      isLoading: false,
      error: null,
    })
  })

  it('renders the exact four supervisor metrics through shared MetricGrid and StatCard semantics', () => {
    render(<SupervisorWorkPage />)

    const group = screen.getByRole('group', { name: 'ملخص حالة أعمال الفريق' })
    const cards = Array.from(group.querySelectorAll('.ds-stat-card'))

    expect(group.className).toContain('ds-metric-grid')
    expect(group.className).toContain('ds-metric-grid--cols-4')
    expect(group.getAttribute('data-columns')).toBe('4')
    expect(cards).toHaveLength(4)
    expect(cards.map(card => card.querySelector('.ds-stat-card__label')?.textContent)).toEqual([
      'عمل نشط',
      'متأخر',
      'معطل',
      'معرض للخطر',
    ])
    expect(cards.map(card => card.querySelector('.ds-stat-card__value')?.textContent)).toEqual([
      '4',
      '1',
      '2',
      '1',
    ])
    expect(cards.map(card => card.getAttribute('data-tone'))).toEqual([
      'neutral',
      'danger',
      'danger',
      'warning',
    ])
    expect(group.querySelector('.work-summary-card')).toBeNull()
  })

  it('keeps supervisor assignee and attention filters page-owned when the summary renderer changes', () => {
    render(<SupervisorWorkPage />)

    expect(mocks.useSupervisorOverview).toHaveBeenLastCalledWith({
      assigneeUserId: null,
      attentionOnly: false,
    })

    fireEvent.change(screen.getByLabelText('المكلف الحالي'), { target: { value: 'user-1' } })
    expect(mocks.useSupervisorOverview).toHaveBeenLastCalledWith({
      assigneeUserId: 'user-1',
      attentionOnly: false,
    })

    fireEvent.click(screen.getByRole('checkbox', { name: 'اعرض ما يحتاج تدخلًا فقط' }))
    expect(mocks.useSupervisorOverview).toHaveBeenLastCalledWith({
      assigneeUserId: 'user-1',
      attentionOnly: true,
    })

    const group = screen.getByRole('group', { name: 'ملخص حالة أعمال الفريق' })
    expect(within(group).getByText('عمل نشط')).not.toBeNull()
  })
})
