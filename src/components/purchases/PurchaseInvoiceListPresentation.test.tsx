import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { PurchaseInvoiceCard } from './PurchaseInvoiceListPresentation'

const baseSummary = {
  number: 'PIN-20260916-0042',
  supplier: 'مورد النور',
  date: '16/09/2026',
  warehouse: 'مخزن طنطا',
  total: '12,500 ج.م',
  paid: '5,000 ج.م',
  statusLabel: 'معتمدة',
  statusTone: 'warning' as const,
}

describe('PurchaseInvoiceCard', () => {
  it('composes procurement identity, financial summary and warehouse context without owning business truth', () => {
    const { container } = render(
      <PurchaseInvoiceCard
        summary={baseSummary}
        mode="mobile"
        onOpen={() => undefined}
        openLabel="عرض تفاصيل فاتورة PIN-20260916-0042"
      />,
    )

    const card = container.querySelector('[data-purchase-invoice-card]')
    expect(card).not.toBeNull()
    expect(card?.getAttribute('data-mode')).toBe('mobile')
    expect(screen.queryByText('PIN-20260916-0042')).not.toBeNull()
    expect(screen.queryByText('مورد النور')).not.toBeNull()
    expect(screen.queryByText('16/09/2026')).not.toBeNull()
    expect(screen.queryByText('12,500 ج.م')).not.toBeNull()
    expect(screen.queryByText('5,000 ج.م')).not.toBeNull()
    expect(screen.queryByText('مخزن طنطا')).not.toBeNull()
  })

  it('uses semantic workflow status tone supplied by the page', () => {
    const { rerender } = render(
      <PurchaseInvoiceCard
        summary={baseSummary}
        mode="tablet"
        onOpen={() => undefined}
        openLabel="عرض تفاصيل فاتورة PIN-20260916-0042"
      />,
    )

    expect(screen.getByText('معتمدة').closest('[data-tone]')?.getAttribute('data-tone')).toBe('warning')

    rerender(
      <PurchaseInvoiceCard
        summary={{ ...baseSummary, statusLabel: 'مدفوعة', statusTone: 'success' }}
        mode="tablet"
        onOpen={() => undefined}
        openLabel="عرض تفاصيل فاتورة PIN-20260916-0042"
      />,
    )

    expect(screen.getByText('مدفوعة').closest('[data-tone]')?.getAttribute('data-tone')).toBe('success')
  })

  it('keeps the neutral card non-interactive and exposes one touch-safe page-owned detail action', () => {
    const onOpen = vi.fn()
    const { container } = render(
      <PurchaseInvoiceCard
        summary={baseSummary}
        mode="mobile"
        onOpen={onOpen}
        openLabel="عرض تفاصيل فاتورة PIN-20260916-0042"
      />,
    )

    const card = container.querySelector('[data-purchase-invoice-card]')
    expect(card?.getAttribute('role')).toBeNull()
    expect(card?.getAttribute('tabindex')).toBeNull()

    const openButton = screen.getByRole('button', { name: 'عرض تفاصيل فاتورة PIN-20260916-0042' })
    expect(openButton.classList.contains('btn-touch')).toBe(true)
    fireEvent.click(openButton)
    expect(onOpen).toHaveBeenCalledTimes(1)
  })
})
