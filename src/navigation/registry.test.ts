import { describe, expect, it } from 'vitest'
import {
  CREATION_ACTIONS,
  MOBILE_PRIMARY_DESTINATION_IDS,
  NAVIGATION_DESTINATIONS,
} from './registry'
import {
  canShowNavigation,
  findCreationAction,
  getMobilePrimaryDestinations,
} from './resolvers'

const allowAll = {
  can: () => true,
  canAny: () => true,
}

const denyAll = {
  can: () => false,
  canAny: () => false,
}

describe('navigation registry', () => {
  it('keeps destination ids unique', () => {
    const ids = NAVIGATION_DESTINATIONS.map(item => item.id)
    expect(new Set(ids).size).toBe(ids.length)
  })

  it('keeps destination paths unique except intentionally shared roots are represented once', () => {
    const paths = NAVIGATION_DESTINATIONS.map(item => item.path)
    expect(new Set(paths).size).toBe(paths.length)
  })

  it('keeps the mobile primary set intentionally small', () => {
    expect(MOBILE_PRIMARY_DESTINATION_IDS).toHaveLength(4)
    expect(getMobilePrimaryDestinations(allowAll).map(item => item.id)).toEqual([
      'dashboard',
      'work',
      'sales-orders',
      'customers',
    ])
  })

  it('filters permission-bound mobile destinations without changing order', () => {
    const evaluator = {
      can: (permission: string) => permission === 'customers.read',
      canAny: (permissions: string[]) => permissions.includes('customers.read'),
    }

    expect(getMobilePrimaryDestinations(evaluator).map(item => item.id)).toEqual([
      'dashboard',
      'customers',
    ])
  })

  it('uses any-of semantics for permission arrays', () => {
    expect(canShowNavigation(['one', 'two'], {
      can: () => false,
      canAny: permissions => permissions.includes('two'),
    })).toBe(true)
    expect(canShowNavigation(['one', 'two'], denyAll)).toBe(false)
  })

  it('uses longest-path matching for creation actions', () => {
    const visitAction = findCreationAction('/activities/visit-plans', allowAll)
    expect(visitAction?.id).toBe('new-visit-plan')

    const targetsAction = findCreationAction('/activities/targets', allowAll)
    expect(targetsAction?.id).toBe('new-target')
  })

  it('does not surface an unauthorized creation action', () => {
    expect(findCreationAction('/sales/orders', denyAll)).toBeNull()
  })

  it('keeps creation action ids unique', () => {
    const ids = CREATION_ACTIONS.map(item => item.id)
    expect(new Set(ids).size).toBe(ids.length)
  })
})
