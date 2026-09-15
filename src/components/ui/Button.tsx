import { forwardRef, type ButtonHTMLAttributes, type ReactNode, Children } from 'react'
import { cn } from '@/lib/utils/helpers'

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'danger' | 'success' | 'ghost'
  size?: 'sm' | 'md' | 'lg'
  loading?: boolean
  icon?: ReactNode
  block?: boolean
  /**
   * Keeps the visual size/density variant while guaranteeing a touch-friendly
   * minimum hit target. V2 mobile/task surfaces should opt in during migration.
   * Legacy consumers remain unchanged until explicitly migrated.
   */
  touchTarget?: boolean
}

/**
 * Button — shared action primitive.
 *
 * Backward-compatible with the existing `.btn*` CSS API while exposing the
 * V2 interaction contract (loading semantics + optional touch target).
 */
const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  (
    {
      variant = 'primary',
      size = 'md',
      loading = false,
      icon,
      block,
      touchTarget = false,
      className,
      children,
      disabled,
      ...props
    },
    ref,
  ) => {
    const hasChildren = Children.toArray(children).some(child =>
      typeof child === 'string' ? child.trim().length > 0 : child != null,
    )
    const isIconOnly = !!icon && !hasChildren

    const classes = cn(
      'btn',
      `btn-${variant}`,
      size === 'sm' && 'btn-sm',
      size === 'lg' && 'btn-lg',
      isIconOnly && 'btn-icon',
      touchTarget && 'btn-touch',
      block && 'btn-block',
      className,
    )

    return (
      <button
        ref={ref}
        className={classes}
        disabled={disabled || loading}
        aria-busy={loading || undefined}
        data-loading={loading ? 'true' : undefined}
        {...props}
      >
        {loading ? (
          <span className="spinner spinner-sm" aria-hidden="true" />
        ) : icon ? (
          icon
        ) : null}
        {children}
      </button>
    )
  },
)

Button.displayName = 'Button'
export default Button
