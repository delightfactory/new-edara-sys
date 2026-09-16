import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import TransactionHeader from './TransactionHeader'

describe('TransactionHeader', () => {
  it('keeps identity and semantic status separate from page-owned actions', () => {
    const onConfirm = vi.fn()
    const onEdit = vi.fn()
    const onCancel = vi.fn()

    render(
      <TransactionHeader
        aria-label="تفاصيل أمر البيع"
        title={<span dir="ltr">SO-1024</span>}
        subtitle="شركة النور"
        status={<span>مؤكد</span>}
        backAction={<button type="button">رجوع</button>}
        primaryAction={{ key: 'confirm', label: 'تأكيد', onClick: onConfirm }}
        secondaryActions={[{ key: 'edit', label: 'تعديل', onClick: onEdit }]}
        destructiveActions={[{ key: 'cancel', label: 'إلغاء', onClick: onCancel }]}
        utilityActions={<button type="button">طباعة</button>}
      />,
    )

    expect(screen.getByRole('heading', { level: 1, name: 'SO-1024' })).not.toBeNull()
    expect(screen.getByText('شركة النور')).not.toBeNull()
    expect(screen.getByText('مؤكد')).not.toBeNull()
    expect(screen.getByRole('banner', { name: 'تفاصيل أمر البيع' })).not.toBeNull()

    fireEvent.click(screen.getByRole('button', { name: 'تأكيد' }))
    fireEvent.click(screen.getByRole('button', { name: 'تعديل' }))
    fireEvent.click(screen.getByRole('button', { name: 'إلغاء' }))

    expect(onConfirm).toHaveBeenCalledTimes(1)
    expect(onEdit).toHaveBeenCalledTimes(1)
    expect(onCancel).toHaveBeenCalledTimes(1)
    expect(screen.getByRole('button', { name: 'طباعة' })).not.toBeNull()
  })

  it('uses shared Button variants, touch targets and disabled/loading semantics', () => {
    render(
      <TransactionHeader
        title="طلب #42"
        primaryAction={{ key: 'deliver', label: 'تسليم', onClick: vi.fn(), loading: true }}
        secondaryActions={[{ key: 'copy', label: 'نسخ', onClick: vi.fn(), disabled: true }]}
        destructiveActions={[{ key: 'cancel', label: 'إلغاء', onClick: vi.fn() }]}
      />,
    )

    const deliver = screen.getByRole('button', { name: 'تسليم' })
    const copy = screen.getByRole('button', { name: 'نسخ' })
    const cancel = screen.getByRole('button', { name: 'إلغاء' })

    expect(deliver.className).toContain('btn-primary')
    expect(deliver.className).toContain('btn-touch')
    expect(deliver.getAttribute('aria-busy')).toBe('true')
    expect(deliver).toHaveProperty('disabled', true)

    expect(copy.className).toContain('btn-secondary')
    expect(copy).toHaveProperty('disabled', true)

    expect(cancel.className).toContain('btn-danger')
    expect(cancel.className).toContain('btn-touch')
  })

  it('marks sticky composition without making stickiness mandatory', () => {
    const { rerender } = render(<TransactionHeader title="طلب #1" sticky />)
    const header = screen.getByRole('banner')

    expect(header.className).toContain('ds-transaction-header--sticky')
    expect(header.getAttribute('data-sticky')).toBe('true')

    rerender(<TransactionHeader title="طلب #1" />)
    expect(screen.getByRole('banner').className).not.toContain('ds-transaction-header--sticky')
  })
})
