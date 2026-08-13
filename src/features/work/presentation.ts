import type { WorkItemStatus, WorkPriority, WorkOperationalFlags } from './types'

export type BadgeVariant = 'success' | 'warning' | 'danger' | 'info' | 'primary' | 'neutral'

export const WORK_STATUS_PRESENTATION: Record<WorkItemStatus, { label: string; variant: BadgeVariant }> = {
  draft: { label: 'مسودة', variant: 'neutral' },
  open: { label: 'مفتوحة', variant: 'info' },
  in_progress: { label: 'قيد التنفيذ', variant: 'primary' },
  waiting: { label: 'في انتظار متابعة', variant: 'warning' },
  pending_approval: { label: 'بانتظار اعتماد', variant: 'warning' },
  done: { label: 'مكتملة', variant: 'success' },
  cancelled: { label: 'ملغاة', variant: 'neutral' },
}

export const WORK_PRIORITY_PRESENTATION: Record<WorkPriority, { label: string; variant: BadgeVariant }> = {
  low: { label: 'منخفضة', variant: 'neutral' },
  normal: { label: 'عادية', variant: 'info' },
  high: { label: 'مهمة', variant: 'warning' },
  urgent: { label: 'عاجلة', variant: 'danger' },
  critical: { label: 'حرجة', variant: 'danger' },
}

export const WORK_FLAG_PRESENTATION: Array<{
  key: keyof WorkOperationalFlags
  label: string
  variant: BadgeVariant
}> = [
  { key: 'is_overdue', label: 'متأخرة', variant: 'danger' },
  { key: 'is_followup_due', label: 'متابعة مستحقة', variant: 'warning' },
  { key: 'is_blocked', label: 'معطلة', variant: 'danger' },
  { key: 'is_stale', label: 'بلا حركة', variant: 'warning' },
  { key: 'is_at_risk', label: 'معرضة للتأخير', variant: 'warning' },
  { key: 'is_escalated', label: 'تم تصعيدها', variant: 'danger' },
]

export function formatWorkNumber(workNumber: number): string {
  return `WK-${String(workNumber).padStart(6, '0')}`
}
