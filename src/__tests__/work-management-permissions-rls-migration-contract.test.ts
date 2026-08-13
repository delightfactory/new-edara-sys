import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const permissions = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260813195500_work_management_permissions.sql',
), 'utf8')

const rls = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260813195600_work_management_read_rls.sql',
), 'utf8')

const hierarchyHardening = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260813195700_work_management_read_rls_hierarchy_hardening.sql',
), 'utf8')

describe('work management permissions and read RLS contract', () => {
  it('seeds the existing RBAC model by role name without UUIDs or grade hierarchy', () => {
    expect(permissions).toContain('INSERT INTO public.role_permissions(role_id, permission)')
    expect(permissions).toContain('JOIN public.roles r ON r.name = pm.role_name')
    expect(permissions).toContain('ON CONFLICT (role_id, permission) DO NOTHING')
    expect(permissions).not.toMatch(/'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'/i)
    expect(permissions).not.toContain('.grade')
  })

  it('keeps own, team, all and confidential visibility explicit', () => {
    for (const permission of [
      'work.items.read_own',
      'work.items.read_team',
      'work.items.read_all',
      'work.items.read_restricted',
      'work.items.read_private',
    ]) {
      expect(`${permissions}\n${rls}`).toContain(permission)
    }
  })

  it('separates assignment authority from team operation authority', () => {
    expect(permissions).toContain("'work.items.assign'")
    expect(permissions).toContain("'work.items.manage_team'")
    expect(permissions).toContain("('sales_supervisor', 'work.items.manage_team')")
    expect(permissions).toContain("('branch_manager', 'work.items.manage_team')")
    expect(permissions).toContain("('hr_manager', 'work.items.manage_team')")
  })

  it('derives browser identity from auth.uid and rejects inactive profiles', () => {
    expect(rls).toContain('auth.uid()')
    expect(rls).toContain("p.status::TEXT = 'active'")
    expect(rls).toContain("SET search_path = ''")
  })

  it('uses real branch, department and manager relationships for team scope', () => {
    expect(rls).toContain('b.manager_id = p_user_id')
    expect(rls).toContain('dc.manager_id = p_user_id')
    expect(rls).toContain('manager.id = mc.direct_manager_id')
    expect(rls).toContain('NOT manager.id = ANY(mc.path)')
  })

  it('requires active manager records in the hardened hierarchy resolver', () => {
    expect(hierarchyHardening).toContain("manager.status::TEXT = 'active'")
    expect(hierarchyHardening).toContain("manager_profile.status::TEXT = 'active'")
    expect(hierarchyHardening).toContain('The target employee may be inactive')
  })

  it('requires visibility to both sides before exposing a dependency', () => {
    expect(rls).toMatch(
      /work_dependencies_select_visible[\s\S]*blocked_work_item_id\)[\s\S]*AND private\.work_current_user_can_view_item\(blocker_work_item_id\)/,
    )
  })

  it('keeps browser writes closed until the atomic RPC migration', () => {
    expect(rls).not.toMatch(/FOR\s+(INSERT|UPDATE|DELETE|ALL)/i)
    expect(rls).not.toMatch(/GRANT\s+[^;]*(INSERT|UPDATE|DELETE)[^;]*TO authenticated/i)
  })
})
