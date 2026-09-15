import type { ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'

export interface SectionHeaderProps {
  title: ReactNode
  description?: ReactNode
  icon?: ReactNode
  action?: ReactNode
  headingLevel?: 2 | 3 | 4
  className?: string
}

export default function SectionHeader({
  title,
  description,
  icon,
  action,
  headingLevel = 2,
  className,
}: SectionHeaderProps) {
  const Heading = headingLevel === 2 ? 'h2' : headingLevel === 3 ? 'h3' : 'h4'

  return (
    <div className={cn('ds-section-header', className)}>
      <div className="ds-section-header__main">
        {icon && (
          <span className="ds-section-header__icon" aria-hidden="true">
            {icon}
          </span>
        )}
        <div className="ds-section-header__copy">
          <Heading className="ds-section-header__title">{title}</Heading>
          {description && (
            <div className="ds-section-header__description">{description}</div>
          )}
        </div>
      </div>

      {action && <div className="ds-section-header__action">{action}</div>}
    </div>
  )
}
