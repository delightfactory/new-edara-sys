import type { ReactNode } from 'react'
import { CircleCheck, CircleX, Info, TriangleAlert } from 'lucide-react'
import { cn } from '@/lib/utils/helpers'
import type { SemanticTone } from './StatusBadge'

export interface AlertPanelProps {
  tone?: SemanticTone
  title?: ReactNode
  children: ReactNode
  icon?: ReactNode
  action?: ReactNode
  /** Opt-in live announcement for dynamic messages. Static panels stay quiet. */
  announce?: boolean
  className?: string
}

function DefaultToneIcon({ tone }: { tone: SemanticTone }) {
  const props = { size: 18, strokeWidth: 2 } as const

  if (tone === 'success') return <CircleCheck {...props} />
  if (tone === 'warning') return <TriangleAlert {...props} />
  if (tone === 'danger') return <CircleX {...props} />
  return <Info {...props} />
}

/**
 * AlertPanel — operational information/warning/error/success surface.
 * Tone communicates emphasis; action consequence is decided separately by
 * the Button/ConfirmDialog contract.
 */
export default function AlertPanel({
  tone = 'info',
  title,
  children,
  icon,
  action,
  announce = false,
  className,
}: AlertPanelProps) {
  return (
    <div
      className={cn('ds-alert-panel', `ds-alert-panel--${tone}`, className)}
      data-tone={tone}
      role={announce ? (tone === 'danger' ? 'alert' : 'status') : undefined}
      aria-live={announce ? (tone === 'danger' ? 'assertive' : 'polite') : undefined}
    >
      <div className="ds-alert-panel__icon" aria-hidden="true">
        {icon ?? <DefaultToneIcon tone={tone} />}
      </div>

      <div className="ds-alert-panel__content">
        {title && <div className="ds-alert-panel__title">{title}</div>}
        <div className="ds-alert-panel__body">{children}</div>
      </div>

      {action && <div className="ds-alert-panel__action">{action}</div>}
    </div>
  )
}
