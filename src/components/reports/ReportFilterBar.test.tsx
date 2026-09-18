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

  it('preserves all existing preset date outputs and parent callback ownership', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date(2026, 8, 18, 12, 0, 0))
    const onChange = vi.fn()

    render(
      <ReportFilterBar
        value={{ from: '2026-09-18', to: '2026-09-18' }}
        onChange={onChange}
      />,
    )

    const expectedRanges = [
      ['آخر 7 أيام', { from: '2026-09-12', to: '2026-09-18' }],
      ['آخر 30 يوماً', { from: '2026-08-20', to: '2026-09-18' }],
      ['آخر 90 يوماً', { from: '2026-06-21', to: '2026-09-18' }],
      ['هذا الشهر', { from: '2026-09-01', to: '2026-09-30' }],
    ] as const

    expectedRanges.forEach(([label, range], index) => {
      fireEvent.click(screen.getByRole('button', { name: label }))
      expect(onChange).toHaveBeenNthCalledWith(index + 1, range)
    })
    expect(onChange).toHaveBeenCalledTimes(expectedRanges.length)
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

  it('keeps both custom dates independently named and preserves normalized parent callbacks', () => {
    const onChange = vi.fn()

    render(
      <ReportFilterBar
        value={{ from: '2026-09-10', to: '2026-09-18' }}
        onChange={onChange}
      />,
    )

    const fromInput = screen.getByLabelText('من تاريخ') as HTMLInputElement
    const toInput = screen.getByLabelText('إلى تاريخ') as HTMLInputElement

    expect(fromInput.type).toBe('date')
    expect(toInput.type).toBe('date')

    fireEvent.change(fromInput, { target: { value: '2026-09-12' } })
    expect(onChange).toHaveBeenNthCalledWith(1, { from: '2026-09-12', to: '2026-09-18' })

    fireEvent.change(toInput, { target: { value: '2026-09-17' } })
    expect(onChange).toHaveBeenNthCalledWith(2, { from: '2026-09-10', to: '2026-09-17' })
  })
})
