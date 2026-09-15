import type { ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'

export type CollectionView = 'mobile' | 'tablet' | 'desktop'
export type CollectionState = 'ready' | 'loading' | 'empty' | 'error'

export interface ResponsiveCollectionProps {
  /**
   * Device/view decision is intentionally supplied by the caller/shell.
   * V2 does not freeze tablet breakpoints here before runtime validation.
   */
  view: CollectionView
  state?: CollectionState
  desktop: ReactNode
  mobile: ReactNode
  /** Falls back to desktop presentation until a deliberate tablet mode exists. */
  tablet?: ReactNode
  loading?: ReactNode
  empty?: ReactNode
  error?: ReactNode
  /** Pagination, infinite-load progress/end state, or other collection footer. */
  footer?: ReactNode
  /** Background refresh keeps current content mounted while exposing busy state. */
  refreshing?: boolean
  ariaLabel?: string
  className?: string
}

/**
 * ResponsiveCollection — presentation/state orchestration only.
 *
 * It deliberately does not fetch data, choose query strategies, paginate, or
 * trigger infinite loading. Those remain in the domain page during the first
 * migration so responsive UI work cannot silently alter data semantics.
 */
export default function ResponsiveCollection({
  view,
  state = 'ready',
  desktop,
  mobile,
  tablet,
  loading,
  empty,
  error,
  footer,
  refreshing = false,
  ariaLabel,
  className,
}: ResponsiveCollectionProps) {
  const activePresentation = view === 'mobile'
    ? mobile
    : view === 'tablet'
      ? (tablet ?? desktop)
      : desktop

  const stateContent = state === 'loading'
    ? loading
    : state === 'empty'
      ? empty
      : state === 'error'
        ? error
        : activePresentation

  return (
    <section
      className={cn('ds-responsive-collection', className)}
      data-view={view}
      data-state={state}
      aria-label={ariaLabel}
      aria-busy={state === 'loading' || refreshing || undefined}
    >
      <div className="ds-responsive-collection__body">
        {stateContent}
      </div>

      {state === 'ready' && footer && (
        <div className="ds-responsive-collection__footer">
          {footer}
        </div>
      )}
    </section>
  )
}
