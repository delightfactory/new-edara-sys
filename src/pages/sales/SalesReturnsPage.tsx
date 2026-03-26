import { useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { RotateCcw, Eye, Plus } from 'lucide-react'
import { useSalesReturns } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import type { SalesReturn, SalesReturnStatus } from '@/lib/types/master-data'
import { formatNumber } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import SearchInput from '@/components/shared/SearchInput'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'

const statusLabels: Record<SalesReturnStatus, string> = {
  draft: 'مسودة', confirmed: 'مؤكد', cancelled: 'ملغي',
}
const statusVariants: Record<SalesReturnStatus, 'neutral' | 'success' | 'danger'> = {
  draft: 'neutral', confirmed: 'success', cancelled: 'danger',
}

export default function SalesReturnsPage() {
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState<SalesReturnStatus | ''>('')
  const [page, setPage] = useState(1)

  const queryParams = useMemo(() => ({
    search: search || undefined,
    status: statusFilter || undefined,
    page,
    pageSize: 25,
  }), [search, statusFilter, page])

  const { data: result, isLoading: loading } = useSalesReturns(queryParams)
  const returns = result?.data ?? []
  const totalPages = result?.totalPages ?? 1
  const totalCount = result?.count ?? 0

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="مرتجعات المبيعات"
        subtitle={loading ? '...' : `${totalCount} مرتجع`}
        actions={can('sales.returns.create') ? (
          <Button icon={<Plus size={16} />} onClick={() => navigate('/sales/returns/new')}>
            مرتجع جديد
          </Button>
        ) : undefined}
      />

      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="flex gap-3" style={{ flexWrap: 'wrap' }}>
          <div style={{ flex: 2, minWidth: 200 }}>
            <SearchInput value={search} onChange={val => { setSearch(val); setPage(1) }}
              placeholder="بحث برقم المرتجع..." />
          </div>
          <select className="form-select" style={{ width: 130 }} value={statusFilter}
            onChange={e => { setStatusFilter(e.target.value as any); setPage(1) }}>
            <option value="">كل الحالات</option>
            <option value="draft">مسودة</option>
            <option value="confirmed">مؤكد</option>
            <option value="cancelled">ملغي</option>
          </select>
        </div>
      </div>

      <div className="edara-card" style={{ overflow: 'auto' }}>
        <DataTable<SalesReturn>
          columns={[
            {
              key: 'return_number', label: 'رقم المرتجع',
              render: r => (
                <>
                  <div style={{ fontWeight: 600, fontFamily: 'monospace' }} dir="ltr">{r.return_number}</div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                    {new Date(r.return_date).toLocaleDateString('ar-EG')}
                  </div>
                </>
              ),
            },
            {
              key: 'order', label: 'الفاتورة الأصلية',
              render: r => (
                <span style={{ fontFamily: 'monospace', color: 'var(--color-primary)', cursor: 'pointer' }}
                  onClick={e => { e.stopPropagation(); navigate(`/sales/orders/${r.order_id}`) }}>
                  {r.order?.order_number || '—'}
                </span>
              ),
            },
            {
              key: 'customer', label: 'العميل',
              render: r => r.customer?.name || '—',
            },
            {
              key: 'total', label: 'الإجمالي', hideOnMobile: true,
              render: r => (
                <span style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>
                  {formatNumber(r.total_amount)} ج.م
                </span>
              ),
            },
            {
              key: 'reason', label: 'السبب', hideOnMobile: true,
              render: r => r.reason ? (
                <span style={{ fontSize: 'var(--text-xs)', maxWidth: 150, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', display: 'block' }}>
                  {r.reason}
                </span>
              ) : <span style={{ color: 'var(--text-muted)' }}>—</span>,
            },
            {
              key: 'status', label: 'الحالة',
              render: r => <Badge variant={statusVariants[r.status]}>{statusLabels[r.status]}</Badge>,
            },
            {
              key: 'actions', label: '', width: 50,
              render: r => (
                <div onClick={e => e.stopPropagation()}>
                  <Button variant="ghost" size="sm" onClick={() => navigate(`/sales/returns/${r.id}`)}>
                    <Eye size={14} />
                  </Button>
                </div>
              ),
            },
          ]}
          data={returns}
          loading={loading}
          onRowClick={r => navigate(`/sales/returns/${r.id}`)}
          emptyIcon={<RotateCcw size={48} />}
          emptyTitle="لا توجد مرتجعات"
          emptyText="لم يتم تسجيل أي مرتجع بعد"
          page={page}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setPage}
        />
      </div>
    </div>
  )
}
