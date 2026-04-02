// src/components/notifications/NotificationBell.tsx
// ─────────────────────────────────────────────────────────────
// App-bar bell icon with unread count badge.
// Reads count from Zustand store (kept live by GlobalRealtimeManager).
// ─────────────────────────────────────────────────────────────

import { Bell } from 'lucide-react'
import { cn } from '@/lib/utils/helpers'
import { useNotificationStore } from '@/stores/notification-store'
import { useUnreadCountQuery } from '@/hooks/useNotificationQueries'

interface NotificationBellProps {
  className?: string
}

export default function NotificationBell({ className }: NotificationBellProps) {
  // Hydrate count from server on mount; kept live by Realtime + store
  useUnreadCountQuery()

  const { unreadCount, togglePanel } = useNotificationStore(s => ({
    unreadCount: s.unreadCount,
    togglePanel: s.togglePanel,
  }))

  const displayCount = unreadCount > 99 ? '+99' : unreadCount
  const ariaLabel = unreadCount > 0
    ? `الإشعارات (${unreadCount} غير مقروء)`
    : 'الإشعارات'

  return (
    <button
      className={cn('app-bar-bell notif-bell-btn', className)}
      aria-label={ariaLabel}
      type="button"
      onClick={togglePanel}
    >
      <Bell size={20} />

      {unreadCount > 0 && (
        <span className="notif-badge" aria-hidden="true">
          {displayCount}
        </span>
      )}

      <style>{`
        .notif-bell-btn {
          position: relative;
        }

        .notif-badge {
          position: absolute;
          top: 3px;
          inset-inline-start: 3px;
          min-width: 18px;
          height: 18px;
          padding: 0 4px;
          border-radius: 9px;
          background: var(--danger, #dc2626);
          color: #fff;
          font-size: 10px;
          font-weight: 700;
          line-height: 18px;
          text-align: center;
          pointer-events: none;
          animation: notif-badge-pop 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
        }

        @keyframes notif-badge-pop {
          0%   { transform: scale(0); opacity: 0; }
          100% { transform: scale(1); opacity: 1; }
        }
      `}</style>
    </button>
  )
}
