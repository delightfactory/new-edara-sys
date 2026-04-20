import type { Activity } from '@/lib/types/activities'
import ActivityStatusBadge from './ActivityStatusBadge'

function formatArabicDate(dateStr: string): string {
  try {
    return new Date(dateStr).toLocaleDateString('ar-EG-u-nu-latn', {
      day: 'numeric', month: 'short', year: 'numeric',
    })
  } catch {
    return dateStr
  }
}

interface ActivityTimelineProps {
  activities: Activity[]
  loading?: boolean
  limit?: number
}

// ✅ category من type.category (مطابق للـ schema)
const CATEGORY_ICON: Record<string, string> = {
  visit: '🏢',
  call:  '📞',
  task:  '✅',
}

export default function ActivityTimeline({ activities, loading, limit }: ActivityTimelineProps) {
  if (loading) {
    return (
      <div className="act-timeline">
        {[1, 2, 3].map(i => (
          <div key={i} className="act-timeline-skeleton">
            <div className="skeleton" style={{ width: 36, height: 36, borderRadius: '50%' }} />
            <div style={{ flex: 1 }}>
              <div className="skeleton skeleton-row" style={{ width: '60%' }} />
              <div className="skeleton skeleton-row" style={{ width: '40%', marginTop: 6 }} />
            </div>
          </div>
        ))}
      </div>
    )
  }

  const items = limit ? activities.slice(0, limit) : activities

  if (items.length === 0) {
    return (
      <div className="empty-state" style={{ padding: 'var(--space-6)' }}>
        <p className="empty-state-title">لا توجد أنشطة</p>
      </div>
    )
  }

  return (
    <div className="act-timeline">
      {items.map((act, idx) => {
        const category = act.type?.category ?? 'task'
        const icon     = CATEGORY_ICON[category] ?? '📋'
        const isLast   = idx === items.length - 1

        return (
          <div key={act.id} className="act-timeline-item">
            {!isLast && <div className="act-timeline-line" />}
            <div className="act-timeline-icon">{icon}</div>
            <div className="act-timeline-content">
              <div className="act-timeline-header">
                <span className="act-timeline-type">{act.type?.name ?? 'نشاط'}</span>
                {act.outcome_type && (
                  <ActivityStatusBadge outcomeType={act.outcome_type} size="sm" />
                )}
                <span className="act-timeline-date">
                  {formatArabicDate(act.activity_date)}
                  {act.start_time && ` • ${new Date(act.start_time).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' })}`}
                </span>
              </div>
              {act.customer && (
                <div className="act-timeline-customer">
                  {act.customer.name}
                  {act.customer.code && ` (${act.customer.code})`}
                </div>
              )}
              {act.outcome_notes && (
                <p className="act-timeline-notes">{act.outcome_notes}</p>
              )}
            </div>
          </div>
        )
      })}

      <style>{`
        .act-timeline {
          display: flex;
          flex-direction: column;
          gap: 0;
          position: relative;
          padding: var(--space-2) 0;
        }
        .act-timeline-item {
          display: grid;
          grid-template-columns: 36px 1fr;
          gap: var(--space-3);
          position: relative;
          padding-bottom: var(--space-4);
        }
        .act-timeline-line {
          position: absolute;
          top: 36px;
          right: 17px;
          width: 2px;
          bottom: 0;
          background: var(--border-primary);
          border-radius: 1px;
        }
        .act-timeline-icon {
          width: 36px;
          height: 36px;
          border-radius: 50%;
          background: var(--bg-surface-2);
          border: 2px solid var(--border-primary);
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 16px;
          flex-shrink: 0;
          position: relative;
          z-index: 1;
        }
        .act-timeline-content {
          padding-top: 6px;
        }
        .act-timeline-header {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          flex-wrap: wrap;
        }
        .act-timeline-type {
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--text-primary);
        }
        .act-timeline-date {
          font-size: var(--text-xs);
          color: var(--text-muted);
          margin-right: auto;
        }
        .act-timeline-customer {
          font-size: var(--text-sm);
          color: var(--color-primary);
          font-weight: 500;
          margin-top: var(--space-1);
        }
        .act-timeline-notes {
          font-size: var(--text-xs);
          color: var(--text-muted);
          margin-top: var(--space-1);
          margin-bottom: 0;
          line-height: 1.5;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .act-timeline-skeleton {
          display: flex;
          gap: var(--space-3);
          align-items: flex-start;
          padding-bottom: var(--space-4);
        }
      `}</style>
    </div>
  )
}
