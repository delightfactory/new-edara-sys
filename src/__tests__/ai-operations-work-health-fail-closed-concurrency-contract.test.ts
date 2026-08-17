import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817008600_ai_operations_work_health_fail_closed_concurrency.sql',
), 'utf8')

describe('AI Operations Work Health fail-closed and concurrency hardening', () => {
  it('fails snapshot/capture closed when native Work operational settings are missing', () => {
    expect(migration).toContain('SELECT 1 FROM public.work_operational_settings s WHERE s.singleton=true')
    expect(migration).toContain('Work operational settings are missing; Work Health capture fails closed')
    expect(migration).toContain('Work operational settings are missing; operational snapshot fails closed')
    expect(migration).toContain('refresh_work_health_cases_pre_settings_guard_v1')
    expect(migration).toContain('build_operational_snapshot_pre_work_health_settings_guard_v1')
  })

  it('serializes recovery commits by source Work across different decisions/runs', () => {
    expect(migration).toContain("'ai_ops:work-health-source:'||v_source_work_id::TEXT")
    expect(migration).toContain('pg_advisory_xact_lock')
    expect(migration).toContain('work_create_ai_reviewed_work_health_task_pre_source_lock_v1')
    expect(migration).toContain("WHERE d.id=p_decision_id AND sc.domain='work_health'")
  })

  it('keeps all new wrappers private from generic API roles', () => {
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.refresh_work_health_cases(UUID,DATE,INTEGER)')
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.build_operational_snapshot(UUID,INTEGER)')
    expect(migration).toContain('REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_work_health_task(UUID,UUID)')
    expect(migration).toContain('FROM PUBLIC,anon,authenticated,service_role')
  })
})
