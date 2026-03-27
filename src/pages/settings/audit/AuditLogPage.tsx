import { useState } from 'react'
import { Search, FileText, Eye } from 'lucide-react'
import { useAuditLogs } from '@/hooks/useQueryHooks'
import type { AuditLog } from '@/lib/types/auth'

const ACTION_LABELS: Record<string, { label: string; cls: string }> = {
  create: { label: 'إنشاء', cls: 'badge-success' },
  update: { label: 'تعديل', cls: 'badge-info' },
  delete: { label: 'حذف', cls: 'badge-danger' },
  confirm: { label: 'تأكيد', cls: 'badge-primary' },
  cancel: { label: 'إلغاء', cls: 'badge-warning' },
  password_reset: { label: 'إعادة كلمة المرور', cls: 'badge-warning' },
}

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

  const formatDate = (d: string) => {
    const date = new Date(d)
    return date.toLocaleDateString('ar-EG-u-nu-latn') + ' ' + date.toLocaleTimeString('ar-EG-u-nu-latn', { hour: '2-digit', minute: '2-digit' })
  }

  return (
    <div className="page-container animate-enter">
      <div className="page-header">
        <div className="page-header-info">
          <h1 className="page-title">سجل التدقيق</h1>
          <p className="page-subtitle">تتبع كل التغييرات في النظام</p>
        </div>
      </div>

      {/* Filters */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="flex gap-4" style={{ flexWrap: 'wrap' }}>
          <select className="form-select" style={{ width: 160 }} value={actionFilter}
            onChange={e => { setActionFilter(e.target.value); setPage(1) }}>
            <option value="">كل الإجراءات</option>
            <option value="create">إنشاء</option>
            <option value="update">تعديل</option>
            <option value="delete">حذف</option>
            <option value="confirm">تأكيد</option>
            <option value="cancel">إلغاء</option>
            <option value="password_reset">إعادة كلمة المرور</option>
          </select>
          <select className="form-select" style={{ width: 180 }} value={entityFilter}
            onChange={e => { setEntityFilter(e.target.value); setPage(1) }}>
            <option value="">كل الجداول</option>
            <option value="profiles">المستخدمون</option>
            <option value="roles">الأدوار</option>
            <option value="company_settings">الإعدادات</option>
          </select>
        </div>
      </div>

      {/* Table */}
      <div className="edara-card" style={{ overflow: 'auto' }}>
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
                const action = ACTION_LABELS[log.action] || { label: log.action, cls: 'badge-neutral' }
                return (
                  <tr key={log.id}>
                    <td>
                      <span style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>
                        {(log.profile as any)?.full_name || 'نظام'}
                      </span>
                    </td>
                    <td><span className={`badge ${action.cls}`}>{action.label}</span></td>
                    <td className="hide-mobile"><span style={{ fontSize: 'var(--text-xs)', fontFamily: 'monospace' }}>{log.entity_type}</span></td>
                    <td className="hide-mobile"><span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{formatDate(log.created_at)}</span></td>
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

      {/* Detail Modal */}
      {detail && (
        <div className="modal-overlay" onClick={() => setDetail(null)}>
          <div className="modal-box modal-md" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <span className="modal-title">تفاصيل التغيير</span>
              <button className="btn btn-ghost btn-icon" onClick={() => setDetail(null)}>✕</button>
            </div>
            <div className="modal-body">
              {detail.old_data && (
                <div style={{ marginBottom: 'var(--space-4)' }}>
                  <h4 style={{ fontSize: 'var(--text-sm)', fontWeight: 700, color: 'var(--color-danger)', marginBottom: 'var(--space-2)' }}>
                    البيانات القديمة
                  </h4>
                  <pre style={{
                    background: 'var(--bg-surface-2)', padding: 'var(--space-3)',
                    borderRadius: 'var(--radius-md)', fontSize: 'var(--text-xs)',
                    direction: 'ltr', overflow: 'auto', maxHeight: 200,
                  }}>
                    {JSON.stringify(detail.old_data, null, 2)}
                  </pre>
                </div>
              )}
              {detail.new_data && (
                <div>
                  <h4 style={{ fontSize: 'var(--text-sm)', fontWeight: 700, color: 'var(--color-success)', marginBottom: 'var(--space-2)' }}>
                    البيانات الجديدة
                  </h4>
                  <pre style={{
                    background: 'var(--bg-surface-2)', padding: 'var(--space-3)',
                    borderRadius: 'var(--radius-md)', fontSize: 'var(--text-xs)',
                    direction: 'ltr', overflow: 'auto', maxHeight: 200,
                  }}>
                    {JSON.stringify(detail.new_data, null, 2)}
                  </pre>
                </div>
              )}
              {detail.ip_address && (
                <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 'var(--space-3)' }}>
                  IP: {detail.ip_address}
                </p>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
