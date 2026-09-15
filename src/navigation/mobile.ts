import { NAVIGATION_DESTINATIONS, type NavigationDestination, type NavigationPermission } from './registry'
import { canShowNavigation, type PermissionEvaluator } from './resolvers'

interface MobilePrimaryItem {
  destinationId: string
  label?: string
  permission?: NavigationPermission
}

export interface MobileNavigationDestination extends NavigationDestination {
  mobileLabel: string
}

/**
 * Mobile-specific visibility + compact-label contract preserved from the
 * current BottomNav. Paths still come from the shared navigation registry.
 */
export const MOBILE_PRIMARY_ITEMS: MobilePrimaryItem[] = [
  { destinationId: 'dashboard', label: 'الرئيسية' },
  { destinationId: 'work', label: 'العمل', permission: ['work.items.read_own', 'work.items.read_team', 'work.items.read_all'] },
  { destinationId: 'sales-orders', label: 'المبيعات', permission: 'sales.orders.read' },
  { destinationId: 'customers', label: 'العملاء', permission: 'customers.read' },
]

export function getVisibleMobilePrimaryDestinations(
  evaluator: PermissionEvaluator,
): MobileNavigationDestination[] {
  const destinations = new Map(NAVIGATION_DESTINATIONS.map(item => [item.id, item]))

  return MOBILE_PRIMARY_ITEMS
    .filter(item => canShowNavigation(item.permission, evaluator))
    .map(item => {
      const destination = destinations.get(item.destinationId)
      if (!destination) return null
      return {
        ...destination,
        mobileLabel: item.label ?? destination.label,
      }
    })
    .filter((item): item is MobileNavigationDestination => Boolean(item))
}
