import type { ActivityOutcome, PlanStatus, PlanItemStatus, TargetTrend } from '@/lib/types/activities'

// ─── Config Maps ──────────────────────────────────────────────

const OUTCOME_CONFIG: Record<ActivityOutcome, { label: string; color: string }> = {
  order_placed:         { label: 'طلب مبيعات',       color: 'var(--color-success)' },
  agreed_order:         { label: 'اتفاق على طلب',    color: 'var(--color-success)' },
  collection:           { label: 'تحصيل',             color: 'var(--color-primary)' },
  promised_payment:     { label: 'وعد بالدفع',        color: 'var(--color-primary)' },
  followup_scheduled:   { label: 'متابعة مجدولة',    color: 'var(--color-warning)' },
  followup_visit:       { label: 'زيارة متابعة',      color: 'var(--color-warning)' },
  refused:              { label: 'رفض',               color: 'var(--color-danger)' },
  not_interested:       { label: 'غير مهتم',          color: 'var(--color-danger)' },
  closed:               { label: 'مغلق',              color: 'var(--text-muted)' },
  promotion:            { label: 'ترويج',             color: '#8b5cf6' },
  exploratory:          { label: 'استكشافية',         color: 'var(--text-muted)' },
  info_only:            { label: 'معلومات فقط',       color: 'var(--text-muted)' },
  no_answer:            { label: 'لا يرد',            color: 'var(--color-warning)' },
  busy:                 { label: 'مشغول',             color: 'var(--color-warning)' },
  callback_scheduled:   { label: 'مكالمة لاحقة',     color: 'var(--color-info)' },
}

const PLAN_STATUS_CONFIG: Record<PlanStatus, { label: string; color: string }> = {
  draft:       { label: 'مسودة',   color: 'var(--text-muted)' },
  confirmed:   { label: 'مؤكدة',  color: 'var(--color-primary)' },
  in_progress: { label: 'جارية',  color: 'var(--color-warning)' },
  completed:   { label: 'مكتملة', color: 'var(--color-success)' },
  partial:     { label: 'جزئية',  color: 'var(--color-warning)' },
  cancelled:   { label: 'ملغاة',  color: 'var(--color-danger)' },
  missed:      { label: 'فائتة',  color: 'var(--color-danger)' },
}

const ITEM_STATUS_CONFIG: Record<PlanItemStatus, { label: string; color: string }> = {
  pending:      { label: 'قيد الانتظار',  color: 'var(--text-muted)' },
  in_progress:  { label: 'جارية',         color: 'var(--color-warning)' },
  completed:    { label: 'مكتملة',        color: 'var(--color-success)' },
  skipped:      { label: 'متخطاة',        color: 'var(--text-secondary)' },
  missed:       { label: 'فائتة',         color: 'var(--color-danger)' },
  rescheduled:  { label: 'مُعاد جدولتها', color: '#8b5cf6' },
}

const TREND_CONFIG: Record<TargetTrend, { label: string; color: string }> = {
  on_track:  { label: 'في المسار',    color: 'var(--color-success)' },
  at_risk:   { label: 'في خطر',      color: 'var(--color-warning)' },
  behind:    { label: 'متأخر',       color: 'var(--color-danger)' },
  achieved:  { label: 'مُحقَّق',     color: 'var(--color-success)' },
  exceeded:  { label: 'تجاوز الهدف', color: '#8b5cf6' },
}

// ─── Shared badge style ────────────────────────────────────────

interface BadgeProps {
  label: string
  color: string
  size?: 'sm' | 'md'
}

function Badge({ label, color, size = 'md' }: BadgeProps) {
  const pad = size === 'sm' ? '2px 7px' : '3px 10px'
  const fs  = size === 'sm' ? '10px'    : '11px'
  return (
    <span style={{
      display: 'inline-flex',
      alignItems: 'center',
      padding: pad,
      borderRadius: '99px',
      fontSize: fs,
      fontWeight: 700,
      color: '#fff',
      background: color,
      whiteSpace: 'nowrap',
      letterSpacing: '0.2px',
    }}>
      {label}
    </span>
  )
}

// ─── Public API ────────────────────────────────────────────────

interface ActivityStatusBadgeProps {
  outcomeType?: ActivityOutcome | null
  planStatus?: PlanStatus | null
  itemStatus?: PlanItemStatus | null
  trend?: TargetTrend | null
  size?: 'sm' | 'md'
}

/**
 * Badge موحد لحالات الأنشطة والخطط والأهداف
 */
export default function ActivityStatusBadge({
  outcomeType,
  planStatus,
  itemStatus,
  trend,
  size = 'md',
}: ActivityStatusBadgeProps) {
  if (outcomeType && OUTCOME_CONFIG[outcomeType]) {
    const cfg = OUTCOME_CONFIG[outcomeType]
    return <Badge label={cfg.label} color={cfg.color} size={size} />
  }
  if (planStatus && PLAN_STATUS_CONFIG[planStatus]) {
    const cfg = PLAN_STATUS_CONFIG[planStatus]
    return <Badge label={cfg.label} color={cfg.color} size={size} />
  }
  if (itemStatus && ITEM_STATUS_CONFIG[itemStatus]) {
    const cfg = ITEM_STATUS_CONFIG[itemStatus]
    return <Badge label={cfg.label} color={cfg.color} size={size} />
  }
  if (trend && TREND_CONFIG[trend]) {
    const cfg = TREND_CONFIG[trend]
    return <Badge label={cfg.label} color={cfg.color} size={size} />
  }
  return null
}

export { OUTCOME_CONFIG, PLAN_STATUS_CONFIG, ITEM_STATUS_CONFIG, TREND_CONFIG }
