import type { ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'

export interface KeyValueItem {
  key: string
  label: ReactNode
  value: ReactNode
  emphasis?: 'default' | 'strong' | 'muted'
}

export interface KeyValueListProps {
  items: KeyValueItem[]
  columns?: 1 | 2 | 3 | 4
  compact?: boolean
  className?: string
}

/**
 * KeyValueList — shared summary/details anatomy for entity and transaction data.
 */
export default function KeyValueList({
  items,
  columns = 2,
  compact = false,
  className,
}: KeyValueListProps) {
  return (
    <dl
      className={cn(
        'ds-key-value-list',
        `ds-key-value-list--cols-${columns}`,
        compact && 'ds-key-value-list--compact',
        className,
      )}
    >
      {items.map(item => (
        <div className="ds-key-value-list__item" key={item.key}>
          <dt className="ds-key-value-list__label">{item.label}</dt>
          <dd
            className={cn(
              'ds-key-value-list__value',
              item.emphasis && item.emphasis !== 'default' && `ds-key-value-list__value--${item.emphasis}`,
            )}
          >
            {item.value}
          </dd>
        </div>
      ))}
    </dl>
  )
}
