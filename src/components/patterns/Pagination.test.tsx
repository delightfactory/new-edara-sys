import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import Pagination from './Pagination'

const stylesheetPath = fileURLToPath(new URL('../../styles/design-system-v2-pagination.css', import.meta.url))
const stylesheet = readFileSync(stylesheetPath, 'utf8')

describe('Pagination', () => {
  it('exposes current-page semantics and preserves the established five-page window', () => {
    render(
      <Pagination
        page={4}
        totalPages={8}
        totalCount={173}
        onPageChange={() => undefined}
      />,
    )

    expect(screen.getByRole('navigation', { name: 'ترقيم صفحات البيانات' })).toBeInTheDocument()
    expect(screen.getByText('صفحة 4 من 8 (173)')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'الصفحة 4' })).toHaveAttribute('aria-current', 'page')
    expect(screen.getByRole('button', { name: 'الصفحة 2' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'الصفحة 6' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'الصفحة 1' })).not.toBeInTheDocument()
  })

  it('delegates bounded previous, numbered and next page requests', () => {
    const onPageChange = vi.fn()
    render(
      <Pagination
        page={2}
        totalPages={4}
        onPageChange={onPageChange}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: 'الصفحة السابقة' }))
    fireEvent.click(screen.getByRole('button', { name: 'الصفحة 4' }))
    fireEvent.click(screen.getByRole('button', { name: 'الصفحة التالية' }))

    expect(onPageChange.mock.calls).toEqual([[1], [4], [3]])
  })

  it('disables boundary navigation and renders nothing for a single page', () => {
    const { rerender } = render(
      <Pagination
        page={1}
        totalPages={3}
        onPageChange={() => undefined}
      />,
    )

    expect(screen.getByRole('button', { name: 'الصفحة السابقة' })).toBeDisabled()

    rerender(
      <Pagination
        page={3}
        totalPages={3}
        onPageChange={() => undefined}
      />,
    )
    expect(screen.getByRole('button', { name: 'الصفحة التالية' })).toBeDisabled()

    rerender(
      <Pagination
        page={1}
        totalPages={1}
        onPageChange={() => undefined}
      />,
    )
    expect(screen.queryByRole('navigation')).not.toBeInTheDocument()
  })

  it('keeps pagination controls on the canonical touch target through Tablet without changing Desktop density', () => {
    const tabletMediaStart = stylesheet.indexOf('@media (max-width: 1024px)')
    const mobileMediaStart = stylesheet.indexOf('@media (max-width: 768px)')

    expect(tabletMediaStart).toBeGreaterThan(-1)
    expect(mobileMediaStart).toBeGreaterThan(tabletMediaStart)

    const tabletContract = stylesheet.slice(tabletMediaStart, mobileMediaStart)
    expect(tabletContract).toContain('.ds-pagination .pagination-btn')
    expect(tabletContract).toContain('min-width: var(--ds-icon-hit-target)')
    expect(tabletContract).toContain('height: var(--ds-icon-hit-target)')
    expect(tabletContract).toContain('.pagination-btn.pagination-btn-nav')
  })
})
