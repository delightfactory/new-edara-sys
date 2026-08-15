import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const read = (path: string) => readFileSync(resolve(process.cwd(), path), 'utf8')
const normalizeWhitespace = (value: string) => value.replace(/\s+/g, ' ').trim()
const migrationPath = 'supabase/migrations/20260815002000_work_management_acceptance_hardening.sql'

describe('work management acceptance hardening', () => {
  it('fixes browser RLS helper execution without granting arbitrary-user authority helpers', () => {
    const migration = read(migrationPath)

    expect(migration).toContain('GRANT USAGE ON SCHEMA private TO authenticated')
    expect(migration).toContain('private.work_current_user_is_queue_member')
    expect(migration).toContain('private.work_current_user_can_triage_queue')
    expect(migration).toContain('private.work_current_user_is_queue_member(id)')
    expect(migration).toContain('private.work_current_user_can_triage_queue(queue_id)')
    expect(migration).not.toContain('GRANT EXECUTE ON FUNCTION private.work_user_is_queue_member(UUID,UUID) TO authenticated')
    expect(migration).not.toContain('GRANT EXECUTE ON FUNCTION private.work_user_can_triage_queue(UUID,UUID) TO authenticated')
  })

  it('lets queue managers inspect inactive queue configuration while normal users remain active-only', () => {
    const migration = read(migrationPath)
    const policyStart = migration.indexOf('CREATE POLICY work_queues_select_visible')
    const nextPolicy = migration.indexOf('CREATE POLICY work_queue_members_select_visible')
    const policy = normalizeWhitespace(migration.slice(policyStart, nextPolicy))

    expect(policy).toContain("public.check_permission(auth.uid(),'work.queues.manage')")
    expect(policy).toContain('OR ( is_active=true AND (')
  })

  it('provides a server-filtered mention directory and sends selected users through the existing atomic comment command', () => {
    const migration = read(migrationPath)
    const api = read('src/features/work/mentions-api.ts')
    const ui = read('src/pages/work/WorkMentionComposer.tsx')
    const detail = read('src/pages/work/WorkDetailPage.tsx')

    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.work_list_mention_candidates')
    expect(migration).toContain('private.work_actor_can_comment_item(v_actor,p_work_item_id)')
    expect(migration).toContain('private.work_user_can_view_row(')
    expect(api).toContain("supabase.rpc('work_list_mention_candidates'")
    expect(ui).toContain('mentionedUserIds: selected.map(person => person.user_id)')
    expect(ui).toContain('حقه في رؤية المهمة')
    expect(detail).toContain('<WorkMentionComposer item={itemQuery.data} />')
  })

  it('downloads private attachments through a short-lived signed URL instead of the direct download API', () => {
    const api = read('src/features/work/detail-api.ts')

    expect(api).toContain('.createSignedUrl(attachment.storage_path, 60')
    expect(api).toContain('download: attachment.original_filename')
    expect(api).toContain('fetch(data.signedUrl')
    expect(api).not.toContain('.download(attachment.storage_path)')
  })

  it('pins local acceptance to the same Node major used by CI', () => {
    const nvmrc = read('.nvmrc').trim()
    const workflow = read('.github/workflows/work-management-ci.yml')
    const runbook = read('docs/work-management/LOCAL_PREMERGE_VALIDATION.md')

    expect(nvmrc).toBe('22')
    expect(workflow).toContain("node-version: '22'")
    expect(runbook).toContain('Node.js **22**')
    expect(runbook).toContain('sanitized local baseline')
  })
})
