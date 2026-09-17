import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { Eye, Pencil } from 'lucide-react'
import { EmployeeCard, EmployeeSummary } from './EmployeeOverviewPresentation'
import type { AppAction } from '@/components/patterns/ActionRegistry'

const summary = {
  name: 'أحمد علي',
  employeeNumber: 'EMP-014',
  department: 'المبيعات',
  position: 'مندوب مبيعات',
  phone: <span dir="ltr">01000000000</span>,
  salary: '8,000 ج.م',
  fieldLabel: 'ميداني',
  statusLabel: 'نشط',
  statusTone: 'success' as const,
}

function makeActions(onView = vi.fn(), onEdit = vi.fn()): AppAction[] {
  return [
    {
      id: 'view',
      label: 'عرض الملف',
      ariaLabel: 'عرض ملف أحمد علي',
      icon: <Eye size={14} />,
      importance: 'primary',
      tone: 'secondary',
      onSelect: onView,
    },
    {
      id: 'edit',
      label: 'تعديل',
      ariaLabel: 'تعديل أحمد علي',
      icon: <Pencil size={14} />,
      tone: 'ghost',
      availableOn: ['tablet', 'desktop'],
      onSelect: onEdit,
    },
  ]
}

describe('EmployeeOverviewPresentation', () => {
  it('keeps categorical field count neutral while using semantic tones for workflow counts', () => {
    render(
      <EmployeeSummary
        metrics={{ active: 12, onLeave: 2, field: 5, total: 19 }}
      />,
    )

    expect(screen.getByText('نشط').closest('[data-tone]')?.getAttribute('data-tone')).toBe('success')
    expect(screen.getByText('في إجازة').closest('[data-tone]')?.getAttribute('data-tone')).toBe('info')
    expect(screen.getByText('ميداني').closest('[data-tone]')?.getAttribute('data-tone')).toBe('neutral')
    expect(screen.getByText('الإجمالي').closest('[data-tone]')?.getAttribute('data-tone')).toBe('neutral')
  })

  it('renders semantic status, neutral employee type and permission-projected metadata', () => {
    render(
      <EmployeeCard
        summary={summary}
        mode="tablet"
        actions={makeActions()}
        onOpen={() => undefined}
      />,
    )

    expect(screen.getByText('نشط').closest('[data-tone]')?.getAttribute('data-tone')).toBe('success')
    expect(screen.getByText('ميداني').classList.contains('badge-neutral')).toBe(true)
    expect(screen.getByText('الراتب الأساسي')).toBeTruthy()
    expect(screen.getByText('8,000 ج.م')).toBeTruthy()
  })

  it('keeps mobile to the existing view action while tablet also exposes edit', () => {
    const onView = vi.fn()
    const onEdit = vi.fn()
    const actions = makeActions(onView, onEdit)
    const { rerender } = render(
      <EmployeeCard
        summary={{ ...summary, salary: undefined }}
        mode="mobile"
        actions={actions}
        onOpen={() => undefined}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: 'عرض ملف أحمد علي' }))
    expect(onView).toHaveBeenCalledTimes(1)
    expect(screen.queryByRole('button', { name: 'تعديل أحمد علي' })).toBeNull()
    expect(screen.queryByText('الراتب الأساسي')).toBeNull()

    rerender(
      <EmployeeCard
        summary={summary}
        mode="tablet"
        actions={actions}
        onOpen={() => undefined}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: 'تعديل أحمد علي' }))
    expect(onEdit).toHaveBeenCalledTimes(1)
  })

  it('delegates identity opening from an explicit control inside the neutral Card', () => {
    const onOpen = vi.fn()
    render(
      <EmployeeCard
        summary={summary}
        mode="mobile"
        actions={makeActions()}
        onOpen={onOpen}
      />,
    )

    const openButton = screen.getByRole('button', { name: 'فتح ملف أحمد علي' })
    fireEvent.click(openButton)
    expect(onOpen).toHaveBeenCalledTimes(1)
    expect(openButton.closest('[data-employee-card]')?.getAttribute('data-mode')).toBe('mobile')
  })
})
