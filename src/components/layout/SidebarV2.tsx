import { useEffect, useMemo, useState } from 'react'
import { NavLink, useLocation, useNavigate } from 'react-router-dom'
import {
  BarChart3,
  Bell,
  BoxesIcon,
  Building2,
  ChevronDown,
  ClipboardCheck,
  ClipboardList,
  DollarSign,
  LayoutDashboard,
  LogOut,
  Moon,
  Package,
  Settings,
  ShoppingCart,
  Sun,
  Truck,
  UserCog,
  Users,
  Warehouse,
  X,
} from 'lucide-react'
import { useAuthStore } from '@/stores/auth-store'
import { useNotificationStore } from '@/stores/notification-store'
import { useUiStore } from '@/stores/ui-store'
import { signOut } from '@/lib/services/auth'
import { getVisibleSidebarSections } from '@/navigation/sidebar'
import type { VisibleSidebarGroup, VisibleSidebarLeaf } from '@/navigation/sidebar'
import '@/styles/design-system-v2-sidebar.css'

const iconByEntryId = {
  dashboard: LayoutDashboard,
  notifications: Bell,
  work: ClipboardCheck,
  sales: ShoppingCart,
  purchases: Package,
  customers: Users,
  suppliers: Truck,
  inventory: Warehouse,
  products: BoxesIcon,
  branches: Building2,
  finance: DollarSign,
  activities: ClipboardList,
  reports: BarChart3,
  'hr-self': Users,
  hr: UserCog,
  settings: Settings,
} as const

function pathMatches(pathname: string, path: string, exact?: boolean) {
  if (exact) return pathname === path
  return pathname === path || pathname.startsWith(`${path}/`)
}

