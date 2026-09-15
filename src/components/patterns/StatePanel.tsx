import type { ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'

export type StateKind = 'empty' | 'error' | 'permission' | 'offline' | 'sync' | 'success'

export interface StatePanelProps {
  kind?: StateKind
  icon?: ReactNode
  title: ReactNode
  description?: ReactNode
  action?: ReactNode
  compact?: boolean
  className?: string
}

/**
 * StatePanel — shared page/collection/task state surface.
 *
 * Keeps state presentation consistent while leaving retry/navigation/business
 * behavior to the caller through the `action` slot.
 */
export default function StatePanel({
  kind = 'empty',
  icon,
  title,
  description,
  action,
  compact = false,
  className,
}: StatePanelProps) {
  return (
    <section
      className={cn(
        'ds-state-panel',
        `ds-state-panel--${kind}`,
        compact && 'ds-state-panel--compact',
        className,
      )}
      data-state-kind={kind}
      aria-live={kind === 'error' ? 'polite' : undefined}
    >
      {icon && (
        <div className="ds-state-panel__icon" aria-hidden="true">
          {icon}
        </div>
      )}
      <div className="ds-state-panel__title">{title}</div>
      {description && (
        <div className="ds-state-panel__description">{description}</div>
      )}
      {action && <div className="ds-state-panel__action">{action}</div>}
    </section>
  )
}
