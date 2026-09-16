import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { StockBalanceCard } from './StockListPresentation'

const baseSummary = {
  productName: 'شامبو واكس',
  productCode: 'SW-001',
  warehouse: 'مخزن طنطا',
  quantity: '120',
  available: '95',
  reserved: '25',
  statusLabel: 'كافي',
  statusTone: 'success' as const,
}

describe('StockBalanceCard', () => {
  it('composes shared stock identity, status and quantity hierarchy for Mobile', () => {
    const { container } = render(
      <StockBalanceCard summary={baseSummary} mode="mobile" />,
    )

    const card = container.querySelector('[data-stock-balance-card]')
    expect(card).not.toBeNull()
    expect(card?.getAttribute('data-mode')).toBe('mobile')
    expect(screen.queryByText('شامبو واكس')).not.toBeNull()
    expect(screen.queryByText('SW-001')).not.toBeNull()
    expect(screen.queryByText('كافي')).not.toBeNull()
    expect(screen.queryByText('95')).not.toBeNull()
    expect(screen.queryByText('120')).not.toBeNull()
    expect(screen.queryByText('25')).not.toBeNull()
    expect(screen.queryByText('مخزن طنطا')).not.toBeNull()
  })

  it('keeps cost and valuation visibility page-controlled', () => {
    const { rerender } = render(
      <StockBalanceCard summary={baseSummary} mode="tablet" />,
    )

    expect(screen.queryByText('التكلفة المرجحة')).toBeNull()
    expect(screen.queryByText('القيمة')).toBeNull()

    rerender(
      <StockBalanceCard
        summary={{
          ...baseSummary,
          weightedCost: '42.50 ج.م',
          stockValue: '5,100.00 ج.م',
        }}
        mode="tablet"
      />,
    )

    expect(screen.queryByText('التكلفة المرجحة')).not.toBeNull()
    expect(screen.queryByText('42.50 ج.م')).not.toBeNull()
    expect(screen.queryByText('القيمة')).not.toBeNull()
    expect(screen.queryByText('5,100.00 ج.م')).not.toBeNull()
  })

  it('preserves local review mode as a controlled accessible presentation boundary', () => {
    const onActualValueChange = vi.fn()
    const { container } = render(
      <StockBalanceCard
        summary={{ ...baseSummary, statusLabel: 'منخفض', statusTone: 'warning' }}
        mode="mobile"
        review={{
          actualValue: '91',
          onActualValueChange,
          diff: '-4',
          diffTone: 'danger',
        }}
      />,
    )

    const input = screen.getByLabelText('العدد الفعلي') as HTMLInputElement
    expect(input.value).toBe('91')
    expect(input.getAttribute('inputmode')).toBe('decimal')
    expect(container.querySelector('[data-stock-review]')).not.toBeNull()
    expect(container.querySelector('[data-review-diff]')?.textContent).toBe('-4')

    fireEvent.change(input, { target: { value: '93' } })
    expect(onActualValueChange).toHaveBeenCalledWith('93')
  })
})
