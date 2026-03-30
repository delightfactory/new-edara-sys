import type { VisitPlanItem, CallPlanItem, PlanItemStatus } from '@/lib/types/activities'
import ActivityStatusBadge from './ActivityStatusBadge'

interface PlanItemCardProps {
  item: VisitPlanItem | CallPlanItem
  type: 'visit' | 'call'
  onStart?: () => void
  onSkip?: () => void
  disabled?: boolean
}

const STATUS_ICON: Record<PlanItemStatus, string> = {
  pending:      '⏳',
  in_progress:  '▶',
  completed:    '✓',
  skipped:      '—',
  missed:       '✗',              // ✅ أضيف missed
  rescheduled:  '↻',
}

const PURPOSE_AR: Record<string, string> = {
  sales:       'مبيعات',
  collection:  'تحصيل',
  activation:  'تفعيل',
  promotion:   'ترويج',
  followup:    'متابعة',
  service:     'خدمة',
}

function getCustomerName(item: VisitPlanItem | CallPlanItem): string {
  if (item.customer) return item.customer.name
  // ✅ call_plan_items قد تحتوي contact_name بدلاً من customer
  const callItem = item as CallPlanItem
  if (callItem.contact_name) return callItem.contact_name
  if (callItem.phone_number) return callItem.phone_number
  return '—'
}

export default function PlanItemCard({
  item,
  type,
  onStart,
  onSkip,
  disabled,
}: PlanItemCardProps) {
  const isDone    = item.status === 'completed' || item.status === 'skipped' || item.status === 'missed'
  const isActive  = item.status === 'in_progress'
  const purposeType = (item as VisitPlanItem).purpose_type
  const purpose   = purposeType ? (PURPOSE_AR[purposeType] ?? purposeType) : ''
  // ✅ sequence (لا sequence_order)
  const seq = (item as VisitPlanItem | CallPlanItem).sequence

  return (
    <div className={`pic${isActive ? ' pic--active' : ''}${isDone ? ' pic--done' : ''}`}>
      <div className="pic-seq">
        <span className="pic-num">#{seq}</span>
        <span className="pic-status-icon" title={item.status}>
          {STATUS_ICON[item.status]}
        </span>
      </div>

      <div className="pic-body">
        <div className="pic-top">
          <span className="pic-customer">{getCustomerName(item)}</span>
          <ActivityStatusBadge itemStatus={item.status} size="sm" />
        </div>

        <div className="pic-meta">
          {purpose && <span className="pic-purpose">{purpose}</span>}
          {item.planned_time && (
            <span className="pic-time">🕐 {item.planned_time.slice(0, 5)}</span>
          )}
          {/* ✅ estimated_duration_min (لا planned_duration_min) */}
          {item.estimated_duration_min > 0 && (
            <span className="pic-duration">{item.estimated_duration_min} د</span>
          )}
        </div>

        {/* ✅ skip_reason (لا notes) */}
        {item.skip_reason && (
          <p className="pic-notes">سبب التخطي: {item.skip_reason}</p>
        )}

        {!isDone && !disabled && (
          <div className="pic-actions">
            {onStart && (
              <button className="btn btn--primary btn--sm" onClick={onStart} type="button">
                {type === 'visit' ? '▶ بدء الزيارة' : '▶ بدء المكالمة'}
              </button>
            )}
            {onSkip && (
              <button className="btn btn--ghost btn--sm" onClick={onSkip} type="button">
                تخطي
              </button>
            )}
          </div>
        )}

        {isDone && item.activity && (item.activity as any).outcome_type && (
          <div className="pic-result">
            <ActivityStatusBadge
              outcomeType={(item.activity as any).outcome_type}
              size="sm"
            />
          </div>
        )}
      </div>

      <style>{`
        .pic {
          display: grid;
          grid-template-columns: 48px 1fr;
          gap: var(--space-3);
          padding: var(--space-3) var(--space-4);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-md);
          background: var(--bg-surface);
          transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
        }
        .pic--active {
          border-color: var(--color-primary);
          box-shadow: 0 0 0 3px var(--color-primary-light);
        }
        .pic--done { opacity: 0.65; }
        .pic-seq {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 4px;
          padding-top: 2px;
        }
        .pic-num {
          font-size: var(--text-xs);
          font-weight: 700;
          color: var(--text-muted);
        }
        .pic-status-icon { font-size: 16px; }
        .pic-body { display: flex; flex-direction: column; gap: var(--space-1); }
        .pic-top {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          justify-content: space-between;
        }
        .pic-customer {
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--text-primary);
        }
        .pic-meta {
          display: flex;
          align-items: center;
          gap: var(--space-3);
        }
        .pic-purpose {
          font-size: var(--text-xs);
          color: var(--color-primary);
          font-weight: 500;
        }
        .pic-time, .pic-duration {
          font-size: var(--text-xs);
          color: var(--text-muted);
        }
        .pic-notes {
          font-size: var(--text-xs);
          color: var(--text-muted);
          margin: 0;
          line-height: 1.5;
        }
        .pic-actions {
          display: flex;
          gap: var(--space-2);
          margin-top: var(--space-2);
          flex-wrap: wrap;
        }
        .pic-result { margin-top: var(--space-1); }
      `}</style>
    </div>
  )
}
