// src/components/notifications/NotificationPanel.tsx
// ─────────────────────────────────────────────────────────────
// Premium Notification Panel — Popover on desktop / Bottom Sheet on mobile.
// Glassmorphism, animated tabs, smooth scroll, rich empty state.
// Rendered via createPortal to escape z-index stacking contexts.
// ─────────────────────────────────────────────────────────────

import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { useNavigate } from 'react-router-dom'
import { X, BellOff, CheckCheck, Settings, Bell } from 'lucide-react'
import { useNotificationStore } from '@/stores/notification-store'
import {
  useRecentNotificationsQuery,
  useMarkAsReadMutation,
  useMarkAllAsReadMutation,
  useArchiveMutation,
} from '@/hooks/useNotificationQueries'
import { Skeleton } from '@/components/ui/Skeleton'
import NotificationItem from './NotificationItem'

// ── Tab type ─────────────────────────────────────────────────
type Tab = 'all' | 'unread'

// ── Detect mobile via JS ────────────────────────────────────
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
        <div className="np-header-start">
          <Bell size={18} className="np-header-icon" />
          <span className="np-title">الإشعارات</span>
          {unreadCount > 0 && (
            <span className="np-title-badge">{unreadCount > 99 ? '+99' : unreadCount}</span>
          )}
        </div>
        <div className="np-header-actions">
          {unreadCount > 0 && (
            <button
              className="np-action-btn"
              onClick={() => markAll.mutate(undefined)}
              title="تحديد الكل كمقروء"
              aria-label="تحديد الكل كمقروء"
              type="button"
            >
              <CheckCheck size={15} />
            </button>
          )}
          <button
            className="np-action-btn"
            onClick={handleSettings}
            aria-label="الإعدادات"
            title="الإعدادات"
            type="button"
          >
            <Settings size={15} />
          </button>
          <button
            className="np-action-btn np-close-btn"
            onClick={onClose}
            aria-label="إغلاق"
            type="button"
          >
            <X size={16} />
          </button>
        </div>
      </div>

      {/* Tabs — animated indicator */}
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
            <div key={i} className="np-skeleton-item">
              <Skeleton width={40} height={40} className="np-skeleton-icon" />
              <div className="np-skeleton-content">
                <Skeleton width="70%" height={14} />
                <Skeleton width="100%" height={12} />
                <Skeleton width="30%" height={10} />
              </div>
            </div>
          ))
        ) : filtered.length === 0 ? (
          <div className="np-empty">
            <div className="np-empty-icon">
              <BellOff size={32} />
            </div>
            <p className="np-empty-title">
              {tab === 'unread' ? 'لا توجد إشعارات غير مقروءة' : 'لا توجد إشعارات'}
            </p>
            <p className="np-empty-text">ستظهر إشعاراتك الجديدة هنا</p>
          </div>
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
          className="np-footer-btn"
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

  // Close on outside click (desktop only)
  useEffect(() => {
    if (!isPanelOpen || isMobile) return
    const onClick = (e: MouseEvent) => {
      if (panelRef.current && !panelRef.current.contains(e.target as Node)) {
        setPanelOpen(false)
      }
    }
    const id = setTimeout(() => document.addEventListener('mousedown', onClick), 100)
    return () => {
      clearTimeout(id)
      document.removeEventListener('mousedown', onClick)
    }
  }, [isPanelOpen, isMobile, setPanelOpen])

  if (!isPanelOpen) return null

  return createPortal(
    <>
      {/* Mobile overlay */}
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
          background: rgba(0,0,0,0.4);
          backdrop-filter: blur(4px);
          -webkit-backdrop-filter: blur(4px);
          animation: np-fade-in 0.25s ease;
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
          border-radius: 16px;
          box-shadow:
            0 12px 40px rgba(0,0,0,0.12),
            0 4px 12px rgba(0,0,0,0.06),
            0 0 0 1px rgba(0,0,0,0.03);
          display: flex;
          flex-direction: column;
          overflow: hidden;
          animation: np-slide-in 0.3s cubic-bezier(0.16, 1, 0.3, 1);

          top: calc(var(--app-bar-height, 56px) + 8px);
          inset-inline-end: var(--space-4);
          width: 400px;
          max-height: calc(100vh - var(--app-bar-height, 56px) - 24px);
        }

        @keyframes np-slide-in {
          from { opacity: 0; transform: translateY(-10px) scale(0.97); }
          to   { opacity: 1; transform: translateY(0) scale(1); }
        }

        /* ── Panel shell — Mobile bottom sheet ── */
        .np-panel--mobile {
          top: auto;
          bottom: var(--bottom-nav-height, 64px);
          inset-inline-end: 0;
          inset-inline-start: 0;
          width: 100%;
          border-radius: 20px 20px 0 0;
          max-height: 75vh;
          animation: np-slide-up 0.3s cubic-bezier(0.16, 1, 0.3, 1);
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
          padding: var(--space-4);
          border-bottom: 1px solid var(--border-primary);
          flex-shrink: 0;
          background: linear-gradient(180deg, var(--bg-surface) 0%, var(--bg-app, #f8fafc) 100%);
        }
        .np-header-start {
          display: flex;
          align-items: center;
          gap: var(--space-2);
        }
        .np-header-icon {
          color: var(--primary, #2563eb);
        }
        .np-title {
          font-size: var(--text-base, 15px);
          font-weight: 700;
          color: var(--text-primary);
        }
        .np-title-badge {
          font-size: 10px;
          font-weight: 700;
          background: var(--primary, #2563eb);
          color: #fff;
          padding: 1px 6px;
          border-radius: 9px;
          line-height: 1.5;
        }
        .np-header-actions {
          display: flex;
          align-items: center;
          gap: 2px;
        }
        .np-action-btn {
          width: 32px;
          height: 32px;
          border-radius: 8px;
          border: none;
          background: transparent;
          color: var(--text-muted);
          display: flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
          transition: background 0.15s, color 0.15s;
        }
        .np-action-btn:hover {
          background: var(--bg-hover, rgba(0,0,0,0.06));
          color: var(--text-primary);
        }
        .np-close-btn:hover {
          background: rgba(220,38,38,0.08);
          color: var(--danger, #dc2626);
        }

        /* ── Tabs ── */
        .np-tabs {
          display: flex;
          padding: 0 var(--space-4);
          gap: 0;
          border-bottom: 1px solid var(--border-primary);
          flex-shrink: 0;
        }
        .np-tab {
          padding: var(--space-3) var(--space-4);
          border: none;
          background: none;
          font-size: var(--text-sm, 14px);
          font-family: var(--font-sans);
          font-weight: 500;
          color: var(--text-muted);
          cursor: pointer;
          border-bottom: 2px solid transparent;
          margin-bottom: -1px;
          display: flex;
          align-items: center;
          gap: var(--space-1);
          transition: color 0.2s, border-color 0.2s;
        }
        .np-tab:hover { color: var(--text-primary); }
        .np-tab--active {
          color: var(--primary, #2563eb);
          border-bottom-color: var(--primary, #2563eb);
          font-weight: 600;
        }
        .np-tab-badge {
          font-size: 10px;
          font-weight: 700;
          background: var(--primary, #2563eb);
          color: #fff;
          padding: 1px 6px;
          border-radius: 9px;
          line-height: 1.4;
        }

        /* ── List (scrollable) ── */
        .np-list {
          flex: 1;
          overflow-y: auto;
          scrollbar-width: thin;
          scrollbar-color: var(--border-primary) transparent;
        }
        .np-list::-webkit-scrollbar { width: 4px; }
        .np-list::-webkit-scrollbar-thumb {
          background: var(--border-primary);
          border-radius: 4px;
        }

        /* ── Skeleton loading ── */
        .np-skeleton-item {
          padding: var(--space-3) var(--space-4);
          display: flex;
          gap: 12px;
          border-bottom: 1px solid var(--border-primary);
        }
        .np-skeleton-icon { border-radius: 12px !important; }
        .np-skeleton-content {
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 6px;
        }

        /* ── Empty state ── */
        .np-empty {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          padding: var(--space-10) var(--space-6);
          text-align: center;
        }
        .np-empty-icon {
          width: 64px;
          height: 64px;
          border-radius: 20px;
          background: var(--bg-hover, rgba(0,0,0,0.04));
          color: var(--text-muted);
          display: flex;
          align-items: center;
          justify-content: center;
          margin-bottom: var(--space-4);
        }
        .np-empty-title {
          font-size: var(--text-sm, 14px);
          font-weight: 600;
          color: var(--text-primary);
          margin-bottom: var(--space-1);
        }
        .np-empty-text {
          font-size: var(--text-xs, 12px);
          color: var(--text-muted);
        }

        /* ── Footer ── */
        .np-footer {
          padding: var(--space-3) var(--space-4);
          border-top: 1px solid var(--border-primary);
          flex-shrink: 0;
        }
        .np-footer-btn {
          width: 100%;
          padding: var(--space-2) 0;
          border: none;
          background: none;
          font-family: var(--font-sans);
          font-size: var(--text-sm, 14px);
          font-weight: 600;
          color: var(--primary, #2563eb);
          cursor: pointer;
          border-radius: 8px;
          transition: background 0.15s;
        }
        .np-footer-btn:hover {
          background: rgba(37,99,235,0.06);
        }
      `}</style>
    </>,
    document.body,
  )
}
