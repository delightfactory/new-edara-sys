import type { ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'
import Card, { type CardPadding, type CardSurface } from './Card'
import SectionHeader from './SectionHeader'

export interface FormSectionProps {
  title?: ReactNode
  description?: ReactNode
  icon?: ReactNode
  action?: ReactNode
  children: ReactNode
  footer?: ReactNode
  surface?: CardSurface
  padding?: CardPadding
  className?: string
}

/**
 * FormSection — shared visual grouping for transaction/master-data forms.
 * It owns presentation only; validation and workflow logic stay with the page.
 */
export default function FormSection({
  title,
  description,
  icon,
  action,
  children,
  footer,
  surface = 'default',
  padding = 'lg',
  className,
}: FormSectionProps) {
  return (
    <Card surface={surface} padding={padding} className={cn('ds-form-section', className)}>
      {(title || description || icon || action) && (
        <SectionHeader
          title={title ?? ''}
          description={description}
          icon={icon}
          action={action}
          className="ds-form-section__header"
        />
      )}
      <div className="ds-form-section__body">{children}</div>
      {footer && <div className="ds-form-section__footer">{footer}</div>}
    </Card>
  )
}
