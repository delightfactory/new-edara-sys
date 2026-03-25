import { useState, useEffect } from 'react'
import { toast } from 'sonner'
import { PackageSearch, AlertTriangle } from 'lucide-react'
import { getStock, getWarehouses } from '@/lib/services/inventory'
import { useAuthStore } from '@/stores/auth-store'
import type { Stock, Warehouse } from '@/lib/types/master-data'
import { formatNumber, formatCurrency } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import SearchInput from '@/components/shared/SearchInput'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'

export default function StockPage() {
  const can = useAuthStore(s => s.can)
  const canViewCosts = can('finance.view_costs')
  const [stock, setStock] = useState<Stock[]>([])
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [whFilter, setWhFilter] = useState('')
  const [lowStockOnly, setLowStockOnly] = useState(false)
  const [page, setPage] = useState(1)
  const [totalPages, setTotalPages] = useState(1)
  const [totalCount, setTotalCount] = useState(0)

  const loadData = async () => {
    setLoading(true)
    try {
      const [res, whs] = await Promise.all([
        getStock({
          search, warehouseId: whFilter, lowStockOnly, page, pageSize: 25,
        }),
        warehouses.length ? Promise.resolve(warehouses) : getWarehouses(),
      ])
      setStock(res.data)
      setTotalPages(res.totalPages)
      setTotalCount(res.count)
      if (!warehouses.length) setWarehouses(whs as Warehouse[])
    } catch { toast.error('فشل تحميل أرصدة المخزون') }
    finally { setLoading(false) }
  }

  useEffect(() => { loadData() }, [search, whFilter, lowStockOnly, page])

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="أرصدة المخزون"
        subtitle={loading ? '...' : `${totalCount} سجل`}
      />

      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="flex gap-4" style={{ flexWrap: 'wrap', alignItems: 'center' }}>
          <div style={{ flex: 1, minWidth: 200 }}>
            <SearchInput
              value={search}
              onChange={val => { setSearch(val); setPage(1) }}
              placeholder="بحث بالمنتج..."
            />
          </div>
          <select className="form-select" style={{ width: 160 }} value={whFilter}
            onChange={e => { setWhFilter(e.target.value); setPage(1) }}>
            <option value="">كل المخازن</option>
            {warehouses.map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
          </select>
          <label style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', fontSize: 'var(--text-sm)', cursor: 'pointer' }}>
            <input type="checkbox" checked={lowStockOnly} onChange={e => { setLowStockOnly(e.target.checked); setPage(1) }} />
            <AlertTriangle size={14} style={{ color: 'var(--color-warning)' }} />
            أقل من الحد الأدنى
          </label>
        </div>
      </div>

      <div className="edara-card" style={{ overflow: 'auto' }}>
        <DataTable<Stock>
          columns={[
            {
              key: 'product', label: 'المنتج',
              render: s => (
                <>
                  <div style={{ fontWeight: 600 }}>{s.product?.name || '—'}</div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }} dir="ltr">{s.product?.sku}</div>
                </>
              ),
            },
            { key: 'warehouse', label: 'المخزن', render: s => s.warehouse?.name || '—' },
            { key: 'quantity', label: 'الكمية', render: s => <span style={{ fontWeight: 600 }}>{formatNumber(s.quantity)}</span> },
            { key: 'reserved', label: 'المحجوز', hideOnMobile: true, render: s => formatNumber(s.reserved_quantity) },
            {
              key: 'available', label: 'المتاح',
              render: s => {
                const isLow = s.product && s.quantity <= 0
                return <span style={{ fontWeight: 700, color: isLow ? 'var(--color-danger)' : 'var(--color-success)' }}>{formatNumber(s.available_quantity)}</span>
              },
            },
            ...(canViewCosts ? [
              { key: 'wac' as const, label: 'التكلفة المرجحة', hideOnMobile: true, render: (s: Stock) => formatCurrency(s.wac) },
              { key: 'value' as const, label: 'القيمة', hideOnMobile: true, render: (s: Stock) => <span style={{ fontWeight: 600 }}>{formatCurrency(s.total_cost_value)}</span> },
            ] : []),
            {
              key: 'status', label: 'الحالة',
              render: s => {
                const isLow = s.product && s.quantity <= 0
                return isLow
                  ? <Badge variant="danger"><AlertTriangle size={10} /> منخفض</Badge>
                  : <Badge variant="success">كافي</Badge>
              },
            },
          ]}
          data={stock}
          loading={loading}
          emptyIcon={<PackageSearch size={48} />}
          emptyTitle="لا يوجد أرصدة"
          emptyText="لم يتم العثور على أرصدة مطابقة"
          page={page}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setPage}
        />
      </div>
    </div>
  )
}
