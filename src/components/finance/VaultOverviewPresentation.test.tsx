import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { VaultCard, VaultSummary } from './VaultOverviewPresentation'

const baseSummary = {
  name: 'الخزنة الرئيسية',
  kind: 'cash' as const,
  typeLabel: 'نقدي',
  typeVariant: 'success' as const,
  balance: '125,000.00 ج.م',
  balanceTone: 'success' as const,
  branch: 'طنطا',
  responsible: 'أحمد عبد القادر',
  statusLabel: 'نشطة',
  statusTone: 'success' as const,
}

describe('Vault overview presentation', () => {
  it('composes Finance summary values through the shared metric/stat grammar without calculating them', () => {
    const { container } = render(
      <VaultSummary
        metrics={{
          totalBalance: '250,000.00 ج.م',
          totalBalanceTone: 'success',
          activeCount: '2',
          totalCount: '3',
        }}
      />,
    )

    expect(container.querySelector('[data-metric-grid]')?.getAttribute('data-columns')).toBe('3')
    expect(screen.getByText('إجمالي الرصيد')).not.toBeNull()
    expect(screen.getByText('250,000.00 ج.م')).not.toBeNull()
    expect(screen.getByText('الخزائن النشطة')).not.toBeNull()
    expect(screen.getByText('إجمالي الخزائن')).not.toBeNull()
  })

  it('keeps vault type as categorical metadata while active state uses semantic status tone', () => {
    const onStatement = vi.fn()
    render(
      <VaultCard
        summary={baseSummary}
        mode="tablet"
        actions={{ onStatement }}
      />,
    )

    expect(screen.getByText('نقدي').closest('.badge')?.classList.contains('badge-success')).toBe(true)
    expect(screen.getByText('نقدي').closest('[data-tone]')).toBeNull()
    expect(screen.getByText('نشطة').closest('[data-tone]')?.getAttribute('data-tone')).toBe('success')
    expect(screen.getByText('طنطا')).not.toBeNull()
    expect(screen.getByText('أحمد عبد القادر')).not.toBeNull()
  })

  it('renders only page-authorized financial actions and keeps every rendered action touch-safe', () => {
    const onStatement = vi.fn()
    const onDeposit = vi.fn()
    const onEdit = vi.fn()
    const { rerender } = render(
      <VaultCard
        summary={baseSummary}
        mode="mobile"
        actions={{ onStatement, onDeposit, onEdit }}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: 'كشف حساب' }))
    fireEvent.click(screen.getByRole('button', { name: 'إيداع' }))
    fireEvent.click(screen.getByRole('button', { name: 'تعديل' }))

    expect(onStatement).toHaveBeenCalledTimes(1)
    expect(onDeposit).toHaveBeenCalledTimes(1)
    expect(onEdit).toHaveBeenCalledTimes(1)
    expect(screen.queryByRole('button', { name: 'افتتاحي' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'سحب' })).toBeNull()

    for (const button of screen.getAllByRole('button')) {
      expect(button.classList.contains('btn-touch')).toBe(true)
    }

    rerender(
      <VaultCard
        summary={{ ...baseSummary, statusLabel: 'معطلة', statusTone: 'neutral' }}
        mode="mobile"
        actions={{ onStatement }}
      />,
    )

    expect(screen.getByText('معطلة').closest('[data-tone]')?.getAttribute('data-tone')).toBe('neutral')
    expect(screen.getAllByRole('button')).toHaveLength(1)
  })
})
