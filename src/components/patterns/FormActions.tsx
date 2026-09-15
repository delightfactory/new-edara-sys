import type { HTMLAttributes, ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'

export type FormActionsAlign = 'start' | 'end' | 'between'

export interface FormActionsProps extends HTMLAttributes<HTMLDivElement> {
  align?: FormActionsAlign
  stickyOnMobile?: boolean
  children: ReactNode
}

/**
 * FormActions — consistent form action surface.
 * Sticky mobile behavior is explicit opt-in because not every form should pin
 * controls above the bottom navigation.
 */
export default function FormActions({
  align = 'end',
  stickyOnMobile = false,
  className,
  children,
  ...props
}: FormActionsProps) {
  return (
    <div
      className={cn(
        'ds-form-actions',
        `ds-form-actions--${align}`,
        stickyOnMobile && 'ds-form-actions--sticky-mobile',
        className,
      )}
      {...props}
    >
      {children}
    </div>
  )
}
