import { forwardRef, type InputHTMLAttributes } from 'react'
import { cn } from '@/lib/utils/helpers'

interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label?: string
  error?: string
  hint?: string
  required?: boolean
  /** react-hook-form register function return */
  register?: Record<string, unknown>
}

/**
 * Input — مكون حقل إدخال موحد
 * يغلف form-group + form-label + form-input + form-error
 */
const Input = forwardRef<HTMLInputElement, InputProps>(
  ({ label, error, hint, required, register, className, id, ...props }, ref) => {
    const inputId = id || label?.replace(/\s/g, '_')

    return (
      <div className="form-group">
        {label && (
          <label className={cn('form-label', required && 'required')} htmlFor={inputId}>
            {label}
          </label>
        )}
        <input
          ref={ref}
          id={inputId}
          className={cn('form-input', error && 'error', className)}
          {...register}
          {...props}
        />
        {error && <span className="form-error">{error}</span>}
        {hint && !error && <span className="form-hint">{hint}</span>}
      </div>
    )
  }
)

Input.displayName = 'Input'
export default Input
