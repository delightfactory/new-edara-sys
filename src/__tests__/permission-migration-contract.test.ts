import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { PERMISSIONS } from '@/lib/permissions/constants'

const migrationPath = resolve(
  process.cwd(),
  'supabase/migrations/20260726131028_user_permission_overrides_management.sql',
)
const migration = readFileSync(migrationPath, 'utf8')

describe('individual permission migration contract', () => {
  it('hardens every privileged function with an empty search path', () => {
    const privilegedFunctions = [
      'get_user_permissions',
      'get_my_permission_denials',
      'get_user_permission_context',
      'set_user_permission_overrides',
      'set_user_roles_atomic',
      'set_user_access_atomic',
      'update_user_with_access_atomic',
    ]

    for (const functionName of privilegedFunctions) {
      const functionStart = migration.indexOf(
        `CREATE OR REPLACE FUNCTION public.${functionName}(`,
      )
      expect(functionStart, `${functionName} definition is missing`).toBeGreaterThanOrEqual(0)
      const functionEnd = migration.indexOf('$$;', functionStart)
      const definition = migration.slice(functionStart, functionEnd)
      expect(definition, `${functionName} must be SECURITY DEFINER`).toContain('SECURITY DEFINER')
      expect(definition, `${functionName} must use an empty search_path`).toContain("SET search_path = ''")
    }
  })

  it('allows every frontend permission constant in the atomic RPC', () => {
    const match = migration.match(
      /v_known_permissions CONSTANT TEXT\[\] := ARRAY\[([\s\S]*?)\n  \];/,
    )
    expect(match, 'known-permission allowlist was not found').not.toBeNull()

    const allowed = new Set(
      [...match![1].matchAll(/'([^']+)'/g)].map(item => item[1]),
    )
    for (const permission of new Set(Object.values(PERMISSIONS))) {
      if (permission === '*') continue
      expect(allowed.has(permission), `${permission} missing from SQL allowlist`).toBe(true)
    }
  })

  it('restricts privileged RPC execution and blocks direct browser writes', () => {
    expect(migration).toContain(
      'REVOKE ALL ON FUNCTION public.set_user_permission_overrides(UUID, JSONB) FROM PUBLIC',
    )
    expect(migration).toContain(
      'GRANT EXECUTE ON FUNCTION public.set_user_permission_overrides(UUID, JSONB) TO authenticated',
    )
    expect(migration).toContain(
      'REVOKE ALL ON TABLE public.user_permission_overrides FROM anon, authenticated',
    )
    expect(migration).toContain(
      'GRANT SELECT ON TABLE public.user_permission_overrides TO authenticated',
    )
    expect(migration).not.toMatch(
      /GRANT\s+(?:INSERT|UPDATE|DELETE|TRUNCATE)[^;]*user_permission_overrides[^;]*authenticated/i,
    )
    expect(migration).toContain(
      "public.check_permission(v_actor, 'auth.user_permissions.manage')",
    )
    expect(migration).toContain(
      'REVOKE ALL ON FUNCTION public.set_user_access_atomic(UUID, UUID[], JSONB) FROM PUBLIC',
    )
  })

  it('blocks self-escalation and enforces the role hierarchy in database functions', () => {
    expect(migration).toContain('IF p_target_user_id = p_user_id THEN')
    expect(migration).toContain('IF p_target_user_id = v_actor THEN')
    expect(migration).toContain(
      'IF v_current_target_grade >= v_actor_grade OR v_requested_grade >= v_actor_grade THEN',
    )
    expect(migration).toContain('IF v_target_grade >= v_actor_grade THEN')
  })

  it('keeps the established permission RPC positive-only and exposes denies separately', () => {
    const establishedFunctionStart = migration.indexOf(
      'CREATE OR REPLACE FUNCTION public.get_user_permissions(',
    )
    const establishedFunctionEnd = migration.indexOf('$$;', establishedFunctionStart)
    const establishedFunction = migration.slice(establishedFunctionStart, establishedFunctionEnd)
    expect(establishedFunction).not.toContain("SELECT '!' || upo.permission")

    expect(migration).toContain(
      'CREATE OR REPLACE FUNCTION public.get_my_permission_denials()',
    )
    expect(migration).toContain("SELECT '!' || upo.permission")
    expect(migration).toContain('AND upo.granted = false')
    expect(migration).toContain(
      'GRANT EXECUTE ON FUNCTION public.get_my_permission_denials() TO authenticated',
    )
  })

  it('preserves trusted backend access to the existing permission RPC', () => {
    expect(migration).toContain(
      'GRANT EXECUTE ON FUNCTION public.get_user_permissions(UUID) TO service_role',
    )
    expect(migration).toContain("COALESCE(auth.jwt()->>'role', '') <> 'service_role'")
  })

  it('preserves unchanged role assignments and audits real role changes', () => {
    expect(migration).toContain(
      'CREATE OR REPLACE FUNCTION public.set_user_roles_atomic(',
    )
    expect(migration).toContain('p_user_id UUID DEFAULT auth.uid()')
    expect(migration).toContain(
      'GRANT EXECUTE ON FUNCTION public.set_user_roles_atomic(UUID, UUID[], UUID) TO service_role',
    )
    expect(migration).not.toContain(
      'DELETE FROM public.user_roles WHERE user_id = p_target_user_id;',
    )
    expect(migration).toContain('Apply only the role delta')
    expect(migration).toContain("'user_roles.updated'")
    expect(migration).toContain("'assigned_by', ur.assigned_by")
    expect(migration).toContain("'branch_id', ur.branch_id")
  })

  it('provides a restricted all-or-nothing profile and access RPC', () => {
    expect(migration).toContain(
      'CREATE OR REPLACE FUNCTION public.update_user_with_access_atomic(',
    )
    expect(migration).toContain(
      'REVOKE ALL ON FUNCTION public.update_user_with_access_atomic(UUID, TEXT, TEXT, UUID[], JSONB) FROM PUBLIC',
    )
    expect(migration).toContain(
      'GRANT EXECUTE ON FUNCTION public.update_user_with_access_atomic(UUID, TEXT, TEXT, UUID[], JSONB) TO authenticated',
    )
    expect(migration).toContain('FROM (')
    expect(migration).toContain(') role_delta')
    expect(migration).toContain(
      'PERFORM public.set_user_roles_atomic(p_target_user_id, p_role_ids, v_actor);',
    )
  })
})
