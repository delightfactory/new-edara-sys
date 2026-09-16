import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const sourcePath = fileURLToPath(new URL('./SalesOrderDetail.tsx', import.meta.url))
const source = readFileSync(sourcePath, 'utf8')

describe('SalesOrderDetail V2 transaction-header contract', () => {
  it('wires the live page through the shared Sales transaction header and removes legacy hero presentation', () => {
    expect(source).toContain("from '@/components/sales/SalesOrderDetailPresentation'")
    expect(source).toContain("from '@/components/patterns/ActionRegistry'")
    expect(source).toContain('<SalesOrderDetailHeader')
    expect(source).toContain('actions={headerActions}')
    expect(source).toContain('tools={<DocumentActions kind="sales-order" entityId={id!} />}')
    expect(source).not.toContain('function ActionBtn(')
    expect(source).not.toContain('statusColors')
    expect(source).not.toContain('statusLabels')
    expect(source).not.toContain("overflowX: 'auto'")
  })

  it('preserves every existing permission and status gate as page-owned action truth', () => {
    expect(source).toContain("if (order.status === 'draft' && can('sales.orders.update'))")
    expect(source).toContain("if (order.status === 'draft' && can('sales.orders.confirm'))")
    expect(source).toContain("if (order.status === 'confirmed' && can('sales.orders.deliver'))")
    expect(source).toContain("const canAdjustDueDate = can('customers.credit.update')")
    expect(source).toContain("&& ['delivered', 'partially_delivered'].includes(order.status)")
    expect(source).toContain("&& ['credit', 'mixed'].includes(order.payment_terms || '')")
    expect(source).toContain("if ((order.status === 'delivered' || order.status === 'completed') && can('sales.returns.create'))")
    expect(source).toContain("if (can('sales.orders.create'))")
    expect(source).toContain("if ((order.status === 'draft' || order.status === 'confirmed') && can('sales.orders.cancel'))")
  })

  it('preserves the live callbacks, routes and confirm-warehouse fallback without moving business behavior', () => {
    expect(source).toContain('onSelect: () => navigate(`/sales/orders/${id}/edit`)')
    expect(source).toContain('let resolvedMyWh = myWarehouses as typeof myWarehouses')
    expect(source).toContain('try { resolvedMyWh = await getMyWarehouses() } catch { resolvedMyWh = [] }')
    expect(source).toContain("const defaultWh = resolvedMyWh.length > 0 ? resolvedMyWh[0].id : ''")
    expect(source).toContain('setConfirmWarehouseId(defaultWh)')
    expect(source).toContain('setShowConfirmModal(true)')
    expect(source).toContain('if (defaultWh) checkStockAvailability(defaultWh)')
    expect(source).toContain('onSelect: openDeliverModal')
    expect(source).toContain('onSelect: openDueDateModal')
    expect(source).toContain('onSelect: () => navigate(`/sales/returns/new?orderId=${order.id}`)')
    expect(source).toContain('onSelect: () => navigate(`/sales/orders/new?copyFrom=${id}`)')
    expect(source).toContain('onSelect: () => setShowCancelModal(true)')
  })

  it('preserves action loading guards while delegating placement and tone to the shared registry', () => {
    expect(source.match(/disabled: actionLoading/g)?.length ?? 0).toBe(4)
    expect(source).toContain("id: 'confirm'")
    expect(source).toContain("id: 'deliver'")
    expect(source).toContain("importance: 'primary'")
    expect(source).toContain("id: 'cancel'")
    expect(source).toContain("tone: 'danger'")
    expect(source).toContain("importance: 'tertiary'")
  })

  it('keeps financial, receipt and modal business surfaces outside this bounded header migration', () => {
    expect(source).toContain("queryKey: ['order-receipts', id]")
    expect(source).toContain('const remaining = order')
    expect(source).toContain('await confirmSalesOrderWithWarehouse(id!, confirmWarehouseId)')
    expect(source).toContain('await deliverSalesOrder(id!, {')
    expect(source).toContain('await cancelSalesOrder(id!, cancelReason)')
    expect(source).toContain('await updateSalesOrderDueDate(order.id, dueDateCreditDays, dueDateReason.trim())')
    expect(source).toContain('<ResponsiveModal')
    expect(source).toContain('<FinBadge label="الإجمالي"')
  })
})
