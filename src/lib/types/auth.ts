export type UserStatus = 'active' | 'inactive' | 'suspended'

export interface Profile {
  id: string
  full_name: string
  email: string | null
  phone: string | null
  avatar_url: string | null
  status: UserStatus
  last_login_at: string | null
  created_at: string
  updated_at: string
}

export interface Role {
  id: string
  name: string
  name_ar: string
  description: string | null
  is_system: boolean
  color: string
  created_at: string
}

export interface RolePermission {
  id: string
  role_id: string
  permission: string
}

export interface UserRole {
  id: string
  user_id: string
  role_id: string
  branch_id: string | null
  is_active: boolean
  assigned_by: string | null
  assigned_at: string
  role?: Role
}

export interface UserPermissionOverride {
  id: string
  user_id: string
  permission: string
  granted: boolean
  granted_by: string
  reason: string | null
  expires_at: string | null
  created_at: string
}

export interface MyProfile extends Profile {
  roles: Pick<Role, 'id' | 'name' | 'name_ar' | 'color'>[]
  permissions: string[]
}

export interface CompanySetting {
  key: string
  value: string
  type: 'text' | 'number' | 'boolean' | 'json'
  description: string | null
  category: string
  is_public: boolean
  updated_by: string | null
  updated_at: string
}

export interface AuditLog {
  id: string
  user_id: string | null
  action: string
  entity_type: string
  entity_id: string | null
  old_data: Record<string, unknown> | null
  new_data: Record<string, unknown> | null
  ip_address: string | null
  user_agent: string | null
  created_at: string
  profile?: Pick<Profile, 'id' | 'full_name' | 'avatar_url'>
}

// User with roles for admin pages
export interface UserWithRoles extends Profile {
  user_roles: (UserRole & { role: Role })[]
}
