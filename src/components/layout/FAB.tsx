import { useNavigate, useLocation } from 'react-router-dom'
import { useEffect, useRef, useState } from 'react'
import {
  Plus, ShoppingCart, UserPlus, Package, ArrowLeftRight,
  Receipt, RotateCcw,
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
  { path: '/sales/orders',        label: '+ طلب بيع', icon: ShoppingCart,   navigateTo: '/sales/orders/new',        permission: 'sales.orders.create'         },
  { path: '/customers',           label: '+ عميل',    icon: UserPlus,       navigateTo: '/customers/new',           permission: 'customers.create'            },
  { path: '/purchases/invoices',  label: '+ فاتورة',  icon: Package,        navigateTo: '/purchases/invoices/new',  permission: 'procurement.invoices.create' },
  { path: '/purchases/returns',   label: '+ مرتجع',   icon: RotateCcw,      navigateTo: '/purchases/returns/new',   permission: 'procurement.returns.create'  },
  { path: '/inventory/transfers', label: '+ تحويل',   icon: ArrowLeftRight, navigateTo: '/inventory/transfers/new', permission: 'inventory.transfers.create'  },
  { path: '/finance/expenses',    label: '+ مصروف',   icon: Receipt,        navigateTo: '/finance/expenses/new',    permission: 'finance.expenses.create'     },
  // Vaults, Payments, Journals use inline modals — they have their own smart local FABs
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
  const config = FAB_MAP.find(c => location.pathname.startsWith(c.path))
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

      <style>{`
        /* Hidden on desktop by default */
        .fab { display: none; }

        @media (max-width: 768px) {
          .fab {
            display: flex;
            align-items: center;
            gap: var(--space-2);
            position: fixed;
            bottom: calc(var(--bottom-nav-height) + var(--space-4));
            inset-inline-end: var(--space-4);
            z-index: var(--z-fab);
            height: var(--fab-size);
            padding: 0 var(--space-4);
            border-radius: var(--radius-full);
            background: var(--color-primary);
            color: white;
            border: none;
            cursor: pointer;
            font-family: var(--font-sans);
            font-size: var(--text-sm);
            font-weight: 700;
            box-shadow: var(--shadow-lg);
            animation: fab-enter 0.3s cubic-bezier(0.34, 1.56, 0.64, 1) both;
            transition: opacity 0.2s ease, transform 0.2s ease;
            -webkit-tap-highlight-color: transparent;
          }

          /* Soft-hide: modal open OR scroll direction down */
          .fab--hidden {
            opacity: 0;
            transform: translateY(14px) scale(0.9);
            pointer-events: none;
          }

          .fab:not(.fab--hidden):active {
            transform: scale(0.95);
          }

          .fab-label { white-space: nowrap; }

          @keyframes fab-enter {
            from { opacity: 0; transform: scale(0.6) translateY(8px); }
            to   { opacity: 1; transform: scale(1)   translateY(0);   }
          }
        }
      `}</style>
    </button>
  )
}
