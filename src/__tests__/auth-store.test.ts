/**
 * auth-store.test.ts
 * Tests for useAuthStore permission logic (can / canAny / canAll / wildcard)
 */
import { describe, it, expect, beforeEach } from 'vitest'
import { useAuthStore } from '@/stores/auth-store'

beforeEach(() => {
  useAuthStore.getState().reset()
})

describe('useAuthStore.can()', () => {
  it('returns false when no permissions are loaded', () => {
    expect(useAuthStore.getState().can('sales.orders.read')).toBe(false)
  })

  it('returns true when the exact permission is present', () => {
    useAuthStore.getState().setPermissions(['sales.orders.read', 'customers.read'])
    expect(useAuthStore.getState().can('sales.orders.read')).toBe(true)
  })

  it('returns false for a permission that is not present', () => {
    useAuthStore.getState().setPermissions(['sales.orders.read'])
    expect(useAuthStore.getState().can('sales.orders.create')).toBe(false)
  })

  it('wildcard "*" grants every permission', () => {
    useAuthStore.getState().setPermissions(['*'])
    expect(useAuthStore.getState().can('sales.orders.create')).toBe(true)
    expect(useAuthStore.getState().can('auth.users.delete')).toBe(true)
  })

  it('canAny returns true when at least one permission matches', () => {
    useAuthStore.getState().setPermissions(['sales.orders.read'])
    expect(useAuthStore.getState().canAny(['sales.orders.create', 'sales.orders.read'])).toBe(true)
  })

  it('canAll returns false when not all permissions match', () => {
    useAuthStore.getState().setPermissions(['sales.orders.read'])
    expect(useAuthStore.getState().canAll(['sales.orders.read', 'sales.orders.create'])).toBe(false)
  })

  it('reset clears permissions and profile', () => {
    useAuthStore.getState().setPermissions(['*'])
    useAuthStore.getState().setHasSession(true)
    useAuthStore.getState().setProfileLoadError('rpc_error')
    useAuthStore.getState().reset()
    expect(useAuthStore.getState().permissions).toHaveLength(0)
    expect(useAuthStore.getState().profile).toBeNull()
    expect(useAuthStore.getState().hasSession).toBe(false)
    expect(useAuthStore.getState().profileLoadError).toBeNull()
  })
})
