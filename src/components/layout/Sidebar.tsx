import { NavLink, useNavigate, useLocation } from 'react-router-dom'
import { useAuthStore } from '@/stores/auth-store'
import { useUiStore } from '@/stores/ui-store'
import { signOut } from '@/lib/services/auth'
import { PERMISSIONS } from '@/lib/permissions/constants'
import {
  LayoutDashboard, ShoppingCart, Package, Warehouse, DollarSign,
  Users, Settings, Shield, ClipboardList, Target, BarChart3,
  LogOut, Moon, Sun, ChevronDown, ChevronLeft, X,
  BoxesIcon, Truck, Building2, Tags
} from 'lucide-react'
import { useState, useEffect } from 'react'

interface NavItem {
  id: string
  label: string
  icon: React.ElementType
  path?: string
  permission?: string | string[]
  comingSoon?: boolean
  children?: { label: string; path: string; permission?: string | string[] }[]
}

const navItems: NavItem[] = [
  { id: 'dashboard', label: 'الرئيسية', icon: LayoutDashboard, path: '/' },
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
  { id: 'customers', label: 'العملاء', icon: Users, permission: [PERMISSIONS.CUSTOMERS_READ, PERMISSIONS.CUSTOMERS_CREATE], path: '/customers' },
  {
    id: 'suppliers', label: 'الموردين', icon: Truck,
    permission: [PERMISSIONS.SUPPLIERS_READ, PERMISSIONS.SUPPLIERS_CREATE], path: '/suppliers',
  },
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
  { id: 'branches', label: 'الفروع', icon: Building2, permission: PERMISSIONS.BRANCHES_READ, path: '/branches' },
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
      { label: 'فواتير الشراء',   path: '/purchases/invoices', permission: PERMISSIONS.PURCHASES_ORDERS_READ },
      { label: 'مرتجعات المشتريات', path: '/purchases/returns', permission: 'procurement.returns.read' },
    ],
  },
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
  { id: 'targets', label: 'الأهداف', icon: Target, permission: PERMISSIONS.TARGETS_READ_OWN, path: '/targets', comingSoon: true },
  { id: 'reports', label: 'التقارير', icon: BarChart3, permission: PERMISSIONS.REPORTS_SALES, path: '/reports', comingSoon: true },
  { id: 'hr', label: 'الموارد البشرية', icon: ClipboardList, permission: PERMISSIONS.HR_EMPLOYEES_READ, path: '/hr', comingSoon: true },
  {
    id: 'settings', label: 'الإعدادات', icon: Settings,
    children: [
      { label: 'المستخدمون', path: '/settings/users', permission: PERMISSIONS.AUTH_USERS_READ },
      { label: 'الأدوار', path: '/settings/roles', permission: PERMISSIONS.AUTH_ROLES_READ },
      { label: 'إعدادات الشركة', path: '/settings/company', permission: PERMISSIONS.SETTINGS_READ },
      { label: 'سجل التدقيق', path: '/settings/audit', permission: PERMISSIONS.SETTINGS_AUDIT_READ },
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

  // تحديد المجموعة المفتوحة تلقائياً حسب المسار الحالي
  useEffect(() => {
    const current = navItems.find(item =>
      item.children?.some(c => location.pathname.startsWith(c.path))
    )
    if (current) setExpanded(current.id)
  }, [location.pathname])

  // إغلاق الـ Sidebar تلقائياً عند النقر على رابط في الموبايل
  const handleNavClick = () => {
    if (window.innerWidth <= 768) {
      setSidebarOpen(false)
    }
  }

  const handleSignOut = async () => {
    await signOut()
    navigate('/login', { replace: true })
  }

  // دالة فحص مرنة تدعم الصلاحية الواحدة والمصفوفة
  const canAccess = (perm?: string | string[]) => {
    if (!perm) return true
    return Array.isArray(perm) ? canAny(perm) : can(perm)
  }

  const visibleItems = navItems.filter(item => {
    if (item.children) {
      // الأب يظهر فقط إذا كان هناك ابن واحد على الأقل مسموح به
      return item.children.some(c => canAccess(c.permission))
    }
    return canAccess(item.permission)
  })

  const toggleExpand = (id: string) => {
    setExpanded(prev => prev === id ? null : id)
  }

  return (
    <>
      {/* Mobile overlay */}
      {sidebarOpen && (
        <div
          className="sidebar-overlay"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      <aside className={`sidebar ${sidebarOpen ? 'sidebar--open' : ''}`}>
        {/* Header */}
        <div className="sidebar-logo">
          <Shield size={24} />
          <span className="sidebar-logo-text">EDARA</span>
          <button
            className="sidebar-close-btn"
            onClick={() => setSidebarOpen(false)}
            aria-label="إغلاق القائمة"
          >
            <X size={18} />
          </button>
        </div>

        {/* Navigation */}
        <nav className="sidebar-nav">
          {visibleItems.map(item => {
            const Icon = item.icon
            const hasChildren = item.children && item.children.length > 0
            const isExpanded = expanded === item.id
            const visibleChildren = hasChildren
              ? item.children!.filter(c => canAccess(c.permission))
              : []

            if (hasChildren && visibleChildren.length === 0) return null

            if (!hasChildren && item.path) {
              // comingSoon — عرض باهت بدون نقر
              if (item.comingSoon) {
                return (
                  <div key={item.id} className="sidebar-item" style={{ opacity: 0.45, cursor: 'default', pointerEvents: 'none' }} title="قريباً">
                    <Icon size={18} />
                    <span>{item.label}</span>
                    <span style={{ marginRight: 'auto', marginLeft: 0, fontSize: '0.55rem', background: 'var(--bg-surface-2)', padding: '1px 6px', borderRadius: 'var(--radius-sm)', color: 'var(--text-muted)' }}>قريباً</span>
                  </div>
                )
              }
              return (
                <NavLink
                  key={item.id}
                  to={item.path}
                  className={({ isActive }) => `sidebar-item ${isActive ? 'active' : ''}`}
                  end={item.path === '/'}
                  onClick={handleNavClick}
                >
                  <Icon size={18} />
                  <span>{item.label}</span>
                </NavLink>
              )
            }

            return (
              <div key={item.id} className="sidebar-group">
                {item.comingSoon ? (
                  <div className="sidebar-item" style={{ opacity: 0.45, cursor: 'default', pointerEvents: 'none' }} title="قريباً">
                    <Icon size={18} />
                    <span>{item.label}</span>
                    <span style={{ marginRight: 'auto', marginLeft: 0, fontSize: '0.55rem', background: 'var(--bg-surface-2)', padding: '1px 6px', borderRadius: 'var(--radius-sm)', color: 'var(--text-muted)' }}>قريباً</span>
                  </div>
                ) : (
                <>
                <button
                  className={`sidebar-item sidebar-group-toggle ${isExpanded ? 'expanded' : ''}`}
                  onClick={() => toggleExpand(item.id)}
                >
                  <Icon size={18} />
                  <span>{item.label}</span>
                  <ChevronDown
                    size={14}
                    className="sidebar-chevron"
                    style={{
                      marginRight: 'auto',
                      marginLeft: 0,
                      transition: 'transform 0.2s',
                      transform: isExpanded ? 'rotate(180deg)' : 'none',
                    }}
                  />
                </button>
                <div className={`sidebar-children ${isExpanded ? 'sidebar-children--open' : ''}`}>
                  {visibleChildren.map(child => (
                    <NavLink
                      key={child.path}
                      to={child.path}
                      className={({ isActive }) => `sidebar-child-item ${isActive ? 'active' : ''}`}
                      onClick={handleNavClick}
                    >
                      <ChevronLeft size={12} />
                      <span>{child.label}</span>
                    </NavLink>
                  ))}
                </div>
                </>
                )}
              </div>
            )
          })}
        </nav>

        {/* Footer */}
        <div className="sidebar-footer">
          <button className="theme-toggle-btn" onClick={toggleTheme} title="تغيير المظهر">
            <span className="theme-toggle-icon">
              {theme === 'light' ? <Moon size={16} /> : <Sun size={16} />}
            </span>
            <span>{theme === 'light' ? 'الوضع الداكن' : 'الوضع الفاتح'}</span>
          </button>
          <div className="sidebar-user">
            <div className="sidebar-user-avatar">
              {profile?.full_name?.charAt(0) || '?'}
            </div>
            <div className="sidebar-user-info">
              <span className="sidebar-user-name">{profile?.full_name}</span>
              <span className="sidebar-user-role">
                {profile?.roles?.[0]?.name_ar || ''}
              </span>
            </div>
          </div>
          <button className="sidebar-item sidebar-logout" onClick={handleSignOut}>
            <LogOut size={18} />
            <span>تسجيل الخروج</span>
          </button>
        </div>

        <style>{`
          .sidebar-overlay {
            display: none;
          }
          .sidebar {
            width: var(--sidebar-width);
            height: 100vh; position: fixed;
            top: 0; right: 0; z-index: 50;
            background: var(--sidebar-bg);
            display: flex; flex-direction: column;
            transition: transform 0.3s cubic-bezier(0.4, 0, 0.2, 1),
                        background 0.3s ease,
                        border-color 0.3s ease;
            overflow-x: hidden;
            border-left: 1px solid var(--sidebar-border);
          }
          .sidebar-close-btn {
            display: none;
            background: none; border: none;
            color: var(--sidebar-text); cursor: pointer;
            padding: 4px; border-radius: var(--radius-sm);
            margin-right: auto; margin-left: 0;
          }
          .sidebar-close-btn:hover { background: var(--sidebar-item-hover); color: var(--sidebar-text-active); }

          .sidebar-logo {
            display: flex; align-items: center; gap: var(--space-3);
            padding: var(--space-4) var(--space-4);
            color: var(--sidebar-logo-color); font-weight: 700;
            border-bottom: 1px solid var(--sidebar-border);
            flex-shrink: 0;
          }
          .sidebar-logo-text {
            font-size: var(--text-lg); letter-spacing: 2px;
          }

          .sidebar-nav {
            flex: 1; overflow-y: auto; padding: var(--space-3) var(--space-2);
            display: flex; flex-direction: column; gap: 2px;
          }
          .sidebar-nav::-webkit-scrollbar { width: 3px; }
          .sidebar-nav::-webkit-scrollbar-thumb { background: var(--sidebar-item-hover); border-radius: 99px; }

          .sidebar-item {
            display: flex; align-items: center; gap: var(--space-3);
            padding: var(--space-2-5, 10px) var(--space-3);
            border-radius: var(--radius-md); cursor: pointer;
            color: var(--sidebar-text);
            font-size: var(--text-sm); font-weight: 500;
            transition: all 0.15s ease;
            text-decoration: none; border: none;
            background: none; width: 100%; font-family: var(--font-sans);
          }
          .sidebar-item:hover {
            background: var(--sidebar-item-hover);
            color: var(--sidebar-text-active);
          }
          .sidebar-item.active {
            background: var(--sidebar-item-active);
            color: var(--color-primary); font-weight: 600;
          }

          .sidebar-children {
            padding-right: var(--space-7);
            display: flex; flex-direction: column; gap: 1px;
            max-height: 0; overflow: hidden;
            transition: max-height 0.25s ease-out, opacity 0.2s ease;
            opacity: 0;
          }
          .sidebar-children--open {
            max-height: 300px;
            opacity: 1;
            transition: max-height 0.35s ease-in, opacity 0.25s ease;
          }

          .sidebar-child-item {
            display: flex; align-items: center; gap: var(--space-2);
            padding: var(--space-2) var(--space-3);
            border-radius: var(--radius-sm);
            color: var(--sidebar-text); font-size: var(--text-xs);
            text-decoration: none; transition: all 0.15s ease;
          }
          .sidebar-child-item:hover { background: var(--sidebar-item-hover); color: var(--sidebar-text-active); }
          .sidebar-child-item.active {
            color: var(--color-primary); font-weight: 600;
            background: var(--sidebar-item-active);
          }

          .sidebar-footer {
            border-top: 1px solid var(--sidebar-border);
            padding: var(--space-3) var(--space-2);
            display: flex; flex-direction: column; gap: 2px;
            flex-shrink: 0;
          }

          /* ===== Theme Toggle Button ===== */
          .theme-toggle-btn {
            display: flex; align-items: center; gap: var(--space-3);
            padding: var(--space-2-5, 10px) var(--space-3);
            border-radius: var(--radius-md); cursor: pointer;
            color: var(--sidebar-text);
            font-size: var(--text-sm); font-weight: 500;
            transition: all 0.15s ease;
            border: none; background: none; width: 100%;
            font-family: var(--font-sans);
          }
          .theme-toggle-btn:hover {
            background: var(--sidebar-item-hover);
            color: var(--sidebar-text-active);
          }
          .theme-toggle-icon {
            display: flex; align-items: center; justify-content: center;
            width: 32px; height: 32px;
            border-radius: var(--radius-full);
            background: var(--bg-active);
            transition: transform 0.4s cubic-bezier(0.4, 0, 0.2, 1),
                        background 0.3s ease;
            flex-shrink: 0;
          }
          .theme-toggle-btn:hover .theme-toggle-icon {
            transform: rotate(30deg) scale(1.1);
          }

          .sidebar-user {
            display: flex; align-items: center; gap: var(--space-3);
            padding: var(--space-3);
          }
          .sidebar-user-avatar {
            width: 34px; height: 34px; border-radius: var(--radius-full);
            background: var(--color-primary); color: white;
            display: flex; align-items: center; justify-content: center;
            font-weight: 700; font-size: var(--text-xs); flex-shrink: 0;
          }
          .sidebar-user-info { display: flex; flex-direction: column; overflow: hidden; }
          .sidebar-user-name {
            color: var(--sidebar-text-active); font-size: var(--text-sm); font-weight: 600;
            white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
          }
          .sidebar-user-role {
            color: var(--sidebar-text); font-size: 11px;
            white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
          }
          .sidebar-logout { color: var(--color-danger) !important; }
          .sidebar-logout:hover { background: rgba(220,38,38,0.1) !important; }

          /* ===== Mobile ===== */
          @media (max-width: 768px) {
            .sidebar-overlay {
              display: block;
              position: fixed; inset: 0; z-index: 49;
              background: var(--overlay-bg);
              backdrop-filter: blur(2px);
              animation: fadeIn 0.2s ease;
            }
            .sidebar {
              transform: translateX(100%);
              width: 280px;
              box-shadow: -4px 0 24px rgba(0,0,0,0.3);
            }
            .sidebar.sidebar--open {
              transform: translateX(0);
            }
            .sidebar-close-btn {
              display: flex;
            }
          }

          @keyframes fadeIn {
            from { opacity: 0; }
            to { opacity: 1; }
          }
        `}</style>
      </aside>
    </>
  )
}
