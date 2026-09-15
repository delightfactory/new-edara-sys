import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import Input from './Input'
import Select from './Select'
import Textarea from './Textarea'

describe('V2 Field anatomy', () => {
  it('connects an Input label and hint with generated accessible ids', () => {
    render(<Input label="اسم العميل" hint="اكتب الاسم التجاري" />)

    const input = screen.getByLabelText('اسم العميل') as HTMLInputElement
    const hint = screen.getByText('اكتب الاسم التجاري')

    expect(input.id).not.toBe('')
    expect(input.getAttribute('aria-describedby')).toBe(hint.id)
    expect(input.getAttribute('aria-invalid')).toBeNull()
  })

  it('exposes errors accessibly and suppresses the hint while invalid', () => {
    render(
      <Input
        label="الهاتف"
        hint="رقم التواصل الأساسي"
        error="رقم الهاتف غير صحيح"
      />,
    )

    const input = screen.getByLabelText('الهاتف') as HTMLInputElement
    const error = screen.getByRole('alert')

    expect(input.getAttribute('aria-invalid')).toBe('true')
    expect(input.getAttribute('aria-describedby')).toBe(error.id)
    expect(screen.queryByText('رقم التواصل الأساسي')).toBeNull()
  })

  it('marks required fields for assistive technology without introducing native validation', () => {
    render(<Input label="اسم المنتج" required />)

    const input = screen.getByLabelText(/اسم المنتج/) as HTMLInputElement
    expect(input.getAttribute('aria-required')).toBe('true')
    expect(input.required).toBe(false)
  })

  it('applies the same contract to Select', () => {
    render(
      <Select
        label="المخزن"
        error="اختر المخزن"
        placeholder="اختر"
        options={[{ value: 'w1', label: 'المخزن الرئيسي' }]}
      />,
    )

    const select = screen.getByLabelText('المخزن') as HTMLSelectElement
    expect(select.getAttribute('aria-invalid')).toBe('true')
    expect(screen.getByRole('option', { name: 'المخزن الرئيسي' })).not.toBeNull()
  })

  it('supports optional Textarea fields through the shared anatomy', () => {
    render(<Textarea label="ملاحظات" optional hint="اختياري" />)

    const textarea = screen.getByLabelText(/ملاحظات/) as HTMLTextAreaElement
    expect(textarea.id).not.toBe('')
    expect(screen.getAllByText('اختياري').length).toBeGreaterThan(0)
  })
})
