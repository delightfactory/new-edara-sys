import { forwardRef, type ReactNode, type TextareaHTMLAttributes } from 'react'
import { cn } from '@/lib/utils/helpers'
import Field from './Field'

export interface TextareaProps extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  label?: ReactNode
  error?: ReactNode
  hint?: ReactNode
  required?: boolean
  optional?: boolean
  fieldClassName?: string
  /** react-hook-form register function return */
  register?: Record<string, unknown>
}

const Textarea = forwardRef<HTMLTextAreaElement, TextareaProps>(
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
          <textarea
            ref={ref}
            {...register}
            {...props}
            id={controlId}
            className={cn('form-textarea', invalid && 'error', className)}
            aria-describedby={mergedDescription}
            aria-invalid={invalid || undefined}
            aria-required={required || undefined}
          />
        )
      }}
    </Field>
  ),
)

Textarea.displayName = 'Textarea'
export default Textarea
