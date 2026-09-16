import type { HTMLAttributes, ReactNode } from 'react'
import Button, { type ButtonProps } from '@/components/ui/Button'
import { cn } from '@/lib/utils/helpers'

export interface TransactionHeaderAction {
  key: string
  label: ReactNode
  icon?: ReactNode
  onClick: () => void
  variant?: ButtonProps['variant']
  disabled?: boolean
  loading?: boolean
  ariaLabel?: string
}

export interface TransactionHeaderProps extends Omit<HTMLAttributes<HTMLElement>, 'title'> {
  title: ReactNode
  subtitle?: ReactNode
  status?: ReactNode
  backAction?: ReactNode
  primaryAction?: TransactionHeaderAction
  secondaryActions?: TransactionHeaderAction[]
  destructiveActions?: TransactionHeaderAction[]
  utilityActions?: ReactNode
  sticky?: boolean
}

function HeaderAction({
  action,
  fallbackVariant,
}: {
  action: TransactionHeaderAction
  fallbackVariant: NonNullable<ButtonProps['variant']>
}) {
  const accessibleLabel = action.ariaLabel
    ?? (typeof action.label === 'string' ? action.label : undefined)

  return (
    <Button
      type="button"
      variant={action.variant ?? fallbackVariant}
      size="sm"
      touchTarget
      icon={action.icon}
      onClick={action.onClick}
      disabled={action.disabled}
      loading={action.loading}
      aria-label={accessibleLabel}
    >
      {action.label}
    </Button>
  )
}

/**
 * TransactionHeader — shared V2 page header for operational transaction detail screens.
 *
 * The domain/page owns action availability, permissions, workflow meaning and status mapping.
 * This pattern owns only hierarchy, responsive action placement and shared Button mechanics.
 */
export default function TransactionHeader({
  title,
  subtitle,
  status,
  backAction,
  primaryAction,
  secondaryActions = [],
  destructiveActions = [],
  utilityActions,
  sticky = false,
  className,
  ...props
}: TransactionHeaderProps) {
  const hasActions = !!primaryAction
    || secondaryActions.length > 0
    || destructiveActions.length > 0
    || !!utilityActions

  return (
    <header
      className={cn('ds-transaction-header', sticky && 'ds-transaction-header--sticky', className)}
      data-sticky={sticky ? 'true' : undefined}
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
        <div className="ds-transaction-header__actions" aria-label="إجراءات المستند">
          {primaryAction && (
            <div className="ds-transaction-header__primary">
              <HeaderAction action={primaryAction} fallbackVariant="primary" />
            </div>
          )}

          {secondaryActions.length > 0 && (
            <div className="ds-transaction-header__secondary">
              {secondaryActions.map(action => (
                <HeaderAction key={action.key} action={action} fallbackVariant="secondary" />
              ))}
            </div>
          )}

          {destructiveActions.length > 0 && (
            <div className="ds-transaction-header__destructive">
              {destructiveActions.map(action => (
                <HeaderAction key={action.key} action={action} fallbackVariant="danger" />
              ))}
            </div>
          )}

          {utilityActions && (
            <div className="ds-transaction-header__utility">{utilityActions}</div>
          )}
        </div>
      )}
    </header>
  )
}
