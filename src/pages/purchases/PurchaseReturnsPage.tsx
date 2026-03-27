import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { RotateCcw, Search, TrendingDown, Building2, Package } from 'lucide-react'
import { useAuthStore } from '@/stores/auth-store'
import { getPurchaseReturns } from '@/lib/services/purchase-returns'
import { formatCurrency } from '@/lib/utils/format'
import type { PurchaseReturnStatus } from '@/lib/types/master-data'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'

const STATUS_MAP: Record<string, { label: string; variant: 'neutral' | 'success' | 'warning' | 'danger' }> = {
  draft:     { label: 'مسودة', variant: 'neutral'  },
  confirmed: { label: 'مؤكد',  variant: 'success'  },
}

export default function PurchaseReturnsPage() {
  const navigate = useNavigate()
  const can      = useAuthStore(s => s.can)

  const [search, setSearch] = useState('')
  const [status, setStatus] = useState<PurchaseReturnStatus | ''>('')
  const [page, setPage]     = useState(1)
  const pageSize = 25

  const { data, isLoading } = useQuery({
    queryKey: ['purchase-returns', search, status, page],
    queryFn:  () => getPurchaseReturns({
      search:   search || undefined,
      status:   (status || undefined) as PurchaseReturnStatus | undefined,
      page, pageSize,
    }),
  })

  const returns    = data?.data    || []
  const totalPages = data?.totalPages || 1
  const totalCount = data?.count ?? returns.length

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="مرتجعات المشتريات"
        subtitle={isLoading ? '...' : `${totalCount} مرتجع`}
        actions={
          can('procurement.returns.create') ? (
            <Button icon={<RotateCcw size={16} />} onClick={() => navigate('/purchases/returns/new')}>
              مرتجع جديد
            </Button>
          ) : undefined
        }
      />

      {/* ── Filters ─────────────────────────────────────────── */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="flex gap-4" style={{ flexWrap: 'wrap' }}>
          <div style={{ position: 'relative', flex: '1 1 200px', minWidth: 180 }}>
            <Search size={14} style={{ position: 'absolute', insetInlineEnd: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)', pointerEvents: 'none' }} />
            <input
              className="form-input"
              style={{ paddingInlineEnd: 32 }}
              placeholder="بحث بالرقم..."
              value={search}
              onChange={e => { setSearch(e.target.value); setPage(1) }}
            />
          </div>
          <select
            className="form-select"
            style={{ width: 140 }}
            value={status}
            onChange={e => { setStatus(e.target.value as PurchaseReturnStatus | ''); setPage(1) }}
          >
            <option value="">كل الحالات</option>
            <option value="draft">مسودة</option>
            <option value="confirmed">مؤكد</option>
          </select>
        </div>
      </div>

      {/* ── DESKTOP: DataTable ─────────────────────────────── */}
      <div className="pret-table-view edara-card" style={{ overflow: 'auto' }}>
        <DataTable<any>
          columns={[
            { key: 'number',      label: 'الرقم',      render: r => <span style={{ fontWeight: 700, fontFamily: 'monospace', color: 'var(--color-primary)', direction: 'ltr', display: 'inline-block' }}>{r.number}</span> },
            { key: 'supplier',    label: 'المورد',     render: r => r.supplier?.name || '—' },
            { key: 'warehouse',   label: 'المخزن',     hideOnMobile: true, render: r => r.warehouse?.name || '—' },
            { key: 'return_date', label: 'التاريخ',    hideOnMobile: true, render: r => r.return_date },
            { key: 'total_amount',label: 'الإجمالي',   render: r => (
                <span style={{ fontWeight: 700, color: 'var(--color-danger)', fontVariantNumeric: 'tabular-nums' }}>
                  {formatCurrency(r.total_amount)}
                </span>
              )
            },
            { key: 'status', label: 'الحالة', render: r => {
                const cfg = STATUS_MAP[r.status]
                return cfg ? <Badge variant={cfg.variant}>{cfg.label}</Badge> : <Badge>{r.status}</Badge>
              }
            },
          ]}
          data={returns}
          loading={isLoading}
          onRowClick={r => navigate(`/purchases/returns/${r.id}`)}
          emptyIcon={<RotateCcw size={48} />}
          emptyTitle="لا توجد مرتجعات"
          emptyText='اضغط "+ مرتجع" لإنشاء أول مرتجع مشتريات'
          page={page}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setPage}
        />
      </div>

      {/* ── MOBILE: Return Cards ──────────────────────────── */}
      <div className="pret-card-view">
        {isLoading ? (
          <div className="mobile-card-list">
            {[1,2,3].map(i => <div key={i} className="edara-card" style={{ height: 100 }}><div className="skeleton" style={{ height: '100%' }} /></div>)}
          </div>
        ) : returns.length === 0 ? (
          <div className="edara-card" style={{ padding: 'var(--space-8)', textAlign: 'center', color: 'var(--text-muted)' }}>
            <RotateCcw size={40} style={{ margin: '0 auto 12px', display: 'block', opacity: 0.3 }} />
            <p>لا توجد مرتجعات</p>
          </div>
        ) : (
          <div className="mobile-card-list">
            {returns.map((r: any) => {
              const cfg = STATUS_MAP[r.status]
              return (
                <div
                  key={r.id}
                  className="edara-card pret-mobile-card"
                  onClick={() => navigate(`/purchases/returns/${r.id}`)}
                >
                  {/* Header row */}
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 8 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <div style={{ width: 36, height: 36, borderRadius: 'var(--radius-md)', background: 'rgba(239,68,68,0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                        <TrendingDown size={16} style={{ color: 'var(--color-danger)' }} />
                      </div>
                      <div>
                        <div style={{ fontFamily: 'monospace', fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--color-primary)' }} dir="ltr">{r.number}</div>
                        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 2 }}>{r.return_date}</div>
                      </div>
                    </div>
                    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 4 }}>
                      {cfg && <Badge variant={cfg.variant}>{cfg.label}</Badge>}
                      <span style={{ fontWeight: 800, fontSize: '1rem', color: 'var(--color-danger)', fontVariantNumeric: 'tabular-nums' }}>
                        {formatCurrency(r.total_amount)}
                      </span>
                    </div>
                  </div>
                  {/* Meta */}
                  <div style={{ display: 'flex', gap: 12, fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }}>
                    {r.supplier?.name && (
                      <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                        <Building2 size={10} /> {r.supplier.name}
                      </span>
                    )}
                    {r.warehouse?.name && (
                      <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                        <Package size={10} /> {r.warehouse.name}
                      </span>
                    )}
                    <span style={{ marginInlineStart: 'auto', color: 'var(--color-primary)', fontSize: '10px' }}>عرض التفاصيل ›</span>
                  </div>
                </div>
              )
            })}
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
        .pret-table-view { display: block; }
        .pret-card-view  { display: none; }
        .pret-mobile-card { padding: var(--space-4); cursor: pointer; transition: background 0.12s; }
        .pret-mobile-card:hover { background: var(--bg-hover); }
        .mobile-card-list { display: flex; flex-direction: column; gap: var(--space-3); }
        .mobile-pagination { display: flex; align-items: center; justify-content: center; gap: var(--space-4); padding: var(--space-4) 0; }
        @media (max-width: 768px) {
          .pret-table-view { display: none; }
          .pret-card-view  { display: block; }
        }
      `}</style>
    </div>
  )
}
