import type { ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'
import { useDeviceMode, type DeviceMode } from '@/hooks/useDeviceMode'
import StatePanel from './StatePanel'

export interface ResponsiveCollectionRenderContext {
  device: DeviceMode
}

export interface ResponsiveCollectionProps<T> {
  items: T[]
  loading?: boolean
  renderDesktop: (items: T[], context: ResponsiveCollectionRenderContext) => ReactNode
  renderMobile: (items: T[], context: ResponsiveCollectionRenderContext) => ReactNode
  renderTablet?: (items: T[], context: ResponsiveCollectionRenderContext) => ReactNode
  tabletFallback?: 'desktop' | 'mobile'
  loadingState?: ReactNode
  emptyState?: ReactNode
  emptyTitle?: ReactNode
  emptyDescription?: ReactNode
  className?: string
}

/**
 * ResponsiveCollection — one data capability with deliberate device composition.
 *
 * The caller owns the business/data logic and provides presentation renderers.
 * Only one renderer is mounted at a time, so desktop tables and mobile cards do
 * not duplicate interactive descendants or side effects in the DOM.
 */
export default function ResponsiveCollection<T>({
  items,
  loading = false,
  renderDesktop,
  renderMobile,
  renderTablet,
  tabletFallback = 'desktop',
  loadingState,
  emptyState,
  emptyTitle = 'لا توجد بيانات',
  emptyDescription,
  className,
}: ResponsiveCollectionProps<T>) {
  const device = useDeviceMode()

  if (loading) {
    return (
      <div className={cn('ds-responsive-collection', className)} data-device={device} data-collection-state="loading">
        {loadingState ?? (
          <div aria-label="جاري تحميل البيانات" aria-live="polite">
            {[1, 2, 3, 4].map(i => <div key={i} className="skeleton skeleton-row" />)}
          </div>
        )}
      </div>
    )
  }

  if (items.length === 0) {
    return (
      <div className={cn('ds-responsive-collection', className)} data-device={device} data-collection-state="empty">
        {emptyState ?? (
          <StatePanel
            kind="empty"
            title={emptyTitle}
            description={emptyDescription}
            compact
          />
        )}
      </div>
    )
  }

  const context = { device }
  let content: ReactNode

  if (device === 'mobile') {
    content = renderMobile(items, context)
  } else if (device === 'tablet') {
    content = renderTablet
      ? renderTablet(items, context)
      : tabletFallback === 'mobile'
        ? renderMobile(items, context)
        : renderDesktop(items, context)
  } else {
    content = renderDesktop(items, context)
  }

  return (
    <div className={cn('ds-responsive-collection', className)} data-device={device} data-collection-state="ready">
      {content}
    </div>
  )
}
