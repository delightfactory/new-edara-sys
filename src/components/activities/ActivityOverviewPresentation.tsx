import { CheckSquare, MapPin, MoreHorizontal, Phone } from 'lucide-react'
import type { ActivityCategory, ActivityOutcome } from '@/lib/types/activities'
import Card from '@/components/patterns/Card'
import KeyValueList, { type KeyValueItem } from '@/components/patterns/KeyValueList'
import StatusBadge, { type SemanticTone } from '@/components/patterns/StatusBadge'
import { resolveActionSet, type AppAction } from '@/components/patterns/ActionRegistry'
import Badge from '@/components/ui/Badge'
import Button, { type ButtonProps } from '@/components/ui/Button'
import { CustomerLink } from '@/components/shared/EntityLink'
import '@/styles/field-activities-v2.css'

const OUTCOME_LABEL: Record<ActivityOutcome, string> = {
  visited: 'تمت الزيارة',
  order_placed: 'طلب مبيعات',
  agreed_order: 'اتفاق على طلب',
  collection: 'تحصيل',
  promised_payment: 'وعد بالدفع',
  followup_scheduled: 'متابعة مجدولة',
  followup_visit: 'زيارة متابعة',
  refused: 'رفض',
  not_interested: 'غير مهتم',
  closed: 'مغلق',
  promotion: 'ترويج',
  exploratory: 'استكشافية',
  info_only: 'معلومات فقط',
  no_answer: 'لا يرد',
  busy: 'مشغول',
  callback_scheduled: 'مكالمة لاحقة',
}

const OUTCOME_TONE: Record<ActivityOutcome, SemanticTone> = {
  visited: 'success',
  order_placed: 'success',
  agreed_order: 'success',
  collection: 'info',
  promised_payment: 'info',
  followup_scheduled: 'warning',
  followup_visit: 'warning',
  refused: 'danger',
  not_interested: 'danger',
  closed: 'neutral',
  promotion: 'info',
  exploratory: 'neutral',
  info_only: 'neutral',
  no_answer: 'warning',
  busy: 'warning',
  callback_scheduled: 'info',
}

const CATEGORY_META: Record<ActivityCategory, { label: string; icon: React.ReactNode }> = {
  visit: { label: 'زيارة', icon: <MapPin size={16} /> },
  call: { label: 'مكالمة', icon: <Phone size={16} /> },
  task: { label: 'مهمة', icon: <CheckSquare size={16} /> },
}

export function ActivityOutcomeBadge({ outcome }: { outcome: ActivityOutcome }) {
  return <StatusBadge label={OUTCOME_LABEL[outcome]} tone={OUTCOME_TONE[outcome]} />
}

export interface ActivityCardSummary {
  typeName: string
  category: ActivityCategory
  customer?: { id: string; name: string } | null
  date: React.ReactNode
  notes?: React.ReactNode
  gpsVerified: boolean
  outcome: ActivityOutcome
}

export interface ActivityCardProps {
  summary: ActivityCardSummary
  mode: 'mobile' | 'tablet'
  actions: AppAction[]
  onOpen: () => void
}

function actionVariant(action: AppAction): NonNullable<ButtonProps['variant']> {
  if (action.tone) return action.tone
  return action.importance === 'primary' ? 'primary' : 'secondary'
}

function ActivityAction({ action }: { action: AppAction }) {
  return (
    <Button
      type="button"
      variant={actionVariant(action)}
      size="sm"
      touchTarget
      icon={action.icon}
      onClick={action.onSelect}
      disabled={action.disabled}
      loading={action.loading}
      aria-label={action.ariaLabel ?? action.label}
      data-action-id={action.id}
    >
      {action.label}
    </Button>
  )
}

/**
 * ActivityCard — field-domain projection over shared V2 card/status/action grammar.
 * The caller owns permission, route and action eligibility truth; this component
 * owns hierarchy and device-aware placement only.
 */
export function ActivityCard({ summary, mode, actions, onOpen }: ActivityCardProps) {
  const resolvedActions = resolveActionSet(actions, mode)
  const category = CATEGORY_META[summary.category]
  const metadata: KeyValueItem[] = [
    { key: 'date', label: 'التاريخ', value: summary.date },
    { key: 'gps', label: 'GPS', value: summary.gpsVerified ? 'موثق' : 'غير موثق' },
  ]

  if (summary.notes) {
    metadata.push({ key: 'notes', label: 'ملاحظات', value: summary.notes })
  }

  return (
    <Card
      surface="default"
      padding={mode === 'tablet' ? 'md' : 'sm'}
      className="ds-activity-card"
      data-activity-card
      data-mode={mode}
    >
      <div className="ds-activity-card__header">
        <button
          type="button"
          className="ds-activity-card__identity"
          onClick={onOpen}
          aria-label={`فتح نشاط ${summary.typeName}`}
        >
          <span className="ds-activity-card__icon" aria-hidden="true">{category.icon}</span>
          <span className="ds-activity-card__copy">
            <span className="ds-activity-card__title">{summary.typeName}</span>
            <span className="ds-activity-card__category">{category.label}</span>
          </span>
        </button>

        <div className="ds-activity-card__badges">
          <ActivityOutcomeBadge outcome={summary.outcome} />
          <Badge variant="neutral">{category.label}</Badge>
        </div>
      </div>

      {summary.customer && (
        <div className="ds-activity-card__customer">
          <span className="ds-activity-card__customer-label">العميل</span>
          <CustomerLink id={summary.customer.id} name={summary.customer.name} />
        </div>
      )}

      <KeyValueList items={metadata} columns={mode === 'tablet' ? 2 : 1} compact />

      {(resolvedActions.visible.length > 0 || resolvedActions.overflow.length > 0) && (
        <div className="ds-action-set" role="group" aria-label="إجراءات النشاط" data-device={mode}>
          {resolvedActions.visible.length > 0 && (
            <div className="ds-action-set__visible">
              {resolvedActions.visible.map(action => <ActivityAction key={action.id} action={action} />)}
            </div>
          )}

          {resolvedActions.overflow.length > 0 && (
            <details className="ds-action-set__overflow">
              <summary className="ds-action-set__overflow-trigger" aria-label="المزيد من إجراءات النشاط">
                <MoreHorizontal size={16} aria-hidden="true" />
                <span>المزيد</span>
              </summary>
              <div className="ds-action-set__overflow-actions">
                {resolvedActions.overflow.map(action => <ActivityAction key={action.id} action={action} />)}
              </div>
            </details>
          )}
        </div>
      )}
    </Card>
  )
}

export { OUTCOME_LABEL, OUTCOME_TONE }
