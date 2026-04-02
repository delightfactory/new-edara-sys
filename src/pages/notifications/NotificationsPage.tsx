// src/pages/notifications/NotificationsPage.tsx
// ─────────────────────────────────────────────────────────────
// Notifications page wrapper with top-level tabs:
//   • الإشعارات  → NotificationCenter (active)
//   • المؤرشف    → NotificationCenter (archived)
//   • الإعدادات  → NotificationPreferences
//
// URL: /notifications?tab=notifications|archived|settings
// The ?tab=settings route is used by the panel's ⚙️ button.
// ─────────────────────────────────────────────────────────────

import { useSearchParams } from 'react-router-dom'
import { Bell, Archive, Settings } from 'lucide-react'
import NotificationCenter from '@/components/notifications/NotificationCenter'
import NotificationPreferences from '@/components/notifications/NotificationPreferences'

type PageTab = 'notifications' | 'archived' | 'settings'

const TABS: { id: PageTab; label: string; icon: React.ReactNode }[] = [
  { id: 'notifications', label: 'الإشعارات',  icon: <Bell    size={16} /> },
  { id: 'archived',      label: 'المؤرشف',    icon: <Archive size={16} /> },
  { id: 'settings',      label: 'الإعدادات',  icon: <Settings size={16} /> },
]

export default function NotificationsPage() {
  const [params, setParams] = useSearchParams()

  // Read active tab from URL — default to 'notifications'
  const rawTab = params.get('tab') as PageTab | null
  const activeTab: PageTab =
    rawTab === 'archived' || rawTab === 'settings' ? rawTab : 'notifications'

  const switchTab = (tab: PageTab) => {
    // Clear all filters when switching tabs — fresh start
    if (tab === 'notifications') {
      setParams({})
    } else if (tab === 'archived') {
      setParams({ tab: 'archived', archived: 'true' })
    } else {
      setParams({ tab })
    }
  }

  return (
    <div className="notif-page">

      {/* ── Page-level tab bar ── */}
      <div className="notif-page-tabs" role="tablist" aria-label="تبويبات الإشعارات">
        {TABS.map(t => (
          <button
            key={t.id}
            role="tab"
            type="button"
            aria-selected={activeTab === t.id}
            className={`notif-page-tab${activeTab === t.id ? ' notif-page-tab--active' : ''}`}
            onClick={() => switchTab(t.id)}
          >
            {t.icon}
            <span>{t.label}</span>
          </button>
        ))}
      </div>

      {/* ── Tab content ── */}
      <div className="notif-page-body">
        {activeTab === 'notifications' && <NotificationCenter />}
        {activeTab === 'archived'      && <NotificationCenter />}
        {activeTab === 'settings'      && (
          <div className="notif-settings-wrapper">
            <NotificationPreferences />
          </div>
        )}
      </div>

      <style>{`
        .notif-page {
          display: flex;
          flex-direction: column;
          min-height: 100%;
        }

        /* ── Top tab bar ── */
        .notif-page-tabs {
          display: flex;
          gap: 0;
          background: var(--bg-surface);
          border-bottom: 2px solid var(--border-primary);
          padding: 0 var(--space-6);
          position: sticky;
          top: var(--app-bar-height, 0);
          z-index: var(--z-sticky, 10);
        }

        .notif-page-tab {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          padding: var(--space-3) var(--space-4);
          border: none;
          background: none;
          font-family: var(--font-sans);
          font-size: var(--text-sm);
          font-weight: 500;
          color: var(--text-secondary);
          cursor: pointer;
          border-bottom: 2px solid transparent;
          margin-bottom: -2px;
          transition: color 0.15s, border-color 0.15s;
          white-space: nowrap;
        }

        .notif-page-tab:hover:not(.notif-page-tab--active) {
          color: var(--text-primary);
          background: var(--bg-hover, rgba(0,0,0,0.04));
        }

        .notif-page-tab--active {
          color: var(--primary, #2563eb);
          border-bottom-color: var(--primary, #2563eb);
          font-weight: 600;
        }

        /* ── Body ── */
        .notif-page-body {
          flex: 1;
        }

        /* ── Settings wrapper ── */
        .notif-settings-wrapper {
          max-width: 640px;
          margin: var(--space-6) auto;
          padding: 0 var(--space-4);
        }

        /* ── Mobile adjustments ── */
        @media (max-width: 768px) {
          .notif-page-tabs {
            padding: 0 var(--space-2);
            overflow-x: auto;
            scrollbar-width: none;
          }
          .notif-page-tabs::-webkit-scrollbar { display: none; }

          .notif-settings-wrapper {
            margin: var(--space-4) auto;
            padding: 0 var(--space-3);
          }
        }
      `}</style>
    </div>
  )
}
