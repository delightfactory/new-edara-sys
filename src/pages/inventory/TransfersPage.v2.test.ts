import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const sourcePath = fileURLToPath(new URL('./TransfersPage.tsx', import.meta.url))
const source = readFileSync(sourcePath, 'utf8')

describe('TransfersPage V2 composition contract', () => {
  it('uses one ResponsiveCollection boundary with deliberate Desktop, Tablet and Mobile renderers', () => {
    expect(source).toContain("import ResponsiveCollection from '@/components/patterns/ResponsiveCollection'")
    expect(source).toContain("import { TransferCard } from '@/components/inventory/TransferListPresentation'")
    expect(source).toContain('<ResponsiveCollection<StockTransfer>')
    expect(source).toContain('renderDesktop={items =>')
    expect(source).toContain("renderTablet={items => renderCardCollection(items, 'tablet')}")
    expect(source).toContain("renderMobile={items => renderCardCollection(items, 'mobile')}")
    expect(source).toContain("gridTemplateColumns: mode === 'tablet' ? 'repeat(2, minmax(0, 1fr))' : 'minmax(0, 1fr)'")
    expect(source).not.toContain('tr-table-view')
    expect(source).not.toContain('tr-card-view')
    expect(source).not.toContain('tr-mobile-card')
  })

  it('preserves the existing transfer query and previous/next pagination semantics', () => {
    expect(source).toContain('status: (statusFilter || undefined) as TransferStatus | undefined')
    expect(source).toContain('page, pageSize: 25')
    expect(source).toContain("onChange={e => { setStatusFilter(e.target.value); setPage(1) }}")
    expect(source).toContain('disabled={page <= 1}')
    expect(source).toContain('onClick={() => setPage(p => p - 1)}')
    expect(source).toContain('disabled={page >= totalPages}')
    expect(source).toContain('onClick={() => setPage(p => p + 1)}')
    expect(source).toContain('السابق')
    expect(source).toContain('التالي')
    expect(source).not.toContain('Array.from({ length: Math.min(totalPages')
  })

  it('keeps exact page-owned transfer workflow predicates and callbacks', () => {
    expect(source).toContain("t.status === 'pending' && t.direction === 'push' && iManageSource")
    expect(source).toContain("setConfirmAction({ transfer: t, action: 'ship' })")
    expect(source).toContain("t.status === 'pending' && t.direction === 'pull' && iManageSource")
    expect(source).toContain("setConfirmAction({ transfer: t, action: 'approve_ship' })")
    expect(source).toContain("t.status === 'in_transit' && iManageDest && t.approved_by !== userId")
    expect(source).toContain("setConfirmAction({ transfer: t, action: 'receive' })")
    expect(source).toContain("t.status === 'pending' && iAmCreator")
    expect(source).toContain("t.status === 'in_transit' && iManageSource")
    expect(source).toContain("setConfirmAction({ transfer: t, action: 'cancel' })")
    expect(source).toContain('iManageSource: isAdmin || myWhIds.has(t.from_warehouse_id)')
    expect(source).toContain('iManageDest: isAdmin || myWhIds.has(t.to_warehouse_id)')
    expect(source).toContain('iAmCreator: isAdmin || t.requested_by === userId')
  })

  it('keeps Desktop expansion and authorized cost review capability', () => {
    expect(source).toContain("const canViewCosts = can('finance.view_costs')")
    expect(source).toContain('expandedId === t.id && t.items && t.items.length > 0')
    expect(source).toContain('{canViewCosts && <th>تكلفة الوحدة</th>}')
    expect(source).toContain("{canViewCosts && <td>{it.unit_cost ? formatCurrency(it.unit_cost) : '—'}</td>}")
    expect(source).toContain('ملاحظات: {t.notes}')
    expect(source).toContain('تاريخ الشحن: {formatDateShort(t.sent_at)}')
    expect(source).toContain('تاريخ الاستلام: {formatDateShort(t.received_at)}')
  })

  it('makes the migrated Desktop collection keyboard, screen-reader and RTL complete', () => {
    expect(source).toContain("import { Link, useNavigate } from 'react-router-dom'")
    expect(source).toContain("aria-label={`${expandedId === t.id ? 'طي' : 'عرض'} بنود التحويل ${t.number}`}")
    expect(source).toContain('aria-expanded={expandedId === t.id}')
    expect(source).toContain('to={`/inventory/transfers/${t.id}`}')
    expect(source).toContain('aria-label={`عرض تفاصيل التحويل ${t.number}`}')
    expect(source).not.toContain("onClick={() => navigate(`/inventory/transfers/${t.id}`)}")
    expect(source).toContain('aria-label="الصفحة السابقة"')
    expect(source).toContain('aria-label="الصفحة التالية"')
    expect(source).not.toContain('className="pagination-btn"')
    expect(source).not.toContain('>‹</button>')
    expect(source).not.toContain('>›</button>')
  })

  it('treats direction as categorical metadata and status as semantic workflow state', () => {
    expect(source).toContain('<Badge variant="neutral">')
    expect(source).toContain("directionLabel: directionLabel(t.direction)")
    expect(source).toContain("directionIcon: t.direction === 'push' ? <Send size={10} /> : <Download size={10} />")
    expect(source).toContain('<StatusBadge')
    expect(source).toContain("statusTone: st?.tone || 'neutral'")
    expect(source).not.toContain('directionTone')
  })

  it('preserves create, stock, confirmation, service and route boundaries', () => {
    expect(source).toContain('await createTransfer(')
    expect(source).toContain('await shipTransfer(confirmAction.transfer.id)')
    expect(source).toContain('await approveAndShipTransfer(confirmAction.transfer.id)')
    expect(source).toContain('await receiveTransfer(confirmAction.transfer.id)')
    expect(source).toContain('await cancelTransfer(confirmAction.transfer.id)')
    expect(source).toContain('await getAvailableStock(sourceWh, productId)')
    expect(source).toContain('queryFn: () => getMyWarehouses()')
    expect(source).toContain('<ResponsiveModal open={createModal}')
    expect(source).toContain('<ConfirmDialog')
    expect(source).toContain("navigate(`/inventory/transfers/${t.id}`)")
    expect(source).toContain("invalidate('transfers')")
  })
})
