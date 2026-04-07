import { Clock, AlertCircle } from 'lucide-react'

interface Props {
  lastCompletedAt: string | null
  isStale: boolean
}

export default function FreshnessIndicator({ lastCompletedAt, isStale }: Props) {
  const formatted = lastCompletedAt
    ? new Intl.DateTimeFormat('ar-EG', {
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      }).format(new Date(lastCompletedAt))
    : null

  const color = isStale ? 'var(--color-warning)' : 'var(--text-muted)'
  const Icon = isStale ? AlertCircle : Clock

  return (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: '4px',
        fontSize: '11px',
        color,
        whiteSpace: 'nowrap',
      }}
      title={isStale ? 'البيانات قديمة — آخر تحديث ناجح:' + (formatted ?? 'غير متاح') : 'آخر تحديث: ' + (formatted ?? 'غير متاح')}
    >
      <Icon size={11} strokeWidth={2} />
      {formatted ? formatted : 'لا يوجد بيانات بعد'}
      {isStale && <span style={{ fontWeight: 700 }}>— قديم</span>}
    </span>
  )
}
