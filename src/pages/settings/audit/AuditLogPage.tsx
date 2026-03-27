import { useState } from 'react'
import { Search, FileText, Eye, User, Clock, Terminal } from 'lucide-react'
import { useAuditLogs } from '@/hooks/useQueryHooks'
import type { AuditLog } from '@/lib/types/auth'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import Button from '@/components/ui/Button'
import Badge from '@/components/ui/Badge'

// ── Action config ─────────────────────────────────────────────
const ACTION_CFG: Record<string, { label: string; variant: 'success' | 'info' | 'danger' | 'warning' | 'primary'; dot: string }> = {
  create:         { label: 'إنشاء',              variant: 'success', dot: '#22c55e' },
  update:         { label: 'تعديل',              variant: 'info',    dot: '#3b82f6' },
  delete:         { label: 'حذف',               variant: 'danger',  dot: '#ef4444' },
  confirm:        { label: 'تأكيد',              variant: 'primary', dot: '#2563eb' },
  cancel:         { label: 'إلغاء',              variant: 'warning', dot: '#f59e0b' },
  password_reset: { label: 'إعادة كلمة المرور', variant: 'warning', dot: '#f59e0b' },
}

// ── Utilities ────────────────────────────────────────────────
function formatAuditDate(d: string) {
  const date = new Date(d)
  return {
    date: date.toLocaleDateString('ar-EG-u-nu-latn'),
    time: date.toLocaleTimeString('ar-EG-u-nu-latn', { hour: '2-digit', minute: '2-digit' }),
  }
}

function sameDay(a: string, b: string) {
  return new Date(a).toDateString() === new Date(b).toDateString()
}

