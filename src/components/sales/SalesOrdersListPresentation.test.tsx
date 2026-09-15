import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import {
  SALES_ORDER_STATUS_LABELS,
  SalesOrderStatusBadge,
  SalesOrdersKpiGrid,
} from './SalesOrdersListPresentation'

describe('SalesOrdersListPresentation', () => {
  it('maps domain statuses into the shared semantic StatusBadge contract', () => {
    const { rerender } = render(<SalesOrderStatusBadge status="cancelled" />)

    expect(screen.getByText(SALES_ORDER_STATUS_LABELS.cancelled).closest('[data-tone]')?.getAttribute('data-tone')).toBe('danger')

    rerender(<SalesOrderStatusBadge status="delivered" />)
    expect(screen.getByText(SALES_ORDER_STATUS_LABELS.delivered).closest('[data-tone]')?.getAttribute('data-tone')).toBe('success')
  })

  it('renders the existing KPI truth through shared StatCard surfaces without recalculation', () => {
    window.innerWidth = 390

    render(
      <SalesOrdersKpiGrid
        stats={{
          totalSales: 125000.5,
          statusCounts: {
            draft: 3,
            confirmed: 4,
            delivered: 5,
            cancelled: 1,
          },
        }}
      />,
    )

    const region = screen.getByRole('region', { name: 'ملخص أوامر البيع' })
    expect(region.getAttribute('data-device')).toBe('mobile')
    expect(screen.getByText('إجمالي المبيعات')).not.toBeNull()
    expect(screen.getByText('3')).not.toBeNull()
    expect(screen.getByText('4')).not.toBeNull()
    expect(screen.getByText('5')).not.toBeNull()
    expect(screen.getByText('1')).not.toBeNull()
  })

  it('uses the canonical tablet mode instead of collapsing into desktop composition', () => {
    window.innerWidth = 900

    render(
      <SalesOrdersKpiGrid
        stats={{
          totalSales: 0,
          statusCounts: {},
        }}
      />,
    )

    expect(screen.getByRole('region', { name: 'ملخص أوامر البيع' }).getAttribute('data-device')).toBe('tablet')
  })
})
