import { NavLink } from 'react-router-dom'
import { ClipboardCheck, LayoutDashboard, ShoppingCart, Users, Menu } from 'lucide-react'
import { useUiStore } from '@/stores/ui-store'
import { useAuthStore } from '@/stores/auth-store'
import { getVisibleMobilePrimaryDestinations } from '@/navigation/mobile'

const iconByDestinationId = {
  dashboard: LayoutDashboard,
  work: ClipboardCheck,
  'sales-orders': ShoppingCart,
  customers: Users,
} as const

export default function BottomNav() {
  const { setSidebarOpen } = useUiStore()
  const can = useAuthStore(s => s.can)
  const canAny = useAuthStore(s => s.canAny)

  const visibleTabs = getVisibleMobilePrimaryDestinations({ can, canAny })

  return (
    <nav className="bottom-nav" aria-label="التنقل الرئيسي">
      {visibleTabs.map(tab => {
        const Icon = iconByDestinationId[tab.id as keyof typeof iconByDestinationId]
        if (!Icon) return null

        return (
          <NavLink
            key={tab.id}
            to={tab.path}
            end={tab.exact}
            className={({ isActive }) =>
              `bottom-nav-tab ${isActive ? 'bottom-nav-tab--active' : ''}`
            }
            aria-label={tab.mobileLabel}
          >
            <span className="bottom-nav-icon"><Icon size={22} /></span>
            <span className="bottom-nav-label">{tab.mobileLabel}</span>
          </NavLink>
        )
      })}

      <button
        className="bottom-nav-tab"
        onClick={() => setSidebarOpen(true)}
        aria-label="فتح القائمة الجانبية"
        type="button"
      >
        <span className="bottom-nav-icon"><Menu size={22} /></span>
        <span className="bottom-nav-label">القائمة</span>
      </button>

      <style>{`
        .bottom-nav {
          display: none;
        }

        @media (max-width: 768px) {
          .bottom-nav {
            display: flex;
            position: fixed;
            bottom: 0;
            left: 0;
            right: 0;
            height: var(--bottom-nav-height);
            background: var(--bottom-nav-bg);
            backdrop-filter: var(--bottom-nav-blur);
            -webkit-backdrop-filter: var(--bottom-nav-blur);
            border-top: 1px solid var(--border-primary);
            z-index: var(--z-bottom-nav);
            align-items: stretch;
            padding-bottom: env(safe-area-inset-bottom, 0px);
          }

          .bottom-nav-tab {
            flex: 1;
            min-width: 0;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 3px;
            padding: 0.25rem 0.2rem;
            min-height: var(--touch-target);
            color: var(--text-muted);
            text-decoration: none;
            background: none;
            border: none;
            cursor: pointer;
            font-family: var(--font-sans);
            border-top: 2px solid transparent;
            transition: color var(--transition-fast), border-color var(--transition-fast);
            -webkit-tap-highlight-color: transparent;
            position: relative;
          }

          .bottom-nav-tab:active {
            background: var(--bg-hover);
          }

          .bottom-nav-tab:focus-visible {
            outline: 2px solid var(--color-primary);
            outline-offset: -3px;
          }

          .bottom-nav-tab--active {
            color: var(--color-primary);
            border-top-color: var(--color-primary);
          }

          .bottom-nav-icon {
            display: flex;
            align-items: center;
            justify-content: center;
            width: 24px;
            height: 24px;
            transition: transform var(--transition-fast);
          }

          .bottom-nav-tab--active .bottom-nav-icon {
            transform: translateY(-1px);
          }

          .bottom-nav-label {
            max-width: 100%;
            overflow: hidden;
            text-overflow: ellipsis;
            font-size: 0.6875rem;
            font-weight: 600;
            line-height: 1;
            white-space: nowrap;
          }

          @media (prefers-reduced-motion: reduce) {
            .bottom-nav-icon { transition: none; }
            .bottom-nav-tab--active .bottom-nav-icon { transform: none; }
          }
        }
      `}</style>
    </nav>
  )
}
