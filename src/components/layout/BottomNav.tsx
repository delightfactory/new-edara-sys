import { NavLink, useNavigate } from 'react-router-dom'
import { LayoutDashboard, ShoppingCart, Users, Menu } from 'lucide-react'
import { useUiStore } from '@/stores/ui-store'
import { useAuthStore } from '@/stores/auth-store'

interface Tab {
  id: string
  label: string
  icon: React.ElementType
  path?: string
  permission?: string | string[]
  action?: 'openMenu'
}

const tabs: Tab[] = [
  { id: 'home',      label: 'الرئيسية', icon: LayoutDashboard, path: '/' },
  { id: 'sales',     label: 'المبيعات', icon: ShoppingCart,    path: '/sales/orders',  permission: 'sales.orders.read' },
  { id: 'customers', label: 'العملاء',  icon: Users,           path: '/customers',     permission: 'customers.read' },
  { id: 'menu',      label: 'القائمة',  icon: Menu,            action: 'openMenu' },
]

export default function BottomNav() {
  const { setSidebarOpen } = useUiStore()
  const can = useAuthStore(s => s.can)
  const canAny = useAuthStore(s => s.canAny)

  const canAccess = (perm?: string | string[]) => {
    if (!perm) return true
    return Array.isArray(perm) ? canAny(perm) : can(perm)
  }

  const visibleTabs = tabs.filter(t => canAccess(t.permission))

  return (
    <nav className="bottom-nav" aria-label="التنقل الرئيسي">
      {visibleTabs.map(tab => {
        const Icon = tab.icon

        if (tab.action === 'openMenu') {
          return (
            <button
              key={tab.id}
              className="bottom-nav-tab"
              onClick={() => setSidebarOpen(true)}
              aria-label="فتح القائمة الجانبية"
              type="button"
            >
              <span className="bottom-nav-icon"><Icon size={22} /></span>
              <span className="bottom-nav-label">{tab.label}</span>
            </button>
          )
        }

        return (
          <NavLink
            key={tab.id}
            to={tab.path!}
            end={tab.path === '/'}
            className={({ isActive }) =>
              `bottom-nav-tab ${isActive ? 'bottom-nav-tab--active' : ''}`
            }
            aria-label={tab.label}
          >
            <span className="bottom-nav-icon"><Icon size={22} /></span>
            <span className="bottom-nav-label">{tab.label}</span>
          </NavLink>
        )
      })}

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
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 3px;
            padding: 0.25rem 0.5rem;
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
            font-size: 0.65rem;
            font-weight: 600;
            line-height: 1;
            white-space: nowrap;
          }
        }
      `}</style>
    </nav>
  )
}
