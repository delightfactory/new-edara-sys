import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817010100_ai_operations_worker_deadman.sql',
), 'utf8')

describe('AI Operations worker dead-man', () => {
  it('materializes missing due runs and alerts management without business mutation', () => {
    expect(migration).toContain('v_materialized:=ai_ops.materialize_due_runs(p_now)')
    expect(migration).toContain("public.check_permission(p.id,'work.policies.manage')")
    expect(migration).toContain("'due_run_not_claimed'")
    expect(migration).toContain("'worker_lease_expired'")
    expect(migration).toContain("'worker_run_failed'")
    expect(migration).toContain("'commit_lifecycle_stalled'")
    expect(migration).toContain("'employee_performance_signal',false")
    expect(migration).toContain("'operational_mutation_performed',false")
  })

  it('deduplicates alerts and keeps browser roles away from the health gateway', () => {
    expect(migration).toContain("n.event_key='system.ai_operations.worker_health'")
    expect(migration).toContain('p_notification_cooldown_minutes')
    expect(migration).toContain('FROM PUBLIC,anon,authenticated')
    expect(migration).toContain('TO service_role')
  })

  it('schedules an independent DB dead-man only when pg_cron is actually available', () => {
    expect(migration).toContain("extname='pg_cron'")
    expect(migration).toContain("to_regclass('cron.job') IS NOT NULL")
    expect(migration).toContain("'*/15 * * * *'")
    expect(migration).toContain("'ai-operations-worker-deadman'")
  })
})
