import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import DateField from './DateField'

describe('DateField', () => {
  it('locks the shared control to native date semantics while forwarding accessible native props', () => {
    const onChange = vi.fn()

    render(
      <DateField
        aria-label="من تاريخ"
        value="2026-09-01"
        min="2026-01-01"
        max="2026-12-31"
        onChange={onChange}
      />,
    )

    const input = screen.getByLabelText('من تاريخ') as HTMLInputElement
    expect(input.type).toBe('date')
    expect(input.value).toBe('2026-09-01')
    expect(input.min).toBe('2026-01-01')
    expect(input.max).toBe('2026-12-31')

    fireEvent.change(input, { target: { value: '2026-09-02' } })
    expect(onChange).toHaveBeenCalledTimes(1)
  })

  it('inherits shared Field label, error and state plumbing without adding date business rules', () => {
    render(
      <DateField
        label="إلى تاريخ"
        value="2026-09-18"
        error="التاريخ مطلوب"
        disabled
        readOnly
        onChange={vi.fn()}
      />,
    )

    const input = screen.getByLabelText('إلى تاريخ') as HTMLInputElement
    const error = screen.getByRole('alert')

    expect(input.disabled).toBe(true)
    expect(input.readOnly).toBe(true)
    expect(input.getAttribute('aria-invalid')).toBe('true')
    expect(input.getAttribute('aria-describedby')).toBe(error.id)
  })
})