// ── Component ─────────────────────────────────────────────────
export default function AuditLogPage() {
  const [page, setPage] = useState(1)
  const [actionFilter, setActionFilter] = useState('')
  const [entityFilter, setEntityFilter] = useState('')
  const [detail, setDetail] = useState<AuditLog | null>(null)

  const { data: result, isLoading: loading } = useAuditLogs({
    action: actionFilter, entityType: entityFilter, page,
  })
  const logs = (result?.data as AuditLog[]) || []
  const totalPages = result?.totalPages || 1

  return (
    <div className="page-container animate-enter">
      {/* Header */}
      <div className="page-header">
        <div className="page-header-info">
          <h1 className="page-title">سجل التدقيق</h1>
          <p className="page-subtitle">تتبع كل التغييرات في النظام</p>
        </div>
      </div>

      {/* Filters */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="flex gap-4" style={{ flexWrap: 'wrap' }}>
          <select className="form-select" style={{ minWidth: 160 }} value={actionFilter}
            onChange={e => { setActionFilter(e.target.value); setPage(1) }}>
            <option value="">كل الإجراءات</option>
            {Object.entries(ACTION_CFG).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
          </select>
          <select className="form-select" style={{ minWidth: 180 }} value={entityFilter}
            onChange={e => { setEntityFilter(e.target.value); setPage(1) }}>
            <option value="">كل الجداول</option>
            <option value="profiles">المستخدمون</option>
            <option value="roles">الأدوار</option>
            <option value="company_settings">الإعدادات</option>
            <option value="sales_orders">المبيعات</option>
            <option value="purchase_invoices">المشتريات</option>
            <option value="customers">العملاء</option>
            <option value="suppliers">الموردين</option>
          </select>
        </div>
      </div>

      {/* ── DESKTOP: Table ──────────────────────────────────── */}
      <div className="al-table-view edara-card" style={{ overflow: 'auto' }}>
        {loading ? (
          <div style={{ padding: 'var(--space-6)' }}>
            {[1,2,3,4,5].map(i => <div key={i} className="skeleton skeleton-row" />)}
          </div>
        ) : logs.length === 0 ? (
          <div className="empty-state">
            <FileText size={48} className="empty-state-icon" />
            <p className="empty-state-title">لا توجد سجلات</p>
          </div>
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th>المستخدم</th>
                <th>الإجراء</th>
                <th className="hide-mobile">الجدول</th>
                <th className="hide-mobile">التاريخ</th>
                <th style={{ width: 60 }}>تفاصيل</th>
              </tr>
            </thead>
            <tbody>
              {logs.map(log => {
                const cfg = ACTION_CFG[log.action] || { label: log.action, variant: 'neutral' as any, dot: '#94a3b8' }
                const { date, time } = formatAuditDate(log.created_at)
                return (
                  <tr key={log.id}>
                    <td>
                      <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>
                        {(log.profile as any)?.full_name || 'نظام'}
                      </div>
                    </td>
                    <td><Badge variant={cfg.variant}>{cfg.label}</Badge></td>
                    <td className="hide-mobile"><span style={{ fontSize: 'var(--text-xs)', fontFamily: 'monospace' }}>{log.entity_type}</span></td>
                    <td className="hide-mobile"><span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{date} {time}</span></td>
                    <td>
                      {(log.old_data || log.new_data) && (
                        <button className="btn btn-ghost btn-sm" onClick={() => setDetail(log)}>
                          <Eye size={14} />
                        </button>
                      )}
                    </td>
                  </tr>
                )
              })}
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

      {/* ── MOBILE: Timeline View ──────────────────────────── */}
      <div className="al-timeline-view">
        {loading ? (
          <div className="mobile-card-list">
            {[1,2,3].map(i => <div key={i} className="edara-card" style={{ height: 80 }}><div className="skeleton" style={{ height: '100%' }} /></div>)}
          </div>
        ) : logs.length === 0 ? (
          <div className="edara-card" style={{ padding: 'var(--space-8)', textAlign: 'center', color: 'var(--text-muted)' }}>
            <FileText size={40} style={{ margin: '0 auto 12px', display: 'block', opacity: 0.3 }} />
            <p>لا توجد سجلات</p>
          </div>
        ) : (
          <div className="al-timeline">
            {logs.map((log, idx) => {
              const cfg = ACTION_CFG[log.action] || { label: log.action, variant: 'neutral' as any, dot: '#94a3b8' }
              const { date, time } = formatAuditDate(log.created_at)
              const showDateSep = idx === 0 || !sameDay(log.created_at, logs[idx - 1].created_at)

              return (
                <div key={log.id}>
                  {showDateSep && (
                    <div className="al-date-sep">
                      <span>{date}</span>
                    </div>
                  )}
                  <div className="al-timeline-item">
                    {/* Spine dot */}
                    <div className="al-dot" style={{ background: cfg.dot }} />
                    {/* Card */}
                    <div className="al-item-card edara-card"
                      onClick={() => (log.old_data || log.new_data) ? setDetail(log) : undefined}
                      style={{ cursor: (log.old_data || log.new_data) ? 'pointer' : 'default' }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8 }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                          <Badge variant={cfg.variant}>{cfg.label}</Badge>
                          <span style={{ fontFamily: 'monospace', fontSize: '11px', color: 'var(--text-muted)', background: 'var(--bg-surface-2)', padding: '2px 6px', borderRadius: 4 }}>
                            {log.entity_type}
                          </span>
                        </div>
                        <span style={{ fontSize: '11px', color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: 3, flexShrink: 0 }}>
                          <Clock size={9} /> {time}
                        </span>
                      </div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 6, fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }}>
                        <User size={10} />
                        <span>{(log.profile as any)?.full_name || 'نظام'}</span>
                        {(log.old_data || log.new_data) && (
                          <span style={{ marginRight: 'auto', color: 'var(--color-primary)', fontSize: '10px' }}>
                            عرض التغييرات ›
                          </span>
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
          <div className="mobile-pagination">
            <Button variant="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(p => p - 1)}>السابق</Button>
            <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>{page} / {totalPages}</span>
            <Button variant="ghost" size="sm" disabled={page >= totalPages} onClick={() => setPage(p => p + 1)}>التالي</Button>
          </div>
        )}
      </div>

      {/* ── Detail Modal (Responsive) ── */}
      <ResponsiveModal
        open={!!detail}
        onClose={() => setDetail(null)}
        title="تفاصيل التغيير"
      >
        {detail && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
            {detail.old_data && (
              <div>
                <h4 style={{ fontSize: 'var(--text-sm)', fontWeight: 700, color: 'var(--color-danger)', marginBottom: 'var(--space-2)', display: 'flex', alignItems: 'center', gap: 6 }}>
                  <Terminal size={13} /> البيانات القديمة
                </h4>
                <pre style={{ background: 'var(--bg-surface-2)', padding: 'var(--space-3)', borderRadius: 'var(--radius-md)', fontSize: '11px', direction: 'ltr', overflow: 'auto', maxHeight: 180 }}>
                  {JSON.stringify(detail.old_data, null, 2)}
                </pre>
              </div>
            )}
            {detail.new_data && (
              <div>
                <h4 style={{ fontSize: 'var(--text-sm)', fontWeight: 700, color: 'var(--color-success)', marginBottom: 'var(--space-2)', display: 'flex', alignItems: 'center', gap: 6 }}>
                  <Terminal size={13} /> البيانات الجديدة
                </h4>
                <pre style={{ background: 'var(--bg-surface-2)', padding: 'var(--space-3)', borderRadius: 'var(--radius-md)', fontSize: '11px', direction: 'ltr', overflow: 'auto', maxHeight: 180 }}>
                  {JSON.stringify(detail.new_data, null, 2)}
                </pre>
              </div>
            )}
            {detail.ip_address && (
              <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>IP: {detail.ip_address}</p>
            )}
          </div>
        )}
      </ResponsiveModal>

      <style>{`
        .al-table-view   { display: block; }
        .al-timeline-view { display: none; }
        .mobile-card-list { display: flex; flex-direction: column; gap: var(--space-3); }
        .mobile-pagination { display: flex; align-items: center; justify-content: center; gap: var(--space-4); padding: var(--space-4) 0; }

        /* Timeline */
        .al-timeline { display: flex; flex-direction: column; padding-bottom: var(--space-4); }
        .al-date-sep {
          display: flex; align-items: center; gap: var(--space-3);
          margin: var(--space-3) 0; font-size: 11px; font-weight: 600;
          color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.06em;
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
          flex-shrink: 0; margin-top: 4px; position: relative; z-index: 1;
          box-shadow: 0 0 0 3px var(--bg-base);
        }
        .al-item-card {
          flex: 1; padding: var(--space-3) var(--space-4);
          transition: background 0.12s;
        }
        .al-item-card:hover { background: var(--bg-hover); }

        @media (max-width: 768px) {
          .al-table-view    { display: none; }
          .al-timeline-view { display: block; }
        }
      `}</style>
    </div>
  )
}
