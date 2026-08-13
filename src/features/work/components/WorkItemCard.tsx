import DataCard from '@/components/ui/DataCard'
import { formatWorkNumber } from '../presentation'
import type { WorkItem, WorkOperationalFlags } from '../types'
import { WorkOperationalBadges, WorkPriorityBadge, WorkStatusBadge } from './WorkBadges'

interface WorkItemCardProps {
  item: WorkItem
  ownerName?: string | null
  assigneeName?: string | null
  flags?: WorkOperationalFlags
  onClick?: () => void
}

const formatDateTime = (value: string | null) => {
  if (!value) return '—'
  return new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Africa/Cairo',
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(new Date(value))
}

export default function WorkItemCard({
  item,
  ownerName,
  assigneeName,
  flags,
  onClick,
}: WorkItemCardProps) {
  const currentBallHolder = item.status === 'waiting'
    ? item.waiting_on_label || 'جهة انتظار'
    : assigneeName || 'غير محدد'

  const clock = item.status === 'waiting' && item.next_action_at
    ? item.next_action_at
    : item.due_at

  return (
    <DataCard
      title={item.title}
      subtitle={formatWorkNumber(item.work_number)}
      badge={(
        <span style={{ display: 'inline-flex', gap: 6, flexWrap: 'wrap' }}>
          <WorkStatusBadge status={item.status} />
          <WorkPriorityBadge priority={item.priority} />
          {flags && <WorkOperationalBadges flags={flags} />}
        </span>
      )}
      metadata={[
        { label: 'المسؤول النهائي', value: ownerName || '—' },
        { label: 'الكرة الآن عند', value: currentBallHolder, highlight: true },
        { label: 'الخطوة التالية', value: item.next_action_text || '—' },
        { label: item.status === 'waiting' ? 'موعد المتابعة' : 'الموعد', value: formatDateTime(clock) },
      ]}
      onClick={onClick}
    />
  )
}
