import {
  CREATION_ACTIONS,
  MOBILE_PRIMARY_DESTINATION_IDS,
  NAVIGATION_DESTINATIONS,
  type CreationActionDescriptor,
  type NavigationDestination,
  type NavigationPermission,
} from './registry'

export interface PermissionEvaluator {
  can: (permission: string) => boolean
  canAny: (permissions: string[]) => boolean
}

export function canShowNavigation(
  permission: NavigationPermission | undefined,
  evaluator: PermissionEvaluator,
): boolean {
  if (!permission) return true
  return Array.isArray(permission)
    ? evaluator.canAny(permission)
    : evaluator.can(permission)
}

export function getVisibleNavigationDestinations(
  evaluator: PermissionEvaluator,
): NavigationDestination[] {
  return NAVIGATION_DESTINATIONS.filter(destination =>
    canShowNavigation(destination.permission, evaluator),
  )
}

export function getMobilePrimaryDestinations(
  evaluator: PermissionEvaluator,
): NavigationDestination[] {
  const byId = new Map(NAVIGATION_DESTINATIONS.map(destination => [destination.id, destination]))

  return MOBILE_PRIMARY_DESTINATION_IDS
    .map(id => byId.get(id))
    .filter((destination): destination is NavigationDestination => Boolean(destination))
    .filter(destination => canShowNavigation(destination.permission, evaluator))
}

export function findCreationAction(
  pathname: string,
  evaluator: PermissionEvaluator,
): CreationActionDescriptor | null {
  const candidates = CREATION_ACTIONS
    .filter(action => pathname === action.matchPath || pathname.startsWith(`${action.matchPath}/`))
    .filter(action => evaluator.can(action.permission))
    .sort((a, b) => b.matchPath.length - a.matchPath.length)

  return candidates[0] ?? null
}
