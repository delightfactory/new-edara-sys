import { NAVIGATION_DESTINATIONS, type NavigationDestination, type NavigationPermission } from './registry'
import { canShowNavigation, type PermissionEvaluator } from './resolvers'

interface MobilePrimaryItem {
  destinationId: string
  permission?: NavigationPermission
}

/**
 * Mobile-specific visibility contract preserved from the current BottomNav.
 * The destination itself still comes from the shared registry; this list only
 * captures the intentionally stricter mobile shortcut visibility rules.
 */
export const MOBILE_PRIMARY_ITEMS: MobilePrimaryItem[] = [
  { destinationId: 'dashboard' },
  { destinationId: 'work', permission: ['work.items.read_own', 'work.items.read_team', 'work.items.read_all'] },
  { destinationId: 'sales-orders', permission: 'sales.orders.read' },
  { destinationId: 'customers', permission: 'customers.read' },
]

export function getVisibleMobilePrimaryDestinations(
  evaluator: PermissionEvaluator,
): NavigationDestination[] {
  const destinations = new Map(NAVIGATION_DESTINATIONS.map(item => [item.id, item]))

  return MOBILE_PRIMARY_ITEMS
    .filter(item => canShowNavigation(item.permission, evaluator))
    .map(item => destinations.get(item.destinationId))
    .filter((item): item is NavigationDestination => Boolean(item))
}
