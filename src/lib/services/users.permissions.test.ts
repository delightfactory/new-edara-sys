import { beforeEach, describe, expect, it, vi } from 'vitest'
import { supabase } from '@/lib/supabase/client'
import {
  getUserPermissionContext,
  setUserRoles,
  setUserAccessAtomic,
  setUserPermissionOverrides,
  updateUserWithAccessAtomic,
} from '@/lib/services/users'
import { getAuthUserId } from '@/lib/services/_get-user-id'

vi.mock('@/lib/supabase/client', () => ({
  supabase: {
    rpc: vi.fn(),
    from: vi.fn(),
  },
}))

vi.mock('@/lib/services/_get-user-id', () => ({
  getAuthUserId: vi.fn(),
}))

describe('user permission override services', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('loads inherited permissions, per-role permissions and overrides', async () => {
    const context = {
      inherited_permissions: ['sales.orders.read'],
      has_wildcard: false,
      role_permissions_by_role: { 'role-1': ['sales.orders.read'] },
      overrides: [{
        id: 'override-1',
        user_id: 'user-2',
        permission: 'sales.orders.confirm',
        granted: true,
        granted_by: 'admin-1',
        reason: 'مؤقت',
        expires_at: null,
        created_at: '2026-07-26T10:00:00.000Z',
      }],
    }
    vi.mocked(supabase.rpc).mockResolvedValueOnce({ data: context, error: null } as never)

    await expect(getUserPermissionContext('user-2')).resolves.toEqual(context)
    expect(supabase.rpc).toHaveBeenCalledWith('get_user_permission_context', {
      p_target_user_id: 'user-2',
    })
  })

  it('normalizes an empty permission context response', async () => {
    vi.mocked(supabase.rpc).mockResolvedValueOnce({ data: null, error: null } as never)

    await expect(getUserPermissionContext('user-2')).resolves.toEqual({
      inherited_permissions: [],
      has_wildcard: false,
      role_permissions_by_role: {},
      overrides: [],
    })
  })

  it('sends the complete override set to the atomic RPC', async () => {
    const overrides = [{
      permission: 'finance.view_costs',
      granted: false,
      reason: 'سرية التكلفة',
      expires_at: null,
    }]
    vi.mocked(supabase.rpc).mockResolvedValueOnce({
      data: { saved_count: 1, changed: true },
      error: null,
    } as never)

    await expect(setUserPermissionOverrides('user-2', overrides)).resolves.toEqual({
      saved_count: 1,
      changed: true,
    })
    expect(supabase.rpc).toHaveBeenCalledWith('set_user_permission_overrides', {
      p_target_user_id: 'user-2',
      p_overrides: overrides,
    })
  })

  it('saves roles and overrides through one access transaction', async () => {
    const overrides = [{
      permission: 'sales.orders.confirm',
      granted: true,
      reason: null,
      expires_at: null,
    }]
    vi.mocked(supabase.rpc).mockResolvedValueOnce({
      data: { saved_count: 1, changed: true },
      error: null,
    } as never)

    await setUserAccessAtomic('user-2', ['role-1'], overrides)

    expect(supabase.rpc).toHaveBeenCalledWith('set_user_access_atomic', {
      p_target_user_id: 'user-2',
      p_role_ids: ['role-1'],
      p_overrides: overrides,
    })
  })

  it('preserves the established setUserRoles RPC name and parameter contract', async () => {
    vi.mocked(getAuthUserId).mockResolvedValueOnce('admin-1')
    vi.mocked(supabase.rpc).mockResolvedValueOnce({ data: null, error: null } as never)

    await setUserRoles('user-2', ['role-1'])

    expect(supabase.rpc).toHaveBeenCalledWith('set_user_roles_atomic', {
      p_target_user_id: 'user-2',
      p_role_ids: ['role-1'],
      p_user_id: 'admin-1',
    })
  })

  it('updates profile and access through one database transaction', async () => {
    vi.mocked(supabase.rpc).mockResolvedValueOnce({
      data: { saved_count: 0, changed: true },
      error: null,
    } as never)

    await updateUserWithAccessAtomic(
      'user-2',
      { full_name: 'مستخدم تجريبي', phone: null },
      ['role-1'],
      null,
    )

    expect(supabase.rpc).toHaveBeenCalledWith('update_user_with_access_atomic', {
      p_target_user_id: 'user-2',
      p_full_name: 'مستخدم تجريبي',
      p_phone: null,
      p_role_ids: ['role-1'],
      p_overrides: null,
    })
  })

  it('propagates database authorization errors without masking them', async () => {
    const error = { message: 'ليس لديك صلاحية إدارة صلاحيات المستخدمين' }
    vi.mocked(supabase.rpc).mockResolvedValueOnce({ data: null, error } as never)

    await expect(getUserPermissionContext('user-2')).rejects.toBe(error)
  })
})
