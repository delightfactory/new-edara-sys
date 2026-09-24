import type { Key, ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'

export interface ChartTooltipItem {
  key: Key
  label: ReactNode
  value: ReactNode
  color?: string
  valueDirection?: 'ltr' | 'rtl' | 'auto'
}

export interface ChartTooltipProps {
  label: ReactNode
  items: readonly ChartTooltipItem[]
  className?: string
}

/**
 * ChartTooltip — shared V2 presentation for informational chart tooltips.
 *
 * The caller owns chart-library payload interpretation, series/domain labels,
 * row order, value formatting and any business meaning. This pattern owns only
 * the visual surface and RTL-safe label/value anatomy.
 */
export default function ChartTooltip({ label, items, className }: ChartTooltipProps) {
  return (
    <div className={cn('ds-chart-tooltip', className)} dir="rtl">
      <div className="ds-chart-tooltip__label">{label}</div>
      <div className="ds-chart-tooltip__items">
        {items.map(item => (
          <div
            key={item.key}
            className="ds-chart-tooltip__row"
            style={item.color ? { color: item.color } : undefined}
          >
            <span className="ds-chart-tooltip__item-label">{item.label}</span>
            <span
              className="ds-chart-tooltip__value"
              dir={item.valueDirection ?? 'auto'}
            >
              {item.value}
            </span>
          </div>
        ))}
      </div>
    </div>
  )
}
