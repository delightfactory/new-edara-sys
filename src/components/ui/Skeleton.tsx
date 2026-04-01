import { cn } from '@/lib/utils/helpers'

interface SkeletonProps {
  className?: string
  width?: string | number
  height?: string | number
}

/**
 * Basic Skeleton for loading states
 * Automatically applies the shimmer animation from CSS
 */
export function Skeleton({ className, width, height }: SkeletonProps) {
  return (
    <div
      className={cn('skeleton', className)}
      style={{
        width: typeof width === 'number' ? `${width}px` : width,
        height: typeof height === 'number' ? `${height}px` : height,
      }}
    />
  )
}

/**
 * Standard Page Skeleton with rows
 */
export function PageSkeleton() {
  return (
    <div className="space-y-4" style={{ padding: 'var(--space-6)' }}>
      {[1, 2, 3, 4, 5].map(i => (
        <Skeleton key={i} className="skeleton-row" height={48} />
      ))}
    </div>
  )
}

/**
 * Standard Card Skeleton for grids
 */
export function CardSkeleton() {
  return (
    <div className="edara-card" style={{ padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
      <Skeleton width="60%" height={20} />
      <Skeleton width="40%" height={14} />
      <div style={{ marginTop: 'auto', paddingTop: 'var(--space-3)' }}>
        <Skeleton width="100%" height={32} />
      </div>
    </div>
  )
}
