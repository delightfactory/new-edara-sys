import type { ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'

export interface SegmentedControlItem {
  value: string
  label: ReactNode
  icon?: ReactNode
  disabled?: boolean
}

export interface SegmentedControlProps {
  value: string
  onValueChange: (value: string) => void
  items: SegmentedControlItem[]
  ariaLabel: string
  className?: string
  block?: boolean
}

/**
 * SegmentedControl — compact single-choice control for filters/view modes.
 *
 * This is intentionally not a tablist: it changes one selected value and does
 * not claim ownership of tab panels or route navigation.
 */
export default function SegmentedControl({
  value,
  onValueChange,
  items,
  ariaLabel,
  className,
  block = false,
}: SegmentedControlProps) {
  return (
    <div
      className={cn(
        'ds-segmented-control',
        block && 'ds-segmented-control--block',
        className,
      )}
      role="group"
      aria-label={ariaLabel}
    >
      {items.map(item => {
        const selected = item.value === value
        return (
          <button
            key={item.value}
            type="button"
            className={cn(
              'ds-segmented-control__item',
              selected && 'ds-segmented-control__item--active',
            )}
            aria-pressed={selected}
            disabled={item.disabled}
            onClick={() => onValueChange(item.value)}
          >
            {item.icon && (
              <span className="ds-segmented-control__icon" aria-hidden="true">
                {item.icon}
              </span>
            )}
            <span>{item.label}</span>
          </button>
        )
      })}
    </div>
  )
}
