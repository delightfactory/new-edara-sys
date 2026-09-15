import type { ReactNode } from 'react'
import { NavLink } from 'react-router-dom'
import { cn } from '@/lib/utils/helpers'

export interface SubNavItem {
  to: string
  label: ReactNode
  icon?: ReactNode
  badge?: ReactNode
  end?: boolean
  disabled?: boolean
}

export interface SubNavProps {
  items: SubNavItem[]
  ariaLabel: string
  className?: string
  compact?: boolean
}

/**
 * SubNav — route-level secondary navigation.
 *
 * Uses real links/NavLink semantics. Do not use this component for in-page
 * panels that require ARIA tab semantics; use Tabs for those.
 */
export default function SubNav({
  items,
  ariaLabel,
  className,
  compact = false,
}: SubNavProps) {
  return (
    <nav
      className={cn('ds-subnav', compact && 'ds-subnav--compact', className)}
      aria-label={ariaLabel}
    >
      <div className="ds-subnav__track">
        {items.map(item => {
          if (item.disabled) {
            return (
              <span
                key={`${item.to}-${String(item.label)}`}
                className="ds-subnav__item ds-subnav__item--disabled"
                aria-disabled="true"
              >
                {item.icon && (
                  <span className="ds-subnav__icon" aria-hidden="true">{item.icon}</span>
                )}
                <span className="ds-subnav__label">{item.label}</span>
                {item.badge && <span className="ds-subnav__badge">{item.badge}</span>}
              </span>
            )
          }

          return (
            <NavLink
              key={`${item.to}-${String(item.label)}`}
              to={item.to}
              end={item.end}
              className={({ isActive }) =>
                cn('ds-subnav__item', isActive && 'ds-subnav__item--active')
              }
            >
              {item.icon && (
                <span className="ds-subnav__icon" aria-hidden="true">{item.icon}</span>
              )}
              <span className="ds-subnav__label">{item.label}</span>
              {item.badge && <span className="ds-subnav__badge">{item.badge}</span>}
            </NavLink>
          )
        })}
      </div>
    </nav>
  )
}
