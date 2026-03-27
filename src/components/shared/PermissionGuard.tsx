import { type ReactNode } from 'react'
import { Lock } from 'lucide-react'
import { useAuthStore } from '@/stores/auth-store'

interface PermissionGuardProps {
  /** The permission(s) required. Array = any-of logic (canAny). */
  permission: string | string[]
  /**
   * - 'hide' (default): renders null if user has no permission
   * - 'disable': renders grayed-out element with lock icon + aria-disabled + tooltip
   */
  mode?: 'hide' | 'disable'
  /** Optional custom tooltip message for disable mode */
  disabledTitle?: string
  children: ReactNode
}

/**
 * PermissionGuard — wraps any UI element with a permission check.
 *
 * Usage:
 * ```tsx
 * // Hides element entirely
 * <PermissionGuard permission="sales.orders.delete">
 *   <Button>حذف</Button>
 * </PermissionGuard>
 *
 * // Shows grayed-out element with lock icon
 * <PermissionGuard permission="finance.journals.create" mode="disable">
 *   <Button>قيد جديد</Button>
 * </PermissionGuard>
 * ```
 */
export default function PermissionGuard({
  permission,
  mode = 'hide',
  disabledTitle = 'ليس لديك صلاحية للقيام بهذا الإجراء',
  children,
}: PermissionGuardProps) {
  const can = useAuthStore(s => s.can)
  const canAny = useAuthStore(s => s.canAny)

  const hasPermission = Array.isArray(permission)
    ? canAny(permission)
    : can(permission)

  if (hasPermission) {
    return <>{children}</>
  }

  if (mode === 'hide') {
    return null
  }

  // mode === 'disable'
  return (
    <div
      className="permission-guard-disabled"
      aria-disabled="true"
      role="group"
      title={disabledTitle}
      tabIndex={-1}
    >
      <div className="permission-guard-content" aria-hidden="true">
        {children}
      </div>
      <span className="permission-guard-lock" aria-hidden="true">
        <Lock size={12} />
      </span>

      <style>{`
        .permission-guard-disabled {
          position: relative;
          display: inline-flex;
          align-items: center;
          gap: var(--space-1);
          cursor: not-allowed;
          user-select: none;
        }

        .permission-guard-content {
          opacity: 0.4;
          pointer-events: none;
          filter: grayscale(0.3);
          transition: opacity var(--transition-fast);
        }

        .permission-guard-lock {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 18px;
          height: 18px;
          border-radius: var(--radius-full);
          background: var(--bg-surface-2);
          border: 1px solid var(--border-primary);
          color: var(--text-muted);
          flex-shrink: 0;
          position: absolute;
          top: -4px;
          inset-inline-end: -6px;
        }
      `}</style>
    </div>
  )
}
