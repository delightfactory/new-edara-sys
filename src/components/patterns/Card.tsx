import type { HTMLAttributes, ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'

export type CardSurface = 'default' | 'subtle' | 'elevated'
export type CardPadding = 'none' | 'sm' | 'md' | 'lg'

export interface CardProps extends HTMLAttributes<HTMLDivElement> {
  surface?: CardSurface
  padding?: CardPadding
  children: ReactNode
}

/**
 * Card — neutral V2 content surface.
 *
 * It intentionally carries no click/navigation semantics. Interactive cards
 * must use an appropriate link/button structure rather than making a generic
 * div pretend to be a button.
 */
export default function Card({
  surface = 'default',
  padding = 'md',
  className,
  children,
  ...props
}: CardProps) {
  return (
    <div
      className={cn(
        'ds-card',
        `ds-card--${surface}`,
        `ds-card--padding-${padding}`,
        className,
      )}
      {...props}
    >
      {children}
    </div>
  )
}
