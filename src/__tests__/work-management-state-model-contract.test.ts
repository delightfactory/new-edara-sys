import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260813194600_work_management_state_model_correction.sql',
), 'utf8')

describe('work management state model contract', () => {
  it('keeps only the approved canonical lifecycle states', () => {
    for (const status of [
      'draft',
      'open',
      'in_progress',
      'waiting',
      'pending_approval',
      'done',
      'cancelled',
    ]) {
      expect(migration).toContain(`'${status}'`)
    }
  })

  it('does not keep blocked/internal/external waiting as canonical statuses', () => {
    expect(migration).toContain("WHEN 'waiting_internal' THEN 'waiting'")
    expect(migration).toContain("WHEN 'waiting_external' THEN 'waiting'")
    expect(migration).toContain("WHEN 'blocked' THEN 'open'")
    expect(migration).toContain('Operational flags such as blocked/overdue/stale are computed separately')
  })
})
