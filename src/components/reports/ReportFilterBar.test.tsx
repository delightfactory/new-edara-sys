import { fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import ReportFilterBar from './ReportFilterBar'

afterEach(() => {
  vi.useRealTimers()
})

describe('ReportFilterBar', () => {
  it('renders the existing Arabic presets in order inside the shared single-choice group', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date(2026, 8, 18, 12, 0, 0))

    render(
      <ReportFilterBar
        value={{ from: '2026-09-18', to: '2026-09-18' }}
        onChange={vi.fn()}
      />,
    )

    const group = screen.getByRole('group', { name: 'اختصارات الفترة' })
    expect(within(group).getAllByRole('button').map(button => button.textContent)).toEqual([
      'آخر 7 أيام',
      'آخر 30 يوماً',
      'آخر 90 يوماً',
      'هذا الشهر',
    ])
  })

  it('preserves the existing seven-day date math and parent callback ownership', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date(2026, 8, 18, 12, 0, 0))
    const onChange = vi.fn()

    render(
      <ReportFilterBar
        value={{ from: '2026-09-18', to: '2026-09-18' }}
        onChange={onChange}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: 'آخر 7 أيام' }))

    expect(onChange).toHaveBeenCalledTimes(1)
    expect(onChange).toHaveBeenCalledWith({ from: '2026-09-12', to: '2026-09-18' })
  })

  it('marks a matching preset as pressed and leaves custom ranges unselected', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date(2026, 8, 18, 12, 0, 0))
    const onChange = vi.fn()

    const { rerender } = render(
      <ReportFilterBar
        value={{ from: '2026-09-12', to: '2026-09-18' }}
        onChange={onChange}
      />,
    )

    expect(screen.getByRole('button', { name: 'آخر 7 أيام' }).getAttribute('aria-pressed')).toBe('true')

    rerender(
      <ReportFilterBar
        value={{ from: '2026-09-10', to: '2026-09-18' }}
        onChange={onChange}
      />,
    )

    const group = screen.getByRole('group', { name: 'اختصارات الفترة' })
    within(group).getAllByRole('button').forEach(button => {
      expect(button.getAttribute('aria-pressed')).toBe('false')
    })
  })
})
