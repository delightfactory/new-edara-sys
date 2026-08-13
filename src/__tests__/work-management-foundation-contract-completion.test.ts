import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260813194500_work_management_foundation_contract.sql',
), 'utf8')

describe('work management foundation contract completion', () => {
  it('adds source lineage and recurrence identity without premature foreign keys', () => {
    expect(migration).toContain('CREATE TYPE public.work_source_kind AS ENUM')
    expect(migration).toContain("ADD COLUMN source_kind public.work_source_kind NOT NULL DEFAULT 'manual'")
    expect(migration).toContain('ADD COLUMN source_key TEXT')
    expect(migration).toContain('ADD COLUMN request_type_id UUID')
    expect(migration).toContain('ADD COLUMN recurrence_occurrence_id UUID')
    expect(migration).toContain('work_items_source_key_uniq')
    expect(migration).toContain('work_items_recurrence_occurrence_uniq')
    expect(migration).not.toContain('REFERENCES public.work_request_types')
    expect(migration).not.toContain('REFERENCES public.work_recurrence_occurrences')
  })

  it('upgrades optimistic concurrency and waiting clocks to the reviewed contract', () => {
    expect(migration).toMatch(/ALTER COLUMN state_version TYPE BIGINT/)
    expect(migration).toContain('ADD COLUMN start_not_before TIMESTAMPTZ')
    expect(migration).toContain('ADD COLUMN waiting_on_label VARCHAR(250)')
    expect(migration).toContain('ADD COLUMN waiting_since TIMESTAMPTZ')
    expect(migration).toMatch(/ALTER COLUMN next_action_text TYPE VARCHAR\(500\)/)
  })

  it('keeps one active participant row per user and preserves comment capability', () => {
    expect(migration).toContain('ADD COLUMN can_comment BOOLEAN NOT NULL DEFAULT true')
    expect(migration).toContain('DROP INDEX public.work_participants_active_role_uniq')
    expect(migration).toContain('work_participants_active_user_uniq')
    expect(migration).toContain('ON public.work_participants(work_item_id, user_id)')
    expect(migration).toContain('WHERE removed_at IS NULL')
  })

  it('makes operation and delegated-actor lineage first-class in the timeline', () => {
    expect(migration).toContain('ADD COLUMN acting_for_user_id UUID')
    expect(migration).toContain('ADD COLUMN operation_id UUID')
    expect(migration).toContain('ADD COLUMN client_event_at TIMESTAMPTZ')
    expect(migration).toContain('idx_work_events_operation')
    expect(migration).toContain('idx_work_events_type_created')
  })

  it('separates dependency timing from hard or soft blocking strength', () => {
    expect(migration).toContain('CREATE TYPE public.work_dependency_strength AS ENUM')
    expect(migration).toContain("'hard'")
    expect(migration).toContain("'soft'")
    expect(migration).toContain("ADD COLUMN dependency_strength public.work_dependency_strength NOT NULL DEFAULT 'hard'")
    expect(migration).toContain('ADD COLUMN resolution_reason TEXT')
  })

  it('classifies attachment intent for evidence and outputs', () => {
    expect(migration).toContain('CREATE TYPE public.work_attachment_purpose AS ENUM')
    expect(migration).toContain("'reference'")
    expect(migration).toContain("'evidence'")
    expect(migration).toContain("'output'")
    expect(migration).toContain("ADD COLUMN purpose public.work_attachment_purpose NOT NULL DEFAULT 'reference'")
  })
})
