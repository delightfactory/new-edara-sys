import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const foundation = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814120000_work_management_workflow_foundation.sql',
), 'utf8')
const authoring = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814120500_work_management_workflow_authoring.sql',
), 'utf8')
const runtime = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814121500_work_management_workflow_runtime.sql',
), 'utf8')
const hardening = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814121600_work_management_workflow_runtime_hardening.sql',
), 'utf8')

const dynamicSqlExecute = /(?:^|\n)\s*EXECUTE\b/i

describe('work workflow engine contract', () => {
  it('pins every run to an immutable published version', () => {
    expect(foundation).toContain('template_version_id UUID NOT NULL REFERENCES public.work_workflow_template_versions')
    expect(foundation).toContain('published workflow versions are immutable')
    expect(authoring).toContain('current_published_version_id')
    expect(runtime).toContain('VALUES(v_version.id,p_parent_work_item_id')
  })

  it('supports task and approval steps with explicit dependencies', () => {
    expect(foundation).toContain("CREATE TYPE public.work_workflow_step_kind AS ENUM ('task','approval')")
    expect(foundation).toContain('work_workflow_step_dependencies')
    expect(runtime).toContain("v_def.step_kind='task'")
    expect(hardening).toContain('private.work_start_approval_request')
  })

  it('rejects dependency cycles before publication/runtime', () => {
    expect(authoring).toContain('private.work_workflow_version_has_cycle')
    expect(authoring).toContain("RAISE EXCEPTION 'workflow contains a dependency cycle'")
    expect(authoring).toContain("'WORKFLOW_CYCLE'")
  })

  it('uses a bounded JSON condition DSL and no dynamic SQL', () => {
    expect(authoring).toContain('private.work_validate_workflow_condition_dsl')
    for (const op of ['always', 'eq', 'ne', 'exists', 'in', 'all', 'any', 'not']) {
      expect(authoring).toContain(`'${op}'`)
    }
    expect(authoring).not.toMatch(dynamicSqlExecute)
    expect(runtime).not.toMatch(dynamicSqlExecute)
  })

  it('enforces structured outputs for workflow task steps', () => {
    expect(foundation).toContain('output_schema JSONB')
    expect(runtime).toContain('private.work_validate_intake_payload(v_def.output_schema')
    expect(runtime).toContain('trg_work_validate_workflow_completion')
  })

  it('uses a non-recursive SECURITY DEFINER workflow visibility helper', () => {
    expect(authoring).toContain('private.work_user_can_view_workflow_run')
    expect(authoring).toContain('CREATE POLICY work_workflow_runs_select')
    expect(authoring).toContain('CREATE POLICY work_workflow_step_instances_select')
    expect(authoring).not.toContain('si.workflow_run_id=id AND si.work_item_id')
  })

  it('hardens activation before runtime use and uses the canonical meaningful activity column', () => {
    expect(hardening).toContain('CREATE OR REPLACE FUNCTION private.work_activate_workflow_step')
    expect(hardening).toContain('last_meaningful_activity_at')
    expect(hardening).not.toContain('last_meaning_activity_at')
    expect(hardening).toContain('workflow step definition/version mismatch')
  })
})
