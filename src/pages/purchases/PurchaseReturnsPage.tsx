import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { RotateCcw, Plus, Search } from 'lucide-react'
import { useAuthStore } from '@/stores/auth-store'
import { getPurchaseReturns } from '@/lib/services/purchase-returns'
import { formatNumber } from '@/lib/utils/format'
import type { PurchaseReturnStatus } from '@/lib/types/master-data'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'

function StatusBadge({ status }: { status: PurchaseReturnStatus }) {
  const map = {
    draft:     { label: 'مسودة', color: '#92400e', bg: '#fef3c7' },
    confirmed: { label: 'مؤكد',  color: '#166534', bg: '#dcfce7' },
  }
  const { label, color, bg } = map[status]
  return (
    <span style={{ padding: '2px 10px', borderRadius: 99, fontSize: '0.75rem', fontWeight: 700, color, background: bg }}>
      {label}
    </span>
  )
}

export default function PurchaseReturnsPage() {
  const navigate = useNavigate()
  const can      = useAuthStore(s => s.can)

  const [search, setSearch]   = useState('')
  const [status, setStatus]   = useState<PurchaseReturnStatus | ''>('')
  const [page, setPage]       = useState(1)
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

  return (
    <div style={{ padding: 'var(--space-4)', maxWidth: 1200, margin: '0 auto', animation: 'fade-in 0.3s ease' }}>
      <PageHeader
        title="مرتجعات المشتريات"
        subtitle="إدارة مرتجعات البضاعة المُعادة للموردين"
        actions={
          can('procurement.returns.create') ? (
            <Button
              variant="primary"
              icon={<Plus size={16} />}
              onClick={() => navigate('/purchases/returns/new')}
            >
              مرتجع جديد
            </Button>
          ) : undefined
        }
      />

      {/* ── Filters ─────────────────────────────────────────── */}
      <div style={{
        display: 'flex', gap: 12, marginBottom: 16, flexWrap: 'wrap',
        background: 'var(--bg-surface)', border: '1px solid var(--border-color)',
        borderRadius: 'var(--radius-lg)', padding: '12px 16px',
      }}>
        <div style={{ position: 'relative', flex: '1 1 200px', minWidth: 180 }}>
          <Search size={14} style={{ position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)', pointerEvents: 'none' }} />
          <input
            className="form-input"
            style={{ paddingRight: 32 }}
            placeholder="بحث بالرقم..."
            value={search}
            onChange={e => { setSearch(e.target.value); setPage(1) }}
          />
        </div>
        <select
          className="form-input"
          style={{ width: 140 }}
          value={status}
          onChange={e => { setStatus(e.target.value as PurchaseReturnStatus | ''); setPage(1) }}
        >
          <option value="">كل الحالات</option>
          <option value="draft">مسودة</option>
          <option value="confirmed">مؤكد</option>
        </select>
      </div>

      {/* ── Table ───────────────────────────────────────────── */}
      <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-color)', borderRadius: 'var(--radius-lg)', overflow: 'hidden' }}>
        {isLoading ? (
          <div style={{ padding: 'var(--space-6)' }}>
            {[1,2,3,4,5].map(i => <div key={i} className="skeleton skeleton-row" style={{ marginBottom: 8, height: 44 }} />)}
          </div>
        ) : returns.length === 0 ? (
          <div style={{ padding: '48px 24px', textAlign: 'center', color: 'var(--text-muted)' }}>
            <RotateCcw size={40} style={{ opacity: 0.3, marginBottom: 12 }} />
            <div style={{ fontWeight: 600, marginBottom: 4 }}>لا توجد مرتجعات</div>
            <div style={{ fontSize: '0.85rem' }}>اضغط "مرتجع جديد" لإنشاء أول مرتجع مشتريات</div>
          </div>
        ) : (
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.85rem' }}>
            <thead>
              <tr style={{ background: 'var(--bg-surface-2)', borderBottom: '2px solid var(--border-color)' }}>
                {['رقم المرتجع', 'المورد', 'المخزن', 'تاريخ المرتجع', 'الإجمالي', 'الحالة', 'إجراء'].map(h => (
                  <th key={h} style={{ padding: '10px 14px', textAlign: 'right', fontWeight: 600, fontSize: '0.8rem', whiteSpace: 'nowrap' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {returns.map((ret, idx) => (
                <tr
                  key={ret.id}
                  style={{ borderBottom: '1px solid var(--border-color)', background: idx % 2 === 1 ? 'var(--bg-surface-2)' : 'var(--bg-surface)', cursor: 'pointer', transition: 'background 0.15s' }}
                  onClick={() => navigate(`/purchases/returns/${ret.id}`)}
                  onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg-hover)')}
                  onMouseLeave={e => (e.currentTarget.style.background = idx % 2 === 1 ? 'var(--bg-surface-2)' : 'var(--bg-surface)')}
                >
                  <td style={{ padding: '10px 14px', fontWeight: 700, color: 'var(--color-primary)', direction: 'ltr', textAlign: 'right' }}>
                    {ret.number}
                  </td>
                  <td style={{ padding: '10px 14px' }}>{(ret as any).supplier?.name || '—'}</td>
                  <td style={{ padding: '10px 14px' }}>{(ret as any).warehouse?.name || '—'}</td>
                  <td style={{ padding: '10px 14px', direction: 'ltr', textAlign: 'right' }}>{ret.return_date}</td>
                  <td style={{ padding: '10px 14px', fontWeight: 600 }}>{formatNumber(ret.total_amount)} ج.م</td>
                  <td style={{ padding: '10px 14px' }}><StatusBadge status={ret.status} /></td>
                  <td style={{ padding: '10px 14px' }}>
                    <button
                      type="button"
                      onClick={e => { e.stopPropagation(); navigate(`/purchases/returns/${ret.id}`) }}
                      style={{ fontSize: '0.8rem', color: 'var(--color-primary)', cursor: 'pointer', background: 'none', border: '1px solid var(--color-primary)', borderRadius: 6, padding: '3px 10px' }}
                    >
                      عرض
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}

        {/* Pagination */}
        {totalPages > 1 && (
          <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', gap: 8, padding: '12px 16px', borderTop: '1px solid var(--border-color)' }}>
            <button
              className="btn btn-ghost btn-sm"
              disabled={page === 1}
              onClick={() => setPage(p => p - 1)}
            >السابق</button>
            <span style={{ fontSize: '0.82rem', color: 'var(--text-muted)' }}>صفحة {page} / {totalPages}</span>
            <button
              className="btn btn-ghost btn-sm"
              disabled={page === totalPages}
              onClick={() => setPage(p => p + 1)}
            >التالي</button>
          </div>
        )}
      </div>

      <style>{`
        @keyframes fade-in {
          from { opacity: 0; transform: translateY(8px); }
          to   { opacity: 1; transform: translateY(0); }
        }
      `}</style>
    </div>
  )
}
