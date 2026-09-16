import { fireEvent, render, screen } from '@testing-library/react'
import { Send } from 'lucide-react'
import { describe, expect, it, vi } from 'vitest'
import Button from '@/components/ui/Button'
import { TransferCard } from './TransferListPresentation'

const baseSummary = {
  number: 'TR-2026-0042',
  directionLabel: 'إرسال',
  directionIcon: <Send size={10} />,
  statusLabel: 'قيد الشحن',
  statusTone: 'info' as const,
  createdAt: '16/09/2026',
  fromWarehouse: 'مخزن طنطا',
  toWarehouse: 'مخزن القاهرة',
}

describe('TransferCard', () => {
  it('composes transfer identity and warehouse context for Mobile without owning workflow truth', () => {
    const { container } = render(
      <TransferCard summary={baseSummary} mode="mobile" />,
    )

    const card = container.querySelector('[data-transfer-card]')
    expect(card).not.toBeNull()
    expect(card?.getAttribute('data-mode')).toBe('mobile')
    expect(screen.queryByText('TR-2026-0042')).not.toBeNull()
    expect(screen.queryByText('إرسال')).not.toBeNull()
    expect(screen.queryByText('قيد الشحن')).not.toBeNull()
    expect(screen.queryByText('مخزن طنطا')).not.toBeNull()
    expect(screen.queryByText('مخزن القاهرة')).not.toBeNull()
    expect(screen.queryByText('16/09/2026')).not.toBeNull()
  })

  it('keeps direction neutral metadata while workflow status owns semantic status tone', () => {
    const { rerender } = render(
      <TransferCard summary={baseSummary} mode="tablet" />,
    )

    expect(screen.getByText('إرسال').closest('.badge')?.classList.contains('badge-neutral')).toBe(true)
    expect(screen.getByText('إرسال').closest('[data-tone]')).toBeNull()
    expect(screen.getByText('قيد الشحن').closest('[data-tone]')?.getAttribute('data-tone')).toBe('info')

    rerender(
      <TransferCard
        mode="tablet"
        summary={{
          ...baseSummary,
          directionLabel: 'طلب',
          directionIcon: undefined,
          statusLabel: 'ملغي',
          statusTone: 'danger',
        }}
      />,
    )

    expect(screen.getByText('طلب').closest('.badge')?.classList.contains('badge-neutral')).toBe(true)
    expect(screen.getByText('طلب').closest('[data-tone]')).toBeNull()
    expect(screen.getByText('ملغي').closest('[data-tone]')?.getAttribute('data-tone')).toBe('danger')
  })

  it('renders page-owned actions and a touch-safe detail entry without inventing actions', () => {
    const onShip = vi.fn()
    const onOpen = vi.fn()
    const { rerender } = render(
      <TransferCard
        summary={baseSummary}
        mode="mobile"
        actions={<Button onClick={onShip}>شحن</Button>}
        onOpen={onOpen}
        openLabel="فتح التحويل TR-2026-0042"
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: 'شحن' }))
    fireEvent.click(screen.getByRole('button', { name: 'فتح التحويل TR-2026-0042' }))
    expect(onShip).toHaveBeenCalledTimes(1)
    expect(onOpen).toHaveBeenCalledTimes(1)
    expect(screen.getByRole('group', { name: 'إجراءات التحويل' })).not.toBeNull()

    rerender(<TransferCard summary={baseSummary} mode="mobile" />)
    expect(screen.queryByRole('group', { name: 'إجراءات التحويل' })).toBeNull()
    expect(screen.queryByText('شحن')).toBeNull()
    expect(screen.queryByText('عرض التفاصيل')).toBeNull()
  })
})
