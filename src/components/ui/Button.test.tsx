import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import Button from './Button'
import IconButton from './IconButton'

function TestIcon() {
  return <svg data-testid="test-icon" aria-hidden="true" />
}

describe('Button V2 contract', () => {
  it('keeps legacy density unless touchTarget is explicitly enabled', () => {
    const { rerender } = render(<Button size="sm">حفظ</Button>)
    const button = screen.getByRole('button', { name: 'حفظ' })

    expect(button.className).toContain('btn-sm')
    expect(button.className).not.toContain('btn-touch')

    rerender(<Button size="sm" touchTarget>حفظ</Button>)
    expect(button.className).toContain('btn-sm')
    expect(button.className).toContain('btn-touch')
  })

  it('preserves icon-button shape while loading and exposes busy state', () => {
    render(
      <Button icon={<TestIcon />} loading aria-label="حفظ سريع" />,
    )

    const button = screen.getByRole('button', { name: 'حفظ سريع' }) as HTMLButtonElement
    expect(button.className).toContain('btn-icon')
    expect(button.disabled).toBe(true)
    expect(button.getAttribute('aria-busy')).toBe('true')
    expect(button.getAttribute('data-loading')).toBe('true')
    expect(button.querySelector('.spinner')).not.toBeNull()
  })

  it('prevents repeated activation while loading', () => {
    const onClick = vi.fn()
    render(<Button loading onClick={onClick}>حفظ</Button>)

    fireEvent.click(screen.getByRole('button', { name: 'حفظ' }))
    expect(onClick).not.toHaveBeenCalled()
  })
})

describe('IconButton V2 contract', () => {
  it('requires an accessible label and uses a touch target by default', () => {
    render(<IconButton icon={<TestIcon />} label="حذف" variant="danger" />)

    const button = screen.getByRole('button', { name: 'حذف' }) as HTMLButtonElement
    expect(button.className).toContain('btn-icon')
    expect(button.className).toContain('btn-touch')
    expect(button.className).toContain('btn-danger')
    expect(button.type).toBe('button')
    expect(button.title).toBe('حذف')
  })

  it('supports an explicit tooltip without changing the accessible name', () => {
    render(
      <IconButton
        icon={<TestIcon />}
        label="فتح التفاصيل"
        tooltip="عرض التفاصيل الكاملة"
      />,
    )

    const button = screen.getByRole('button', { name: 'فتح التفاصيل' }) as HTMLButtonElement
    expect(button.title).toBe('عرض التفاصيل الكاملة')
  })
})
