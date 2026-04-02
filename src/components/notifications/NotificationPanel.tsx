// src/components/notifications/NotificationPanel.tsx
// ─────────────────────────────────────────────────────────────
// Notification Panel — Popover on desktop / Bottom Sheet on mobile.
// Rendered via createPortal to escape z-index stacking contexts.
//
// BUG FIX: overlay rendered conditionally in JS (not via CSS display:none)
// because <style> inside createPortal body doesn't scope correctly in all
// browsers — global CSS class manipulation via display:none/block causes
// the overlay to appear on desktop when it shouldn't.
// ─────────────────────────────────────────────────────────────

import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { useNavigate } from 'react-router-dom'
import { X, BellOff, CheckCheck, Settings } from 'lucide-react'
import { useNotificationStore } from '@/stores/notification-store'
import {
  useRecentNotificationsQuery,
  useMarkAsReadMutation,
  useMarkAllAsReadMutation,
  useArchiveMutation,
} from '@/hooks/useNotificationQueries'
import { Skeleton } from '@/components/ui/Skeleton'
import EmptyState from '@/components/shared/EmptyState'
import NotificationItem from './NotificationItem'

// ── Tab type ─────────────────────────────────────────────────
type Tab = 'all' | 'unread'

// ── Detect mobile via JS (avoids CSS media-query scoping issues in portal) ─
function useIsMobile() {
  const [isMobile, setIsMobile] = useState(() => window.innerWidth <= 768)
  useEffect(() => {
    const mq = window.matchMedia('(max-width: 768px)')
    const handler = (e: MediaQueryListEvent) => setIsMobile(e.matches)
    mq.addEventListener('change', handler)
    return () => mq.removeEventListener('change', handler)
  }, [])
  return isMobile
}

// ── Panel inner ───────────────────────────────────────────────
function PanelContent({ onClose }: { onClose: () => void }) {
  const navigate = useNavigate()
  const [tab, setTab] = useState<Tab>('all')

  const unreadCount = useNotificationStore(s => s.unreadCount)
  const { data: notifications, isLoading } = useRecentNotificationsQuery(15)
  const markRead   = useMarkAsReadMutation()
  const markAll    = useMarkAllAsReadMutation()
  const archive    = useArchiveMutation()

  const filtered = tab === 'unread'
    ? (notifications ?? []).filter(n => !n.isRead)
    : (notifications ?? [])

  const handleViewAll = () => {
    navigate('/notifications')
    onClose()
  }

  const handleSettings = () => {
    navigate('/notifications?tab=settings')
    onClose()
  }

  return (
    <>
      {/* Header */}
      <div className="np-header">
        <span className="np-title">الإشعارات</span>
        <div className="np-header-actions">
          {unreadCount > 0 && (
            <button
              className="btn btn-ghost btn-sm"
              onClick={() => markAll.mutate(undefined)}
              title="تحديد الكل كمقروء"
              aria-label="تحديد الكل كمقروء"
              type="button"
            >
              <CheckCheck size={14} />
              <span style={{ marginInlineStart: 4 }}>الكل مقروء</span>
            </button>
          )}
          <button
            className="btn btn-ghost btn-sm btn-icon"
            onClick={handleSettings}
            aria-label="إعدادات الإشعارات"
            title="إعدادات الإشعارات"
            type="button"
          >
            <Settings size={16} />
          </button>
          <button
            className="btn btn-ghost btn-sm btn-icon"
            onClick={onClose}
            aria-label="إغلاق لوحة الإشعارات"
            type="button"
          >
            <X size={16} />
          </button>
        </div>
      </div>

      {/* Tabs */}
      <div className="np-tabs" role="tablist">
        <button
          role="tab"
          aria-selected={tab === 'all'}
          className={`np-tab${tab === 'all' ? ' np-tab--active' : ''}`}
          onClick={() => setTab('all')}
          type="button"
        >
          الكل
        </button>
        <button
          role="tab"
          aria-selected={tab === 'unread'}
          className={`np-tab${tab === 'unread' ? ' np-tab--active' : ''}`}
          onClick={() => setTab('unread')}
          type="button"
        >
          غير مقروء
          {unreadCount > 0 && (
            <span className="np-tab-badge">{unreadCount > 99 ? '+99' : unreadCount}</span>
          )}
        </button>
      </div>

      {/* List */}
      <div className="np-list" role="list">
        {isLoading ? (
          [1, 2, 3].map(i => (
            <div key={i} style={{ padding: 'var(--space-3) var(--space-4)', display: 'flex', gap: 12, borderBottom: '1px solid var(--border-primary)' }}>
              <Skeleton width={32} height={32} className="skeleton-circle" />
              <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 6 }}>
                <Skeleton width="70%" height={14} />
                <Skeleton width="100%" height={12} />
                <Skeleton width="30%" height={10} />
              </div>
            </div>
          ))
        ) : filtered.length === 0 ? (
          <EmptyState
            icon={<BellOff size={36} />}
            title="لا توجد إشعارات"
            text="ستظهر إشعاراتك الجديدة هنا"
          />
        ) : (
          filtered.map(n => (
            <NotificationItem
              key={n.id}
              notification={n}
              compact
              onRead={id => markRead.mutate(id)}
              onArchive={id => archive.mutate(id)}
            />
          ))
        )}
      </div>

      {/* Footer */}
      <div className="np-footer">
        <button
          className="btn btn-ghost btn-sm btn-block"
          onClick={handleViewAll}
          type="button"
        >
          عرض كل الإشعارات
        </button>
      </div>
    </>
  )
}

// ── Main exported component ───────────────────────────────────

