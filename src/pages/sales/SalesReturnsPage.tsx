import { useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { RotateCcw, Eye, Plus, User, CalendarDays } from 'lucide-react'
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
    page, pageSize: 25,
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
          <Button icon={<Plus size={16} />} onClick={() => navigate('/sales/returns/new')} className="desktop-only-btn">
            مرتجع جديد
          </Button>
        ) : undefined}
      />

      {/* Filters */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div style={{ display: 'flex', gap: 'var(--space-3)', flexWrap: 'wrap' }}>
          <div style={{ flex: 2, minWidth: 180 }}>
            <SearchInput value={search} onChange={val => { setSearch(val); setPage(1) }}
              placeholder="بحث برقم المرتجع أو العميل..." />
          </div>
          <select className="form-select" style={{ width: 140 }} value={statusFilter}
            onChange={e => { setStatusFilter(e.target.value as any); setPage(1) }}>
            <option value="">كل الحالات</option>
            <option value="draft">مسودة</option>
            <option value="confirmed">مؤكد</option>
            <option value="cancelled">ملغي</option>
          </select>
        </div>
      </div>

      {/* ── DESKTOP: DataTable ─────────────────────── */}
      <div className="ret-table-view edara-card" style={{ overflow: 'auto' }}>
        <DataTable<SalesReturn>
          columns={[
            {
              key: 'return_number', label: 'رقم المرتجع',
              render: r => (
                <>
                  <div style={{ fontWeight: 600, fontFamily: 'monospace' }} dir="ltr">{r.return_number}</div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                    {new Date(r.return_date).toLocaleDateString('ar-EG-u-nu-latn')}
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
            { key: 'customer', label: 'العميل', render: r => r.customer?.name || '—' },
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

      {/* ── MOBILE: Return Card List ─────────────────── */}
      <div className="ret-card-view">
        {loading ? (
          <div className="mobile-card-list">
            {[1, 2, 3].map(i => <div key={i} className="edara-card" style={{ height: 96 }}><div className="skeleton" style={{ height: '100%' }} /></div>)}
          </div>
        ) : returns.length === 0 ? (
          <div className="edara-card" style={{ padding: 'var(--space-8)', textAlign: 'center', color: 'var(--text-muted)' }}>
            <RotateCcw size={40} style={{ margin: '0 auto 12px', display: 'block', opacity: 0.3 }} />
            <p>لا توجد مرتجعات</p>
          </div>
        ) : (
          <div className="mobile-card-list">
            {returns.map((r: SalesReturn) => (
              <div key={r.id} className="edara-card ret-mobile-card" onClick={() => navigate(`/sales/returns/${r.id}`)}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 8 }}>
                  <div>
                    <div style={{ fontWeight: 700, fontFamily: 'monospace', fontSize: 'var(--text-sm)' }} dir="ltr">
                      {r.return_number}
                    </div>
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--color-primary)', marginTop: 2, cursor: 'pointer' }}
                      onClick={e => { e.stopPropagation(); navigate(`/sales/orders/${r.order_id}`) }}>
                      ← {r.order?.order_number || '—'}
                    </div>
                  </div>
                  <Badge variant={statusVariants[r.status]}>{statusLabels[r.status]}</Badge>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <div style={{ display: 'flex', gap: 'var(--space-3)', fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                    {r.customer?.name && (
                      <span style={{ display: 'flex', alignItems: 'center', gap: 3 }}>
                        <User size={10} /> {r.customer.name}
                      </span>
                    )}
                    <span style={{ display: 'flex', alignItems: 'center', gap: 3 }}>
                      <CalendarDays size={10} />
                      {new Date(r.return_date).toLocaleDateString('ar-EG-u-nu-latn')}
                    </span>
                  </div>
                  <div style={{ fontWeight: 800, fontSize: '1rem', color: 'var(--color-danger)', fontVariantNumeric: 'tabular-nums' }}>
                    {formatNumber(r.total_amount)} ج.م
                  </div>
                </div>
                {r.reason && (
                  <div style={{ marginTop: 6, fontSize: 'var(--text-xs)', color: 'var(--text-muted)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {r.reason}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
        {totalPages > 1 && (
          <div className="mobile-pagination">
            <Button variant="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(p => p - 1)}>السابق</Button>
            <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>{page} / {totalPages}</span>
            <Button variant="ghost" size="sm" disabled={page >= totalPages} onClick={() => setPage(p => p + 1)}>التالي</Button>
          </div>
        )}
      </div>

      <style>{`
        .ret-table-view { display: block; }
        .ret-card-view  { display: none; }
        .ret-mobile-card { padding: var(--space-4); cursor: pointer; transition: background 0.12s; }
        .ret-mobile-card:hover { background: var(--bg-hover); }
        .mobile-card-list { display: flex; flex-direction: column; gap: var(--space-3); }
        .mobile-pagination { display: flex; align-items: center; justify-content: center; gap: var(--space-4); padding: var(--space-4) 0; }
        @media (max-width: 768px) {
          .desktop-only-btn { display: none !important; }
          .ret-table-view { display: none; }
          .ret-card-view  { display: block; }
        }
      `}</style>
    </div>
  )
}
