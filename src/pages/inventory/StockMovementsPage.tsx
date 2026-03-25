import { useState, useEffect } from 'react'
import { toast } from 'sonner'
import { Activity } from 'lucide-react'
import { getStockMovements, getWarehouses } from '@/lib/services/inventory'
import { useAuthStore } from '@/stores/auth-store'
import type { StockMovement, Warehouse } from '@/lib/types/master-data'
import { formatNumber, formatCurrency, formatDateShort } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import Badge from '@/components/ui/Badge'

const typeLabels: Record<string, { label: string; variant: 'success' | 'danger' | 'info' | 'warning' | 'primary' }> = {
  in: { label: 'وارد', variant: 'success' },
  out: { label: 'صادر', variant: 'danger' },
  transfer_in: { label: 'تحويل وارد', variant: 'info' },
  transfer_out: { label: 'تحويل صادر', variant: 'warning' },
  adjustment_add: { label: 'تسوية +', variant: 'primary' },
  adjustment_remove: { label: 'تسوية −', variant: 'danger' },
  return_in: { label: 'مرتجع وارد', variant: 'info' },
  return_out: { label: 'مرتجع صادر', variant: 'warning' },
}

export default function StockMovementsPage() {
  const can = useAuthStore(s => s.can)
  const canViewCosts = can('finance.view_costs')
  const [movements, setMovements] = useState<StockMovement[]>([])
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [loading, setLoading] = useState(true)
  const [whFilter, setWhFilter] = useState('')
  const [typeFilter, setTypeFilter] = useState('')
  const [page, setPage] = useState(1)
  const [totalPages, setTotalPages] = useState(1)
  const [totalCount, setTotalCount] = useState(0)

  const load = async () => {
    setLoading(true)
    try {
      const [res, whs] = await Promise.all([
        getStockMovements({
          warehouseId: whFilter || undefined,
          type: typeFilter || undefined,
          page, pageSize: 50,
        }),
        warehouses.length ? Promise.resolve(warehouses) : getWarehouses(),
      ])
      setMovements(res.data)
      setTotalPages(res.totalPages)
      setTotalCount(res.count)
      if (!warehouses.length) setWarehouses(whs as Warehouse[])
    } catch { toast.error('فشل تحميل حركات المخزون') }
    finally { setLoading(false) }
  }

  useEffect(() => { load() }, [whFilter, typeFilter, page])

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="حركات المخزون"
        subtitle={loading ? '...' : `${totalCount} حركة`}
      />

      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="flex gap-4" style={{ flexWrap: 'wrap' }}>
          <select className="form-select" style={{ width: 160 }} value={whFilter}
            onChange={e => { setWhFilter(e.target.value); setPage(1) }}>
            <option value="">كل المخازن</option>
            {warehouses.map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
          </select>
          <select className="form-select" style={{ width: 160 }} value={typeFilter}
            onChange={e => { setTypeFilter(e.target.value); setPage(1) }}>
            <option value="">كل الأنواع</option>
            {Object.entries(typeLabels).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
          </select>
        </div>
      </div>

      <div className="edara-card" style={{ overflow: 'auto' }}>
        {loading ? (
          <div style={{ padding: 'var(--space-6)' }}>
            {[1,2,3,4,5,6,7,8].map(i => <div key={i} className="skeleton skeleton-row" />)}
          </div>
        ) : movements.length === 0 ? (
          <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
            <Activity size={48} className="empty-state-icon" />
            <p className="empty-state-title">لا يوجد حركات</p>
            <p className="empty-state-text">لم يتم العثور على حركات مطابقة</p>
          </div>
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th>التاريخ</th>
                <th>المخزن</th>
                <th>المنتج</th>
                <th>النوع</th>
                <th>الكمية</th>
                {canViewCosts && <th className="hide-mobile">تكلفة الوحدة</th>}
                {canViewCosts && <th className="hide-mobile">WAC قبل</th>}
                {canViewCosts && <th className="hide-mobile">WAC بعد</th>}
                <th className="hide-mobile">الرصيد قبل</th>
                <th className="hide-mobile">الرصيد بعد</th>
                <th className="hide-mobile">المرجع</th>
                <th className="hide-mobile">بواسطة</th>
              </tr>
            </thead>
            <tbody>
              {movements.map(m => (
                <tr key={m.id}>
                  <td style={{ fontSize: 'var(--text-xs)', whiteSpace: 'nowrap' }}>
                    {formatDateShort(m.created_at)}
                  </td>
                  <td>{m.warehouse?.name || '—'}</td>
                  <td>
                    <div style={{ fontWeight: 600 }}>{m.product?.name || '—'}</div>
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }} dir="ltr">{m.product?.sku}</div>
                  </td>
                  <td>
                    <Badge variant={typeLabels[m.type]?.variant || 'neutral'}>{typeLabels[m.type]?.label || m.type}</Badge>
                  </td>
                  <td style={{ fontWeight: 700, color: m.type.includes('in') || m.type.includes('add') ? 'var(--color-success)' : 'var(--color-danger)' }}>
                    {m.type.includes('in') || m.type.includes('add') ? '+' : '−'}{formatNumber(Math.abs(m.quantity))}
                  </td>
                  {canViewCosts && <td className="hide-mobile">{formatCurrency(m.unit_cost)}</td>}
                  {canViewCosts && <td className="hide-mobile">{formatCurrency(m.wac_before)}</td>}
                  {canViewCosts && <td className="hide-mobile">{formatCurrency(m.wac_after)}</td>}
                  <td className="hide-mobile">{formatNumber(m.before_qty)}</td>
                  <td className="hide-mobile">{formatNumber(m.after_qty)}</td>
                  <td className="hide-mobile" style={{ fontSize: 'var(--text-xs)' }}>
                    {m.reference_type && <Badge variant="neutral">{m.reference_type}</Badge>}
                  </td>
                  <td className="hide-mobile" style={{ fontSize: 'var(--text-xs)' }}>{m.created_by_profile?.full_name || '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}

        {totalPages > 1 && (
          <div className="pagination" style={{ padding: 'var(--space-4)' }}>
            <span className="pagination-info">صفحة {page} من {totalPages}</span>
            <div className="pagination-buttons">
              <button className="pagination-btn" disabled={page <= 1} onClick={() => setPage(p => p - 1)}>‹</button>
              <button className="pagination-btn" disabled={page >= totalPages} onClick={() => setPage(p => p + 1)}>›</button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
