import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import Pagination from './Pagination'
import ResponsiveCollection from './ResponsiveCollection'

describe('ResponsiveCollection', () => {
  it('mounts only the selected device presentation', () => {
    const { rerender } = render(
      <ResponsiveCollection
        view="mobile"
        desktop={<div>جدول سطح المكتب</div>}
        tablet={<div>عرض التابلت</div>}
        mobile={<div>بطاقات الموبايل</div>}
      />,
    )

    expect(screen.getByText('بطاقات الموبايل')).not.toBeNull()
    expect(screen.queryByText('جدول سطح المكتب')).toBeNull()
    expect(screen.queryByText('عرض التابلت')).toBeNull()

    rerender(
      <ResponsiveCollection
        view="desktop"
        desktop={<div>جدول سطح المكتب</div>}
        tablet={<div>عرض التابلت</div>}
        mobile={<div>بطاقات الموبايل</div>}
      />,
    )

    expect(screen.getByText('جدول سطح المكتب')).not.toBeNull()
    expect(screen.queryByText('بطاقات الموبايل')).toBeNull()
  })

  it('falls back to desktop presentation when tablet is not provided', () => {
    render(
      <ResponsiveCollection
        view="tablet"
        desktop={<div>عرض كثيف</div>}
        mobile={<div>عرض موبايل</div>}
      />,
    )

    expect(screen.getByText('عرض كثيف')).not.toBeNull()
    expect(screen.queryByText('عرض موبايل')).toBeNull()
  })

  it('lets explicit state content replace the collection without mounting data presentations', () => {
    render(
      <ResponsiveCollection
        view="mobile"
        state="error"
        desktop={<div>جدول</div>}
        mobile={<div>بطاقات</div>}
        error={<div>تعذر تحميل البيانات</div>}
      />,
    )

    expect(screen.getByText('تعذر تحميل البيانات')).not.toBeNull()
    expect(screen.queryByText('بطاقات')).toBeNull()
    expect(screen.queryByText('جدول')).toBeNull()
  })

  it('keeps ready content mounted during background refresh and exposes busy state', () => {
    render(
      <ResponsiveCollection
        ariaLabel="العملاء"
        view="mobile"
        refreshing
        desktop={<div>جدول</div>}
        mobile={<div>العملاء الحاليون</div>}
      />,
    )

    expect(screen.getByText('العملاء الحاليون')).not.toBeNull()
    expect(screen.getByRole('region', { name: 'العملاء' }).getAttribute('aria-busy')).toBe('true')
  })
})

describe('Pagination', () => {
  it('keeps page ownership in the caller', () => {
    const onPageChange = vi.fn()
    render(<Pagination page={3} totalPages={8} onPageChange={onPageChange} />)

    fireEvent.click(screen.getByRole('button', { name: 'الصفحة التالية' }))
    expect(onPageChange).toHaveBeenCalledWith(4)

    fireEvent.click(screen.getByRole('button', { name: 'الصفحة السابقة' }))
    expect(onPageChange).toHaveBeenCalledWith(2)
  })

  it('marks the current page and disables navigation at boundaries', () => {
    const onPageChange = vi.fn()
    const { rerender } = render(
      <Pagination page={1} totalPages={3} onPageChange={onPageChange} />,
    )

    expect((screen.getByRole('button', { name: 'الصفحة السابقة' }) as HTMLButtonElement).disabled).toBe(true)
    expect(screen.getByRole('button', { name: 'الصفحة 1، الحالية' }).getAttribute('aria-current')).toBe('page')

    rerender(<Pagination page={3} totalPages={3} onPageChange={onPageChange} />)
    expect((screen.getByRole('button', { name: 'الصفحة التالية' }) as HTMLButtonElement).disabled).toBe(true)
  })

  it('supports a compact page summary for touch-heavy surfaces', () => {
    render(<Pagination page={2} totalPages={5} compact onPageChange={() => undefined} />)

    expect(screen.getByText('2 / 5')).not.toBeNull()
    expect(screen.queryByRole('button', { name: 'الصفحة 1' })).toBeNull()
  })
})
