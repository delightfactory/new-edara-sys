import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import {
  SALES_ORDER_STATUS_LABELS,
  SalesOrderCard,
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

  it('renders a touch-ready mobile Sales card with semantic status and explicit actions', () => {
    const onOpen = vi.fn()
    const onMap = vi.fn()
    const onCall = vi.fn()

    render(
      <SalesOrderCard
        mode="mobile"
        summary={{
          customerName: 'شركة النور',
          customerCode: 'C-014',
          orderNumber: 'SO-1045',
          orderDate: '16/09/2026',
          status: 'confirmed',
          total: '12,500 ج.م',
          paid: '5,000 ج.م',
          outstanding: '7,500 ج.م',
          paymentTerms: 'آجل',
          representative: 'أحمد علي',
          paidPercent: 40,
        }}
        onOpen={onOpen}
        onMap={onMap}
        onCall={onCall}
      />,
    )

    const card = screen.getByText('شركة النور').closest('[data-sales-order-card]')
    expect(card?.getAttribute('data-mode')).toBe('mobile')
    expect(screen.getByText('مؤكد').closest('[data-tone]')?.getAttribute('data-tone')).toBe('info')
    expect(screen.getByRole('progressbar', { name: 'نسبة سداد أمر البيع' }).getAttribute('aria-valuenow')).toBe('40')

    fireEvent.click(screen.getByRole('button', { name: /عرض الطلب/ }))
    fireEvent.click(screen.getByRole('button', { name: /الخريطة/ }))
    fireEvent.click(screen.getByRole('button', { name: /اتصال/ }))

    expect(onOpen).toHaveBeenCalledTimes(1)
    expect(onMap).toHaveBeenCalledTimes(1)
    expect(onCall).toHaveBeenCalledTimes(1)
  })

  it('keeps tablet composition denser without inventing actions that were not supplied', () => {
    render(
      <SalesOrderCard
        mode="tablet"
        summary={{
          customerName: 'مركز المدينة',
          orderNumber: 'SO-2040',
          orderDate: '15/09/2026',
          status: 'delivered',
          total: '3,200 ج.م',
          paid: '3,200 ج.م',
          paidPercent: 100,
        }}
        onOpen={() => undefined}
      />,
    )

    expect(screen.getByText('مُسلّم').closest('[data-tone]')?.getAttribute('data-tone')).toBe('success')
    expect(screen.queryByRole('button', { name: /الخريطة/ })).toBeNull()
    expect(screen.queryByRole('button', { name: /اتصال/ })).toBeNull()
    expect(screen.getByRole('progressbar', { name: 'نسبة سداد أمر البيع' }).getAttribute('aria-valuenow')).toBe('100')
  })
})
