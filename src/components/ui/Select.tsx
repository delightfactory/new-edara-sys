import { forwardRef, type SelectHTMLAttributes } from 'react'
import { cn } from '@/lib/utils/helpers'

interface SelectOption {
  value: string
  label: string
}

interface SelectProps extends SelectHTMLAttributes<HTMLSelectElement> {
  label?: string
  error?: string
  hint?: string
  required?: boolean
  options?: SelectOption[]
  placeholder?: string
  /** react-hook-form register function return */
  register?: Record<string, unknown>
}

/**
 * Select — مكون قائمة منسدلة موحد
 * يغلف form-group + form-label + form-select + form-error
 */
const Select = forwardRef<HTMLSelectElement, SelectProps>(
  ({ label, error, hint, required, options = [], placeholder, register, className, id, children, ...props }, ref) => {
    const selectId = id || label?.replace(/\s/g, '_')

    return (
      <div className="form-group">
        {label && (
          <label className={cn('form-label', required && 'required')} htmlFor={selectId}>
            {label}
          </label>
        )}
        <select
          ref={ref}
          id={selectId}
          className={cn('form-select', error && 'error', className)}
          {...register}
          {...props}
        >
          {placeholder && <option value="">{placeholder}</option>}
          {options.map(opt => (
            <option key={opt.value} value={opt.value}>{opt.label}</option>
          ))}
          {children}
        </select>
        {error && <span className="form-error">{error}</span>}
        {hint && !error && <span className="form-hint">{hint}</span>}
      </div>
    )
  }
)

Select.displayName = 'Select'
export default Select
