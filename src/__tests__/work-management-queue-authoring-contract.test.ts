import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814134000_work_management_queue_authoring.sql',
), 'utf8')

describe('work queue authoring contract', () => {
  it('versions mutable queue and request-type configuration', () => {
    expect(migration).toContain('ADD COLUMN IF NOT EXISTS state_version BIGINT NOT NULL DEFAULT 1')
    expect(migration).toContain('v_queue.state_version<>p_expected_version')
    expect(migration).toContain('v_type.state_version<>p_expected_version')
    expect(migration).toContain("'VERSION_CONFLICT'")
  })

  it('requires explicit queue-management authority for all configuration writes', () => {
    for (const fn of [
      'work_create_queue',
      'work_update_queue',
      'work_set_queue_member',
      'work_create_request_type',
      'work_update_request_type',
    ]) {
      expect(migration).toContain(`'${fn}'`)
    }
    expect(migration.match(/'work\.queues\.manage'/g)?.length).toBeGreaterThanOrEqual(5)
  })

  it('uses the operation ledger for idempotent configuration commands', () => {
    expect(migration.match(/private\.work_prepare_operation\(/g)?.length).toBeGreaterThanOrEqual(5)
    expect(migration.match(/private\.work_command_success\(/g)?.length).toBeGreaterThanOrEqual(5)
  })

  it('preserves queue membership history instead of overwriting prior authority', () => {
    expect(migration).toContain('SET active_until=v_now WHERE id=v_existing.id')
    expect(migration).toContain('INSERT INTO public.work_queue_members(')
    expect(migration).not.toContain('UPDATE public.work_queue_members\n    SET member_role=')
  })

  it('validates intake schema definitions before publishing request types', () => {
    expect(migration).toContain('private.work_validate_intake_schema_definition')
    expect(migration).toContain("v_type NOT IN ('string','number','boolean','array','object')")
    expect(migration).toContain("'DUPLICATE_FIELD_KEY'")
    expect(migration).toContain("'INVALID_REQUIRED_FLAG'")
  })

  it('keeps request-type department targeting consistent with its queue', () => {
    expect(migration).toContain('v_queue.department_id<>p_target_department_id')
    expect(migration).toContain("'DEPARTMENT_MISMATCH'")
  })

  it('does not grant direct table mutation privileges to browser roles', () => {
    expect(migration).not.toContain('GRANT INSERT ON public.work_queues')
    expect(migration).not.toContain('GRANT UPDATE ON public.work_queues')
    expect(migration).not.toContain('GRANT INSERT ON public.work_request_types')
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.work_create_queue')
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.work_update_request_type')
  })
})
