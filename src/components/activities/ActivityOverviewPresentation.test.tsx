import { fireEvent, render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import type { AppAction } from '@/components/patterns/ActionRegistry'
import { ActivityCard, ActivityOutcomeBadge } from './ActivityOverviewPresentation'

const summary = {
  typeName: 'زيارة متابعة',
  category: 'visit' as const,
  customer: null,
  date: '17 سبتمبر 2026',
  startTime: '09:30 ص',
  notes: 'متابعة الطلب',
  gpsVerified: true,
  outcome: 'followup_scheduled' as const,
}

function actions(): AppAction[] {
  return [
    { id: 'view', label: 'عرض', importance: 'primary', onSelect: vi.fn() },
    { id: 'delete', label: 'حذف', tone: 'danger', importance: 'secondary', onSelect: vi.fn() },
  ]
}

describe('ActivityOverviewPresentation', () => {
  it('maps field outcomes to readable semantic V2 status tones', () => {
    const { rerender } = render(<ActivityOutcomeBadge outcome="visited" />)
    expect(screen.getByText('تمت الزيارة').closest('[data-tone]')).toHaveAttribute('data-tone', 'success')

    rerender(<ActivityOutcomeBadge outcome="refused" />)
    expect(screen.getByText('رفض').closest('[data-tone]')).toHaveAttribute('data-tone', 'danger')

    rerender(<ActivityOutcomeBadge outcome="no_answer" />)
    expect(screen.getByText('لا يرد').closest('[data-tone]')).toHaveAttribute('data-tone', 'warning')
  })

  it('keeps category and unverified GPS metadata neutral without duplicating category hierarchy', () => {
    render(
      <ActivityCard
        summary={{ ...summary, gpsVerified: false }}
        mode="tablet"
        actions={[]}
        onOpen={vi.fn()}
      />,
    )
    expect(screen.getAllByText('زيارة')).toHaveLength(1)
    expect(screen.getByText('زيارة', { selector: '.badge' })).toBeInTheDocument()
    expect(screen.getByText('متابعة مجدولة').closest('[data-tone]')).toHaveAttribute('data-tone', 'warning')
    expect(screen.getByText('GPS').parentElement).toHaveTextContent('—')
    expect(screen.queryByText('غير موثق')).not.toBeInTheDocument()
  })

  it('preserves optional start time on Tablet without expanding legacy Mobile information density', () => {
    const { rerender } = render(
      <ActivityCard summary={summary} mode="tablet" actions={[]} onOpen={vi.fn()} />,
    )

    expect(screen.getByText('الوقت').parentElement).toHaveTextContent('09:30 ص')

    rerender(<ActivityCard summary={summary} mode="mobile" actions={[]} onOpen={vi.fn()} />)
    expect(screen.queryByText('الوقت')).not.toBeInTheDocument()
    expect(screen.queryByText('09:30 ص')).not.toBeInTheDocument()
  })

  it('uses canonical device action placement without owning action eligibility', () => {
    const activityActions = actions()
    const { rerender } = render(
      <ActivityCard summary={summary} mode="mobile" actions={activityActions} onOpen={vi.fn()} />,
    )

    const group = screen.getByRole('group', { name: 'إجراءات النشاط' })
    const direct = group.querySelector('.ds-action-set__visible') as HTMLElement
    expect(within(direct).getAllByRole('button')).toHaveLength(1)
    expect(group.querySelector('details')).toBeInTheDocument()

    rerender(<ActivityCard summary={summary} mode="tablet" actions={activityActions} onOpen={vi.fn()} />)
    const tabletGroup = screen.getByRole('group', { name: 'إجراءات النشاط' })
    const tabletDirect = tabletGroup.querySelector('.ds-action-set__visible') as HTMLElement
    expect(within(tabletDirect).getAllByRole('button')).toHaveLength(2)
    expect(tabletGroup.querySelector('details')).not.toBeInTheDocument()
  })

  it('delegates open and action callbacks to the caller', () => {
    const onOpen = vi.fn()
    const activityActions = actions()
    render(<ActivityCard summary={summary} mode="tablet" actions={activityActions} onOpen={onOpen} />)

    fireEvent.click(screen.getByRole('button', { name: 'فتح نشاط زيارة متابعة' }))
    fireEvent.click(screen.getByRole('button', { name: 'عرض' }))

    expect(onOpen).toHaveBeenCalledTimes(1)
    expect(activityActions[0].onSelect).toHaveBeenCalledTimes(1)
  })
})
