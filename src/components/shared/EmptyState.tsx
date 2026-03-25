import type { ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'

interface EmptyStateProps {
  icon?: ReactNode
  title?: string
  text?: string
  action?: ReactNode
  className?: string
}

/**
 * EmptyState — مكون الحالة الفارغة الموحد
 */
export default function EmptyState({
  icon,
  title = 'لا توجد بيانات',
  text,
  action,
  className,
}: EmptyStateProps) {
  return (
    <div className={cn('empty-state', className)}>
      {icon && <div className="empty-state-icon">{icon}</div>}
      <p className="empty-state-title">{title}</p>
      {text && <p className="empty-state-text">{text}</p>}
      {action}
    </div>
  )
}
