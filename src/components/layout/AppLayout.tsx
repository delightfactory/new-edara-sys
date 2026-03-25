import { Outlet } from 'react-router-dom'
import { Menu } from 'lucide-react'
import { useUiStore } from '@/stores/ui-store'
import Sidebar from './Sidebar'

export default function AppLayout() {
  const { setSidebarOpen } = useUiStore()

  return (
    <div className="app-layout">
      <Sidebar />

      <main className="app-main">
        {/* Mobile top bar with hamburger */}
        <div className="mobile-topbar">
          <button
            className="mobile-menu-btn"
            onClick={() => setSidebarOpen(true)}
            aria-label="فتح القائمة"
          >
            <Menu size={22} />
          </button>
          <span className="mobile-topbar-title">EDARA</span>
        </div>

        <Outlet />
      </main>

      <style>{`
        .app-layout {
          display: flex; min-height: 100vh;
        }
        .app-main {
          flex: 1;
          margin-right: var(--sidebar-width);
          background: var(--bg-app);
          min-height: 100vh;
          transition: margin-right 0.3s cubic-bezier(0.4, 0, 0.2, 1);
        }

        .mobile-topbar {
          display: none;
        }

        @media (max-width: 768px) {
          .app-main { margin-right: 0; }

          .mobile-topbar {
            display: flex;
            align-items: center;
            gap: var(--space-3);
            padding: var(--space-3) var(--space-4);
            background: var(--bg-surface);
            color: var(--text-primary);
            position: sticky;
            top: 0;
            z-index: 40;
            border-bottom: 1px solid var(--border-primary);
            box-shadow: var(--shadow-sm);
          }
          .mobile-menu-btn {
            background: none; border: none;
            color: var(--text-primary); cursor: pointer;
            padding: var(--space-2);
            border-radius: var(--radius-sm);
            display: flex; align-items: center; justify-content: center;
          }
          .mobile-menu-btn:hover { background: var(--bg-hover); }
          .mobile-topbar-title {
            font-weight: 700; letter-spacing: 2px;
            font-size: var(--text-base);
          }
        }
      `}</style>
    </div>
  )
}
