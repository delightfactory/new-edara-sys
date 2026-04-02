// src/components/notifications/NotificationItem.tsx
// ─────────────────────────────────────────────────────────────
// Single notification row — used in both Panel (compact) and Center.
// Priority stripe, category icon, relative time, read/archive actions.
// ─────────────────────────────────────────────────────────────

import { useNavigate } from 'react-router-dom'
import {
  Clock, Users, Calendar, Banknote, Receipt, CheckCircle,
  Package, ShoppingCart, Settings, Shield, AlertTriangle,
  Archive, Bell, Trash2,
} from 'lucide-react'
import type { Notification, NotificationCategory, NotificationPriority } from '@/lib/notifications/types'

// ── Helpers ──────────────────────────────────────────────────

function relativeTime(isoDate: string): string {
  const diff = Date.now() - new Date(isoDate).getTime()
  const seconds = Math.floor(diff / 1000)
  const minutes = Math.floor(seconds / 60)
  const hours   = Math.floor(minutes / 60)
  const days    = Math.floor(hours / 24)

  const rtf = new Intl.RelativeTimeFormat('ar', { numeric: 'auto' })
  if (days > 0)    return rtf.format(-days, 'day')
  if (hours > 0)   return rtf.format(-hours, 'hour')
  if (minutes > 0) return rtf.format(-minutes, 'minute')
  return 'الآن'
}

function priorityColor(p: NotificationPriority): string {
  switch (p) {
    case 'critical': return 'var(--danger, #dc2626)'
    case 'high':     return 'var(--warning, #f59e0b)'
    case 'medium':   return 'var(--info, #3b82f6)'
    default:         return 'transparent'
  }
}

function CategoryIcon({ category }: { category: NotificationCategory }) {
  const size = 16
  switch (category) {
    case 'hr_attendance': return <Clock size={size} />
    case 'hr_leaves':     return <Calendar size={size} />
    case 'hr_payroll':    return <Banknote size={size} />
    case 'finance_expenses': return <Receipt size={size} />
    case 'finance_approvals': return <CheckCircle size={size} />
    case 'inventory':     return <Package size={size} />
    case 'sales':         return <ShoppingCart size={size} />
    case 'system':        return <Settings size={size} />
    case 'alerts':        return <AlertTriangle size={size} />
    case 'procurement':   return <Package size={size} />
    case 'tasks':         return <CheckCircle size={size} />
    default:              return <Bell size={size} />
  }
}

function categoryIconColor(category: NotificationCategory): string {
  switch (category) {
    case 'hr_attendance':    return '#6366f1'
    case 'hr_leaves':        return '#8b5cf6'
    case 'hr_payroll':       return '#10b981'
    case 'finance_expenses': return '#f59e0b'
    case 'finance_approvals':return '#3b82f6'
    case 'inventory':        return '#06b6d4'
    case 'sales':            return '#ec4899'
    case 'system':           return '#6b7280'
    case 'alerts':           return '#ef4444'
    default:                 return '#6b7280'
  }
}

// ── Props ─────────────────────────────────────────────────────

interface NotificationItemProps {
  notification: Notification
  onRead?:    (id: string) => void
  onArchive?: (id: string) => void
  /** Hard-delete — only shown when notification.isArchived is true */
  onDelete?:  (id: string) => void
  compact?: boolean
}

// ── Component ─────────────────────────────────────────────────