export default function SidebarV2() {
  const can = useAuthStore(s => s.can)
  const canAny = useAuthStore(s => s.canAny)
  const profile = useAuthStore(s => s.profile)
  const unreadCount = useNotificationStore(s => s.unreadCount)
  const { theme, toggleTheme, sidebarOpen, setSidebarOpen } = useUiStore()
  const navigate = useNavigate()
  const location = useLocation()
  const [expanded, setExpanded] = useState<string | null>(null)

  const sections = useMemo(
    () => getVisibleSidebarSections({ can, canAny }),
    [can, canAny],
  )

  useEffect(() => {
    for (const section of sections) {
      for (const entry of section.entries) {
        if (entry.kind !== 'group') continue
        if (entry.destinations.some(destination => pathMatches(location.pathname, destination.path, destination.exact))) {
          setExpanded(entry.id)
          return
        }
      }
    }
  }, [location.pathname, sections])

  const closeDrawerAfterNavigation = () => {
    if (typeof window !== 'undefined' && window.innerWidth <= 1024) {
      setSidebarOpen(false)
    }
  }

  const handleSignOut = async () => {
    await signOut()
    navigate('/login', { replace: true })
  }

  const renderLeaf = (entry: VisibleSidebarLeaf) => {
    const Icon = iconByEntryId[entry.id as keyof typeof iconByEntryId] ?? LayoutDashboard
    const notification = entry.id === 'notifications'

    return (
      <div key={entry.id} className="dsv2-sidebar__entry">
        <NavLink
          to={entry.destination.path}
          end={entry.destination.exact}
          className={({ isActive }) =>
            `dsv2-sidebar__link${isActive ? ' dsv2-sidebar__link--active' : ''}`
          }
          onClick={closeDrawerAfterNavigation}
        >
          <span className="dsv2-sidebar__entry-icon" aria-hidden="true">
            <Icon size={17} />
          </span>
          <span className="dsv2-sidebar__entry-label">{entry.destination.label}</span>
          {notification && unreadCount > 0 && (
            <span className="dsv2-sidebar__unread" aria-label={`${unreadCount} إشعار غير مقروء`}>
              {unreadCount > 99 ? '+99' : unreadCount}
            </span>
          )}
        </NavLink>
      </div>
    )
  }

  const renderGroup = (entry: VisibleSidebarGroup) => {
    const Icon = iconByEntryId[entry.id as keyof typeof iconByEntryId] ?? LayoutDashboard
    const isExpanded = expanded === entry.id
    const panelId = `dsv2-sidebar-group-${entry.id}`

    return (
      <div key={entry.id} className="dsv2-sidebar__entry">
        <button
          type="button"
          className="dsv2-sidebar__group-trigger"
          aria-expanded={isExpanded}
          aria-controls={panelId}
          onClick={() => setExpanded(current => current === entry.id ? null : entry.id)}
        >
          <span className="dsv2-sidebar__entry-icon" aria-hidden="true">
            <Icon size={17} />
          </span>
          <span className="dsv2-sidebar__entry-label">{entry.label}</span>
          <ChevronDown size={14} className="dsv2-sidebar__chevron" aria-hidden="true" />
        </button>

        <div
          id={panelId}
          className={`dsv2-sidebar__children${isExpanded ? ' dsv2-sidebar__children--open' : ''}`}
        >
          <div className="dsv2-sidebar__children-inner">
            {entry.destinations.map(destination => (
              <NavLink
                key={destination.id}
                to={destination.path}
                end={destination.exact}
                className={({ isActive }) =>
                  `dsv2-sidebar__child-link${isActive ? ' dsv2-sidebar__child-link--active' : ''}`
                }
                onClick={closeDrawerAfterNavigation}
              >
                {destination.label}
              </NavLink>
            ))}
          </div>
        </div>
      </div>
    )
  }

  const initials = profile?.full_name?.charAt(0)?.toUpperCase() ?? '؟'
  const roleName = profile?.roles?.[0]?.name_ar ?? ''

  return (
    <>
      {sidebarOpen && (
        <button
          type="button"
          className="dsv2-sidebar-overlay"
          onClick={() => setSidebarOpen(false)}
          aria-label="إغلاق القائمة"
        />
      )}

      <aside
        className={`dsv2-sidebar${sidebarOpen ? ' dsv2-sidebar--open' : ''}`}
        aria-label="القائمة الرئيسية"
      >
        <header className="dsv2-sidebar__header">
          <div className="dsv2-sidebar__brand">
            <div className="dsv2-sidebar__logo" aria-label="DE">DE</div>
            <div className="dsv2-sidebar__brand-copy">
              <div className="dsv2-sidebar__brand-name">EDARA</div>
              <div className="dsv2-sidebar__brand-subtitle">نظام الإدارة</div>
            </div>
          </div>
          <button
            type="button"
            className="dsv2-sidebar__close"
            onClick={() => setSidebarOpen(false)}
            aria-label="إغلاق القائمة"
          >
            <X size={18} />
          </button>
        </header>

        <nav className="dsv2-sidebar__nav" aria-label="أقسام النظام">
          {sections.map(section => (
            <section key={section.id} className="dsv2-sidebar__section">
              {section.label && (
                <h2 className="dsv2-sidebar__section-label">{section.label}</h2>
              )}
              {section.entries.map(entry =>
                entry.kind === 'leaf' ? renderLeaf(entry) : renderGroup(entry)
              )}
            </section>
          ))}
        </nav>

        <footer className="dsv2-sidebar__footer">
          <button type="button" className="dsv2-sidebar__theme" onClick={toggleTheme}>
            {theme === 'dark' ? <Sun size={16} /> : <Moon size={16} />}
            <span>{theme === 'dark' ? 'الوضع الفاتح' : 'الوضع الداكن'}</span>
          </button>

          <div className="dsv2-sidebar__user">
            <div className="dsv2-sidebar__avatar" aria-hidden="true">{initials}</div>
            <div className="dsv2-sidebar__user-copy">
              <span className="dsv2-sidebar__user-name">{profile?.full_name ?? '—'}</span>
              {roleName && <span className="dsv2-sidebar__user-role">{roleName}</span>}
            </div>
            <button
              type="button"
              className="dsv2-sidebar__logout"
              onClick={handleSignOut}
              aria-label="تسجيل الخروج"
            >
              <LogOut size={16} />
            </button>
          </div>
        </footer>
      </aside>
    </>
  )
}
