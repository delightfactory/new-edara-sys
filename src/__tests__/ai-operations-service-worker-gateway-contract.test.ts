import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(process.cwd(),'supabase/migrations/20260817010000_ai_operations_service_worker_gateway.sql'),'utf8')

describe('AI Operations service worker gateway', () => {
  it('is service-role only and exposes bounded protocol without operational commit', () => {
    expect(migration).toContain('ai_ops_worker_claim_next_run')
    expect(migration).toContain('ai_ops_worker_get_context')
    expect(migration).toContain('ai_ops_worker_stage_decisions')
    expect(migration).toContain('ai_ops_worker_validate_staged_run')
    expect(migration).toContain('TO service_role')
    expect(migration).toContain('FROM PUBLIC,anon,authenticated')
    expect(migration).not.toContain('ai_ops_commit_reviewed_decision')
  })
})
