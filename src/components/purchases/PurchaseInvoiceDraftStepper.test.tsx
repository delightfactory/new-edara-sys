import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import PurchaseInvoiceDraftStepper from './PurchaseInvoiceDraftStepper'

describe('PurchaseInvoiceDraftStepper', () => {
  it('projects purchase-owned reachability into the shared stepper without unlocking future workflow steps', () => {
    const onStepChange = vi.fn()

    render(
      <PurchaseInvoiceDraftStepper
        currentStep={0}
        canProceedFromBasics={false}
        canProceedFromItems={false}
        onStepChange={onStepChange}
      />,
    )

    expect(screen.getByRole('navigation', { name: 'مراحل فاتورة المشتريات' })).toBeTruthy()
    expect(screen.getByRole('button', { name: 'الخطوة الحالية: المورد واللوجستيات' }).getAttribute('aria-current')).toBe('step')
    expect((screen.getByRole('button', { name: 'قادمة: المنتجات المستلمة' }) as HTMLButtonElement).disabled).toBe(true)
    expect((screen.getByRole('button', { name: 'قادمة: التكاليف والضرائب' }) as HTMLButtonElement).disabled).toBe(true)
    expect((screen.getByRole('button', { name: 'قادمة: مراجعة وحفظ' }) as HTMLButtonElement).disabled).toBe(true)
  })

  it('keeps completed steps reachable and only unlocks the same future steps as the legacy purchase flow', () => {
    const onStepChange = vi.fn()

    const { rerender } = render(
      <PurchaseInvoiceDraftStepper
        currentStep={1}
        canProceedFromBasics
        canProceedFromItems={false}
        onStepChange={onStepChange}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: 'مكتملة: المورد واللوجستيات' }))
    expect(onStepChange).toHaveBeenLastCalledWith(0)
    expect((screen.getByRole('button', { name: 'قادمة: التكاليف والضرائب' }) as HTMLButtonElement).disabled).toBe(true)

    rerender(
      <PurchaseInvoiceDraftStepper
        currentStep={2}
        canProceedFromBasics
        canProceedFromItems
        onStepChange={onStepChange}
      />,
    )

    expect((screen.getByRole('button', { name: 'مكتملة: المنتجات المستلمة' }) as HTMLButtonElement).disabled).toBe(false)
    expect(screen.getByRole('button', { name: 'الخطوة الحالية: التكاليف والضرائب' }).getAttribute('aria-current')).toBe('step')
    expect((screen.getByRole('button', { name: 'قادمة: مراجعة وحفظ' }) as HTMLButtonElement).disabled).toBe(true)
  })

  it('uses the shared overflow-safe mobile wrap composition', () => {
    const { container } = render(
      <PurchaseInvoiceDraftStepper
        currentStep={3}
        canProceedFromBasics
        canProceedFromItems
        onStepChange={vi.fn()}
      />,
    )

    expect(container.querySelector('.stepper--mobile-wrap')).toBeTruthy()
  })
})