export default function NotificationItem({
  notification,
  onRead,
  onArchive,
  onDelete,
  compact = false,
}: NotificationItemProps) {
  const navigate = useNavigate()

  const handleClick = () => {
    if (!notification.isRead) onRead?.(notification.id)
    if (notification.actionUrl) navigate(notification.actionUrl)
  }

  const handleArchive = (e: React.MouseEvent) => {
    e.stopPropagation()
    onArchive?.(notification.id)
  }

  const handleDelete = (e: React.MouseEvent) => {
    e.stopPropagation()
    onDelete?.(notification.id)
  }

  const stripeColor = priorityColor(notification.priority)
  const iconColor   = categoryIconColor(notification.category)

  return (
    <div
      className={`notif-item${notification.isRead ? ' notif-item--read' : ''}${compact ? ' notif-item--compact' : ''}`}
      onClick={handleClick}
      role="listitem"
      tabIndex={0}
      onKeyDown={e => e.key === 'Enter' && handleClick()}
      aria-label={`إشعار: ${notification.title}`}
    >
      {/* Priority stripe */}
      <div className="notif-stripe" style={{ background: stripeColor }} />

      {/* Icon */}
      <div className="notif-icon" style={{ color: iconColor, background: `${iconColor}18` }}>
        <CategoryIcon category={notification.category} />
      </div>

      {/* Content */}
      <div className="notif-content">
        <div className="notif-title-row">
          {!notification.isRead && <span className="notif-dot" aria-hidden="true" />}
          <span className="notif-title">{notification.title}</span>
        </div>
        <p className="notif-body">{notification.body}</p>
        <span className="notif-time">{relativeTime(notification.createdAt)}</span>
      </div>

      {/* Archive action — visible in active view */}
      {onArchive && (
        <button
          className="notif-action-btn"
          onClick={handleArchive}
          aria-label="أرشفة الإشعار"
          type="button"
          tabIndex={-1}
        >
          <Archive size={14} />
        </button>
      )}

      {/* Delete action — visible in archived view only (BUG-12) */}
      {onDelete && (
        <button
          className="notif-action-btn notif-action-btn--danger"
          onClick={handleDelete}
          aria-label="حذف نهائي"
          type="button"
          tabIndex={-1}
          title="حذف نهائي — لا يمكن التراجع"
        >
          <Trash2 size={14} />
        </button>
      )}

      <style>{`
        .notif-item {
          display: flex;
          align-items: flex-start;
          gap: var(--space-3);
          padding: var(--space-3) var(--space-4);
          cursor: pointer;
          position: relative;
          border-bottom: 1px solid var(--border-primary);
          transition: background var(--transition-fast);
          background: var(--bg-surface);
        }
        .notif-item:hover {
          background: var(--bg-hover);
        }
        .notif-item:hover .notif-archive-btn {
          opacity: 1;
        }
        .notif-item--compact {
          padding: var(--space-2) var(--space-3);
        }
        .notif-item--read {
          opacity: 0.72;
        }
        .notif-item--read .notif-title {
          font-weight: 500;
        }

        .notif-stripe {
          position: absolute;
          inset-inline-end: 0;           /* RTL-aware: logical replacement for right: 0 */
          top: 0;
          bottom: 0;
          width: 3px;
          border-radius: 0 var(--radius-sm) var(--radius-sm) 0;
          flex-shrink: 0;
        }

        .notif-icon {
          width: 32px;
          height: 32px;
          border-radius: var(--radius-full);
          display: flex;
          align-items: center;
          justify-content: center;
          flex-shrink: 0;
          margin-top: 2px;
        }

        .notif-content {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 3px;
        }

        .notif-title-row {
          display: flex;
          align-items: center;
          gap: var(--space-2);
        }

        .notif-dot {
          width: 7px;
          height: 7px;
          border-radius: 50%;
          background: var(--primary, #2563eb);
          flex-shrink: 0;
        }

        .notif-title {
          font-size: var(--text-sm);
          font-weight: 700;
          color: var(--text-primary);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
          flex: 1;
        }

        .notif-body {
          font-size: var(--text-xs);
          color: var(--text-secondary);
          line-height: 1.45;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
          margin: 0;
        }

        .notif-time {
          font-size: 11px;
          color: var(--text-muted);
        }

        /* shared action button (archive / delete) — appears on hover */
        .notif-action-btn {
          position: absolute;
          top: var(--space-2);
          inset-inline-start: var(--space-3);
          width: 28px;
          height: 28px;
          border-radius: var(--radius-sm);
          border: none;
          background: var(--bg-app);
          color: var(--text-muted);
          display: flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
          opacity: 0;
          transition: opacity var(--transition-fast), background var(--transition-fast), color var(--transition-fast);
        }
        .notif-action-btn:hover {
          background: var(--bg-hover);
          color: var(--text-primary);
        }
        /* danger variant — delete button */
        .notif-action-btn--danger:hover {
          background: var(--danger-bg, #fee2e2);
          color: var(--danger, #dc2626);
        }
        /* always visible on mobile — no hover state */
        @media (max-width: 768px) {
          .notif-action-btn {
            opacity: 1;
          }
        }
      `}</style>
    </div>
  )
}
