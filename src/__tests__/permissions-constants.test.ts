/**
 * permissions-constants.test.ts
 * Regression test for EA-DOM-01:
 *   SALES_ORDERS_UPDATE must exist in PERMISSIONS and PERMISSION_GROUPS
 *   so the role editor UI can assign it.
 * Regression test for EA-NOTIF-01:
 *   NOTIFICATIONS_DISPATCH must exist in PERMISSIONS and PERMISSION_GROUPS
 *   so the role editor UI can assign it.
 */
import { describe, it, expect } from 'vitest'
import { PERMISSIONS, PERMISSION_GROUPS } from '@/lib/permissions/constants'

describe('PERMISSIONS constants', () => {
  it('defines SALES_ORDERS_UPDATE', () => {
    expect(PERMISSIONS.SALES_ORDERS_UPDATE).toBeDefined()
    expect(PERMISSIONS.SALES_ORDERS_UPDATE).toBe('sales.orders.update')
  })

  it('SALES_ORDERS_UPDATE appears in PERMISSION_GROUPS under "sales"', () => {
    const salesGroup = PERMISSION_GROUPS.find(g => g.id === 'sales')
    expect(salesGroup).toBeDefined()
    const keys = salesGroup!.permissions.map(p => p.key)
    expect(keys).toContain(PERMISSIONS.SALES_ORDERS_UPDATE)
  })

  it('defines NOTIFICATIONS_DISPATCH', () => {
    expect(PERMISSIONS.NOTIFICATIONS_DISPATCH).toBeDefined()
    expect(PERMISSIONS.NOTIFICATIONS_DISPATCH).toBe('notifications.dispatch')
  })

  it('NOTIFICATIONS_DISPATCH appears in PERMISSION_GROUPS under "notifications"', () => {
    const notificationsGroup = PERMISSION_GROUPS.find(g => g.id === 'notifications')
    expect(notificationsGroup).toBeDefined()
    const keys = notificationsGroup!.permissions.map(p => p.key)
    expect(keys).toContain(PERMISSIONS.NOTIFICATIONS_DISPATCH)
  })

  it('all values in PERMISSIONS are unique strings', () => {
    const values = Object.values(PERMISSIONS)
    const unique  = new Set(values)
    // Except known aliases (TARGETS_READ = TARGETS_READ_TEAM)
    const knownAliasCount = 1
    expect(values.length - unique.size).toBeLessThanOrEqual(knownAliasCount)
  })

  it('no PERMISSION_GROUPS entry references an undefined PERMISSIONS key', () => {
    const allValues = new Set(Object.values(PERMISSIONS))
    for (const group of PERMISSION_GROUPS) {
      for (const perm of group.permissions) {
        expect(allValues.has(perm.key), `${perm.key} not in PERMISSIONS`).toBe(true)
      }
    }
  })
})
