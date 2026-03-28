import { Outlet } from 'react-router-dom'
import { Bell } from 'lucide-react'
import Sidebar from './Sidebar'
import BottomNav from './BottomNav'
import FAB from './FAB'
import PageTitleContext, { PageTitleProvider } from './PageTitleContext'
import OfflineDetector from '@/components/pwa/OfflineDetector'
import InstallBanner from '@/components/pwa/InstallBanner'
import { useContext } from 'react'

function AppBarTitle() {
  const { title } = useContext(PageTitleContext)
  return <span className="app-bar-title">{title}</span>
}

/**
 * AppLayout — Responsive App Shell
 *
 * DESKTOP (≥769px): Collapsible sidebar (right), content fills rest.
 * MOBILE (≤768px):
 *   - Glassmorphism App Bar at top (page title + bell). No hamburger.
 *   - Content area scrolls beneath App Bar and above BottomNav.
 *   - Bottom Navigation for primary routing (Home / Sales / Customers / Menu).
 *   - Context-aware FAB above Bottom Nav.
 *   - Sidebar remains a drawer opened by BottomNav "القائمة" tab.
 */
export default function AppLayout() {
  return (
    <PageTitleProvider>
      <div className="app-layout">
        <Sidebar />

        {/* ── Mobile App Bar ─────────────────────────────── */}
        <header className="app-bar" aria-label="شريط التطبيق">
          <AppBarTitle />
          <button
            className="app-bar-bell"
            aria-label="الإشعارات"
            type="button"
          >
            <Bell size={20} />
          </button>
        </header>

        {/* ── Main Content ──────────────────────────────── */}
        <main className="app-main">
          <Outlet />
        </main>

        {/* ── Mobile Shell ─────────────────────────────── */}
        <FAB />
        <BottomNav />

        {/* ── PWA Utilities ─────────────────────────────── */}
        <OfflineDetector />
        <InstallBanner />

        <style>{`
          /* ── Layout Shell ──────────────────────────── */
          .app-layout {
            display: flex;
            min-height: 100vh;
          }

          .app-main {
            flex: 1;
            margin-inline-start: var(--sidebar-width);
            background: var(--bg-app);
            min-height: 100vh;
            transition: margin-inline-start 0.3s cubic-bezier(0.4, 0, 0.2, 1);
          }

          /* ── App Bar (Mobile Only) ──────────────────── */
          .app-bar {
            display: none;
          }

          @media (max-width: 768px) {
            /* Reset desktop sidebar margin */
            .app-main {
              margin-inline-start: 0;
              /* Push content below App Bar */
              padding-top: var(--app-bar-height);
              /* Prevent BottomNav from covering content */
              padding-bottom: var(--bottom-nav-height);
            }

            /* Glassmorphism App Bar */
            .app-bar {
              display: flex;
              align-items: center;
              justify-content: space-between;
              padding: 0 var(--space-4);
              height: var(--app-bar-height);
              position: fixed;
              top: 0;
              left: 0;
              right: 0;
              z-index: var(--z-app-bar);
              background: var(--app-bar-bg);
              backdrop-filter: var(--app-bar-blur);
              -webkit-backdrop-filter: var(--app-bar-blur);
              border-bottom: 1px solid var(--border-primary);
              box-shadow: 0 1px 0 var(--divider), var(--shadow-sm);
            }

            .app-bar-title {
              font-size: var(--text-base);
              font-weight: 700;
              color: var(--text-primary);
              letter-spacing: 0.01em;
            }

            .app-bar-bell {
              display: flex;
              align-items: center;
              justify-content: center;
              width: var(--touch-target);
              height: var(--touch-target);
              border-radius: var(--radius-full);
              background: none;
              border: none;
              color: var(--text-secondary);
              cursor: pointer;
              transition: background var(--transition-fast), color var(--transition-fast);
              -webkit-tap-highlight-color: transparent;
            }

            .app-bar-bell:hover,
            .app-bar-bell:active {
              background: var(--bg-hover);
              color: var(--text-primary);
            }
          }
        `}</style>
      </div>
    </PageTitleProvider>
  )
}
