import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817008700_ai_operations_work_health_snapshot_asof_integrity.sql',
), 'utf8')

describe('AI Operations Work Health snapshot as-of integrity hardening', () => {
  it('wraps the canonical builder without changing the preserved six-domain implementation', () => {
    expect(migration).toContain('RENAME TO build_operational_snapshot_pre_work_health_asof_integrity_v1')
    expect(migration).toContain('build_operational_snapshot_pre_work_health_asof_integrity_v1(')
  })

  it('checks only newly-created builds and never reinterprets idempotent frozen snapshots', () => {
    expect(migration).toContain("IF NOT COALESCE((v_result->>'idempotent_reuse')::BOOLEAN,false) THEN")
  })

  it('binds the zero-completed verification to the exact immutable snapshot data_as_of', () => {
    expect(migration).toContain("v_capture.case_count=0 AND v_capture.capture_status='completed'")
    expect(migration).toContain('ai_ops.work_health_candidates(v_snapshot.data_as_of,1)')
    expect(migration).toContain("v_capture.capture_version<>'work-health-v1'")
  })

  it('fails the whole build closed instead of preserving a false zero-completed capture', () => {
    expect(migration).toContain('Work Health zero-completed capture disagrees with snapshot data_as_of; build fails closed')
    expect(migration).not.toMatch(/UPDATE\s+ai_ops\.snapshot_domain_captures/i)
  })

  it('keeps the new wrapper closed to generic API roles', () => {
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.build_operational_snapshot(UUID,INTEGER)')
    expect(migration).toContain('FROM PUBLIC,anon,authenticated,service_role')
  })
})
