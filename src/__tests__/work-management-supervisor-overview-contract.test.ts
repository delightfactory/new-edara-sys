import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814134500_work_management_supervisor_overview.sql',
), 'utf8')

describe('work supervisor overview contract', () => {
  it('requires team/all/manage-team authority before returning rows', () => {
    expect(migration).toContain("'work.items.read_team'")
    expect(migration).toContain("'work.items.read_all'")
    expect(migration).toContain("'work.items.manage_team'")
  })

  it('reuses row visibility rules instead of widening supervisor access', () => {
    expect(migration).toContain('private.work_user_can_view_row(')
    expect(migration).toContain('w.visibility,w.creator_user_id,w.requester_user_id')
    expect(migration).not.toContain("w.visibility<>'private'")
  })

  it('returns only operational context and not sensitive descriptions or payloads', () => {
    expect(migration).toContain('w.title')
    expect(migration).toContain('w.next_action_text')
    expect(migration).not.toContain('w.description')
    expect(migration).not.toContain('completion_output')
    expect(migration).not.toContain('metadata')
  })

  it('carries operational flags and optimistic-lock versions', () => {
    for (const flag of ['is_blocked', 'is_overdue', 'is_stale', 'is_at_risk', 'is_escalated', 'is_follow_up_due']) {
      expect(migration).toContain(flag)
    }
    expect(migration).toContain('w.state_version')
  })

  it('caps result size and supports server-side attention filtering', () => {
    expect(migration).toContain('LEAST(GREATEST(COALESCE(p_limit,300),1),500)')
    expect(migration).toContain('p_attention_only BOOLEAN DEFAULT false')
    expect(migration).toContain('p_assignee_user_id UUID DEFAULT NULL')
  })
})
