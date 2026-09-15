import { forwardRef, type ReactNode, type SelectHTMLAttributes } from 'react'
import { cn } from '@/lib/utils/helpers'
import Field from './Field'

export interface SelectOption {
  value: string
  label: string
}

export interface SelectProps extends SelectHTMLAttributes<HTMLSelectElement> {
  label?: ReactNode
  error?: ReactNode
  hint?: ReactNode
  required?: boolean
  optional?: boolean
  fieldClassName?: string
  options?: SelectOption[]
  placeholder?: string
  /** react-hook-form register function return */
  register?: Record<string, unknown>
}

/**
 * Select — native select composed through the V2 Field anatomy.
 */
const Select = forwardRef<HTMLSelectElement, SelectProps>(
  (
    {
      label,
      error,
      hint,
      required,
      optional,
      fieldClassName,
      options = [],
      placeholder,
      register,
      className,
      id,
      children,
      ...props
    },
    ref,
  ) => (
    <Field
      id={id}
      label={label}
      error={error}
      hint={hint}
      required={required}
      optional={optional}
      className={fieldClassName}
    >
      {({ controlId, describedBy, invalid }) => {
        const explicitDescription = props['aria-describedby']
        const mergedDescription = [explicitDescription, describedBy].filter(Boolean).join(' ') || undefined

        return (
          <select
            ref={ref}
            {...register}
            {...props}
            id={controlId}
            className={cn('form-select', invalid && 'error', className)}
            aria-describedby={mergedDescription}
            aria-invalid={invalid || undefined}
            aria-required={required || undefined}
          >
            {placeholder && <option value="">{placeholder}</option>}
            {options.map(option => (
              <option key={option.value} value={option.value}>{option.label}</option>
            ))}
            {children}
          </select>
        )
      }}
    </Field>
  ),
)

Select.displayName = 'Select'
export default Select
