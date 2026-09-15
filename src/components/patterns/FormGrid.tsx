import type { HTMLAttributes, ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'

export type FormGridColumns = 1 | 2 | 3 | 4

export interface FormGridProps extends HTMLAttributes<HTMLDivElement> {
  columns?: FormGridColumns
  compact?: boolean
  children: ReactNode
}

/**
 * FormGrid — responsive field layout for form sections.
 * Mobile is always one column. Tablet is capped at two columns. Desktop uses
 * the requested density up to four columns.
 */
export default function FormGrid({
  columns = 2,
  compact = false,
  className,
  children,
  ...props
}: FormGridProps) {
  return (
    <div
      className={cn(
        'ds-form-grid',
        `ds-form-grid--cols-${columns}`,
        compact && 'ds-form-grid--compact',
        className,
      )}
      {...props}
    >
      {children}
    </div>
  )
}
