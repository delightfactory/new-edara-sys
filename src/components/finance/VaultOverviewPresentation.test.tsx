import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import type { AppAction } from '@/components/patterns/ActionRegistry'
import { VaultCard, VaultSummary } from './VaultOverviewPresentation'

const baseSummary = {
  name: 'الخزنة الرئيسية',
  kind: 'cash' as const,
  typeLabel: 'نقدي',
  balance: '125,000.00 ج.م',
  balanceTone: 'success' as const,
  branch: 'طنطا',
  responsible: 'أحمد عبد القادر',
  statusLabel: 'نشطة',
  statusTone: 'success' as const,
}

function buildActions() {
  return {
    statement: vi.fn(),
    opening: vi.fn(),
    deposit: vi.fn(),
    withdrawal: vi.fn(),
    edit: vi.fn(),
  }
}

function actionSet(callbacks: ReturnType<typeof buildActions>): AppAction[] {
  return [
    { id: 'statement', label: 'كشف حساب', onSelect: callbacks.statement },
    { id: 'opening', label: 'افتتاحي', onSelect: callbacks.opening },
    { id: 'deposit', label: 'إيداع', onSelect: callbacks.deposit, tone: 'success' },
    { id: 'withdrawal', label: 'سحب', onSelect: callbacks.withdrawal, tone: 'danger' },
    { id: 'edit', label: 'تعديل', onSelect: callbacks.edit },
  ]
}

describe('Vault overview presentation', () => {
  it('composes caller-owned Finance summary values and tones without inferring active-count meaning', () => {
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
    expect(screen.getByText('الخزائن النشطة').closest('.ds-stat-card')?.className).not.toContain('ds-stat-card--success')
    expect(screen.getByText('إجمالي الخزائن')).not.toBeNull()
  })

  it('keeps vault type neutral categorical metadata while active state uses semantic status tone', () => {
    render(
      <VaultCard
        summary={baseSummary}
        mode="tablet"
        actions={[{ id: 'statement', label: 'كشف حساب', onSelect: vi.fn() }]}
      />,
    )

    expect(screen.getByText('نقدي').closest('.badge')?.classList.contains('badge-neutral')).toBe(true)
    expect(screen.getByText('نقدي').closest('[data-tone]')).toBeNull()
    expect(screen.getByText('نشطة').closest('[data-tone]')?.getAttribute('data-tone')).toBe('success')
    expect(screen.getByText('طنطا')).not.toBeNull()
    expect(screen.getByText('أحمد عبد القادر')).not.toBeNull()
  })

  it('uses canonical AppAction resolution: one Mobile direct action and every remaining action in overflow', () => {
    const callbacks = buildActions()
    render(<VaultCard summary={baseSummary} mode="mobile" actions={actionSet(callbacks)} />)

    const direct = document.querySelector('.ds-action-set__visible')
    expect(direct?.textContent).toContain('كشف حساب')
    expect(direct?.textContent).not.toContain('افتتاحي')
    expect(direct?.textContent).not.toContain('إيداع')

    fireEvent.click(screen.getByRole('button', { name: 'كشف حساب' }))
    expect(callbacks.statement).toHaveBeenCalledTimes(1)

    fireEvent.click(screen.getByRole('button', { name: 'المزيد من إجراءات الخزنة' }))
    fireEvent.click(screen.getByRole('button', { name: 'إيداع' }))
    fireEvent.click(screen.getByRole('button', { name: 'سحب' }))
    fireEvent.click(screen.getByRole('button', { name: 'تعديل' }))

    expect(callbacks.deposit).toHaveBeenCalledTimes(1)
    expect(callbacks.withdrawal).toHaveBeenCalledTimes(1)
    expect(callbacks.edit).toHaveBeenCalledTimes(1)
    expect(screen.getByRole('button', { name: 'إيداع' }).className).toContain('btn-success')
    expect(screen.getByRole('button', { name: 'سحب' }).className).toContain('btn-danger')
  })

  it('keeps Tablet at two direct actions and preserves omission of unauthorized actions', () => {
    const callbacks = buildActions()
    const { rerender } = render(
      <VaultCard summary={baseSummary} mode="tablet" actions={actionSet(callbacks)} />,
    )

    const direct = document.querySelector('.ds-action-set__visible')
    expect(direct?.textContent).toContain('كشف حساب')
    expect(direct?.textContent).toContain('افتتاحي')
    expect(direct?.textContent).not.toContain('إيداع')
    expect(screen.getByRole('button', { name: 'المزيد من إجراءات الخزنة' })).not.toBeNull()

    rerender(
      <VaultCard
        summary={{ ...baseSummary, statusLabel: 'معطلة', statusTone: 'neutral' }}
        mode="mobile"
        actions={[{ id: 'statement', label: 'كشف حساب', onSelect: callbacks.statement }]}
      />,
    )

    expect(screen.getByText('معطلة').closest('[data-tone]')?.getAttribute('data-tone')).toBe('neutral')
    expect(screen.queryByRole('button', { name: 'المزيد من إجراءات الخزنة' })).toBeNull()
    expect(screen.queryByText('إيداع')).toBeNull()
    expect(screen.getByRole('button', { name: 'كشف حساب' }).classList.contains('btn-touch')).toBe(true)
  })
})
