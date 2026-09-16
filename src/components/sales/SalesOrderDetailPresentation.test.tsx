import { fireEvent, render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { SalesOrderDetailHeader } from './SalesOrderDetailPresentation'

function setViewport(width: number) {
  Object.defineProperty(window, 'innerWidth', {
    configurable: true,
    writable: true,
    value: width,
  })
}

describe('SalesOrderDetailHeader', () => {
  beforeEach(() => setViewport(1280))

  it('reuses shared Sales status semantics and shared AppAction identity', () => {
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
        actions={[
          { id: 'deliver', label: 'تسليم', onSelect: onDeliver, importance: 'primary', tone: 'success' },
          { id: 'copy', label: 'نسخ', onSelect: onCopy },
          { id: 'cancel', label: 'إلغاء', onSelect: onCancel, importance: 'tertiary', tone: 'danger' },
        ]}
        tools={<button type="button">طباعة</button>}
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
