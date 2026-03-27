import { useState, useMemo } from 'react'
import { Activity, Clock, Package, ArrowUpDown } from 'lucide-react'
import { useStockMovements, useWarehouses } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import type { StockMovement } from '@/lib/types/master-data'
import { formatNumber, formatCurrency, formatDateShort } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'

const typeLabels: Record<string, { label: string; variant: 'success' | 'danger' | 'info' | 'warning' | 'primary'; dot: string }> = {
  in:               { label: 'وارد',          variant: 'success',  dot: '#22c55e' },
  out:              { label: 'صادر',          variant: 'danger',   dot: '#ef4444' },
  transfer_in:      { label: 'تحويل وارد',   variant: 'info',     dot: '#3b82f6' },
  transfer_out:     { label: 'تحويل صادر',   variant: 'warning',  dot: '#f59e0b' },
  adjustment_add:   { label: 'تسوية +',      variant: 'primary',  dot: '#8b5cf6' },
  adjustment_remove:{ label: 'تسوية −',      variant: 'danger',   dot: '#ef4444' },
  return_in:        { label: 'مرتجع وارد',   variant: 'info',     dot: '#06b6d4' },
  return_out:       { label: 'مرتجع صادر',   variant: 'warning',  dot: '#f97316' },
}

function isIncoming(type: string) { return type.includes('in') || type.includes('add') }

function sameDay(a: string, b: string) {
  return new Date(a).toDateString() === new Date(b).toDateString()
}

