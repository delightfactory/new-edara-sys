import { describe, expect, it } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'

const migrationPath = path.resolve(
  process.cwd(),
  'supabase/migrations/20260814124500_work_management_workflow_approval_version_pinning.sql',
)

const sql = fs.readFileSync(migrationPath, 'utf8')

describe('Work Management workflow approval version pinning contract', () => {
  it('stores exact approval versions on workflow definitions and generated work', () => {
    expect(sql).toContain('ADD COLUMN approval_template_version_id UUID')
    expect(sql).toContain('ADD COLUMN completion_approval_template_version_id UUID')
    expect(sql).toContain('work_approval_template_versions(id) ON DELETE RESTRICT')
  })

  it('pins approval versions before a workflow version becomes published', () => {
    expect(sql).toContain('private.work_pin_workflow_approval_versions')
    expect(sql).toContain('private.work_pin_workflow_before_publish')
    expect(sql).toContain('BEFORE UPDATE OF status ON public.work_workflow_template_versions')
    expect(sql).toContain("OLD.status='draft' AND NEW.status='published'")
  })

  it('requires a published approval version when pinning approval steps', () => {
    expect(sql).toContain("av.status='published'")
    expect(sql).toContain('workflow approval step % has no published approval version')
    expect(sql).toContain('workflow task step % has no published completion approval version')
  })

  it('starts workflow approvals by exact version instead of current template version', () => {
    expect(sql).toContain('private.work_start_approval_request_version')
    expect(sql).toContain("WHERE id=p_template_version_id AND status='published'")
    expect(sql).toContain("'pinned_version',true")
    expect(sql).toContain('v_def.approval_template_version_id')
  })

  it('propagates the pinned completion version to generated workflow tasks', () => {
    expect(sql).toContain('completion_approval_template_id,completion_approval_template_version_id')
    expect(sql).toContain('v_def.completion_approval_template_version_id')
    expect(sql).toContain("'workflow_pinned_version',true")
  })

  it('keeps non-workflow approval completion compatible with latest-published behavior', () => {
    expect(sql).toContain('IF v_item.completion_approval_template_version_id IS NOT NULL THEN')
    expect(sql).toContain('private.work_start_approval_request(')
  })

  it('does not grant private workflow approval helpers to clients', () => {
    expect(sql).toContain('REVOKE ALL ON FUNCTION private.work_pin_workflow_approval_versions(UUID)')
    expect(sql).toContain('REVOKE ALL ON FUNCTION private.work_start_approval_request_version')
    expect(sql).toContain('FROM PUBLIC,anon,authenticated,service_role')
  })
})
