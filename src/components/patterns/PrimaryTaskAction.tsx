import type { MouseEventHandler, ReactNode } from 'react'
import Button from '@/components/ui/Button'
import './OperationalTaskControls.css'

export interface PrimaryTaskActionProps {
  id?: string
  label: ReactNode
  loadingLabel?: ReactNode
  icon?: ReactNode
  disabled?: boolean
  loading?: boolean
  onClick?: MouseEventHandler<HTMLButtonElement>
  ariaLabel?: string
  className?: string
}

/**
 * PrimaryTaskAction — one context-dependent operational next action.
 *
 * Eligibility and action meaning stay with the caller. This is deliberately a
 * thin composition over the shared Button and is not an action registry or a
 * workflow rule engine.
 */
export default function PrimaryTaskAction({
  id,
  label,
  loadingLabel = 'جارٍ التنفيذ...',
  icon,
  disabled = false,
  loading = false,
  onClick,
  ariaLabel,
  className,
}: PrimaryTaskActionProps) {
  return (
    <div
      className={['ds-primary-task-action', className].filter(Boolean).join(' ')}
      data-primary-task-action
    >
      <Button
        id={id}
        type="button"
        size="lg"
        variant="primary"
        block
        touchTarget
        icon={icon}
        disabled={disabled}
        loading={loading}
        onClick={onClick}
        aria-label={ariaLabel ?? (typeof label === 'string' ? label : undefined)}
      >
        {loading ? loadingLabel : label}
      </Button>
    </div>
  )
}
