import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { AlertTriangle, ArrowRight, Clock3, Loader2, ShieldAlert, Users2 } from 'lucide-react'
import { useSupervisorOverview } from '@/features/work/supervisor'

const statusLabel: Record<string, string> = {
  open: 'مفتوحة',
  in_progress: 'قيد التنفيذ',
  waiting: 'بانتظار',
  pending_approval: 'بانتظار اعتماد',
}

export default function SupervisorWorkPage() {
  const navigate = useNavigate()
  const [assignee, setAssignee] = useState('')
  const [attentionOnly, setAttentionOnly] = useState(false)
  const overview = useSupervisorOverview({ assigneeUserId: assignee || null, attentionOnly })

  const people = useMemo(() => {
    const map = new Map<string, string>()
    for (const row of overview.data ?? []) {
      if (row.current_assignee_user_id) map.set(row.current_assignee_user_id, row.assignee_name || 'مستخدم')
    }
    return [...map.entries()].sort((a, b) => a[1].localeCompare(b[1], 'ar'))
  }, [overview.data])

  const metrics = useMemo(() => {
    const rows = overview.data ?? []
    return {
      active: rows.length,
      overdue: rows.filter(row => row.is_overdue).length,
      blocked: rows.filter(row => row.is_blocked).length,
      waiting: rows.filter(row => row.status === 'waiting').length,
      atRisk: rows.filter(row => row.is_at_risk).length,
    }
  }, [overview.data])

  if (overview.isLoading) return <div className="page-container"><div className="work-management-loading"><Loader2 className="animate-spin" /> جاري تحميل صورة الفريق…</div></div>
  if (overview.error) return <div className="page-container"><div className="work-management-error"><p>تعذر تحميل أعمال الفريق ضمن نطاق صلاحياتك.</p></div></div>

  return (
    <div className="page-container animate-enter" style={{ paddingBottom: 'calc(88px + env(safe-area-inset-bottom))' }}>
      <div className="page-header">
        <div className="page-header-info">
          <div style={{ color: 'var(--color-primary)', fontSize: 'var(--text-xs)', fontWeight: 700 }}>Team Operational Pulse</div>
          <h1 className="page-title">صورة الفريق الآن</h1>
          <p className="page-subtitle">من معه الكرة؟ ما المتأخر أو المعطل؟ وما الذي يحتاج تدخلًا قبل أن يتحول لمشكلة؟</p>
        </div>
        <button type="button" className="btn btn-secondary" onClick={() => navigate('/work')}><ArrowRight size={16} /> العودة للعمل</button>
      </div>

      <div className="work-summary-grid" style={{ marginBottom: 'var(--space-5)' }}>
        <div className="work-summary-card"><Users2 size={18} /><strong>{metrics.active}</strong><span>عمل نشط</span></div>
        <div className="work-summary-card"><Clock3 size={18} /><strong>{metrics.overdue}</strong><span>متأخر</span></div>
        <div className="work-summary-card"><ShieldAlert size={18} /><strong>{metrics.blocked}</strong><span>معطل</span></div>
        <div className="work-summary-card"><AlertTriangle size={18} /><strong>{metrics.atRisk}</strong><span>معرض للخطر</span></div>
      </div>

      <section className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="grid grid-2 gap-3">
          <div className="form-group" style={{ margin: 0 }}>
            <label className="form-label" htmlFor="team-assignee">المكلف الحالي</label>
            <select id="team-assignee" className="form-input" value={assignee} onChange={event => setAssignee(event.target.value)}>
              <option value="">كل الفريق المرئي</option>
              {people.map(([id, name]) => <option key={id} value={id}>{name}</option>)}
            </select>
          </div>
          <label className="perm-checkbox-label" style={{ alignSelf: 'end', minHeight: 44 }}>
            <input type="checkbox" checked={attentionOnly} onChange={event => setAttentionOnly(event.target.checked)} />
            اعرض ما يحتاج تدخلًا فقط
          </label>
        </div>
      </section>

      {(overview.data?.length ?? 0) === 0 ? (
        <div className="work-management-empty"><h3>لا توجد أعمال مطابقة</h3><p>لا توجد عناصر نشطة ضمن الفلتر ونطاق رؤيتك الحالي.</p></div>
      ) : (
        <div className="flex flex-col gap-3">
          {overview.data?.map(row => {
            const flags = [
              row.is_overdue && 'متأخر',
              row.is_blocked && 'معطل',
              row.is_at_risk && 'خطر',
              row.is_stale && 'راكد',
              row.is_follow_up_due && 'متابعة مستحقة',
              row.is_escalated && 'مصعد',
            ].filter(Boolean) as string[]
            return (
              <button
                key={row.work_item_id}
                type="button"
                className="work-item-card work-interactive-card"
                onClick={() => navigate(`/work/${row.work_item_id}`)}
                style={{ textAlign: 'right', width: '100%' }}
              >
                <div className="flex items-start justify-between gap-3">
                  <div style={{ minWidth: 0 }}>
                    <div className="flex items-center gap-2" style={{ flexWrap: 'wrap' }}>
                      <strong>#{row.work_number}</strong>
                      <span className="badge">{statusLabel[row.status] ?? row.status}</span>
                      {flags.map(flag => <span key={flag} className="badge badge-warning">{flag}</span>)}
                    </div>
                    <h3 style={{ margin: '8px 0 4px', overflowWrap: 'anywhere' }}>{row.title}</h3>
                    <div style={{ color: 'var(--text-secondary)', fontSize: 'var(--text-sm)' }}>
                      الكرة مع: <strong>{row.assignee_name || 'غير محدد'}</strong>
                      {row.owner_name && row.owner_name !== row.assignee_name ? ` • المسؤول: ${row.owner_name}` : ''}
                    </div>
                  </div>
                  <ArrowRight size={17} style={{ flexShrink: 0, transform: 'rotate(180deg)' }} />
                </div>
                {row.next_action_text && <div style={{ marginTop: 'var(--space-3)', padding: 'var(--space-3)', borderRadius: 'var(--radius-sm)', background: 'var(--bg-surface-2)' }}><span style={{ color: 'var(--text-muted)', fontSize: 11 }}>الإجراء التالي</span><div>{row.next_action_text}</div></div>}
                <div className="flex gap-2" style={{ marginTop: 'var(--space-3)', flexWrap: 'wrap', fontSize: 11, color: 'var(--text-muted)' }}>
                  {row.due_at && <span>الاستحقاق {new Date(row.due_at).toLocaleString('en-GB', { dateStyle: 'short', timeStyle: 'short' })}</span>}
                  {row.next_action_at && <span>• متابعة {new Date(row.next_action_at).toLocaleString('en-GB', { dateStyle: 'short', timeStyle: 'short' })}</span>}
                </div>
              </button>
            )
          })}
        </div>
      )}
    </div>
  )
}
