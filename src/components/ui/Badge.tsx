import type { ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'

interface BadgeProps {
  variant?: 'success' | 'warning' | 'danger' | 'info' | 'primary' | 'neutral'
  children: ReactNode
  className?: string
}

/**
 * Badge — مكون شارة موحد
 */
export default function Badge({ variant = 'neutral', children, className }: BadgeProps) {
  return (
    <span className={cn('badge', `badge-${variant}`, className)}>
      {children}
    </span>
  )
}
