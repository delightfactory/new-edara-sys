import { useId, type ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'

export interface FieldContext {
  controlId: string
  hintId?: string
  errorId?: string
  describedBy?: string
  invalid: boolean
}

export interface FieldProps {
  id?: string
  label?: ReactNode
  hint?: ReactNode
  error?: ReactNode
  required?: boolean
  optional?: boolean
  className?: string
  children: ReactNode | ((context: FieldContext) => ReactNode)
}

function compactId(value: string) {
  return value.replace(/:/g, '')
}

/**
 * Field — V2 form-field anatomy.
 *
 * Owns label/help/error relationships only. Validation/business rules remain
 * in the consuming form. `required` is exposed accessibly but does not inject
 * native browser validation into legacy workflows during migration.
 */
export default function Field({
  id,
  label,
  hint,
  error,
  required = false,
  optional = false,
  className,
  children,
}: FieldProps) {
  const generatedId = useId()
  const controlId = id || `field-${compactId(generatedId)}`
  const hintId = hint && !error ? `${controlId}-hint` : undefined
  const errorId = error ? `${controlId}-error` : undefined
  const describedBy = [errorId, hintId].filter(Boolean).join(' ') || undefined
  const invalid = Boolean(error)

  const context: FieldContext = {
    controlId,
    hintId,
    errorId,
    describedBy,
    invalid,
  }

  return (
    <div className={cn('form-group', 'ds-field', className)}>
      {label && (
        <label
          className={cn('form-label', required && 'required')}
          htmlFor={controlId}
        >
          <span>{label}</span>
          {optional && !required && (
            <span className="ds-field-optional">اختياري</span>
          )}
        </label>
      )}

      {typeof children === 'function' ? children(context) : children}

      {error && (
        <span id={errorId} className="form-error" role="alert">
          {error}
        </span>
      )}

      {hint && !error && (
        <span id={hintId} className="form-hint">
          {hint}
        </span>
      )}
    </div>
  )
}