export default function NotificationPanel() {
  const { isPanelOpen, setPanelOpen } = useNotificationStore(s => ({
    isPanelOpen: s.isPanelOpen,
    setPanelOpen: s.setPanelOpen,
  }))

  const panelRef = useRef<HTMLDivElement>(null)
  // ✅ FIX: detect mobile in JS — avoids CSS media-query scoping issues
  //    inside createPortal which injects into body, not the style cascade
  const isMobile = useIsMobile()

  // Close on Escape
  useEffect(() => {
    if (!isPanelOpen) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setPanelOpen(false)
    }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [isPanelOpen, setPanelOpen])

  // Close on outside click (desktop only — mobile uses overlay tap)
  useEffect(() => {
    if (!isPanelOpen || isMobile) return
    const onClick = (e: MouseEvent) => {
      if (panelRef.current && !panelRef.current.contains(e.target as Node)) {
        setPanelOpen(false)
      }
    }
    // Delay so the button click that opened it doesn't immediately close it
    const id = setTimeout(() => document.addEventListener('mousedown', onClick), 100)
    return () => {
      clearTimeout(id)
      document.removeEventListener('mousedown', onClick)
    }
  }, [isPanelOpen, isMobile, setPanelOpen])

  if (!isPanelOpen) return null

  return createPortal(
    <>
      {/* ✅ FIX: Overlay rendered conditionally in JS — ONLY on mobile.
          Previously used CSS display:none/block which caused overlay to
          bleed through on desktop due to <style> inside portal body context. */}
      {isMobile && (
        <div
          className="np-overlay"
          onClick={() => setPanelOpen(false)}
          aria-hidden="true"
        />
      )}

      {/* Panel */}
      <div
        ref={panelRef}
        className={`np-panel${isMobile ? ' np-panel--mobile' : ''}`}
        role="dialog"
        aria-modal="true"
        aria-label="لوحة الإشعارات"
      >
        <PanelContent onClose={() => setPanelOpen(false)} />
      </div>

      <style>{`
        /* ── Mobile overlay ── */
        .np-overlay {
          position: fixed;
          inset: 0;
          z-index: var(--z-overlay, 190);
          background: rgba(0,0,0,0.45);
          backdrop-filter: blur(2px);
          -webkit-backdrop-filter: blur(2px);
          animation: np-fade-in 0.2s ease;
        }

        @keyframes np-fade-in {
          from { opacity: 0; }
          to   { opacity: 1; }
        }

        /* ── Panel shell — Desktop popover ── */
        .np-panel {
          position: fixed;
          z-index: var(--z-modal, 200);
          background: var(--bg-surface);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-xl, 16px);
          box-shadow: var(--shadow-lg);
          display: flex;
          flex-direction: column;
          overflow: hidden;
          animation: np-slide-in 0.2s cubic-bezier(0.16, 1, 0.3, 1);

          /* Desktop: popover below the bell (~AppBar) */
          top: calc(var(--app-bar-height, 56px) + 8px);
          inset-inline-end: var(--space-4);
          width: 380px;
          max-height: calc(100vh - var(--app-bar-height, 56px) - 24px);
        }

        @keyframes np-slide-in {
          from { opacity: 0; transform: translateY(-8px) scale(0.97); }
          to   { opacity: 1; transform: translateY(0) scale(1); }
        }

        /* ── Panel shell — Mobile bottom sheet ── */
        .np-panel--mobile {
          top: auto;
          bottom: var(--bottom-nav-height, 64px);
          inset-inline-end: 0;
          inset-inline-start: 0;
          width: 100%;
          border-radius: var(--radius-xl) var(--radius-xl) 0 0;
          max-height: 72vh;
          animation: np-slide-up 0.25s cubic-bezier(0.16, 1, 0.3, 1);
        }

        @keyframes np-slide-up {
          from { transform: translateY(100%); }
          to   { transform: translateY(0); }
        }

        /* ── Header ── */
        .np-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: var(--space-3) var(--space-4);
          border-bottom: 1px solid var(--border-primary);
          flex-shrink: 0;
        }
        .np-title {
          font-size: var(--text-base);
          font-weight: 700;
          color: var(--text-primary);
        }
        .np-header-actions {
          display: flex;
          align-items: center;
          gap: var(--space-1);
        }

        /* ── Tabs ── */
        .np-tabs {
          display: flex;
          padding: var(--space-2) var(--space-4) 0;
          gap: var(--space-1);
          border-bottom: 1px solid var(--border-primary);
          flex-shrink: 0;
        }
        .np-tab {
          padding: var(--space-2) var(--space-3);
          border: none;
          background: none;
          font-size: var(--text-sm);
          font-family: var(--font-sans);
          font-weight: 500;
          color: var(--text-secondary);
          cursor: pointer;
          border-bottom: 2px solid transparent;
          margin-bottom: -1px;
          display: flex;
          align-items: center;
          gap: var(--space-1);
          transition: color var(--transition-fast);
        }
        .np-tab--active {
          color: var(--primary, #2563eb);
          border-bottom-color: var(--primary, #2563eb);
        }
        .np-tab-badge {
          font-size: 10px;
          font-weight: 700;
          background: var(--primary, #2563eb);
          color: #fff;
          padding: 1px 5px;
          border-radius: 9px;
          line-height: 1.4;
        }

        /* ── List (scrollable) ── */
        .np-list {
          flex: 1;
          overflow-y: auto;
          scrollbar-width: thin;
        }

        /* ── Footer ── */
        .np-footer {
          padding: var(--space-3) var(--space-4);
          border-top: 1px solid var(--border-primary);
          flex-shrink: 0;
        }
      `}</style>
    </>,
    document.body,
  )
}
