// src/components/notifications/NotificationItem.tsx
// ─────────────────────────────────────────────────────────────
// Premium single notification row with:
//  • Category icon with colored background
//  • Priority stripe (4px, left/RTL-aware)
//  • Unread dot with glow
//  • Relative time in Arabic
//  • Archive/Delete action buttons (hover + always visible on mobile)
//  • Click navigates to action URL (with fallback)
//  • Smooth enter animation
// ─────────────────────────────────────────────────────────────

import { useNavigate } from 'react-router-dom'
import {
  Clock, Users, Calendar, Banknote, Receipt, CheckCircle,
  Package, ShoppingCart, Settings, Shield, AlertTriangle,
  Archive, Bell, Trash2, ExternalLink,
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

const PRIORITY_CONFIG: Record<NotificationPriority, { color: string; glow: string }> = {
  critical: { color: '#dc2626', glow: '0 0 8px rgba(220,38,38,0.3)' },
  high:     { color: '#f59e0b', glow: '0 0 8px rgba(245,158,11,0.3)' },
  medium:   { color: '#3b82f6', glow: 'none' },
  low:      { color: 'transparent', glow: 'none' },
}

const CATEGORY_CONFIG: Record<string, { icon: React.ReactNode; color: string; bg: string }> = {
  hr_attendance:     { icon: <Clock size={18} />,          color: '#6366f1', bg: 'rgba(99,102,241,0.1)' },
  hr_leaves:         { icon: <Calendar size={18} />,       color: '#8b5cf6', bg: 'rgba(139,92,246,0.1)' },
  hr_payroll:        { icon: <Banknote size={18} />,       color: '#10b981', bg: 'rgba(16,185,129,0.1)' },
  finance_expenses:  { icon: <Receipt size={18} />,        color: '#f59e0b', bg: 'rgba(245,158,11,0.1)' },
  finance_approvals: { icon: <CheckCircle size={18} />,    color: '#3b82f6', bg: 'rgba(59,130,246,0.1)' },
  inventory:         { icon: <Package size={18} />,        color: '#06b6d4', bg: 'rgba(6,182,212,0.1)' },
  sales:             { icon: <ShoppingCart size={18} />,    color: '#ec4899', bg: 'rgba(236,72,153,0.1)' },
  system:            { icon: <Settings size={18} />,       color: '#6b7280', bg: 'rgba(107,114,128,0.1)' },
  alerts:            { icon: <AlertTriangle size={18} />,  color: '#ef4444', bg: 'rgba(239,68,68,0.1)' },
  procurement:       { icon: <Package size={18} />,        color: '#0891b2', bg: 'rgba(8,145,178,0.1)' },
  tasks:             { icon: <CheckCircle size={18} />,    color: '#059669', bg: 'rgba(5,150,105,0.1)' },
}

const DEFAULT_CATEGORY = { icon: <Bell size={18} />, color: '#6b7280', bg: 'rgba(107,114,128,0.1)' }

// ── Props ─────────────────────────────────────────────────────

interface NotificationItemProps {
  notification: Notification
  onRead?:    (id: string) => void
  onArchive?: (id: string) => void
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
    if (notification.actionUrl) {
      navigate(notification.actionUrl)
    }
  }

  const handleArchive = (e: React.MouseEvent) => {
    e.stopPropagation()
    onArchive?.(notification.id)
  }

  const handleDelete = (e: React.MouseEvent) => {
    e.stopPropagation()
    onDelete?.(notification.id)
  }

  const priority = PRIORITY_CONFIG[notification.priority] ?? PRIORITY_CONFIG.low
  const cat = CATEGORY_CONFIG[notification.category] ?? DEFAULT_CATEGORY
  const hasLink = !!notification.actionUrl

  return (
    <div
      className={[
        'ni-item',
        notification.isRead ? 'ni-item--read' : '',
        compact ? 'ni-item--compact' : '',
      ].filter(Boolean).join(' ')}
      onClick={handleClick}
      role="listitem"
      tabIndex={0}
      onKeyDown={e => e.key === 'Enter' && handleClick()}
      aria-label={`إشعار: ${notification.title}`}
      style={{ cursor: hasLink ? 'pointer' : 'default' }}
    >
      {/* Priority stripe */}
      <div className="ni-stripe" style={{ background: priority.color }} />

      {/* Category icon */}
      <div
        className="ni-icon"
        style={{ color: cat.color, background: cat.bg }}
      >
        {cat.icon}
      </div>

      {/* Content */}
      <div className="ni-content">
        <div className="ni-title-row">
          {!notification.isRead && (
            <span
              className="ni-dot"
              style={{ boxShadow: priority.glow }}
              aria-hidden="true"
            />
          )}
          <span className="ni-title">{notification.title}</span>
          {hasLink && <ExternalLink size={12} className="ni-link-icon" />}
        </div>
        <p className="ni-body">{notification.body}</p>
        <div className="ni-meta">
          <span className="ni-time">{relativeTime(notification.createdAt)}</span>
          {notification.priority === 'critical' && (
            <span className="ni-priority-tag ni-priority-tag--critical">حرج</span>
          )}
          {notification.priority === 'high' && (
            <span className="ni-priority-tag ni-priority-tag--high">عالي</span>
          )}
        </div>
      </div>

      {/* Action buttons — hover reveal on desktop, always visible on mobile */}
      <div className="ni-actions">
        {onArchive && (
          <button
            className="ni-action-btn"
            onClick={handleArchive}
            aria-label="أرشفة الإشعار"
            type="button"
            title="أرشفة"
          >
            <Archive size={14} />
          </button>
        )}
        {onDelete && (
          <button
            className="ni-action-btn ni-action-btn--danger"
            onClick={handleDelete}
            aria-label="حذف نهائي"
            type="button"
            title="حذف نهائي"
          >
            <Trash2 size={14} />
          </button>
        )}
      </div>

      <style>{`
        .ni-item {
          display: flex;
          align-items: flex-start;
          gap: var(--space-3);
          padding: var(--space-3) var(--space-4);
          position: relative;
          border-bottom: 1px solid var(--border-primary);
          transition: background 0.2s, transform 0.15s;
          background: var(--bg-surface);
          animation: ni-slide-in 0.3s ease-out both;
        }
        .ni-item:hover {
          background: var(--bg-hover, rgba(0,0,0,0.03));
        }
        .ni-item:hover .ni-actions {
          opacity: 1;
          transform: translateX(0);
        }
        .ni-item:active {
          transform: scale(0.995);
        }
        .ni-item--compact {
          padding: var(--space-2) var(--space-3);
        }
        .ni-item--read {
          opacity: 0.65;
        }
        .ni-item--read:hover {
          opacity: 0.85;
        }
        .ni-item--read .ni-title {
          font-weight: 500;
        }

        @keyframes ni-slide-in {
          from { opacity: 0; transform: translateY(4px); }
          to   { opacity: 1; transform: translateY(0); }
        }

        /* Priority stripe */
        .ni-stripe {
          position: absolute;
          inset-inline-end: 0;
          top: 0;
          bottom: 0;
          width: 4px;
          border-radius: 0 var(--radius-sm, 4px) var(--radius-sm, 4px) 0;
          flex-shrink: 0;
        }

        /* Category icon */
        .ni-icon {
          width: 40px;
          height: 40px;
          border-radius: 12px;
          display: flex;
          align-items: center;
          justify-content: center;
          flex-shrink: 0;
          margin-top: 2px;
          transition: transform 0.2s;
        }
        .ni-item:hover .ni-icon {
          transform: scale(1.05);
        }

        /* Content */
        .ni-content {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 4px;
        }

        .ni-title-row {
          display: flex;
          align-items: center;
          gap: var(--space-2);
        }

        .ni-dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          background: var(--primary, #2563eb);
          flex-shrink: 0;
          animation: ni-dot-pulse 2s ease-in-out infinite;
        }

        @keyframes ni-dot-pulse {
          0%, 100% { opacity: 1; }
          50%      { opacity: 0.5; }
        }

        .ni-title {
          font-size: var(--text-sm, 14px);
          font-weight: 600;
          color: var(--text-primary);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
          flex: 1;
          line-height: 1.4;
        }

        .ni-link-icon {
          color: var(--text-muted);
          flex-shrink: 0;
          opacity: 0;
          transition: opacity 0.2s;
        }
        .ni-item:hover .ni-link-icon {
          opacity: 0.6;
        }

        .ni-body {
          font-size: var(--text-xs, 12px);
          color: var(--text-secondary);
          line-height: 1.5;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
          margin: 0;
        }

        .ni-meta {
          display: flex;
          align-items: center;
          gap: var(--space-2);
        }

        .ni-time {
          font-size: 11px;
          color: var(--text-muted);
        }

        .ni-priority-tag {
          font-size: 10px;
          font-weight: 600;
          padding: 1px 6px;
          border-radius: 4px;
          line-height: 1.4;
        }
        .ni-priority-tag--critical {
          background: rgba(220,38,38,0.1);
          color: #dc2626;
        }
        .ni-priority-tag--high {
          background: rgba(245,158,11,0.1);
          color: #d97706;
        }

        /* Action buttons */
        .ni-actions {
          display: flex;
          flex-direction: column;
          gap: 4px;
          align-self: center;
          opacity: 0;
          transform: translateX(4px);
          transition: opacity 0.2s, transform 0.2s;
        }

        .ni-action-btn {
          width: 30px;
          height: 30px;
          border-radius: var(--radius-md, 8px);
          border: none;
          background: var(--bg-app, #f8fafc);
          color: var(--text-muted);
          display: flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
          transition: background 0.15s, color 0.15s, transform 0.15s;
        }
        .ni-action-btn:hover {
          background: var(--bg-hover);
          color: var(--text-primary);
          transform: scale(1.1);
        }
        .ni-action-btn:active {
          transform: scale(0.95);
        }
        .ni-action-btn--danger:hover {
          background: rgba(220,38,38,0.08);
          color: var(--danger, #dc2626);
        }

        /* Mobile: always show actions + compact layout */
        @media (max-width: 768px) {
          .ni-item {
            padding: var(--space-2) var(--space-3);
            gap: var(--space-2);
          }
          .ni-icon {
            width: 32px;
            height: 32px;
            border-radius: 10px;
          }
          .ni-icon svg {
            width: 14px;
            height: 14px;
          }
          .ni-title {
            font-size: 13px;
          }
          .ni-body {
            font-size: 11px;
            -webkit-line-clamp: 1;
          }
          .ni-time {
            font-size: 10px;
          }
          .ni-actions {
            opacity: 1;
            transform: translateX(0);
            flex-direction: row;
          }
          .ni-action-btn {
            width: 26px;
            height: 26px;
          }
          .ni-action-btn svg {
            width: 12px;
            height: 12px;
          }
          .ni-link-icon { opacity: 0.4; }
        }
      `}</style>
    </div>
  )
}
