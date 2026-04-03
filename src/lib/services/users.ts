import { supabase } from '@/lib/supabase/client'
import type { Profile, UserWithRoles, Role, UserRole, UserPermissionOverride } from '@/lib/types/auth'

// ── Roles cache ───────────────────────────────────────────────
// `roles` is reference data that changes rarely; fetching it on every
// getUsers/getUser call is wasteful. Cache with a 5-minute TTL.
const ROLES_CACHE_TTL = 5 * 60 * 1000
let rolesCache: Map<string, Role> | null = null
let rolesCacheTime = 0

async function getRolesMap(): Promise<Map<string, Role>> {
  if (rolesCache && Date.now() - rolesCacheTime < ROLES_CACHE_TTL) {
    return rolesCache
  }
  const { data, error } = await supabase.from('roles').select('*')
  if (error) throw error
  rolesCache = new Map((data || []).map(r => [r.id, r as Role]))
  rolesCacheTime = Date.now()
  return rolesCache
}

/** Invalidate the cache when a role is created/updated/deleted */
export function invalidateRolesCache() {
  rolesCache = null
  rolesCacheTime = 0
}

/**
 * جلب قائمة المستخدمين مع أدوارهم
 */
export async function getUsers(params?: {
  search?: string
  status?: string
  role?: string
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 25
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('profiles')
    .select('*', { count: 'estimated' })
    .order('created_at', { ascending: false })

  if (params?.search) {
    query = query.or(`full_name.ilike.%${params.search}%,email.ilike.%${params.search}%`)
  }
  if (params?.status) {
    query = query.eq('status', params.status)
  }

  // role filter: resolve to user_ids at DB level before pagination so count is accurate
  if (params?.role) {
    const { data: roleRow, error: roleLookupError } = await supabase
      .from('roles')
      .select('id')
      .eq('name', params.role)
      .maybeSingle()
    if (roleLookupError) throw roleLookupError

    if (!roleRow) {
      return { data: [], count: 0, page, pageSize, totalPages: 0 }
    }

    const { data: urRows, error: userRolesLookupError } = await supabase
      .from('user_roles')
      .select('user_id')
      .eq('role_id', roleRow.id)
      .eq('is_active', true)
    if (userRolesLookupError) throw userRolesLookupError

    const roleUserIds = (urRows || []).map(ur => ur.user_id)
    if (roleUserIds.length === 0) {
      return { data: [], count: 0, page, pageSize, totalPages: 0 }
    }
    query = query.in('id', roleUserIds)
  }

  const { data: profiles, error, count } = await query.range(from, to)
  if (error) throw error

  // جلب أدوار كل المستخدمين المحملين
  const pageUserIds = (profiles || []).map(p => p.id)
  let userRolesData: any[] = []
  if (pageUserIds.length > 0) {
    const { data: ur } = await supabase
      .from('user_roles')
      .select('id, user_id, role_id, branch_id, is_active, assigned_at')
      .in('user_id', pageUserIds)
      .eq('is_active', true)

    userRolesData = ur || []
  }

  const rolesMap = await getRolesMap()

  // دمج البيانات
  const users = (profiles || []).map(p => ({
    ...p,
    user_roles: userRolesData
      .filter(ur => ur.user_id === p.id)
      .map(ur => ({ ...ur, role: rolesMap.get(ur.role_id) || null })),
  })) as unknown as UserWithRoles[]

  return {
    data: users,
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

/**
 * جلب مستخدم واحد مع أدواره
 */
export async function getUser(userId: string) {
  const { data: profile, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', userId)
    .single()
  if (error) throw error

  // جلب أدوار المستخدم
  const { data: userRoles } = await supabase
    .from('user_roles')
    .select('id, user_id, role_id, branch_id, is_active, assigned_at')
    .eq('user_id', userId)
    .eq('is_active', true)

  const rolesMap = await getRolesMap()

  return {
    ...profile,
    user_roles: (userRoles || []).map(ur => ({ ...ur, role: rolesMap.get(ur.role_id) || null })),
  } as unknown as UserWithRoles
}

/**
 * تحديث بيانات مستخدم
 */
export async function updateProfile(userId: string, updates: Partial<Profile>) {
  const { error } = await supabase
    .from('profiles')
    .update(updates)
    .eq('id', userId)
  if (error) throw error
}

/**
 * تعطيل / تفعيل مستخدم
 */
export async function toggleUserStatus(userId: string, newStatus: 'active' | 'inactive' | 'suspended') {
  const { error } = await supabase
    .from('profiles')
    .update({ status: newStatus })
    .eq('id', userId)
  if (error) throw error
}

/**
 * تعيين أدوار للمستخدم (يحذف القديمة ويضيف الجديدة)
 */
export async function setUserRoles(userId: string, roleIds: string[]) {
  const currentUserId = (await supabase.auth.getUser()).data.user?.id
  const { error } = await supabase.rpc('set_user_roles_atomic', {
    p_target_user_id: userId,
    p_role_ids: roleIds,
    p_user_id: currentUserId,
  })
  if (error) throw error
}

/**
 * جلب كل الأدوار
 */
export async function getRoles() {
  const { data, error } = await supabase
    .from('roles')
    .select('*')
    .order('created_at')
  if (error) throw error
  return data as Role[]
}

/**
 * جلب دور واحد مع صلاحياته
 */
export async function getRole(roleId: string) {
  const { data: role, error } = await supabase
    .from('roles')
    .select('*')
    .eq('id', roleId)
    .single()
  if (error) throw error

  const { data: perms } = await supabase
    .from('role_permissions')
    .select('id, permission')
    .eq('role_id', roleId)

  return {
    ...role,
    role_permissions: perms || [],
  } as Role & { role_permissions: { id: string; permission: string }[] }
}

/**
 * إنشاء دور جديد
 */
export async function createRole(role: { name: string; name_ar: string; description?: string; color?: string }, permissions: string[]) {
  const { data, error } = await supabase
    .from('roles')
    .insert({
      name: role.name,
      name_ar: role.name_ar,
      description: role.description || null,
      color: role.color || '#6b7280',
    })
    .select()
    .single()
  if (error) throw error

  if (permissions.length > 0) {
    const { error: permErr } = await supabase
      .from('role_permissions')
      .insert(permissions.map(p => ({ role_id: data.id, permission: p })))
    if (permErr) throw permErr
  }

  invalidateRolesCache()
  return data as Role
}

/**
 * تحديث دور وصلاحياته
 */
export async function updateRole(roleId: string, role: { name_ar?: string; description?: string; color?: string }, permissions: string[]) {
  const currentUserId = (await supabase.auth.getUser()).data.user?.id
  const { error } = await supabase.rpc('update_role_atomic', {
    p_role_id: roleId,
    p_name_ar: role.name_ar ?? null,
    p_description: role.description ?? null,
    p_color: role.color ?? null,
    p_permissions: permissions ?? null,
    p_user_id: currentUserId,
  })
  if (error) throw error
  invalidateRolesCache()
}

/**
 * حذف دور (غير نظامي فقط)
 */
export async function deleteRole(roleId: string) {
  const { error } = await supabase
    .from('roles')
    .delete()
    .eq('id', roleId)
  if (error) throw error
  invalidateRolesCache()
}

/**
 * عدد المستخدمين لكل دور
 */
export async function getRoleUserCounts(): Promise<Record<string, number>> {
  const { data, error } = await supabase
    .rpc('get_roles_user_count')
    
  // If no RPC yet, fallback to group query using head+exact or just fetch counts
  // Given we didn't write an RPC for get_roles_user_count, we can do it via REST:
  if (error && error.code === 'PGRST202') { 
    // Fallback: If RPC doesn't exist, we can't do GROUP BY easily with Supabase JS v2 without an RPC. 
    // The previous implementation fetched all. We will just fetch `role_id` and count.
    const { data: fetchAll, error: fetchErr } = await supabase
      .from('user_roles')
      .select('role_id')
      .eq('is_active', true)
    
    if (fetchErr) throw fetchErr
    
    const counts: Record<string, number> = {}
    for (const ur of fetchAll || []) {
      counts[ur.role_id] = (counts[ur.role_id] || 0) + 1
    }
    return counts
  }
  
  if (error) throw error

  const counts: Record<string, number> = {}
  for (const row of data || []) {
    counts[row.role_id] = Number(row.count)
  }
  return counts
}
