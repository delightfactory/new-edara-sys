import type { HTMLAttributes, ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'

export interface MetricGridProps extends HTMLAttributes<HTMLDivElement> {
  columns?: 2 | 3 | 4
  children: ReactNode
}

/**
 * MetricGrid — shared responsive layout for KPI/summary surfaces.
 *
 * Metric values and business meaning stay caller-owned. The grid only owns the
 * canonical 1-column Mobile, 2-column Tablet and dense Desktop composition.
 */
export default function MetricGrid({
  columns = 3,
  className,
  children,
  ...props
}: MetricGridProps) {
  return (
    <div
      className={cn('ds-metric-grid', `ds-metric-grid--cols-${columns}`, className)}
      data-metric-grid
      data-columns={columns}
      {...props}
    >
      {children}
    </div>
  )
}
