import type { ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'
import type { SemanticTone } from './StatusBadge'
import Card from './Card'

export interface StatCardProps {
  label: ReactNode
  value: ReactNode
  context?: ReactNode
  trend?: ReactNode
  icon?: ReactNode
  action?: ReactNode
  tone?: SemanticTone
  className?: string
}

/**
 * StatCard — shared KPI/metric surface.
 *
 * Pages provide metric values and business meaning. The component only owns
 * hierarchy and semantic emphasis; it never calculates trends or KPIs.
 */
export default function StatCard({
  label,
  value,
  context,
  trend,
  icon,
  action,
  tone = 'neutral',
  className,
}: StatCardProps) {
  return (
    <Card
      className={cn('ds-stat-card', `ds-stat-card--${tone}`, className)}
      padding="md"
      data-tone={tone}
    >
      <div className="ds-stat-card__topline">
        <div className="ds-stat-card__label">{label}</div>
        {icon && (
          <div className="ds-stat-card__icon" aria-hidden="true">
            {icon}
          </div>
        )}
      </div>

      <div className="ds-stat-card__value">{value}</div>

      {(context || trend) && (
        <div className="ds-stat-card__meta">
          {context && <div className="ds-stat-card__context">{context}</div>}
          {trend && <div className="ds-stat-card__trend">{trend}</div>}
        </div>
      )}

      {action && <div className="ds-stat-card__action">{action}</div>}
    </Card>
  )
}
