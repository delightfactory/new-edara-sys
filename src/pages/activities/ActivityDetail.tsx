import { useParams, useNavigate } from 'react-router-dom'
import { useActivity } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { PERMISSIONS } from '@/lib/permissions/constants'
import PageHeader from '@/components/shared/PageHeader'
import ActivityStatusBadge from '@/components/shared/ActivityStatusBadge'
import Button from '@/components/ui/Button'
import { Edit2, MapPin, Clock, User } from 'lucide-react'

function fmtDate(d: string) {
  return new Date(d).toLocaleDateString('ar-EG', {
    weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
  })
}
function fmtTime(d: string) {
  return new Date(d).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' })
}

export default function ActivityDetail() {
  const { id }   = useParams<{ id: string }>()
  const navigate = useNavigate()
  const can      = useAuthStore(s => s.can)

  const { data: activity, isLoading, error } = useActivity(id)

  const canEdit = can(PERMISSIONS.ACTIVITIES_UPDATE_OWN) ||
                  can(PERMISSIONS.ACTIVITIES_READ_TEAM)  ||
                  can(PERMISSIONS.ACTIVITIES_READ_ALL)

  if (isLoading) {
    return (
      <div className="page-container animate-enter">
        <div className="edara-card" style={{ padding: 'var(--space-6)' }}>
          {[1, 2, 3, 4].map(i => (
            <div key={i} className="skeleton" style={{ height: 20, marginBottom: 'var(--space-3)', width: `${70 - i * 10}%` }} />
          ))}
        </div>
      </div>
    )
  }

  if (error || !activity) {
    return (
      <div className="page-container animate-enter">
        <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
          <p className="empty-state-title">لم يتم العثور على النشاط</p>
          <Button variant="secondary" onClick={() => navigate('/activities/list')}>
            العودة للقائمة
          </Button>
        </div>
      </div>
    )
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title={activity.type?.name ?? 'تفاصيل النشاط'}
        subtitle={activity.customer?.name}
        breadcrumbs={[
          { label: 'الأنشطة', path: '/activities/list' },
          { label: activity.type?.name ?? 'تفاصيل' },
        ]}
        actions={canEdit ? (
          <Button
            icon={<Edit2 size={16} />}
            variant="secondary"
            onClick={() => navigate(`/activities/${id}/edit`)}
          >
            تعديل
          </Button>
        ) : undefined}
      />

      {/* ── Details Card ─────────────────────────────────────── */}
      <div className="edara-card act-detail-card">
        {/* Status */}
        <div className="act-detail-row act-detail-row--hero">
          <ActivityStatusBadge outcomeType={activity.outcome_type} />
          {activity.gps_verified && (
            <span className="act-detail-gps-badge">
              <MapPin size={12} /> GPS مُؤكَّد
            </span>
          )}
        </div>

        {/* Date & Time */}
        <div className="act-detail-row">
          <span className="act-detail-label">
            <Clock size={14} /> التاريخ
          </span>
          <span className="act-detail-value">{fmtDate(activity.activity_date)}</span>
        </div>
        {activity.start_time && (
          <div className="act-detail-row">
            <span className="act-detail-label">
              <Clock size={14} /> الوقت
            </span>
            <span className="act-detail-value" dir="ltr">
              {fmtTime(activity.start_time)}
              {activity.end_time && ` — ${fmtTime(activity.end_time)}`}
            </span>
          </div>
        )}

        {/* Customer */}
        {activity.customer && (
          <div className="act-detail-row">
            <span className="act-detail-label">
              <User size={14} /> العميل
            </span>
            <span className="act-detail-value">{activity.customer.name}</span>
          </div>
        )}

        {/* GPS Coordinates */}
        {activity.gps_lat && activity.gps_lng && (
          <div className="act-detail-row">
            <span className="act-detail-label">
              <MapPin size={14} /> الموقع
            </span>
            <span className="act-detail-value" dir="ltr" style={{ fontSize: 'var(--text-xs)', fontFamily: 'monospace' }}>
              {activity.gps_lat.toFixed(6)}, {activity.gps_lng.toFixed(6)}
            </span>
          </div>
        )}

        {/* Outcome Notes */}
        {activity.outcome_notes && (
          <div className="act-detail-section">
            <div className="act-detail-section-label">ملاحظات النتيجة</div>
            <div className="act-detail-notes">{activity.outcome_notes}</div>
          </div>
        )}

        {/* Refuse Reason */}
        {activity.refuse_reason && (
          <div className="act-detail-section">
            <div className="act-detail-section-label" style={{ color: 'var(--color-danger)' }}>سبب الرفض</div>
            <div className="act-detail-notes">{activity.refuse_reason}</div>
          </div>
        )}

        {/* Call Detail */}
        {activity.call_detail && (
          <div className="act-detail-section">
            <div className="act-detail-section-label">تفاصيل المكالمة</div>
            <div className="act-detail-call-grid">
              {activity.call_detail.direction && (
                <div>
                  <div className="act-detail-label">الاتجاه</div>
                  <div>{activity.call_detail.direction === 'outbound' ? 'صادرة' : 'واردة'}</div>
                </div>
              )}
              {activity.call_detail.attempt_count && (
                <div>
                  <div className="act-detail-label">عدد المحاولات</div>
                  <div>{activity.call_detail.attempt_count}</div>
                </div>
              )}
              {activity.call_detail.phone_number && (
                <div>
                  <div className="act-detail-label">الرقم</div>
                  <div dir="ltr">{activity.call_detail.phone_number}</div>
                </div>
              )}
            </div>
          </div>
        )}
      </div>

      <style>{`
        .act-detail-card {
          max-width: 640px;
          margin: 0 auto;
          padding: var(--space-6);
          display: flex;
          flex-direction: column;
          gap: var(--space-3);
        }
        .act-detail-row {
          display: flex;
          align-items: center;
          gap: var(--space-3);
          padding: var(--space-2) 0;
          border-bottom: 1px solid var(--border-primary);
        }
        .act-detail-row--hero {
          border-bottom: none;
          padding-bottom: var(--space-2);
          gap: var(--space-2);
        }
        .act-detail-label {
          display: flex;
          align-items: center;
          gap: var(--space-1);
          font-size: var(--text-xs);
          color: var(--text-muted);
          min-width: 110px;
          flex-shrink: 0;
        }
        .act-detail-value {
          font-size: var(--text-sm);
          font-weight: 500;
          color: var(--text-primary);
        }
        .act-detail-gps-badge {
          display: inline-flex;
          align-items: center;
          gap: 4px;
          font-size: 11px;
          color: var(--color-success);
          background: var(--color-success-light);
          padding: 2px 8px;
          border-radius: 99px;
          font-weight: 600;
        }
        .act-detail-section {
          padding: var(--space-3) 0;
          border-bottom: 1px solid var(--border-primary);
        }
        .act-detail-section-label {
          font-size: var(--text-xs);
          color: var(--text-muted);
          font-weight: 600;
          margin-bottom: var(--space-2);
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }
        .act-detail-notes {
          font-size: var(--text-sm);
          color: var(--text-secondary);
          line-height: 1.7;
          white-space: pre-wrap;
        }
        .act-detail-call-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
          gap: var(--space-3);
          font-size: var(--text-sm);
          color: var(--text-primary);
        }
        @media (max-width: 480px) {
          .act-detail-card { padding: var(--space-4); }
          .act-detail-label { min-width: 90px; }
        }
      `}</style>
    </div>
  )
}
