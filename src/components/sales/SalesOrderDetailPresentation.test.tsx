import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { SalesOrderDetailHeader } from './SalesOrderDetailPresentation'

describe('SalesOrderDetailHeader', () => {
  it('reuses shared Sales status semantics and keeps action ownership external', () => {
    const onBack = vi.fn()
    const onDeliver = vi.fn()
    const onCopy = vi.fn()
    const onCancel = vi.fn()

    render(
      <SalesOrderDetailHeader
        orderNumber="SO-77"
        customer={<a href="/customers/c-1">شركة النور</a>}
        status="confirmed"
        onBack={onBack}
        primaryAction={{ key: 'deliver', label: 'تسليم', onClick: onDeliver }}
        secondaryActions={[{ key: 'copy', label: 'نسخ', onClick: onCopy }]}
        destructiveActions={[{ key: 'cancel', label: 'إلغاء', onClick: onCancel }]}
        utilityActions={<button type="button">طباعة</button>}
      />,
    )

    expect(screen.getByRole('banner', { name: 'تفاصيل أمر البيع' })).not.toBeNull()
    expect(screen.getByText('مؤكد').closest('.ds-status-badge')?.getAttribute('data-tone')).toBe('info')
    expect(screen.getByRole('link', { name: 'شركة النور' })).not.toBeNull()

    fireEvent.click(screen.getByRole('button', { name: 'رجوع' }))
    fireEvent.click(screen.getByRole('button', { name: 'تسليم' }))
    fireEvent.click(screen.getByRole('button', { name: 'نسخ' }))
    fireEvent.click(screen.getByRole('button', { name: 'إلغاء' }))

    expect(onBack).toHaveBeenCalledTimes(1)
    expect(onDeliver).toHaveBeenCalledTimes(1)
    expect(onCopy).toHaveBeenCalledTimes(1)
    expect(onCancel).toHaveBeenCalledTimes(1)
  })

  it('does not invent workflow actions when the page supplies none', () => {
    render(
      <SalesOrderDetailHeader
        orderNumber="SO-11"
        customer="عميل تجريبي"
        status="draft"
        onBack={vi.fn()}
      />,
    )

    expect(screen.getByText('مسودة').closest('.ds-status-badge')?.getAttribute('data-tone')).toBe('neutral')
    expect(screen.queryByLabelText('إجراءات المستند')).toBeNull()
    expect(screen.getAllByRole('button')).toHaveLength(1)
  })
})
