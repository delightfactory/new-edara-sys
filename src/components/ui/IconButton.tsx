import { forwardRef, type ReactNode } from 'react'
import Button, { type ButtonProps } from './Button'

export interface IconButtonProps extends Omit<ButtonProps, 'icon' | 'children' | 'aria-label'> {
  icon: ReactNode
  /** Required accessible name for the icon-only action. */
  label: string
  /** Optional native tooltip. Defaults to the accessible label. */
  tooltip?: string
}

/**
 * IconButton — V2 icon-only action primitive.
 *
 * Uses a touch-friendly minimum hit target by default while keeping the icon
 * itself visually compact. It intentionally requires an accessible label.
 */
const IconButton = forwardRef<HTMLButtonElement, IconButtonProps>(
  ({ icon, label, tooltip, touchTarget = true, type = 'button', ...props }, ref) => (
    <Button
      ref={ref}
      icon={icon}
      aria-label={label}
      title={tooltip ?? label}
      touchTarget={touchTarget}
      type={type}
      {...props}
    />
  ),
)

IconButton.displayName = 'IconButton'
export default IconButton
