import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import DataTable from './DataTable'

describe('DataTable V2 pagination semantics', () => {
  it('exposes a labeled Arabic pagination boundary and current-page semantics without changing page callbacks', () => {
    const onPageChange = vi.fn()

    render(
      <DataTable
        columns={[{ key: 'name', label: 'الاسم' }]}
        data={[{ id: 'row-1', name: 'سجل تجريبي' }]}
        page={2}
        totalPages={5}
        totalCount={87}
        onPageChange={onPageChange}
      />,
    )

    expect(screen.getByRole('navigation', { name: 'ترقيم صفحات البيانات' })).toBeTruthy()
    expect(screen.getByText('صفحة 2 من 5 (87)')).toBeTruthy()

    const previous = screen.getByRole('button', { name: 'الصفحة السابقة' })
    const current = screen.getByRole('button', { name: 'الصفحة 2' })
    const next = screen.getByRole('button', { name: 'الصفحة التالية' })

    expect(previous.textContent).toBe('السابق')
    expect(next.textContent).toBe('التالي')
    expect(current.getAttribute('aria-current')).toBe('page')
    expect(screen.getByRole('button', { name: 'الصفحة 1' }).getAttribute('aria-current')).toBeNull()

    fireEvent.click(previous)
    fireEvent.click(screen.getByRole('button', { name: 'الصفحة 4' }))
    fireEvent.click(next)

    expect(onPageChange).toHaveBeenNthCalledWith(1, 1)
    expect(onPageChange).toHaveBeenNthCalledWith(2, 4)
    expect(onPageChange).toHaveBeenNthCalledWith(3, 3)
  })

  it('preserves previous/next disabled conditions at the boundaries', () => {
    const { rerender } = render(
      <DataTable
        columns={[{ key: 'name', label: 'الاسم' }]}
        data={[{ id: 'row-1', name: 'سجل تجريبي' }]}
        page={1}
        totalPages={3}
        onPageChange={() => undefined}
      />,
    )

    expect((screen.getByRole('button', { name: 'الصفحة السابقة' }) as HTMLButtonElement).disabled).toBe(true)
    expect((screen.getByRole('button', { name: 'الصفحة التالية' }) as HTMLButtonElement).disabled).toBe(false)

    rerender(
      <DataTable
        columns={[{ key: 'name', label: 'الاسم' }]}
        data={[{ id: 'row-1', name: 'سجل تجريبي' }]}
        page={3}
        totalPages={3}
        onPageChange={() => undefined}
      />,
    )

    expect((screen.getByRole('button', { name: 'الصفحة السابقة' }) as HTMLButtonElement).disabled).toBe(false)
    expect((screen.getByRole('button', { name: 'الصفحة التالية' }) as HTMLButtonElement).disabled).toBe(true)
  })
})
