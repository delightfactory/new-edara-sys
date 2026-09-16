import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const sourcePath = fileURLToPath(new URL('./SalesOrdersPage.tsx', import.meta.url))
const source = readFileSync(sourcePath, 'utf8')

describe('SalesOrdersPage V2 composition contract', () => {
  it('uses one shared responsive collection boundary instead of CSS-hidden duplicate trees', () => {
    expect(source).toContain("import ResponsiveCollection from '@/components/patterns/ResponsiveCollection'")
    expect(source).toContain('<ResponsiveCollection<SalesOrder>')
    expect(source).toContain('renderDesktop={items =>')
    expect(source).toContain('renderTablet={items =>')
    expect(source).toContain('renderMobile={items =>')
    expect(source).not.toContain("import DataCard from '@/components/ui/DataCard'")
    expect(source).not.toContain('sales-table-view')
    expect(source).not.toContain('sales-card-view')
  })

  it('preserves paged Desktop/Tablet data and accumulated Mobile infinite-list data', () => {
    expect(source).toContain('const [desktopPage, setDesktopPage] = useState(1)')
    expect(source).toContain('const [mobilePage, setMobilePage] = useState(1)')
    expect(source).toContain('const desktopParams = useMemo(() => ({ ...filterParams, page: desktopPage, pageSize: PAGE_SIZE })')
    expect(source).toContain('const mobileParams = useMemo(() => ({ ...filterParams, page: mobilePage, pageSize: PAGE_SIZE })')
    expect(source).toContain('useMobileInfiniteList<SalesOrder>')
    expect(source).toContain('desktopItems: desktopOrders')
    expect(source).toContain('mobileItems: mobileOrders')
    expect(source).toContain("renderOrderCard(order, 'tablet')")
    expect(source).toContain('renderNumberedPagination()')
    expect(source).toContain("renderOrderCard(order, 'mobile')")
    expect(source).toContain('ref={sentinelRef}')
  })

  it('keeps Sales financial projection page-owned while sharing only presentation', () => {
    expect(source).toContain('const collected = order.paid_amount + order.returned_amount')
    expect(source).toContain('const outstanding = Math.max(0, order.total_amount - collected)')
    expect(source).toContain('const paidRatio = order.total_amount > 0 ? collected / order.total_amount : 0')
    expect(source).toContain('paidPercent: order.total_amount > 0 ? Math.round(paidRatio * 100) : undefined')
    expect(source).toContain('progressPercent: order.total_amount > 0 ? paidRatio * 100 : undefined')
    expect(source).toContain('<SalesOrderStatusBadge status={o.status} />')
  })

  it('preserves URL-synced filters, permission gates, Smart Transfer and route destinations', () => {
    expect(source).toContain('urlSync: true')
    expect(source).toContain("setFilters({ governorateId: govId, cityId: '' } as any)")
    expect(source).toContain("can('sales.orders.create')")
    expect(source).toContain('setSmartTransferOpen(true)')
    expect(source).toContain("navigate('/sales/orders/new')")
    expect(source).toContain('navigate(`/sales/orders/${order.id}`)')
    expect(source).toContain('<SmartTransferDialog')
  })
})
