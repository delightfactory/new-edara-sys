import {
  type KeyboardEvent,
  type ReactNode,
  useId,
  useRef,
} from 'react'
import { cn } from '@/lib/utils/helpers'

export interface TabItem {
  value: string
  label: ReactNode
  icon?: ReactNode
  badge?: ReactNode
  disabled?: boolean
  panel?: ReactNode
}

export interface TabsProps {
  value: string
  onValueChange: (value: string) => void
  items: TabItem[]
  ariaLabel: string
  className?: string
  listClassName?: string
  panelClassName?: string
  compact?: boolean
}

function compactId(value: string) {
  return value.replace(/:/g, '')
}

/**
 * Tabs — controlled V2 content-tabs pattern.
 *
 * Use only when tabs switch panels in the current page. Route navigation uses
 * SubNav instead so link semantics are preserved.
 */
export default function Tabs({
  value,
  onValueChange,
  items,
  ariaLabel,
  className,
  listClassName,
  panelClassName,
  compact = false,
}: TabsProps) {
  const generatedId = compactId(useId())
  const refs = useRef<Record<string, HTMLButtonElement | null>>({})
  const activeItem = items.find(item => item.value === value && !item.disabled)

  const moveFocus = (currentValue: string, delta: number) => {
    const enabledItems = items.filter(item => !item.disabled)
    if (enabledItems.length === 0) return

    const currentIndex = enabledItems.findIndex(item => item.value === currentValue)
    const safeIndex = currentIndex < 0 ? 0 : currentIndex
    const nextIndex = (safeIndex + delta + enabledItems.length) % enabledItems.length
    const next = enabledItems[nextIndex]

    refs.current[next.value]?.focus()
    onValueChange(next.value)
  }

  const handleKeyDown = (event: KeyboardEvent<HTMLButtonElement>, item: TabItem) => {
    if (event.key === 'Home') {
      const first = items.find(candidate => !candidate.disabled)
      if (!first) return
      event.preventDefault()
      refs.current[first.value]?.focus()
      onValueChange(first.value)
      return
    }

    if (event.key === 'End') {
      const last = [...items].reverse().find(candidate => !candidate.disabled)
      if (!last) return
      event.preventDefault()
      refs.current[last.value]?.focus()
      onValueChange(last.value)
      return
    }

    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return

    event.preventDefault()
    const direction = getComputedStyle(event.currentTarget).direction
    const isRtl = direction === 'rtl'
    const physicalDelta = event.key === 'ArrowRight' ? 1 : -1
    const logicalDelta = isRtl ? -physicalDelta : physicalDelta
    moveFocus(item.value, logicalDelta)
  }

  return (
    <div className={cn('ds-tabs', compact && 'ds-tabs--compact', className)}>
      <div
        className={cn('ds-tabs__list', listClassName)}
        role="tablist"
        aria-label={ariaLabel}
      >
        {items.map(item => {
          const selected = item.value === value && !item.disabled
          const tabId = `ds-tabs-${generatedId}-${item.value}-tab`
          const panelId = `ds-tabs-${generatedId}-${item.value}-panel`

          return (
            <button
              key={item.value}
              ref={node => { refs.current[item.value] = node }}
              id={tabId}
              type="button"
              role="tab"
              className={cn('ds-tabs__tab', selected && 'ds-tabs__tab--active')}
              aria-selected={selected}
              aria-controls={item.panel !== undefined ? panelId : undefined}
              disabled={item.disabled}
              tabIndex={selected ? 0 : -1}
              onClick={() => onValueChange(item.value)}
              onKeyDown={event => handleKeyDown(event, item)}
            >
              {item.icon && (
                <span className="ds-tabs__icon" aria-hidden="true">{item.icon}</span>
              )}
              <span className="ds-tabs__label">{item.label}</span>
              {item.badge && <span className="ds-tabs__badge">{item.badge}</span>}
            </button>
          )
        })}
      </div>

      {activeItem?.panel !== undefined && (
        <div
          id={`ds-tabs-${generatedId}-${activeItem.value}-panel`}
          className={cn('ds-tabs__panel', panelClassName)}
          role="tabpanel"
          aria-labelledby={`ds-tabs-${generatedId}-${activeItem.value}-tab`}
          tabIndex={0}
        >
          {activeItem.panel}
        </div>
      )}
    </div>
  )
}
