import { cn } from '@/lib/utils/helpers'

interface SpinnerProps {
  size?: 'sm' | 'md' | 'lg'
  className?: string
}

/**
 * Spinner — مكون تحميل دائري موحد
 */
export default function Spinner({ size = 'md', className }: SpinnerProps) {
  return (
    <span
      className={cn(
        'spinner',
        size === 'sm' && 'spinner-sm',
        size === 'lg' && 'spinner-lg',
        className
      )}
      role="status"
      aria-label="جاري التحميل"
    />
  )
}
