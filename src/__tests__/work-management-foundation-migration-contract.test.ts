import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260813193000_work_management_foundation.sql',
), 'utf8')

const tables = [
  'work_items',
  'work_participants',
  'work_comments',
  'work_mentions',
  'work_events',
  'work_checklist_items',
  'work_dependencies',
  'work_links',
  'work_attachments',
] as const

describe('work management foundation migration contract', () => {
  it('creates the complete Migration A table set', () => {
    for (const table of tables) {
      expect(migration).toContain(`CREATE TABLE public.${table}`)
      expect(migration).toContain(`ALTER TABLE public.${table} ENABLE ROW LEVEL SECURITY;`)
    }
  })

  it('keeps the reviewed responsibility, next-action and completion fields', () => {
    expect(migration).toContain('accountable_owner_user_id UUID')
    expect(migration).toContain('current_assignee_user_id UUID')
    expect(migration).toContain('next_action_text TEXT')
    expect(migration).toContain('next_action_at TIMESTAMPTZ')
    expect(migration).toContain('expected_outcome TEXT')
    expect(migration).toContain('completion_summary TEXT')
    expect(migration).toContain('blocks_parent_completion BOOLEAN NOT NULL DEFAULT true')
  })

  it('tracks assignment receipt separately from meaningful activity', () => {
    expect(migration).toContain('assigned_at TIMESTAMPTZ')
    expect(migration).toContain('first_viewed_at TIMESTAMPTZ')
    expect(migration).toContain('acknowledged_at TIMESTAMPTZ')
    expect(migration).toContain('last_meaningful_activity_at TIMESTAMPTZ')
  })

  it('binds mentions and attachments to their Work Item', () => {
    expect(migration).toContain('work_mentions_comment_same_item_fk')
    expect(migration).toContain('work_attachments_comment_same_item_fk')
    expect(migration).toContain("storage_path LIKE ('work/' || work_item_id::TEXT || '/%')")
  })

  it('installs the key operational indexes', () => {
    expect(migration).toContain('idx_work_items_assignee_status')
    expect(migration).toContain('idx_work_items_owner_status')
    expect(migration).toContain('idx_work_items_status_due')
    expect(migration).toContain('idx_work_items_status_next_action')
    expect(migration).toContain('idx_work_events_item_cursor')
    expect(migration).toContain('idx_work_dependencies_blocked_open')
    expect(migration).toContain('idx_work_items_title_trgm')
  })

  it('does not create premature foreign keys to later Work modules', () => {
    expect(migration).not.toContain('queue_id UUID REFERENCES public.work_queues')
    expect(migration).not.toContain('workflow_run_id UUID REFERENCES public.work_workflow_runs')
    expect(migration).not.toContain('policy_id UUID REFERENCES public.work_policies')
  })
})
