import { Outlet } from 'react-router-dom'
import { Menu } from 'lucide-react'
import Sidebar from './Sidebar'
import BottomNav from './BottomNav'
import FAB from './FAB'
import PageTitleContext, { PageTitleProvider } from './PageTitleContext'
import OfflineDetector from '@/components/pwa/OfflineDetector'
import InstallBanner from '@/components/pwa/InstallBanner'
import { NotificationBell, NotificationPanel } from '@/components/notifications'
import GeoPermissionDialog from '@/components/shared/GeoPermissionDialog'
import { useGeoOnboarding } from '@/hooks/useGeoOnboarding'
import { useUiStore } from '@/stores/ui-store'
import { useContext } from 'react'

function AppBarTitle() {
  const { title } = useContext(PageTitleContext)
  return <span className="app-bar-title">{title}</span>
}

/**
 * AppLayout — Device-aware application shell.
 *
 * DESKTOP (>1024px): persistent right sidebar + dense content surface.
 * TABLET (769–1024px): top app bar + menu button + sidebar drawer.
 * MOBILE (≤768px): top app bar + BottomNav + context-aware FAB; full menu opens
 * from the existing BottomNav "القائمة" shortcut.
 */
export default function AppLayout() {
  const geoOnboarding = useGeoOnboarding()
  const setSidebarOpen = useUiStore(s => s.setSidebarOpen)

  return (
    <PageTitleProvider>
      <div className="app-layout">
        <Sidebar />

        <header className="app-bar" aria-label="شريط التطبيق">
          <div className="app-bar-start">
            <button
              type="button"
              className="app-bar-menu"
              onClick={() => setSidebarOpen(true)}
              aria-label="فتح القائمة الرئيسية"
            >
              <Menu size={20} />
            </button>
            <AppBarTitle />
          </div>
          <NotificationBell className="app-bar-bell" />
        </header>

        <main className="app-main">
          <Outlet />
        </main>

        <FAB />
        <BottomNav />

        <OfflineDetector />
        <InstallBanner />

        <NotificationPanel />

        <GeoPermissionDialog
          open={geoOnboarding.showDialog}
          context="app_onboarding"
          onAllow={geoOnboarding.handleAllow}
          onDismiss={geoOnboarding.handleDismiss}
        />

        <style>{`
          .app-layout {
            display: flex;
            min-height: 100vh;
          }

          .app-main {
            flex: 1;
            margin-inline-start: var(--sidebar-width);
            background: var(--bg-app);
            min-height: 100vh;
            min-width: 0;
            max-width: calc(100vw - var(--sidebar-width));
            overflow-x: hidden;
            transition: margin-inline-start 0.3s cubic-bezier(0.4, 0, 0.2, 1);
          }

          .app-bar {
            display: none;
          }

          .app-bar-start {
            display: flex;
            align-items: center;
            gap: var(--space-2);
            min-width: 0;
          }

          .app-bar-menu {
            display: none;
            align-items: center;
            justify-content: center;
            width: var(--touch-target);
            height: var(--touch-target);
            flex: 0 0 var(--touch-target);
            border: none;
            border-radius: var(--radius-full);
            background: transparent;
            color: var(--text-secondary);
            cursor: pointer;
          }

          @media (max-width: 1024px) {
            .app-main {
              margin-inline-start: 0;
              padding-top: var(--app-bar-height);
              min-width: 0;
              overflow-x: hidden;
              max-width: 100vw;
            }

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
              min-width: 0;
              overflow: hidden;
              text-overflow: ellipsis;
              white-space: nowrap;
              font-size: var(--text-base);
              font-weight: 700;
              color: var(--text-primary);
              letter-spacing: 0.01em;
            }

            .app-bar-bell,
            .app-bar-menu {
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
            .app-bar-bell:active,
            .app-bar-menu:hover,
            .app-bar-menu:active {
              background: var(--bg-hover);
              color: var(--text-primary);
            }
          }

          /* Tablet: compact shell. Sidebar becomes an on-demand drawer. */
          @media (min-width: 769px) and (max-width: 1024px) {
            .app-bar-menu {
              display: flex;
            }

            .sb-ov {
              display: block;
              position: fixed;
              inset: 0;
              z-index: calc(var(--z-sidebar, 200) - 1);
              background: rgba(0, 0, 0, 0.4);
              backdrop-filter: blur(3px);
              -webkit-backdrop-filter: blur(3px);
            }

            .sb {
              transform: translateX(110%);
              width: min(320px, 82vw);
              box-shadow: -12px 0 48px rgba(0, 0, 0, 0.24);
            }

            .sb--open {
              transform: translateX(0);
            }

            .sb-close {
              display: flex;
            }
          }

          /* Mobile keeps BottomNav as the primary global navigation surface. */
          @media (max-width: 768px) {
            .app-main {
              padding-bottom: var(--bottom-nav-height);
            }

            .app-bar-menu {
              display: none;
            }
          }
        `}</style>
      </div>
    </PageTitleProvider>
  )
}
