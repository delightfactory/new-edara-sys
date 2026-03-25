import { supabase } from '@/lib/supabase/client'
import type { Profile, UserWithRoles, Role, UserRole, UserPermissionOverride } from '@/lib/types/auth'

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
    .select('*', { count: 'exact' })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.search) {
    query = query.or(`full_name.ilike.%${params.search}%,email.ilike.%${params.search}%`)
  }
  if (params?.status) {
    query = query.eq('status', params.status)
  }

  const { data: profiles, error, count } = await query
  if (error) throw error

  // جلب أدوار كل المستخدمين المحملين
  const userIds = (profiles || []).map(p => p.id)
  let userRolesData: any[] = []
  if (userIds.length > 0) {
    const { data: ur } = await supabase
      .from('user_roles')
      .select('id, user_id, role_id, branch_id, is_active, assigned_at')
      .in('user_id', userIds)
      .eq('is_active', true)

    userRolesData = ur || []
  }

  // جلب كل الأدوار
  const { data: allRoles } = await supabase.from('roles').select('*')
  const rolesMap = new Map((allRoles || []).map(r => [r.id, r]))

  // دمج البيانات
  let users = (profiles || []).map(p => ({
    ...p,
    user_roles: userRolesData
      .filter(ur => ur.user_id === p.id)
      .map(ur => ({ ...ur, role: rolesMap.get(ur.role_id) || null })),
  })) as unknown as UserWithRoles[]

  // فلترة بالدور على العميل
  if (params?.role) {
    users = users.filter(u =>
      u.user_roles?.some(ur => ur.role?.name === params.role)
    )
  }

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

  const { data: allRoles } = await supabase.from('roles').select('*')
  const rolesMap = new Map((allRoles || []).map(r => [r.id, r]))

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
  // حذف الأدوار الحالية
  const { error: delErr } = await supabase
    .from('user_roles')
    .delete()
    .eq('user_id', userId)
  if (delErr) throw delErr

  // إضافة الأدوار الجديدة
  if (roleIds.length > 0) {
    const { error: insErr } = await supabase
      .from('user_roles')
      .insert(roleIds.map(rid => ({ user_id: userId, role_id: rid })))
    if (insErr) throw insErr
  }
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

  return data as Role
}

/**
 * تحديث دور وصلاحياته
 */
export async function updateRole(roleId: string, role: { name_ar?: string; description?: string; color?: string }, permissions: string[]) {
  const { error } = await supabase
    .from('roles')
    .update({
      name_ar: role.name_ar,
      description: role.description,
      color: role.color,
    })
    .eq('id', roleId)
  if (error) throw error

  // حذف الصلاحيات القديمة وإضافة الجديدة
  const { error: delErr } = await supabase
    .from('role_permissions')
    .delete()
    .eq('role_id', roleId)
  if (delErr) throw delErr

  if (permissions.length > 0) {
    const { error: permErr } = await supabase
      .from('role_permissions')
      .insert(permissions.map(p => ({ role_id: roleId, permission: p })))
    if (permErr) throw permErr
  }
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
}

/**
 * عدد المستخدمين لكل دور
 */
export async function getRoleUserCounts(): Promise<Record<string, number>> {
  const { data, error } = await supabase
    .from('user_roles')
    .select('role_id')
    .eq('is_active', true)
  if (error) throw error

  const counts: Record<string, number> = {}
  for (const ur of data || []) {
    counts[ur.role_id] = (counts[ur.role_id] || 0) + 1
  }
  return counts
}
