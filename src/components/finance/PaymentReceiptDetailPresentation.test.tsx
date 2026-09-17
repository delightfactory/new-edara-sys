import { fireEvent, render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { PaymentReceiptDetailHeader } from './PaymentReceiptDetailPresentation'

function setViewport(width: number) {
  Object.defineProperty(window, 'innerWidth', {
    configurable: true,
    writable: true,
    value: width,
  })
}

describe('PaymentReceiptDetailHeader', () => {
  beforeEach(() => setViewport(1280))

  it.each([
    ['pending', 'معلق — بانتظار المراجعة', 'warning'],
    ['confirmed', 'مؤكد', 'success'],
    ['rejected', 'مرفوض', 'danger'],
  ])('maps Finance status %s to the shared semantic badge', (status, label, tone) => {
    render(
      <PaymentReceiptDetailHeader
        receiptNumber="PR-1024"
        context="شركة النور • 17/09/2026"
        status={status}
        onBack={vi.fn()}
      />,
    )

    expect(screen.getByRole('banner', { name: 'تفاصيل إيصال التحصيل' })).not.toBeNull()
    expect(screen.getByRole('heading', { level: 1, name: 'PR-1024' })).not.toBeNull()
    const statusText = screen.getByText(label)
    expect(statusText.closest('.ds-status-badge')?.getAttribute('data-tone')).toBe(tone)
  })

  it('keeps back navigation and output tooling as separate header capabilities', () => {
    const onBack = vi.fn()

    render(
      <PaymentReceiptDetailHeader
        receiptNumber="PR-1024"
        context={<a href="/customers/customer-1">شركة النور</a>}
        status="pending"
        onBack={onBack}
        tools={<button type="button">تنزيل PDF</button>}
      />,
    )

    const back = screen.getByRole('button', { name: 'رجوع' })
    expect(back.className).toContain('btn-touch')
    fireEvent.click(back)
    expect(onBack).toHaveBeenCalledTimes(1)
    expect(screen.getByRole('button', { name: 'تنزيل PDF' })).not.toBeNull()
  })

  it('delegates Mobile review-action placement to the shared action registry', () => {
    setViewport(390)
    const onConfirm = vi.fn()
    const onReject = vi.fn()

    const { container } = render(
      <PaymentReceiptDetailHeader
        receiptNumber="PR-1024"
        context="شركة النور"
        status="pending"
        onBack={vi.fn()}
        actions={[
          {
            id: 'confirm',
            label: 'تأكيد الاستلام',
            onSelect: onConfirm,
            importance: 'primary',
            order: 10,
          },
          {
            id: 'reject',
            label: 'رفض',
            onSelect: onReject,
            importance: 'tertiary',
            tone: 'danger',
            order: 20,
          },
        ]}
      />,
    )

    expect(screen.getByRole('banner').getAttribute('data-device')).toBe('mobile')
    expect(container.querySelector('.ds-transaction-header__visible-actions')?.textContent).toContain('تأكيد الاستلام')
    expect(container.querySelector('.ds-transaction-header__overflow-actions')?.textContent).toContain('رفض')

    fireEvent.click(screen.getByRole('button', { name: 'تأكيد الاستلام' }))
    fireEvent.click(screen.getByRole('button', { name: 'رفض' }))
    expect(onConfirm).toHaveBeenCalledTimes(1)
    expect(onReject).toHaveBeenCalledTimes(1)
  })
})
