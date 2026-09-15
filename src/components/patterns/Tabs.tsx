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
  direction?: 'rtl' | 'ltr'
  className?: string
  listClassName?: string
  panelClassName?: string
  compact?: boolean
}

function safeId(value: string) {
  return value.replace(/[^a-zA-Z0-9_-]/g, '-')
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
  direction,
  className,
  listClassName,
  panelClassName,
  compact = false,
}: TabsProps) {
  const generatedId = safeId(useId())
  const refs = useRef<Record<string, HTMLButtonElement | null>>({})
  const activeItem = items.find(item => item.value === value && !item.disabled)
  const resolvedDirection = direction ?? (
    typeof document !== 'undefined' && document.documentElement.dir === 'rtl'
      ? 'rtl'
      : 'ltr'
  )

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
    const physicalDelta = event.key === 'ArrowRight' ? 1 : -1
    const logicalDelta = resolvedDirection === 'rtl' ? -physicalDelta : physicalDelta
    moveFocus(item.value, logicalDelta)
  }

  return (
    <div
      className={cn('ds-tabs', compact && 'ds-tabs--compact', className)}
      dir={resolvedDirection}
    >
      <div
        className={cn('ds-tabs__list', listClassName)}
        role="tablist"
        aria-label={ariaLabel}
      >
        {items.map(item => {
          const selected = item.value === value && !item.disabled
          const itemId = safeId(item.value)
          const tabId = `ds-tabs-${generatedId}-${itemId}-tab`
          const panelId = `ds-tabs-${generatedId}-${itemId}-panel`

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

      {activeItem?.panel !== undefined && (() => {
        const activeId = safeId(activeItem.value)
        return (
          <div
            id={`ds-tabs-${generatedId}-${activeId}-panel`}
            className={cn('ds-tabs__panel', panelClassName)}
            role="tabpanel"
            aria-labelledby={`ds-tabs-${generatedId}-${activeId}-tab`}
            tabIndex={0}
          >
            {activeItem.panel}
          </div>
        )
      })()}
    </div>
  )
}
