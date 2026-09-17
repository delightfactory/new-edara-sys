import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import ProcessProgress from './ProcessProgress'
import PrimaryTaskAction from './PrimaryTaskAction'

describe('ProcessProgress', () => {
  it('renders caller-owned step truth with readable non-color state and current-step semantics', () => {
    render(
      <ProcessProgress
        ariaLabel="تقدم تسجيل الحضور"
        steps={[
          { id: 'gps', label: 'تحديد الموقع GPS', state: 'completed', meta: '±18م' },
          { id: 'submit', label: 'تسجيل الحضور', state: 'current' },
        ]}
      />,
    )

    expect(screen.getByLabelText('تقدم تسجيل الحضور')).not.toBeNull()

    const completed = screen.getByText('تحديد الموقع GPS').closest('li')
    const current = screen.getByText('تسجيل الحضور').closest('li')

    expect(completed?.getAttribute('data-state')).toBe('completed')
    expect(completed?.getAttribute('aria-current')).toBeNull()
    expect(screen.getByText('مكتملة')).not.toBeNull()
    expect(screen.getByText('±18م')).not.toBeNull()

    expect(current?.getAttribute('data-state')).toBe('current')
    expect(current?.getAttribute('aria-current')).toBe('step')
    expect(screen.getByText('الخطوة الحالية')).not.toBeNull()
  })
})

describe('PrimaryTaskAction', () => {
  it('delegates action meaning and callback while inheriting shared Button touch semantics', () => {
    const onAction = vi.fn()

    const { rerender } = render(
      <PrimaryTaskAction
        id="btn-check-in"
        label="بدء الدوام"
        icon={<span aria-hidden="true">↪</span>}
        onClick={onAction}
      />,
    )

    const button = screen.getByRole('button', { name: 'بدء الدوام' })
    expect(button.classList.contains('btn')).toBe(true)
    expect(button.classList.contains('btn-lg')).toBe(true)
    expect(button.classList.contains('btn-touch')).toBe(true)
    expect(button.classList.contains('btn-primary')).toBe(true)

    fireEvent.click(button)
    expect(onAction).toHaveBeenCalledTimes(1)

    rerender(
      <PrimaryTaskAction
        label="إنهاء الدوام"
        loading
        loadingLabel="جارٍ التسجيل..."
        onClick={onAction}
      />,
    )

    const loadingButton = screen.getByRole('button', { name: 'إنهاء الدوام' })
    expect(loadingButton.getAttribute('aria-busy')).toBe('true')
    expect(loadingButton.hasAttribute('disabled')).toBe(true)
    expect(screen.getByText('جارٍ التسجيل...')).not.toBeNull()
  })
})
