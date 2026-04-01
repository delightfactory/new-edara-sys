import { NavLink, useNavigate, useLocation } from 'react-router-dom'
import { useAuthStore } from '@/stores/auth-store'
import { useUiStore } from '@/stores/ui-store'
import { signOut } from '@/lib/services/auth'
import { PERMISSIONS } from '@/lib/permissions/constants'
import {
  LayoutDashboard, ShoppingCart, Package, Warehouse, DollarSign,
  Users, Settings, ClipboardList, Target, BarChart3,
  LogOut, Moon, Sun, ChevronDown, X,
  BoxesIcon, Truck, Building2, UserCog,
} from 'lucide-react'
import { useState, useEffect } from 'react'

interface NavChild {
  label: string
  path: string
  permission?: string | string[]
}
interface NavItem {
  id: string
  label: string
  icon: React.ElementType
  path?: string
  permission?: string | string[]
  comingSoon?: boolean
  children?: NavChild[]
}
interface NavSection {
  label?: string
  items: NavItem[]
}

// ── Exact same items as original, just grouped visually ──
const sections: NavSection[] = [
  {
    items: [
      { id: 'dashboard', label: 'الرئيسية', icon: LayoutDashboard, path: '/' },
    ],
  },
  {
    label: 'التشغيل',
    items: [
      {
        id: 'sales', label: 'المبيعات', icon: ShoppingCart,
        children: [
          { label: 'طلبات البيع', path: '/sales/orders', permission: [PERMISSIONS.SALES_ORDERS_READ, PERMISSIONS.SALES_ORDERS_CREATE] },
          { label: 'المرتجعات', path: '/sales/returns', permission: [PERMISSIONS.SALES_RETURNS_READ, PERMISSIONS.SALES_RETURNS_CREATE] },
          { label: 'شركات الشحن', path: '/sales/shipping', permission: PERMISSIONS.SALES_SHIPPING_MANAGE },
        ],
      },
      {
        id: 'purchases', label: 'المشتريات', icon: Package,
        children: [
          { label: 'فواتير الشراء', path: '/purchases/invoices', permission: PERMISSIONS.PURCHASES_ORDERS_READ },
          { label: 'مرتجعات المشتريات', path: '/purchases/returns', permission: 'procurement.returns.read' },
        ],
      },
      { id: 'customers', label: 'العملاء', icon: Users, path: '/customers', permission: [PERMISSIONS.CUSTOMERS_READ, PERMISSIONS.CUSTOMERS_CREATE] },
      { id: 'suppliers', label: 'الموردين', icon: Truck, path: '/suppliers', permission: [PERMISSIONS.SUPPLIERS_READ, PERMISSIONS.SUPPLIERS_CREATE] },
    ],
  },
  {
    label: 'المخزون',
    items: [
      {
        id: 'inventory', label: 'المخزون', icon: Warehouse,
        children: [
          { label: 'المخازن', path: '/inventory/warehouses', permission: PERMISSIONS.INVENTORY_READ },
          { label: 'أرصدة المخزون', path: '/inventory/stock', permission: PERMISSIONS.INVENTORY_READ },
          { label: 'التحويلات', path: '/inventory/transfers', permission: [PERMISSIONS.INVENTORY_TRANSFERS_READ, PERMISSIONS.INVENTORY_TRANSFERS_CREATE] },
          { label: 'التسويات', path: '/inventory/adjustments', permission: [PERMISSIONS.INVENTORY_ADJUSTMENTS_READ, PERMISSIONS.INVENTORY_ADJUSTMENTS_CREATE] },
          { label: 'حركات المخزون', path: '/inventory/movements', permission: PERMISSIONS.INVENTORY_READ },
        ],
      },
      {
        id: 'products', label: 'المنتجات', icon: BoxesIcon,
        children: [
          { label: 'قائمة المنتجات', path: '/products', permission: [PERMISSIONS.PRODUCTS_READ, PERMISSIONS.PRODUCTS_CREATE] },
          { label: 'التصنيفات', path: '/products/categories', permission: PERMISSIONS.CATEGORIES_CREATE },
          { label: 'قوائم الأسعار', path: '/products/price-lists', permission: PERMISSIONS.PRICE_LISTS_READ },
          { label: 'الباقات', path: '/products/bundles', permission: PERMISSIONS.PRODUCTS_READ },
          { label: 'العلامات التجارية', path: '/products/brands', permission: PERMISSIONS.PRODUCTS_READ },
        ],
      },
      { id: 'branches', label: 'الفروع', icon: Building2, path: '/branches', permission: PERMISSIONS.BRANCHES_READ },
    ],
  },
  {
    label: 'المالية',
    items: [
      {
        id: 'finance', label: 'المالية', icon: DollarSign,
        children: [
          { label: 'الخزائن', path: '/finance/vaults', permission: PERMISSIONS.FINANCE_VAULTS_READ },
          { label: 'العُهد', path: '/finance/custody', permission: [PERMISSIONS.FINANCE_CUSTODY_READ, PERMISSIONS.FINANCE_CUSTODY_CREATE] },
          { label: 'إيصالات الدفع', path: '/finance/payments', permission: [PERMISSIONS.FINANCE_PAYMENTS_READ, PERMISSIONS.FINANCE_PAYMENTS_CREATE] },
          { label: 'المصروفات', path: '/finance/expenses', permission: [PERMISSIONS.FINANCE_EXPENSES_READ, PERMISSIONS.FINANCE_EXPENSES_CREATE] },
          { label: 'شجرة الحسابات', path: '/finance/accounts', permission: PERMISSIONS.FINANCE_JOURNAL_READ },
          { label: 'القيود المحاسبية', path: '/finance/journals', permission: PERMISSIONS.FINANCE_JOURNAL_READ },
          { label: 'دفتر الحسابات', path: '/finance/ledger', permission: PERMISSIONS.FINANCE_LEDGER_READ },
          { label: 'قواعد الموافقات', path: '/finance/approval-rules', permission: PERMISSIONS.SETTINGS_UPDATE },
        ],
      },
    ],
  },
  {
    label: 'الأنشطة الميدانية',
    items: [
      {
        id: 'activities', label: 'الأنشطة', icon: ClipboardList,
        path: '/activities',
        permission: [PERMISSIONS.ACTIVITIES_READ_OWN, PERMISSIONS.ACTIVITIES_READ_TEAM, PERMISSIONS.ACTIVITIES_READ_ALL],
        children: [
          { label: 'لوحة الأنشطة',  path: '/activities',              permission: [PERMISSIONS.ACTIVITIES_READ_OWN, PERMISSIONS.ACTIVITIES_READ_TEAM, PERMISSIONS.ACTIVITIES_READ_ALL] },
          { label: 'قائمة الأنشطة', path: '/activities/list',         permission: [PERMISSIONS.ACTIVITIES_READ_OWN, PERMISSIONS.ACTIVITIES_READ_TEAM, PERMISSIONS.ACTIVITIES_READ_ALL] },
          { label: 'خطط الزيارات',   path: '/activities/visit-plans',  permission: [PERMISSIONS.VISIT_PLANS_READ_OWN, PERMISSIONS.VISIT_PLANS_READ_TEAM, PERMISSIONS.VISIT_PLANS_READ_ALL] },
          { label: 'خطط المكالمات',  path: '/activities/call-plans',   permission: [PERMISSIONS.CALL_PLANS_READ_OWN, PERMISSIONS.CALL_PLANS_READ_TEAM, PERMISSIONS.CALL_PLANS_READ_ALL] },
          { label: 'الأهداف',        path: '/activities/targets',      permission: [PERMISSIONS.TARGETS_READ_OWN, PERMISSIONS.TARGETS_READ_TEAM, PERMISSIONS.TARGETS_READ_ALL] },
        ],
      },
    ],
  },
  {
    label: 'أدوات',
    items: [
      { id: 'reports', label: 'التقارير', icon: BarChart3, path: '/reports', permission: PERMISSIONS.REPORTS_SALES, comingSoon: true },
      {
        id: 'hr', label: 'الموارد البشرية', icon: UserCog,
        path: '/hr',
        children: [
          { label: 'لوحة التحكم',     path: '/hr',                    permission: PERMISSIONS.HR_EMPLOYEES_READ },
          { label: 'الموظفون',        path: '/hr/employees',          permission: PERMISSIONS.HR_EMPLOYEES_READ },
          { label: 'الحضور',          path: '/hr/attendance',         permission: PERMISSIONS.HR_EMPLOYEES_READ },
          { label: 'تسجيل الحضور',   path: '/hr/attendance/checkin', permission: 'hr.attendance.checkin' },
          { label: 'الأذونات',        path: '/hr/permissions',        permission: ['hr.permissions.approve', 'hr.attendance.checkin', 'hr.leaves.create'] },
          { label: 'الإجازات',        path: '/hr/leaves',             permission: ['hr.leaves.create', 'hr.leaves.read', 'hr.leaves.approve', 'hr.leaves.request'] },
          { label: 'السلف',           path: '/hr/advances',           permission: ['hr.advances.create', 'hr.advances.read', 'hr.advances.approve'] },
          { label: 'التفويضات',       path: '/hr/delegations',        permission: ['hr.leaves.approve', 'hr.advances.approve', 'hr.attendance.approve', 'hr.permissions.approve'] },
          { label: 'ملفي الشخصي',     path: '/hr/my-profile' },
          { label: 'العمولات',        path: '/hr/commissions',        permission: ['hr.commissions.create', PERMISSIONS.HR_EMPLOYEES_READ] },
          { label: 'مسير الرواتب',   path: '/hr/payroll',                  permission: 'hr.payroll.read' },
          { label: 'مكافآت الأهداف', path: '/hr/payroll/target-payouts',   permission: 'hr.payroll.read' },
          { label: 'مكافآت وخصومات', path: '/hr/adjustments',              permission: ['hr.payroll.read', 'hr.adjustments.read', 'hr.adjustments.create'] },
          { label: 'إعدادات HR',     path: '/hr/settings',           permission: 'hr.settings.update' },
        ],
      },
      {
        id: 'settings', label: 'الإعدادات', icon: Settings,
        children: [
          { label: 'المستخدمون', path: '/settings/users', permission: PERMISSIONS.AUTH_USERS_READ },
          { label: 'الأدوار', path: '/settings/roles', permission: PERMISSIONS.AUTH_ROLES_READ },
          { label: 'إعدادات الشركة', path: '/settings/company', permission: PERMISSIONS.SETTINGS_READ },
          { label: 'سجل التدقيق', path: '/settings/audit', permission: PERMISSIONS.SETTINGS_AUDIT_READ },
        ],
      },
    ],
  },
]


