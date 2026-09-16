import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const sourcePath = fileURLToPath(new URL('./PurchaseInvoicesPage.tsx', import.meta.url))
const source = readFileSync(sourcePath, 'utf8')

describe('PurchaseInvoicesPage V2 composition contract', () => {
  it('uses one responsive collection boundary with deliberate Desktop, Tablet and Mobile renderers', () => {
    expect(source).toContain("import ResponsiveCollection from '@/components/patterns/ResponsiveCollection'")
    expect(source).toContain('<ResponsiveCollection<PurchaseInvoice>')
    expect(source).toContain('renderDesktop={items =>')
    expect(source).toContain("renderTablet={items => renderCardCollection(items, 'tablet')}")
    expect(source).toContain("renderMobile={items => renderCardCollection(items, 'mobile')}")
    expect(source).not.toContain("import DataCard from '@/components/ui/DataCard'")
    expect(source).not.toContain('purch-table-view')
    expect(source).not.toContain('purch-card-view')
  })

  it('preserves purchase query, filter reset and page-size semantics exactly', () => {
    expect(source).toContain("queryKey: ['purchase-invoices', search, statusFilter, page]")
    expect(source).toContain('search:   search  || undefined')
    expect(source).toContain('status:   (statusFilter as PurchaseInvoiceStatus) || undefined')
    expect(source).toContain('page,')
    expect(source).toContain('const PAGE_SIZE = 20')
    expect(source).toContain('pageSize: PAGE_SIZE')
    expect(source).toContain('onChange={val => { setSearch(val); setPage(1) }}')
    expect(source).toContain("onChange={e => { setStatusFilter(e.target.value as PurchaseInvoiceStatus | ''); setPage(1) }}")
    expect(source).toContain('page={page}')
    expect(source).toContain('totalPages={totalPages}')
    expect(source).toContain('onPageChange={setPage}')
  })

  it('keeps Tablet numbered direct jumps while Mobile remains touch-safe previous/next', () => {
    expect(source).toContain("if (mode === 'tablet')")
    expect(source).toContain('aria-label="ترقيم صفحات فواتير الشراء"')
    expect(source).toContain('Array.from({ length: Math.min(totalPages, 5) }')
    expect(source).toContain('onClick={() => setPage(num)}')
    expect(source).toContain("aria-current={num === page ? 'page' : undefined}")
    expect(source).toContain("style={{ minWidth: 'var(--ds-icon-hit-target)' }}")
    expect(source).toContain('touchTarget')
    expect(source).toContain('aria-label="الصفحة السابقة"')
    expect(source).toContain('aria-label="الصفحة التالية"')
    expect(source).toContain('السابق')
    expect(source).toContain('التالي')
  })

  it('keeps supplier, warehouse, money, workflow status and navigation truth page-owned', () => {
    expect(source).toContain('<SupplierLink')
    expect(source).toContain('<WarehouseLink')
    expect(source).toContain('formatNumber(inv.total_amount)')
    expect(source).toContain('formatNumber(inv.paid_amount)')
    expect(source).toContain("paid:      'success'")
    expect(source).toContain("cancelled: 'danger'")
    expect(source).toContain('<StatusBadge')
    expect(source).toContain('<PurchaseInvoiceCard')
    expect(source).toContain("navigate(`/purchases/invoices/${inv.id}`)")
    expect(source).toContain("navigate('/purchases/invoices/new')")
    expect(source).not.toContain("import Badge from '@/components/ui/Badge'")
  })

  it('uses the shared empty-state family without removing the existing create capability', () => {
    expect(source).toContain("import StatePanel from '@/components/patterns/StatePanel'")
    expect(source).toContain('<StatePanel')
    expect(source).toContain('title="لا توجد فواتير مشتريات"')
    expect(source).toContain('description="أنشئ أول فاتورة شراء من المورد"')
    expect(source).toContain('فاتورة جديدة')
  })
})
