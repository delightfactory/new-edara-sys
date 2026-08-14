import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const foundation = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814113000_work_management_approvals_foundation.sql',
), 'utf8')
const runtime = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814114000_work_management_approval_runtime.sql',
), 'utf8')
const templates = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814114500_work_management_approval_templates.sql',
), 'utf8')
const completion = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814115000_work_management_completion_approval_bridge.sql',
), 'utf8')

describe('work approval engine contract', () => {
  it('uses immutable published versions and ordered stages', () => {
    expect(foundation).toContain('work_approval_template_versions')
    expect(foundation).toContain('work_approval_stages')
    expect(foundation).toContain('work_block_published_approval_version_mutation')
    expect(foundation).toContain('published approval versions are immutable')
    expect(foundation).toContain('UNIQUE(template_version_id,stage_order)')
  })

  it('supports sequential stages with all/any decisions', () => {
    expect(foundation).toContain("CREATE TYPE public.work_approval_stage_mode AS ENUM ('all','any')")
    expect(runtime).toContain('min(stage_order)')
    expect(runtime).toContain("v_stage.decision_mode='any'")
    expect(runtime).toContain('stage_order>v_stage.stage_order')
    expect(runtime).toContain('private.work_activate_approval_stage')
  })

  it('resolves concrete approvers and specific delegator-to-delegate authority', () => {
    expect(foundation).toContain('work_approval_selector_kind')
    expect(foundation).toContain('work_approval_delegations')
    expect(foundation).toContain('delegator_user_id=p_original_approver_user_id')
    expect(runtime).toContain('original_approver_user_id')
    expect(runtime).toContain('effective_approver_user_id')
    expect(runtime).toContain('acting_for_user_id')
  })

  it('records every decision through the Work timeline', () => {
    expect(runtime).toContain("'work.approval.decision'")
    expect(runtime).toContain('private.work_append_user_event')
    expect(runtime).toContain('v_acting_for')
  })

  it('binds completion approval to the generic engine', () => {
    expect(completion).toContain("v_item.completion_mode='approval'")
    expect(completion).toContain('private.work_start_approval_request')
    expect(completion).toContain("'completion'")
    expect(completion).not.toContain('APPROVAL_RUNTIME_NOT_READY')
    expect(runtime).toContain("v_request.context_kind='completion'")
  })

  it('supports due-date approval without silently changing the due date', () => {
    expect(runtime).toContain('public.work_request_due_change')
    expect(runtime).toContain("p_context_kind='due_change'")
    expect(runtime).toContain("v_request.context_kind='due_change'")
    const requestFn = runtime.indexOf('CREATE OR REPLACE FUNCTION public.work_request_due_change')
    const dueUpdate = runtime.indexOf('SET due_at=v_new_due')
    expect(requestFn).toBeGreaterThan(-1)
    expect(dueUpdate).toBeLessThan(requestFn)
  })

  it('authors new versions instead of mutating published definitions', () => {
    expect(templates).toContain('public.work_create_approval_template_version')
    expect(templates).toContain('private.work_insert_approval_version_from_definition')
    expect(templates).toContain('public.work_publish_approval_template_version')
    expect(templates).toContain('current_published_version_id')
  })
})