export default function Sidebar() {
  const can = useAuthStore(s => s.can)
  const canAny = useAuthStore(s => s.canAny)
  const profile = useAuthStore(s => s.profile)
  const { theme, toggleTheme, sidebarOpen, setSidebarOpen } = useUiStore()
  const navigate = useNavigate()
  const location = useLocation()
  const [expanded, setExpanded] = useState<string | null>(null)

  // Auto-expand group for current path
  useEffect(() => {
    for (const sec of sections) {
      for (const item of sec.items) {
        if (item.children?.some(c => location.pathname.startsWith(c.path))) {
          setExpanded(item.id)
          return
        }
      }
    }
  }, [location.pathname])

  const handleNavClick = () => {
    if (window.innerWidth <= 768) setSidebarOpen(false)
  }

  const handleSignOut = async () => {
    await signOut()
    navigate('/login', { replace: true })
  }

  const canAccess = (perm?: string | string[]) => {
    if (!perm) return true
    return Array.isArray(perm) ? canAny(perm) : can(perm)
  }

  const toggleExpand = (id: string) =>
    setExpanded(prev => (prev === id ? null : id))

  const renderItem = (item: NavItem) => {
    const Icon = item.icon
    const hasChildren = !!item.children?.length
    const isExpanded = expanded === item.id

    // Get visible children
    const visibleChildren = item.children?.filter(c => canAccess(c.permission)) ?? []

    // Hide parent if no visible children
    if (hasChildren && visibleChildren.length === 0) return null

    // For leaf items, respect permission
    if (!hasChildren && !canAccess(item.permission) && !item.comingSoon) return null

    // ── Leaf item ──
    if (!hasChildren && item.path) {
      if (item.comingSoon) {
        return (
          <div key={item.id} className="si si--soon" title="قريباً">
            <span className="si-icon"><Icon size={16} /></span>
            <span className="si-label">{item.label}</span>
            <span className="si-badge">قريباً</span>
          </div>
        )
      }
      return (
        <NavLink
          key={item.id}
          to={item.path}
          className={({ isActive }) => `si${isActive ? ' si--active' : ''}`}
          end={item.path === '/'}
          onClick={handleNavClick}
        >
          <span className="si-icon"><Icon size={16} /></span>
          <span className="si-label">{item.label}</span>
        </NavLink>
      )
    }

    // ── Group item ──
    return (
      <div key={item.id} className="si-group">
        <button
          className={`si${isExpanded ? ' si--expanded' : ''}`}
          onClick={() => toggleExpand(item.id)}
        >
          <span className="si-icon"><Icon size={16} /></span>
          <span className="si-label">{item.label}</span>
          <ChevronDown size={13} className="si-chevron" style={{ transform: isExpanded ? 'rotate(180deg)' : 'none' }} />
        </button>
        <div className={`si-children${isExpanded ? ' si-children--open' : ''}`}>
          {visibleChildren.map(child => (
            <NavLink
              key={child.path}
              to={child.path}
              className={({ isActive }) => `si-child${isActive ? ' si-child--active' : ''}`}
              onClick={handleNavClick}
            >
              <span className="si-dot" />
              {child.label}
            </NavLink>
          ))}
        </div>
      </div>
    )
  }

  // Only show sections with at least one accessible item
  const visibleSections = sections
    .map(sec => ({
      ...sec,
      items: sec.items.filter(item => {
        if (item.children) return item.children.some(c => canAccess(c.permission))
        return canAccess(item.permission) || item.comingSoon
      }),
    }))
    .filter(sec => sec.items.length > 0)

  const initials = profile?.full_name?.charAt(0)?.toUpperCase() ?? '؟'
  const roleName = profile?.roles?.[0]?.name_ar ?? ''
  const isDark = theme === 'dark'

  return (
    <>
      {sidebarOpen && (
        <div className="sb-ov" onClick={() => setSidebarOpen(false)} aria-hidden="true" />
      )}

      <aside className={`sb${sidebarOpen ? ' sb--open' : ''}`} aria-label="القائمة الرئيسية">

        {/* ── HEADER ── */}
        <div className="sb-hdr">
          <div className="sb-brand">
            <div className="sb-brand-logo">
              <img
                src="/pwa-64x64.png"
                alt="DE"
                onError={e => { (e.currentTarget as HTMLImageElement).style.display = 'none' }}
              />
              <span className="sb-brand-init">DE</span>
            </div>
            <div>
              <div className="sb-brand-name">EDARA</div>
              <div className="sb-brand-sub">نظام الإدارة</div>
            </div>
          </div>
          <button className="sb-close" onClick={() => setSidebarOpen(false)} aria-label="إغلاق">
            <X size={15} />
          </button>
        </div>

        {/* ── NAV ── */}
        <nav className="sb-nav">
          {visibleSections.map((sec, i) => (
            <div key={i} className="sb-sec">
              {sec.label && <p className="sb-sec-lbl">{sec.label}</p>}
              {sec.items.map(renderItem)}
            </div>
          ))}
        </nav>

        {/* ── FOOTER ── */}
        <div className="sb-ftr">
          {/* Theme */}
          <button className="sb-theme" onClick={toggleTheme}>
            <span className="sb-theme-ic">
              {isDark ? <Sun size={14} /> : <Moon size={14} />}
            </span>
            <span>{isDark ? 'الوضع الفاتح' : 'الوضع الداكن'}</span>
          </button>
          {/* User */}
          <div className="sb-user">
            <div className="sb-av">{initials}</div>
            <div className="sb-user-txt">
              <span className="sb-uname">{profile?.full_name ?? '—'}</span>
              {roleName && <span className="sb-urole">{roleName}</span>}
            </div>
            <button className="sb-exit" onClick={handleSignOut} title="تسجيل الخروج">
              <LogOut size={14} />
            </button>
          </div>
        </div>

        {/* ══════════════════════════════════════
            PREMIUM SIDEBAR CSS
            Inspired by Linear / Notion / Vercel
            Uses own color palette (not tokens)
            for full visual control.
        ══════════════════════════════════════ */}
        <style>{`
          /* ── Overlay ── */
          .sb-ov {
            display: none;
          }

          /* ── Shell ── */
          .sb {
            width: var(--sidebar-width, 260px);
            height: 100vh;
            position: fixed;
            top: 0; right: 0;
            z-index: var(--z-sidebar, 200);
            display: flex;
            flex-direction: column;
            overflow: hidden;
            transition: transform 0.28s cubic-bezier(0.4, 0, 0.2, 1);

            /* Premium sidebar: NOT pure white — warm off-white */
            background: ${isDark ? '#0c0f14' : '#f8f9fb'};
            border-left: 1px solid ${isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.07)'};
          }

          /* ── Header ── */
          .sb-hdr {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 16px 14px 14px;
            border-bottom: 1px solid ${isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.07)'};
            flex-shrink: 0;
          }

          .sb-brand {
            display: flex;
            align-items: center;
            gap: 10px;
          }
          .sb-brand-logo {
            position: relative;
            width: 34px; height: 34px;
            border-radius: 9px;
            overflow: hidden;
            background: linear-gradient(135deg, #1e3a8a, #1d4ed8);
            display: flex; align-items: center; justify-content: center;
            flex-shrink: 0;
            box-shadow: 0 2px 8px rgba(37,99,235,0.35);
          }
          .sb-brand-logo img {
            width: 100%; height: 100%;
            object-fit: cover;
            position: absolute; inset: 0;
          }
          .sb-brand-init {
            font-size: 12px;
            font-weight: 800;
            color: #fff;
            letter-spacing: 0.5px;
            position: relative;
          }
          .sb-brand-name {
            font-size: 15px;
            font-weight: 800;
            color: ${isDark ? '#f1f5f9' : '#0f172a'};
            letter-spacing: 1px;
            line-height: 1.1;
          }
          .sb-brand-sub {
            font-size: 10px;
            color: ${isDark ? 'rgba(255,255,255,0.35)' : 'rgba(0,0,0,0.35)'};
            font-weight: 400;
            line-height: 1;
            margin-top: 2px;
          }

          .sb-close {
            display: none;
            align-items: center; justify-content: center;
            width: 28px; height: 28px;
            border-radius: 7px;
            border: none;
            background: ${isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.06)'};
            color: ${isDark ? 'rgba(255,255,255,0.5)' : 'rgba(0,0,0,0.45)'};
            cursor: pointer;
            transition: all 0.15s;
            flex-shrink: 0;
          }
          .sb-close:hover {
            background: ${isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.1)'};
            color: ${isDark ? '#fff' : '#000'};
          }

          /* ── Scrollable nav ── */
          .sb-nav {
            flex: 1;
            overflow-y: auto;
            padding: 10px 8px;
            display: flex;
            flex-direction: column;
            gap: 0;
            scrollbar-width: none;
          }
          .sb-nav::-webkit-scrollbar { display: none; }

          /* ── Section group ── */
          .sb-sec {
            display: flex;
            flex-direction: column;
            padding-bottom: 6px;
            margin-bottom: 2px;
          }
          .sb-sec + .sb-sec {
            border-top: 1px solid ${isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.05)'};
            padding-top: 10px;
            margin-top: 4px;
          }

          .sb-sec-lbl {
            font-size: 10px;
            font-weight: 700;
            letter-spacing: 0.8px;
            text-transform: uppercase;
            color: ${isDark ? 'rgba(255,255,255,0.25)' : 'rgba(0,0,0,0.28)'};
            padding: 4px 10px 6px;
            margin: 0;
          }

          /* ── Nav item ── */
          .si {
            display: flex;
            align-items: center;
            gap: 9px;
            padding: 8px 10px;
            margin: 1px 0;
            border-radius: 8px;
            cursor: pointer;
            color: ${isDark ? 'rgba(255,255,255,0.55)' : 'rgba(0,0,0,0.55)'};
            font-size: 13.5px;
            font-weight: 500;
            text-decoration: none;
            border: none;
            background: none;
            width: 100%;
            font-family: var(--font-sans, inherit);
            position: relative;
            transition: background 0.12s, color 0.12s;
          }
          .si:hover {
            background: ${isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)'};
            color: ${isDark ? 'rgba(255,255,255,0.85)' : 'rgba(0,0,0,0.8)'};
          }

          /* Active — Notion/Linear style: neutral bg + left accent pill */
          .si--active {
            background: ${isDark ? 'rgba(255,255,255,0.09)' : 'rgba(0,0,0,0.07)'};
            color: ${isDark ? '#fff' : '#0f172a'};
            font-weight: 600;
          }
          .si--active::after {
            content: '';
            position: absolute;
            right: 0;
            top: 20%;
            height: 60%;
            width: 3px;
            background: #2563eb;
            border-radius: 99px 0 0 99px;
          }

          /* Expanded parent */
          .si--expanded {
            color: ${isDark ? 'rgba(255,255,255,0.8)' : 'rgba(0,0,0,0.75)'};
          }

          /* Coming soon */
          .si--soon {
            opacity: 0.35;
            cursor: not-allowed;
            pointer-events: none;
          }

          .si-icon {
            display: flex;
            align-items: center;
            justify-content: center;
            width: 20px;
            flex-shrink: 0;
          }
          .si-label {
            flex: 1;
            text-align: right;
          }
          .si-chevron {
            flex-shrink: 0;
            transition: transform 0.2s cubic-bezier(0.4,0,0.2,1);
            color: ${isDark ? 'rgba(255,255,255,0.25)' : 'rgba(0,0,0,0.25)'};
          }
          .si-badge {
            font-size: 9px;
            font-weight: 700;
            background: ${isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.07)'};
            color: ${isDark ? 'rgba(255,255,255,0.3)' : 'rgba(0,0,0,0.35)'};
            padding: 2px 6px;
            border-radius: 4px;
          }

          /* ── Sub-items ── */
          .si-children {
            max-height: 0;
            overflow: hidden;
            opacity: 0;
            transition: max-height 0.25s ease, opacity 0.2s ease;
          }
          .si-children--open {
            max-height: 500px;
            opacity: 1;
          }
          .si-child {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 6px 10px 6px 10px;
            padding-right: 38px;
            margin: 1px 0;
            border-radius: 7px;
            color: ${isDark ? 'rgba(255,255,255,0.45)' : 'rgba(0,0,0,0.45)'};
            font-size: 12.5px;
            font-weight: 400;
            text-decoration: none;
            transition: background 0.12s, color 0.12s;
          }
          .si-child:hover {
            background: ${isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)'};
            color: ${isDark ? 'rgba(255,255,255,0.75)' : 'rgba(0,0,0,0.7)'};
          }
          .si-child--active {
            color: #2563eb;
            font-weight: 600;
          }
          .si-child--active .si-dot { background: #2563eb !important; }

          .si-dot {
            width: 4px; height: 4px;
            border-radius: 50%;
            background: ${isDark ? 'rgba(255,255,255,0.25)' : 'rgba(0,0,0,0.2)'};
            flex-shrink: 0;
          }

          /* ── Footer ── */
          .sb-ftr {
            padding: 10px 8px 12px;
            border-top: 1px solid ${isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.07)'};
            display: flex;
            flex-direction: column;
            gap: 4px;
            flex-shrink: 0;
          }

          .sb-theme {
            display: flex;
            align-items: center;
            gap: 9px;
            padding: 7px 10px;
            border-radius: 8px;
            border: none;
            background: none;
            width: 100%;
            color: ${isDark ? 'rgba(255,255,255,0.45)' : 'rgba(0,0,0,0.45)'};
            font-size: 13px;
            font-weight: 500;
            font-family: var(--font-sans, inherit);
            cursor: pointer;
            text-align: right;
            transition: background 0.12s, color 0.12s;
          }
          .sb-theme:hover {
            background: ${isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)'};
            color: ${isDark ? '#fff' : '#000'};
          }
          .sb-theme-ic {
            display: flex; align-items: center; justify-content: center;
            width: 24px; height: 24px;
            border-radius: 6px;
            background: ${isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)'};
            flex-shrink: 0;
            transition: transform 0.3s;
          }
          .sb-theme:hover .sb-theme-ic { transform: rotate(20deg); }

          /* ── User card ── */
          .sb-user {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 8px 10px;
            border-radius: 10px;
            background: ${isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)'};
            border: 1px solid ${isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.07)'};
          }
          .sb-av {
            width: 32px; height: 32px;
            border-radius: 50%;
            background: linear-gradient(135deg, #1e40af, #2563eb);
            color: #fff;
            display: flex; align-items: center; justify-content: center;
            font-weight: 700;
            font-size: 13px;
            flex-shrink: 0;
            box-shadow: 0 1px 6px rgba(37,99,235,0.4);
          }
          .sb-user-txt {
            flex: 1;
            display: flex;
            flex-direction: column;
            overflow: hidden;
            min-width: 0;
          }
          .sb-uname {
            font-size: 13px;
            font-weight: 600;
            color: ${isDark ? '#f1f5f9' : '#0f172a'};
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
          }
          .sb-urole {
            font-size: 11px;
            color: ${isDark ? 'rgba(255,255,255,0.35)' : 'rgba(0,0,0,0.4)'};
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
          }
          .sb-exit {
            display: flex; align-items: center; justify-content: center;
            width: 28px; height: 28px;
            border-radius: 7px;
            border: none;
            background: none;
            color: ${isDark ? 'rgba(255,255,255,0.3)' : 'rgba(0,0,0,0.3)'};
            cursor: pointer;
            flex-shrink: 0;
            transition: background 0.12s, color 0.12s;
          }
          .sb-exit:hover {
            background: rgba(220,38,38,0.12);
            color: #dc2626;
          }

          /* ══ Mobile ══ */
          @media (max-width: 768px) {
            .sb-ov {
              display: block;
              position: fixed; inset: 0;
              z-index: calc(var(--z-sidebar, 200) - 1);
              background: rgba(0,0,0,0.45);
              backdrop-filter: blur(4px);
              -webkit-backdrop-filter: blur(4px);
            }
            .sb {
              transform: translateX(110%);
              width: min(288px, 88vw);
              box-shadow: -12px 0 48px rgba(0,0,0,0.3);
            }
            .sb--open { transform: translateX(0); }
            .sb-close { display: flex; }
          }
        `}</style>
      </aside>
    </>
  )
}
