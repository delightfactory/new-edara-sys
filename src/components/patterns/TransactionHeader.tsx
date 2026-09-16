import type { HTMLAttributes, ReactNode } from 'react'
import Button, { type ButtonProps } from '@/components/ui/Button'
import { useDeviceMode } from '@/hooks/useDeviceMode'
import { cn } from '@/lib/utils/helpers'
import { resolveActionSet, type AppAction } from './ActionRegistry'

export interface TransactionHeaderProps extends Omit<HTMLAttributes<HTMLElement>, 'title'> {
  title: ReactNode
  subtitle?: ReactNode
  status?: ReactNode
  backAction?: ReactNode
  actions?: AppAction[]
  tools?: ReactNode
  sticky?: boolean
}

function getActionVariant(action: AppAction): NonNullable<ButtonProps['variant']> {
  if (action.tone) return action.tone
  return action.importance === 'primary' ? 'primary' : 'secondary'
}

function HeaderAction({ action }: { action: AppAction }) {
  return (
    <Button
      type="button"
      variant={getActionVariant(action)}
      size="sm"
      touchTarget
      icon={action.icon}
      onClick={action.onSelect}
      disabled={action.disabled}
      loading={action.loading}
      aria-label={action.ariaLabel ?? action.label}
      data-action-id={action.id}
    >
      {action.label}
    </Button>
  )
}

/**
 * TransactionHeader — shared V2 page header for operational transaction detail screens.
 *
 * Domain pages declare actions through the shared ActionRegistry contract. The registry owns
 * device-aware priority/placement; this pattern only renders the resolved header surface.
 * Permissions, workflow meaning, callbacks and status mapping remain page/domain-owned.
 */
export default function TransactionHeader({
  title,
  subtitle,
  status,
  backAction,
  actions = [],
  tools,
  sticky = false,
  className,
  ...props
}: TransactionHeaderProps) {
  const device = useDeviceMode()
  const resolvedActions = resolveActionSet(actions, device)
  const hasActions = resolvedActions.visible.length > 0
    || resolvedActions.overflow.length > 0
    || !!tools

  return (
    <header
      className={cn('ds-transaction-header', sticky && 'ds-transaction-header--sticky', className)}
      data-sticky={sticky ? 'true' : undefined}
      data-device={device}
      {...props}
    >
      <div className="ds-transaction-header__top">
        {backAction && <div className="ds-transaction-header__back">{backAction}</div>}

        <div className="ds-transaction-header__identity">
          <div className="ds-transaction-header__heading-row">
            <h1 className="ds-transaction-header__title">{title}</h1>
            {status && <div className="ds-transaction-header__status">{status}</div>}
          </div>
          {subtitle && <div className="ds-transaction-header__subtitle">{subtitle}</div>}
        </div>
      </div>

      {hasActions && (
        <div
          className="ds-transaction-header__actions"
          role="group"
          aria-label="إجراءات المستند"
        >
          {resolvedActions.visible.length > 0 && (
            <div className="ds-transaction-header__visible-actions">
              {resolvedActions.visible.map(action => (
                <HeaderAction key={action.id} action={action} />
              ))}
            </div>
          )}

          {resolvedActions.overflow.length > 0 && (
            <details className="ds-transaction-header__overflow">
              <summary className="ds-transaction-header__overflow-trigger">
                المزيد
              </summary>
              <div className="ds-transaction-header__overflow-actions">
                {resolvedActions.overflow.map(action => (
                  <HeaderAction key={action.id} action={action} />
                ))}
              </div>
            </details>
          )}

          {tools && <div className="ds-transaction-header__tools">{tools}</div>}
        </div>
      )}
    </header>
  )
}