export default function StockMovementsPage() {
  const can = useAuthStore(s => s.can)
  const canViewCosts = can('finance.view_costs')
  const [whFilter, setWhFilter] = useState('')
  const [typeFilter, setTypeFilter] = useState('')
  const [page, setPage] = useState(1)

  const { data: warehouses = [] } = useWarehouses()

  const queryParams = useMemo(() => ({
    warehouseId: whFilter || undefined,
    type: typeFilter || undefined,
    page, pageSize: 50,
  }), [whFilter, typeFilter, page])

  const { data: result, isLoading: loading } = useStockMovements(queryParams)
  const movements = result?.data ?? []
  const totalPages = result?.totalPages ?? 1
  const totalCount = result?.count ?? 0

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="حركات المخزون"
        subtitle={loading ? '...' : `${totalCount} حركة`}
      />

      {/* Filters */}
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

      {/* ── DESKTOP: Table ────────────────────────────────── */}
      <div className="sm-table-view edara-card" style={{ overflow: 'auto' }}>
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
                  <td style={{ fontWeight: 700, color: isIncoming(m.type) ? 'var(--color-success)' : 'var(--color-danger)' }}>
                    {isIncoming(m.type) ? '+' : '−'}{formatNumber(Math.abs(m.quantity))}
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

      {/* ── MOBILE: Timeline View ─────────────────────────── */}
      <div className="sm-timeline-view">
        {loading ? (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {[1,2,3].map(i => <div key={i} className="skeleton" style={{ height: 80, borderRadius: 12 }} />)}
          </div>
        ) : movements.length === 0 ? (
          <div className="edara-card" style={{ padding: 'var(--space-8)', textAlign: 'center', color: 'var(--text-muted)' }}>
            <Activity size={40} style={{ margin: '0 auto 12px', display: 'block', opacity: 0.3 }} />
            <p>لا يوجد حركات</p>
          </div>
        ) : (
          <div className="sm-timeline">
            {movements.map((m, idx) => {
              const cfg = typeLabels[m.type] || { label: m.type, variant: 'neutral' as any, dot: '#94a3b8' }
              const incoming = isIncoming(m.type)
              const date = new Date(m.created_at)
              const dateStr = formatDateShort(m.created_at)
              const timeStr = date.toLocaleTimeString('ar-EG-u-nu-latn', { hour: '2-digit', minute: '2-digit' })
              const showDateSep = idx === 0 || !sameDay(m.created_at, movements[idx - 1].created_at)

              return (
                <div key={m.id}>
                  {showDateSep && (
                    <div className="al-date-sep"><span>{dateStr}</span></div>
                  )}
                  <div className="al-timeline-item">
                    {/* Spine dot with movement-type color */}
                    <div className="al-dot" style={{ background: cfg.dot }} />
                    {/* Card */}
                    <div className="al-item-card edara-card">
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8 }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                          <Badge variant={cfg.variant}>{cfg.label}</Badge>
                        </div>
                        <span style={{
                          fontWeight: 800, fontSize: 15, fontVariantNumeric: 'tabular-nums',
                          color: incoming ? 'var(--color-success)' : 'var(--color-danger)',
                        }}>
                          {incoming ? '+' : '−'}{formatNumber(Math.abs(m.quantity))}
                        </span>
                      </div>
                      <div style={{ marginTop: 8, display: 'flex', flexDirection: 'column', gap: 4 }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, fontWeight: 600 }}>
                          <Package size={12} style={{ color: 'var(--text-muted)' }} />
                          {m.product?.name || '—'}
                          {m.product?.sku && (
                            <span style={{ fontSize: 11, color: 'var(--text-muted)', fontFamily: 'monospace' }} dir="ltr">
                              {m.product.sku}
                            </span>
                          )}
                        </div>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 12, color: 'var(--text-secondary)' }}>
                          <span>{m.warehouse?.name}</span>
                          {m.before_qty != null && m.after_qty != null && (
                            <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                              <ArrowUpDown size={10} />
                              {formatNumber(m.before_qty)} → {formatNumber(m.after_qty)}
                            </span>
                          )}
                          <span style={{ display: 'flex', alignItems: 'center', gap: 3, marginRight: 'auto' }}>
                            <Clock size={9} /> {timeStr}
                          </span>
                        </div>
                        {m.reference_type && (
                          <div style={{ fontSize: 11 }}>
                            <Badge variant="neutral">{m.reference_type}</Badge>
                          </div>
                        )}
                      </div>
                    </div>
                  </div>
                </div>
              )
            })}
          </div>
        )}
        {totalPages > 1 && (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 'var(--space-4)', padding: 'var(--space-4) 0' }}>
            <Button variant="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(p => p - 1)}>السابق</Button>
            <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>{page} / {totalPages}</span>
            <Button variant="ghost" size="sm" disabled={page >= totalPages} onClick={() => setPage(p => p + 1)}>التالي</Button>
          </div>
        )}
      </div>

      <style>{`
        .sm-table-view   { display: block; }
        .sm-timeline-view { display: none; }

        /* Timeline — same pattern as AuditLog / Ledger */
        .sm-timeline { display: flex; flex-direction: column; padding-bottom: var(--space-4); }
        .al-date-sep {
          display: flex; align-items: center; gap: var(--space-3);
          margin: var(--space-3) 0; font-size: 11px; font-weight: 600;
          color: var(--text-muted); letter-spacing: 0.06em;
        }
        .al-date-sep::before, .al-date-sep::after {
          content: ''; flex: 1; height: 1px; background: var(--border-primary);
        }
        .al-timeline-item {
          display: flex; align-items: flex-start; gap: 12px;
          padding: 0 0 var(--space-3) 4px; position: relative;
        }
        .al-timeline-item::after {
          content: ''; position: absolute; right: 7px; top: 18px;
          width: 1px; bottom: 0; background: var(--border-primary);
        }
        .al-dot {
          width: 14px; height: 14px; border-radius: 50%;
          flex-shrink: 0; margin-top: 6px; position: relative; z-index: 1;
          box-shadow: 0 0 0 3px var(--bg-base);
        }
        .al-item-card {
          flex: 1; padding: var(--space-3) var(--space-4);
        }
        @media (max-width: 768px) {
          .sm-table-view   { display: none; }
          .sm-timeline-view { display: block; }
        }
      `}</style>
    </div>
  )
}
