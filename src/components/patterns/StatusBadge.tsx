import type { ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'

export type SemanticTone = 'neutral' | 'info' | 'success' | 'warning' | 'danger'

export interface StatusBadgeProps {
  /** Human-readable status label. Status must never be color-only. */
  label: ReactNode
  tone?: SemanticTone
  icon?: ReactNode
  className?: string
}

/**
 * StatusBadge — visual mapping for domain statuses.
 *
 * Domain values remain owned by each feature. The feature maps its status to
 * one of the small semantic tones and supplies the user-facing label.
 */
export default function StatusBadge({
  label,
  tone = 'neutral',
  icon,
  className,
}: StatusBadgeProps) {
  return (
    <span
      className={cn('ds-status-badge', `ds-status-badge--${tone}`, className)}
      data-tone={tone}
    >
      {icon && (
        <span className="ds-status-badge__icon" aria-hidden="true">
          {icon}
        </span>
      )}
      <span>{label}</span>
    </span>
  )
}
