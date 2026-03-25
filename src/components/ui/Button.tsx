import { forwardRef, type ButtonHTMLAttributes, type ReactNode, Children } from 'react'
import { cn } from '@/lib/utils/helpers'

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'danger' | 'success' | 'ghost'
  size?: 'sm' | 'md' | 'lg'
  loading?: boolean
  icon?: ReactNode
  block?: boolean
}

/**
 * Button — مكون زر موحد يغلف CSS classes الموجودة
 * يدعم: variant, size, loading, icon, block
 * تلقائياً يضيف btn-icon عند وجود أيقونة فقط بدون نص
 */
const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ variant = 'primary', size = 'md', loading, icon, block, className, children, disabled, ...props }, ref) => {
    const hasChildren = Children.count(children) > 0 || (typeof children === 'string' && children.trim().length > 0)
    const isIconOnly = !!icon && !hasChildren && !loading

    const classes = cn(
      'btn',
      `btn-${variant}`,
      size === 'sm' && 'btn-sm',
      size === 'lg' && 'btn-lg',
      isIconOnly && 'btn-icon',
      block && 'btn-block',
      className
    )

    return (
      <button
        ref={ref}
        className={classes}
        disabled={disabled || loading}
        {...props}
      >
        {loading ? (
          <span className="spinner spinner-sm" />
        ) : icon ? (
          icon
        ) : null}
        {children}
      </button>
    )
  }
)

Button.displayName = 'Button'
export default Button
