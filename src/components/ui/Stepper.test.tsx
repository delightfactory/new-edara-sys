import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import Stepper from './Stepper'

describe('Stepper', () => {
  it('preserves the read-only indicator contract by default', () => {
    render(<Stepper steps={['بيانات الطلب', 'المنتجات']} currentStep={1} />)

    expect(screen.getByRole('navigation', { name: 'خطوات النموذج' })).toBeTruthy()
    expect(screen.queryAllByRole('button')).toHaveLength(0)
    expect(screen.getByLabelText('الخطوة الحالية: المنتجات').getAttribute('aria-current')).toBe('step')
  })

  it('supports page-owned reachability without owning workflow truth', () => {
    const onStepClick = vi.fn()
    render(
      <Stepper
        steps={[
          { label: 'بيانات الطلب' },
          { label: 'المنتجات' },
          { label: 'التوصيل', disabled: true },
        ]}
        currentStep={1}
        onStepClick={onStepClick}
        ariaLabel="مراحل أمر البيع"
      />,
    )

    expect(screen.getByRole('button', { name: 'الخطوة الحالية: المنتجات' }).getAttribute('aria-current')).toBe('step')
    expect((screen.getByRole('button', { name: 'قادمة: التوصيل' }) as HTMLButtonElement).disabled).toBe(true)

    fireEvent.click(screen.getByRole('button', { name: 'مكتملة: بيانات الطلب' }))
    expect(onStepClick).toHaveBeenCalledWith(0)

    fireEvent.click(screen.getByRole('button', { name: 'قادمة: التوصيل' }))
    expect(onStepClick).toHaveBeenCalledTimes(1)
  })

  it('offers the shared overflow-safe wrapped mobile composition as an opt-in', () => {
    const { container } = render(
      <Stepper
        steps={['الأولى', 'الثانية', 'الثالثة', 'الرابعة']}
        currentStep={0}
        mobileLayout="wrap"
      />,
    )

    expect(container.querySelector('.stepper--mobile-wrap')).toBeTruthy()
  })
})
