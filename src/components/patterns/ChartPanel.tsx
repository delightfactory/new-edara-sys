import type { HTMLAttributes, ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'
import Card from './Card'
import SectionHeader from './SectionHeader'

export interface ChartPanelProps extends Omit<HTMLAttributes<HTMLDivElement>, 'title'> {
  title: ReactNode
  description?: ReactNode
  action?: ReactNode
  headingLevel?: 2 | 3 | 4
  bodyClassName?: string
  children: ReactNode
}

/**
 * ChartPanel — shared V2 composition for analytical chart surfaces.
 *
 * It owns presentation hierarchy only. Chart data, loading/empty/blocked
 * states, calculations and interaction semantics remain with the caller.
 */
export default function ChartPanel({
  title,
  description,
  action,
  headingLevel = 3,
  bodyClassName,
  className,
  children,
  ...props
}: ChartPanelProps) {
  return (
    <Card
      surface="default"
      padding="lg"
      className={cn('ds-chart-panel', className)}
      {...props}
    >
      <SectionHeader
        title={title}
        description={description}
        action={action}
        headingLevel={headingLevel}
      />
      <div className={cn('ds-chart-panel__body', bodyClassName)}>{children}</div>
    </Card>
  )
}
