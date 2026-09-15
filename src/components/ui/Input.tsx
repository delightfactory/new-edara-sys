import { forwardRef, type InputHTMLAttributes, type ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'
import Field from './Field'

export interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label?: ReactNode
  error?: ReactNode
  hint?: ReactNode
  required?: boolean
  optional?: boolean
  fieldClassName?: string
  /** react-hook-form register function return */
  register?: Record<string, unknown>
}

/**
 * Input — shared text/number input composed through the V2 Field anatomy.
 *
 * Backward-compatible with the existing label/error/hint API. `required`
 * remains presentation/accessibility metadata during legacy migration and does
 * not introduce new native browser validation by itself.
 */
const Input = forwardRef<HTMLInputElement, InputProps>(
  (
    {
      label,
      error,
      hint,
      required,
      optional,
      fieldClassName,
      register,
      className,
      id,
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
          <input
            ref={ref}
            {...register}
            {...props}
            id={controlId}
            className={cn('form-input', invalid && 'error', className)}
            aria-describedby={mergedDescription}
            aria-invalid={invalid || undefined}
            aria-required={required || undefined}
          />
        )
      }}
    </Field>
  ),
)

Input.displayName = 'Input'
export default Input
