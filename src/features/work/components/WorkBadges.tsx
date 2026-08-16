import Badge from '@/components/ui/Badge'
import {
  WORK_FLAG_PRESENTATION,
  WORK_PRIORITY_PRESENTATION,
  WORK_STATUS_PRESENTATION,
} from '../presentation'
import type { WorkItemStatus, WorkOperationalFlags, WorkPriority } from '../types'

export function WorkStatusBadge({ status }: { status: WorkItemStatus }) {
  const meta = WORK_STATUS_PRESENTATION[status]
  return <Badge variant={meta.variant}>{meta.label}</Badge>
}

export function WorkPriorityBadge({ priority }: { priority: WorkPriority }) {
  const meta = WORK_PRIORITY_PRESENTATION[priority]
  return <Badge variant={meta.variant}>{meta.label}</Badge>
}

export function WorkOperationalBadges({ flags }: { flags: WorkOperationalFlags }) {
  return (
    <>
      {WORK_FLAG_PRESENTATION.filter(({ key }) => flags[key]).map(({ key, label, variant }) => (
        <Badge key={key} variant={variant}>{label}</Badge>
      ))}
    </>
  )
}
