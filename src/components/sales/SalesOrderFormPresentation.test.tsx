import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { Package, Truck, User } from 'lucide-react'
import {
  SalesOrderFormActions,
  SalesOrderFormSection,
  SalesOrderStepNavigator,
  type SalesOrderFormStep,
} from './SalesOrderFormPresentation'

const steps: SalesOrderFormStep[] = [
  { id: 'header', label: 'بيانات الطلب', icon: <User size={14} /> },
  { id: 'items', label: 'المنتجات', icon: <Package size={14} /> },
  { id: 'delivery', label: 'التوصيل', icon: <Truck size={14} /> },
]

describe('SalesOrderFormPresentation', () => {
  it('projects page-owned reachability through the shared Stepper contract', () => {
    const onChange = vi.fn()
    const { container } = render(
      <SalesOrderStepNavigator
        steps={steps}
        activeIndex={1}
        canActivate={index => index <= 1}
        onChange={onChange}
      />,
    )

    expect(screen.getByRole('navigation', { name: 'مراحل أمر البيع' })).toBeTruthy()
    expect(container.querySelector('.stepper--mobile-wrap')).toBeTruthy()
    expect(container.querySelector('.sales-order-stepper-v2__list')).toBeNull()
    expect(screen.getByRole('button', { name: 'الخطوة الحالية: المنتجات' }).getAttribute('aria-current')).toBe('step')
    expect((screen.getByRole('button', { name: 'قادمة: التوصيل' }) as HTMLButtonElement).disabled).toBe(true)

    fireEvent.click(screen.getByRole('button', { name: 'مكتملة: بيانات الطلب' }))
    expect(onChange).toHaveBeenCalledWith(0)
  })

  it('composes Sales sections over the shared FormSection/FormGrid contract', () => {
    const { container } = render(
      <SalesOrderFormSection title="بيانات الطلب" columns={3}>
        <label htmlFor="order-date">تاريخ الطلب</label>
        <input id="order-date" />
      </SalesOrderFormSection>,
    )

    expect(screen.getByText('بيانات الطلب')).toBeTruthy()
    expect(container.querySelector('.ds-form-section')).toBeTruthy()
    expect(container.querySelector('.ds-form-grid--cols-3')).toBeTruthy()
  })

  it('preserves page-owned actions and uses RTL-native directional cues', () => {
    const onCancel = vi.fn()
    const onPrevious = vi.fn()
    const onNext = vi.fn()
    const onSubmit = vi.fn()
    const { rerender } = render(
      <SalesOrderFormActions
        activeIndex={0}
        lastIndex={3}
        saving={false}
        submitDisabled={false}
        isEdit={false}
        onCancel={onCancel}
        onPrevious={onPrevious}
        onNext={onNext}
        onSubmit={onSubmit}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: 'إلغاء' }))
    const nextButton = screen.getByRole('button', { name: /التالي/ })
    expect(nextButton.querySelector('.lucide-chevron-left')).toBeTruthy()
    fireEvent.click(nextButton)
    expect(onCancel).toHaveBeenCalledTimes(1)
    expect(onNext).toHaveBeenCalledTimes(1)
    expect(onPrevious).not.toHaveBeenCalled()

    rerender(
      <SalesOrderFormActions
        activeIndex={3}
        lastIndex={3}
        saving={false}
        submitDisabled
        isEdit
        onCancel={onCancel}
        onPrevious={onPrevious}
        onNext={onNext}
        onSubmit={onSubmit}
      />,
    )

    const previousButton = screen.getByRole('button', { name: /السابق/ })
    expect(previousButton.querySelector('.lucide-chevron-right')).toBeTruthy()
    fireEvent.click(previousButton)
    expect(onPrevious).toHaveBeenCalledTimes(1)
    expect((screen.getByRole('button', { name: /حفظ التعديلات/ }) as HTMLButtonElement).disabled).toBe(true)
  })

  it('uses shared Button loading semantics without changing submit truth', () => {
    render(
      <SalesOrderFormActions
        activeIndex={3}
        lastIndex={3}
        saving
        submitDisabled={false}
        isEdit={false}
        onCancel={vi.fn()}
        onPrevious={vi.fn()}
        onNext={vi.fn()}
        onSubmit={vi.fn()}
      />,
    )

    const saveButton = screen.getByRole('button', { name: 'حفظ المسودة' }) as HTMLButtonElement
    expect(saveButton.disabled).toBe(true)
    expect(saveButton.getAttribute('aria-busy')).toBe('true')
  })
})
