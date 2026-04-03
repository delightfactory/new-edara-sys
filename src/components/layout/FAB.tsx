import { useNavigate, useLocation } from 'react-router-dom'
import { useEffect, useRef, useState } from 'react'
import {
  ShoppingCart, UserPlus, Package,
  Receipt, RotateCcw, Activity, MapPin, Phone,
  Users,
} from 'lucide-react'
import { useAuthStore } from '@/stores/auth-store'
import { useIsAnyModalOpen } from '@/hooks/useModalStack'

interface FabConfig {
  path: string
  label: string
  icon: React.ElementType
  navigateTo: string
  permission: string
}

const FAB_MAP: FabConfig[] = [
  { path: '/sales/orders',              label: '+ طلب بيع',     icon: ShoppingCart,   navigateTo: '/sales/orders/new',             permission: 'sales.orders.create'            },
  { path: '/sales/returns',             label: '+ مرتجع بيع',   icon: RotateCcw,      navigateTo: '/sales/returns/new',            permission: 'sales.returns.create'           },
  { path: '/customers',                 label: '+ عميل',        icon: UserPlus,       navigateTo: '/customers/new',                permission: 'customers.create'               },
  { path: '/suppliers',                 label: '+ مورد',        icon: Users,          navigateTo: '/suppliers/new',                permission: 'suppliers.create'               },
  { path: '/products',                  label: '+ منتج',        icon: Package,        navigateTo: '/products/new',                 permission: 'products.create'                },
  { path: '/purchases/invoices',        label: '+ فاتورة',      icon: Package,        navigateTo: '/purchases/invoices/new',       permission: 'procurement.invoices.create'    },
  { path: '/purchases/returns',         label: '+ مرتجع',       icon: RotateCcw,      navigateTo: '/purchases/returns/new',        permission: 'procurement.returns.create'     },
  // ── Activities Module ──
  { path: '/activities',                label: '+ نشاط',        icon: Activity,       navigateTo: '/activities/new',               permission: 'activities.create'              },
  { path: '/activities/list',           label: '+ نشاط',        icon: Activity,       navigateTo: '/activities/new',               permission: 'activities.create'              },
  { path: '/activities/visit-plans',    label: '+ خطة زيارة',   icon: MapPin,         navigateTo: '/activities/visit-plans/new',   permission: 'visit_plans.create'             },
  { path: '/activities/call-plans',     label: '+ خطة مكالمات', icon: Phone,          navigateTo: '/activities/call-plans/new',    permission: 'call_plans.create'              },
  // Pages below use inline-modal creation (no /new route exists) — they manage their own FAB locally:
  // /inventory/transfers → TransfersPage modal   (tr-fab)
  // /inventory/adjustments → AdjustmentsPage modal
  // /finance/expenses → ExpensesPage modal   (mobile-fab)
  // /finance/vaults, /finance/payments, /finance/journals → modal FABs
]

/**
 * A pathname qualifies as a "form route" when:
 *  • it ends with /new   — creation form
 *  • it contains /edit   — edit form
 *  • its last segment is a UUID — detail / form page
 *
 * On form routes: FAB is completely removed from DOM (not just opacity-hidden).
 * This prevents the "aria-hidden on focused element" console warning and
 * eliminates any transition window where the button could be briefly visible.
 */
const UUID_RE = /\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(\/.*)?$/i

function isFormRoute(pathname: string): boolean {
  return (
    pathname.endsWith('/new') ||
    pathname.includes('/edit') ||
    UUID_RE.test(pathname)
  )
}

export default function FAB() {
  const navigate    = useNavigate()
  const location    = useLocation()
  const can         = useAuthStore(s => s.can)
  const isModalOpen = useIsAnyModalOpen()

  // Scroll-direction: hide FAB when scrolling down, show on scroll-up
  const [scrollHidden, setScrollHidden] = useState(false)
  const lastScrollY = useRef(0)
  useEffect(() => {
    const onScroll = () => {
      const y = window.scrollY
      setScrollHidden(y > lastScrollY.current && y > 100)
      lastScrollY.current = y
    }
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  // ── Guard 1: No matching list page or no permission
  // longest-prefix matching: نأخذ المسار الأطول الذي يبدأ به pathname الحالي
  const config = FAB_MAP
    .filter(c => location.pathname.startsWith(c.path))
    .sort((a, b) => b.path.length - a.path.length)[0]
  if (!config || !can(config.permission)) return null

  // ── Guard 2: User is already on a form or detail page — unmount entirely.
  //    We do NOT use opacity-hide here, because:
  //    a) the button would still be in DOM and could be briefly visible during transition
  //    b) setting aria-hidden on a focused button triggers an accessibility warning
  if (isFormRoute(location.pathname)) return null

  // ── Guard 3: Modal open or scrolling down — CSS-based soft-hide (smooth UX)
  //    The button isn't typically focused in these states so no aria concern.
  const softHidden = isModalOpen || scrollHidden

  const Icon = config.icon

  // Styles live in components.css (.fab, .fab--hidden, .fab-label, @keyframes fab-enter)
  return (
    <button
      className={`fab${softHidden ? ' fab--hidden' : ''}`}
      onClick={() => navigate(config.navigateTo)}
      // Do NOT use aria-hidden — causes "aria-hidden on focused element" warning.
      // tabIndex=-1 prevents keyboard focus while the button is visually hidden.
      tabIndex={softHidden ? -1 : 0}
      type="button"
      title={config.label}
    >
      <Icon size={22} />
      <span className="fab-label">{config.label}</span>
    </button>
  )
}
