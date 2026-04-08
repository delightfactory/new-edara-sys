// src/pages/notifications/NotificationsPage.tsx
// ─────────────────────────────────────────────────────────────
// Premium notifications page wrapper with visual tab bar:
//   • الإشعارات  → NotificationCenter (active)
//   • المؤرشف    → NotificationCenter (archived)
//   • الإعدادات  → NotificationPreferences
//
// URL: /notifications?tab=notifications|archived|settings
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

  const rawTab = params.get('tab') as PageTab | null
  const activeTab: PageTab =
    rawTab === 'archived' || rawTab === 'settings' ? rawTab : 'notifications'

  const switchTab = (tab: PageTab) => {
    if (tab === 'notifications') {
      setParams({})
    } else if (tab === 'archived') {
      setParams({ tab: 'archived', archived: 'true' })
    } else {
      setParams({ tab })
    }
  }

  return (
    <div className="npage">

      {/* Tab bar */}
      <div className="npage-tabs" role="tablist" aria-label="تبويبات الإشعارات">
        {TABS.map(t => {
          const isActive = activeTab === t.id
          return (
            <button
              key={t.id}
              role="tab"
              type="button"
              aria-selected={isActive}
              className={`npage-tab${isActive ? ' npage-tab--active' : ''}`}
              onClick={() => switchTab(t.id)}
            >
              <span className="npage-tab-icon">{t.icon}</span>
              <span>{t.label}</span>
              {isActive && <span className="npage-tab-indicator" />}
            </button>
          )
        })}
      </div>

      {/* Tab content */}
      <div className="npage-body">
        {activeTab === 'notifications' && <NotificationCenter />}
        {activeTab === 'archived'      && <NotificationCenter />}
        {activeTab === 'settings'      && (
          <div className="npage-settings">
            <NotificationPreferences />
          </div>
        )}
      </div>

      <style>{`
        .npage {
          display: flex;
          flex-direction: column;
          min-height: 100%;
          width: 100%;
          overflow-x: hidden;
        }

        .npage-tabs {
          display: flex;
          gap: 0;
          background: var(--bg-surface);
          border-bottom: 1px solid var(--border-primary);
          padding: 0 var(--space-6);
          position: sticky;
          top: 0;
          z-index: var(--z-sticky, 10);
          width: 100%;
          max-width: 100%;
        }

        .npage-tab {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          padding: var(--space-3) var(--space-5);
          border: none;
          background: none;
          font-family: var(--font-sans);
          font-size: var(--text-sm, 14px);
          font-weight: 500;
          color: var(--text-muted);
          cursor: pointer;
          position: relative;
          transition: color 0.2s, background 0.2s;
          white-space: nowrap;
        }

        .npage-tab:hover:not(.npage-tab--active) {
          color: var(--text-secondary);
          background: var(--bg-hover, rgba(0,0,0,0.03));
        }

        .npage-tab--active {
          color: var(--primary, #2563eb);
          font-weight: 600;
        }

        .npage-tab-icon {
          display: flex;
          align-items: center;
          transition: transform 0.2s;
        }
        .npage-tab--active .npage-tab-icon {
          transform: scale(1.1);
        }

        /* Animated indicator — RTL-safe */
        .npage-tab-indicator {
          position: absolute;
          bottom: -1px;
          inset-inline-start: var(--space-3);
          inset-inline-end: var(--space-3);
          height: 2.5px;
          background: var(--color-primary, #2563eb);
          border-radius: 2px 2px 0 0;
          animation: npage-indicator-slide 0.25s ease;
        }

        @keyframes npage-indicator-slide {
          from { transform: scaleX(0); }
          to   { transform: scaleX(1); }
        }

        /* ── Body ── */
        .npage-body {
          flex: 1;
        }

        /* ── Settings wrapper ── */
        .npage-settings {
          max-width: 640px;
          margin: var(--space-6) auto;
          padding: 0 var(--space-4);
        }

        /* ── Mobile ── */
        @media (max-width: 768px) {
          .npage-tabs {
            padding: 0;
            overflow-x: auto;
            -webkit-overflow-scrolling: touch;
            scrollbar-width: none;
            top: var(--app-bar-height, 0);
          }
          .npage-tabs::-webkit-scrollbar { display: none; }

          .npage-tab {
            flex: 1;
            justify-content: center;
            padding: var(--space-3) var(--space-2);
            font-size: var(--text-xs, 12px);
            gap: var(--space-1);
          }

          .npage-tab-indicator {
            inset-inline-start: var(--space-1);
            inset-inline-end: var(--space-1);
          }

          .npage-settings {
            margin: var(--space-4) auto;
            padding: 0 var(--space-3);
          }
        }
      `}</style>
    </div>
  )
}

