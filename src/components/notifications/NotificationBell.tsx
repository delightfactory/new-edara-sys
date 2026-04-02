// src/components/notifications/NotificationBell.tsx
// ─────────────────────────────────────────────────────────────
// Premium bell icon with animated badge + ring pulse on new notifications.
// ─────────────────────────────────────────────────────────────

import { useEffect, useRef } from 'react'
import { Bell } from 'lucide-react'
import { cn } from '@/lib/utils/helpers'
import { useNotificationStore } from '@/stores/notification-store'
import { useUnreadCountQuery } from '@/hooks/useNotificationQueries'

interface NotificationBellProps {
  className?: string
}

export default function NotificationBell({ className }: NotificationBellProps) {
  useUnreadCountQuery()

  const { unreadCount, togglePanel } = useNotificationStore(s => ({
    unreadCount: s.unreadCount,
    togglePanel: s.togglePanel,
  }))

  // Track previous count to trigger ring animation on increment
  const prevCountRef = useRef(unreadCount)
  const bellRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    if (unreadCount > prevCountRef.current && bellRef.current) {
      bellRef.current.classList.remove('notif-bell--ring')
      // Force reflow to restart animation
      void bellRef.current.offsetWidth
      bellRef.current.classList.add('notif-bell--ring')
    }
    prevCountRef.current = unreadCount
  }, [unreadCount])

  const displayCount = unreadCount > 99 ? '+99' : unreadCount
  const ariaLabel = unreadCount > 0
    ? `الإشعارات (${unreadCount} غير مقروء)`
    : 'الإشعارات'

  return (
    <button
      ref={bellRef}
      className={cn('notif-bell-btn', className)}
      aria-label={ariaLabel}
      type="button"
      onClick={togglePanel}
    >
      <Bell size={20} strokeWidth={1.8} />

      {unreadCount > 0 && (
        <span className="notif-badge" aria-hidden="true">
          {displayCount}
        </span>
      )}

      {/* Pulse ring behind bell when there are unread notifications */}
      {unreadCount > 0 && (
        <span className="notif-bell-pulse" aria-hidden="true" />
      )}

      <style>{`
        .notif-bell-btn {
          position: relative;
          display: flex;
          align-items: center;
          justify-content: center;
          width: 40px;
          height: 40px;
          border-radius: var(--radius-full, 50%);
          border: none;
          background: transparent;
          color: var(--text-secondary);
          cursor: pointer;
          transition: background 0.2s, color 0.2s, transform 0.15s;
        }
        .notif-bell-btn:hover {
          background: var(--bg-hover, rgba(0,0,0,0.06));
          color: var(--text-primary);
        }
        .notif-bell-btn:active {
          transform: scale(0.92);
        }

        /* Badge */
        .notif-badge {
          position: absolute;
          top: 4px;
          inset-inline-start: 4px;
          min-width: 18px;
          height: 18px;
          padding: 0 5px;
          border-radius: 9px;
          background: var(--danger, #dc2626);
          color: #fff;
          font-size: 10px;
          font-weight: 700;
          line-height: 18px;
          text-align: center;
          pointer-events: none;
          box-shadow: 0 0 0 2px var(--bg-surface, #fff);
          animation: notif-badge-pop 0.35s cubic-bezier(0.34, 1.56, 0.64, 1);
        }

        @keyframes notif-badge-pop {
          0%   { transform: scale(0); opacity: 0; }
          60%  { transform: scale(1.2); }
          100% { transform: scale(1); opacity: 1; }
        }

        /* Subtle pulse ring behind the bell */
        .notif-bell-pulse {
          position: absolute;
          inset: 0;
          border-radius: var(--radius-full, 50%);
          border: 2px solid var(--danger, #dc2626);
          opacity: 0;
          pointer-events: none;
          animation: notif-pulse-ring 2.5s ease-out infinite;
        }

        @keyframes notif-pulse-ring {
          0%   { transform: scale(0.85); opacity: 0.5; }
          70%  { transform: scale(1.35); opacity: 0; }
          100% { transform: scale(1.35); opacity: 0; }
        }

        /* Ring shake animation — triggered via JS on count increment */
        .notif-bell--ring {
          animation: notif-ring-shake 0.6s ease-in-out;
        }

        @keyframes notif-ring-shake {
          0%   { transform: rotate(0); }
          15%  { transform: rotate(14deg); }
          30%  { transform: rotate(-12deg); }
          45%  { transform: rotate(10deg); }
          60%  { transform: rotate(-6deg); }
          75%  { transform: rotate(3deg); }
          100% { transform: rotate(0); }
        }
      `}</style>
    </button>
  )
}
