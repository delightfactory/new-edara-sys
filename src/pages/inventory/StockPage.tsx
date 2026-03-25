import { useState, useMemo } from 'react'
import { PackageSearch, AlertTriangle } from 'lucide-react'
import { useStock, useWarehouses } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import type { Stock } from '@/lib/types/master-data'
import { formatNumber, formatCurrency } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import SearchInput from '@/components/shared/SearchInput'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'

export default function StockPage() {
  const can = useAuthStore(s => s.can)
  const canViewCosts = can('finance.view_costs')
  const [search, setSearch] = useState('')
  const [whFilter, setWhFilter] = useState('')
  const [lowStockOnly, setLowStockOnly] = useState(false)
  const [page, setPage] = useState(1)

  // React Query — cached & shared
  const { data: warehouses = [] } = useWarehouses()

  const queryParams = useMemo(() => ({
    search, warehouseId: whFilter, lowStockOnly, page, pageSize: 25,
  }), [search, whFilter, lowStockOnly, page])

  const { data: result, isLoading: loading } = useStock(queryParams)
  const stock = result?.data ?? []
  const totalPages = result?.totalPages ?? 1
  const totalCount = result?.count ?? 0

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
