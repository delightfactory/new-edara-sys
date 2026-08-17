import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817009300_ai_operations_shared_reviewed_work_source_guard.sql',
), 'utf8')

describe('AI Operations shared reviewed-work source guard', () => {
  it('defines one cross-domain source serialization invariant', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION private.ai_ops_lock_reviewed_source_work')
    expect(migration).toContain("'ai_ops:reviewed-work-source:'||p_source_work_id::TEXT")
    expect(migration).toContain('pg_advisory_xact_lock')
  })

  it('uses the same shared source lock for Work Health and HR Availability commits', () => {
    expect(migration).toContain('work_create_ai_reviewed_work_health_task_pre_shared_source_guard_v1')
    expect(migration).toContain('work_create_ai_reviewed_hr_availability_task_pre_shared_source_guard_v1')
    expect(migration.match(/PERFORM private\.ai_ops_lock_reviewed_source_work\(v_source_work_id\);/g)).toHaveLength(2)
  })

  it('uses one active-remediation predicate across both domains', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION private.ai_ops_has_active_reviewed_source_remediation')
    expect(migration).toContain("remediation.metadata->>'ai_domain' IN ('work_health','hr_availability')")
    expect(migration).toContain("remediation.status::TEXT NOT IN ('done','cancelled')")
    expect(migration).toContain("'active_coverage_or_work_health_recovery_collision_now'")
  })

  it('makes Work Health validation symmetric with the already cross-aware HR guard', () => {
    expect(migration).toContain('current_work_health_decision_issues_pre_cross_domain_remediation_v1')
    expect(migration).toContain('private.ai_ops_has_active_reviewed_source_remediation(\n       v_source_work_id,v_committed_work_item_id\n     )')
  })

  it('acquires the shared lock before delegating to either preserved commit implementation', () => {
    const workHealthWrapper = migration.slice(
      migration.indexOf('CREATE OR REPLACE FUNCTION private.work_create_ai_reviewed_work_health_task('),
      migration.indexOf('-- Apply the identical shared source lock'),
    )
    const hrWrapper = migration.slice(
      migration.indexOf('CREATE OR REPLACE FUNCTION private.work_create_ai_reviewed_hr_availability_task('),
      migration.indexOf('COMMENT ON FUNCTION private.ai_ops_lock_reviewed_source_work'),
    )

    expect(workHealthWrapper.indexOf('PERFORM private.ai_ops_lock_reviewed_source_work')).toBeGreaterThan(-1)
    expect(workHealthWrapper.indexOf('PERFORM private.ai_ops_lock_reviewed_source_work'))
      .toBeLessThan(workHealthWrapper.indexOf('work_create_ai_reviewed_work_health_task_pre_shared_source_guard_v1'))
    expect(hrWrapper.indexOf('PERFORM private.ai_ops_lock_reviewed_source_work')).toBeGreaterThan(-1)
    expect(hrWrapper.indexOf('PERFORM private.ai_ops_lock_reviewed_source_work'))
      .toBeLessThan(hrWrapper.indexOf('work_create_ai_reviewed_hr_availability_task_pre_shared_source_guard_v1'))
  })

  it('keeps all shared-guard helpers and wrappers private from generic API roles', () => {
    expect(migration).toContain('REVOKE ALL ON FUNCTION private.ai_ops_lock_reviewed_source_work(UUID)')
    expect(migration).toContain('REVOKE ALL ON FUNCTION private.ai_ops_has_active_reviewed_source_remediation(UUID,UUID)')
    expect(migration).toContain('REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_work_health_task(UUID,UUID)')
    expect(migration).toContain('REVOKE ALL ON FUNCTION private.work_create_ai_reviewed_hr_availability_task(UUID,UUID)')
    expect(migration).toContain('FROM PUBLIC,anon,authenticated,service_role')
  })
})
