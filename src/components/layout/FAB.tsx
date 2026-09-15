import { useNavigate, useLocation } from 'react-router-dom'
import { useEffect, useRef, useState } from 'react'
import {
  ShoppingCart, UserPlus, Package,
  RotateCcw, Activity, MapPin, Phone,
  Users, Target,
} from 'lucide-react'
import { useAuthStore } from '@/stores/auth-store'
import { useIsAnyModalOpen } from '@/hooks/useModalStack'
import { findCreationAction } from '@/navigation/resolvers'

const iconByActionId = {
  'new-sales-order': ShoppingCart,
  'new-sales-return': RotateCcw,
  'new-customer': UserPlus,
  'new-supplier': Users,
  'new-product': Package,
  'new-purchase-invoice': Package,
  'new-purchase-return': RotateCcw,
  'new-activity': Activity,
  'new-activity-dashboard': Activity,
  'new-visit-plan': MapPin,
  'new-call-plan': Phone,
  'new-target': Target,
} as const

/**
 * A pathname qualifies as a form/detail route when:
 *  • it ends with /new
 *  • it contains /edit
 *  • its last segment is a UUID
 *
 * On these routes the global FAB is removed from the DOM entirely.
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
  const navigate = useNavigate()
  const location = useLocation()
  const can = useAuthStore(s => s.can)
  const canAny = useAuthStore(s => s.canAny)
  const isModalOpen = useIsAnyModalOpen()

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

  const action = findCreationAction(location.pathname, { can, canAny })
  if (!action) return null

  if (isFormRoute(location.pathname)) return null

  const softHidden = isModalOpen || scrollHidden
  const Icon = iconByActionId[action.id as keyof typeof iconByActionId]
  if (!Icon) return null

  return (
    <button
      className={`fab${softHidden ? ' fab--hidden' : ''}`}
      onClick={() => navigate(action.navigateTo)}
      tabIndex={softHidden ? -1 : 0}
      type="button"
      title={action.label}
    >
      <Icon size={22} />
      <span className="fab-label">{action.label}</span>
    </button>
  )
}
