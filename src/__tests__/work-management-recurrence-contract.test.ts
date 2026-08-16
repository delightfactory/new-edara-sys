import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const foundation = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814123000_work_management_recurrence_foundation.sql',
), 'utf8')
const security = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814123100_work_management_recurrence_security.sql',
), 'utf8')
const runtime = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814124000_work_management_recurrence_runtime.sql',
), 'utf8')

describe('work recurrence contract', () => {
  it('separates recurrence definitions from the occurrence ledger', () => {
    expect(foundation).toContain('CREATE TABLE public.work_recurrence_definitions')
    expect(foundation).toContain('CREATE TABLE public.work_recurrence_occurrences')
    expect(foundation).toContain('UNIQUE(recurrence_definition_id,scheduled_for)')
  })

  it('supports daily, weekly and monthly rules including exact and last-day policies', () => {
    expect(foundation).toContain("work_recurrence_frequency AS ENUM ('daily','weekly','monthly')")
    expect(foundation).toContain("work_recurrence_monthly_policy AS ENUM ('exact_day','last_day')")
    expect(foundation).toContain('extract(isodow FROM p_candidate)')
    expect(foundation).toContain("interval '1 month - 1 day'")
  })

  it('supports open-ended and finite recurrence windows', () => {
    expect(foundation).toContain('ends_on DATE')
    expect(foundation).toContain('ends_on IS NULL OR ends_on>=starts_on')
    expect(runtime).toContain("p_action NOT IN ('pause','resume','stop')")
  })

  it('records single-open overlaps without mutating the original due date', () => {
    expect(foundation).toContain("work_recurrence_overlap_policy AS ENUM ('strict','single_open')")
    expect(runtime).toContain("v_definition.overlap_policy='single_open'")
    expect(runtime).toContain("SET status='overlap',overlap_work_item_id=v_existing_work.id")
    const singleOpenStart = runtime.indexOf("v_definition.overlap_policy='single_open'")
    const overlapReturn = runtime.indexOf("'overlap_work_item_id',v_existing_work.id")
    const itemInsert = runtime.indexOf('INSERT INTO public.work_items(', singleOpenStart)
    expect(overlapReturn).toBeGreaterThan(singleOpenStart)
    expect(itemInsert).toBeGreaterThan(overlapReturn)
  })

  it('keeps strict occurrences independent and source-key idempotent', () => {
    expect(runtime).toContain("'task','recurrence','recurrence:'||v_definition.id::TEXT||':'||p_scheduled_for::TEXT")
    expect(foundation).toContain('work_recurrence_occurrence_definition_schedule_uniq')
  })

  it('supports recurring workflows with pinned or latest-published version policy', () => {
    expect(foundation).toContain("work_recurrence_workflow_version_policy AS ENUM ('pinned','latest_published')")
    expect(runtime).toContain("v_definition.workflow_version_policy='pinned'")
    expect(runtime).toContain('current_published_version_id INTO v_workflow_version')
    expect(runtime).toContain('private.work_start_workflow_version_from_recurrence')
  })

  it('avoids recursive RLS between definitions and occurrences', () => {
    expect(security).toContain('private.work_user_can_view_recurrence_definition')
    expect(security).toContain('CREATE POLICY work_recurrence_definitions_select')
    expect(security).toContain('CREATE POLICY work_recurrence_occurrences_select')
  })

  it('exposes compliance counts without hiding failed or overlap cycles', () => {
    expect(runtime).toContain('CREATE OR REPLACE VIEW public.work_recurrence_compliance')
    expect(runtime).toContain("FILTER (WHERE o.status='overlap')")
    expect(runtime).toContain("FILTER (WHERE o.status='failed')")
  })
})
