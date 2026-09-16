import { fireEvent, render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import TransactionHeader from './TransactionHeader'

function setViewport(width: number) {
  Object.defineProperty(window, 'innerWidth', {
    configurable: true,
    writable: true,
    value: width,
  })
}

describe('TransactionHeader', () => {
  beforeEach(() => setViewport(1280))

  it('renders page-owned actions through the shared ActionRegistry contract', () => {
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
        actions={[
          { id: 'confirm', label: 'تأكيد', onSelect: onConfirm, importance: 'primary', tone: 'success' },
          { id: 'edit', label: 'تعديل', onSelect: onEdit },
          { id: 'cancel', label: 'إلغاء', onSelect: onCancel, importance: 'tertiary', tone: 'danger' },
        ]}
        tools={<button type="button">طباعة</button>}
      />,
    )

    expect(screen.getByRole('heading', { level: 1, name: 'SO-1024' })).not.toBeNull()
    expect(screen.getByText('شركة النور')).not.toBeNull()
    expect(screen.getByText('مؤكد')).not.toBeNull()
    expect(screen.getByRole('banner', { name: 'تفاصيل أمر البيع' })).not.toBeNull()

    const confirm = screen.getByRole('button', { name: 'تأكيد' })
    const edit = screen.getByRole('button', { name: 'تعديل' })
    const cancel = screen.getByRole('button', { name: 'إلغاء' })

    expect(confirm.className).toContain('btn-success')
    expect(edit.className).toContain('btn-secondary')
    expect(cancel.className).toContain('btn-danger')
    expect(confirm.className).toContain('btn-touch')
    expect(edit.className).toContain('btn-touch')
    expect(cancel.className).toContain('btn-touch')

    fireEvent.click(confirm)
    fireEvent.click(edit)
    fireEvent.click(cancel)

    expect(onConfirm).toHaveBeenCalledTimes(1)
    expect(onEdit).toHaveBeenCalledTimes(1)
    expect(onCancel).toHaveBeenCalledTimes(1)
    expect(screen.getByRole('button', { name: 'طباعة' })).not.toBeNull()
  })

  it('uses registry device resolution instead of a header-specific placement taxonomy', () => {
    setViewport(390)

    const { container } = render(
      <TransactionHeader
        title="طلب #42"
        actions={[
          { id: 'copy', label: 'نسخ', onSelect: vi.fn() },
          { id: 'deliver', label: 'تسليم', onSelect: vi.fn(), importance: 'primary' },
          { id: 'cancel', label: 'إلغاء', onSelect: vi.fn(), importance: 'tertiary', tone: 'danger' },
          { id: 'desktop-only', label: 'سطح المكتب', onSelect: vi.fn(), availableOn: ['desktop'] },
          { id: 'hidden', label: 'مخفي', onSelect: vi.fn(), hidden: true, importance: 'primary' },
        ]}
      />,
    )

    const header = screen.getByRole('banner')
    const visible = container.querySelector('.ds-transaction-header__visible-actions')
    const overflow = container.querySelector('.ds-transaction-header__overflow-actions')

    expect(header.getAttribute('data-device')).toBe('mobile')
    expect(visible?.textContent).toContain('تسليم')
    expect(visible?.textContent).not.toContain('نسخ')
    expect(overflow?.textContent).toContain('نسخ')
    expect(overflow?.textContent).toContain('إلغاء')
    expect(container.querySelector('.ds-transaction-header__overflow-trigger')?.textContent).toContain('المزيد')
    expect(screen.queryByText('سطح المكتب')).toBeNull()
    expect(screen.queryByText('مخفي')).toBeNull()
  })

  it('preserves disabled/loading semantics from AppAction', () => {
    render(
      <TransactionHeader
        title="طلب #42"
        actions={[
          { id: 'deliver', label: 'تسليم', onSelect: vi.fn(), importance: 'primary', loading: true },
          { id: 'copy', label: 'نسخ', onSelect: vi.fn(), disabled: true },
        ]}
      />,
    )

    const deliver = screen.getByRole('button', { name: 'تسليم' })
    const copy = screen.getByRole('button', { name: 'نسخ' })

    expect(deliver.className).toContain('btn-primary')
    expect(deliver.getAttribute('aria-busy')).toBe('true')
    expect(deliver).toHaveProperty('disabled', true)
    expect(copy).toHaveProperty('disabled', true)
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
