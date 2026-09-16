import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const sourcePath = fileURLToPath(new URL('./StockPage.tsx', import.meta.url))
const source = readFileSync(sourcePath, 'utf8')

describe('StockPage V2 composition contract', () => {
  it('uses one responsive collection boundary with deliberate Desktop, Tablet and Mobile renderers', () => {
    expect(source).toContain("import ResponsiveCollection from '@/components/patterns/ResponsiveCollection'")
    expect(source).toContain('<ResponsiveCollection<Stock>')
    expect(source).toContain('renderDesktop={items =>')
    expect(source).toContain("renderTablet={items => renderCardCollection(items, 'tablet')}")
    expect(source).toContain("renderMobile={items => renderCardCollection(items, 'mobile')}")
    expect(source).not.toContain('stock-table-view')
    expect(source).not.toContain('stock-card-view')
  })

  it('preserves the existing paged stock query and device-specific pagination capability', () => {
    expect(source).toContain('search: lowStockOnly ? undefined : search')
    expect(source).toContain('warehouseId: whFilter')
    expect(source).toContain('lowStockOnly,')
    expect(source).toContain('stockStatus: effectiveStockStatus')
    expect(source).toContain('page,')
    expect(source).toContain('pageSize: 25')
    expect(source).toContain('useEffect(() => { setPage(1) }, [search, whFilter, lowStockOnly, stockStatus2])')
    expect(source).toContain('page={page}')
    expect(source).toContain('totalPages={totalPages}')
    expect(source).toContain('onPageChange={setPage}')
    expect(source).toContain("if (mode === 'tablet')")
    expect(source).toContain('Array.from({ length: Math.min(totalPages, 5) }')
    expect(source).toContain("className={`pagination-btn${num === page ? ' active' : ''}`}")
    expect(source).toContain('disabled={page <= 1}')
    expect(source).toContain('disabled={page >= totalPages}')
  })

  it('keeps stock health, valuation permission and local review calculations page-owned', () => {
    expect(source).toContain("const canViewCosts = can('finance.view_costs')")
    expect(source).toContain('const outOfStock = stock.filter(s => s.available_quantity <= 0).length')
    expect(source).toContain('const lowStock   = stock.filter(s => s.available_quantity > 0 && s.product && s.quantity <= (s.product as any).min_stock_level).length')
    expect(source).toContain('return a - s.available_quantity')
    expect(source).toContain("weightedCost: canViewCosts && (mode === 'tablet' || s.wac > 0) ? formatCurrency(s.wac) : undefined")
    expect(source).toContain("stockValue: mode === 'tablet' && canViewCosts ? formatCurrency(s.total_cost_value) : undefined")
    expect(source).toContain("actualValue: actualCounts[s.id] ?? ''")
    expect(source).toContain('onActualValueChange: value => setActualCounts')
    expect(source).toContain('هذه مراجعة محلية لا تنشئ تسوية ولا تحفظ العد الفعلي')
  })

  it('reuses shared Inventory card/status/button presentation without moving product or warehouse links', () => {
    expect(source).toContain("import { StockBalanceCard } from '@/components/inventory/StockListPresentation'")
    expect(source).toContain('<StockBalanceCard')
    expect(source).toContain('<ProductLink')
    expect(source).toContain('<WarehouseLink')
    expect(source).toContain('<StatusBadge')
    expect(source).toContain('<Button')
    expect(source).toContain('touchTarget')
  })
})
