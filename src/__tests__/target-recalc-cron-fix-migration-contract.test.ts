import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260801103132_fix_target_recalc_cron_overload_ambiguity.sql',
), 'utf8')

describe('target recalculation cron fix migration contract', () => {
  it('removes only the redundant zero-argument overload', () => {
    expect(migration).toContain('DROP FUNCTION IF EXISTS public.recalculate_all_active_targets();')
    expect(migration).not.toMatch(/DROP\s+FUNCTION[^;]*\(date\)/i)
    expect(migration).not.toMatch(/CREATE\s+OR\s+REPLACE\s+FUNCTION/i)
  })

  it('refuses cleanup unless the canonical date overload and its default exist', () => {
    expect(migration).toContain("pg_get_function_identity_arguments(p.oid) = 'p_snapshot_date date'")
    expect(migration).toContain('IF v_canonical_oid IS NULL THEN')
    expect(migration).toContain('IF v_default_count <> 1 THEN')
  })

  it('verifies that exactly one overload remains without changing cron configuration', () => {
    expect(migration).toContain('IF v_overload_count <> 1 THEN')
    expect(migration).not.toMatch(/cron\.(?:schedule|unschedule|alter_job)/i)
    expect(migration).not.toMatch(/UPDATE\s+cron\./i)
  })
})
