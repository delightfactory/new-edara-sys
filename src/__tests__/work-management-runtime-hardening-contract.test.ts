import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const blockedHardening = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814130100_work_management_operational_flag_hardening.sql',
), 'utf8')
const settingsRls = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814130200_work_management_operational_settings_rls_hardening.sql',
), 'utf8')
const storage = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814131500_work_management_attachment_storage.sql',
), 'utf8')
const runtimeApi = readFileSync(resolve(
  process.cwd(),
  'src/features/work/runtime-api.ts',
), 'utf8')
const runtimeHooks = readFileSync(resolve(
  process.cwd(),
  'src/features/work/runtime-hooks.ts',
), 'utf8')

describe('work runtime hardening contract', () => {
  it('keeps blocker identity hidden while preserving the blocked boolean', () => {
    expect(blockedHardening).toContain('private.work_item_has_open_blocker')
    expect(blockedHardening).toContain('private.work_operational_item_is_blocked')
    expect(blockedHardening).toContain('private.work_current_user_can_view_item(p_work_item_id)')
    expect(blockedHardening).toContain('THEN private.work_item_has_open_blocker(p_work_item_id)')
    expect(blockedHardening).not.toContain('blocker.title')
    expect(blockedHardening).not.toContain('blocker.work_number')
  })

  it('keeps browser-visible operational views security-invoker', () => {
    expect(blockedHardening).toContain('WITH (security_invoker=true)')
  })

  it('does not expose arbitrary-user activity checks through RLS', () => {
    expect(settingsRls).toContain('private.work_current_user_is_active()')
    expect(settingsRls).toContain('private.work_actor_is_active(auth.uid())')
    expect(settingsRls).toContain('GRANT EXECUTE ON FUNCTION private.work_current_user_is_active() TO authenticated')
    expect(settingsRls).not.toContain('p_user_id UUID')
  })

  it('requires active metadata before a stored attachment can be read', () => {
    expect(storage).toContain("a.storage_bucket='work-attachments'")
    expect(storage).toContain('a.storage_path=name')
    expect(storage).toContain('a.removed_at IS NULL')
  })

  it('allows physical cleanup retry after logical removal without reopening metadata', () => {
    const deletePolicy = storage.slice(storage.indexOf('work_attachments_storage_delete'))
    expect(deletePolicy).toContain('owner_id=(select auth.uid())::TEXT')
    expect(deletePolicy).not.toContain('a.removed_at IS NULL')
  })

  it('uses atomic RPC commands instead of direct work table mutations in the client', () => {
    expect(runtimeApi).toContain("supabase.rpc('work_get_action_inbox'")
    expect(runtimeApi).toContain("executeAtomic<WorkItemMutationResult>('work_create_task'")
    expect(runtimeApi).toContain("executeAtomic<WorkItemMutationResult>('work_acknowledge'")
    expect(runtimeApi).toContain("executeAtomic<WorkItemMutationResult>('work_start'")
    expect(runtimeApi).not.toContain(".from('work_items').update(")
    expect(runtimeApi).not.toContain(".from('work_items').insert(")
  })

  it('compensates failed attachment metadata writes and hides soft-removed files first', () => {
    expect(runtimeApi).toContain(".upload(storagePath, input.file, { upsert: false")
    expect(runtimeApi).toContain("'work_add_attachment_metadata'")
    const removeStart = runtimeApi.indexOf('export async function removeWorkAttachment')
    const removeFlow = runtimeApi.slice(removeStart)
    expect(removeFlow.indexOf("'work_remove_attachment_metadata'")).toBeLessThan(removeFlow.indexOf(".remove([input.storagePath])"))
  })

  it('invalidates the full Work query family after runtime mutations', () => {
    expect(runtimeHooks).toContain('queryClient.invalidateQueries({ queryKey: workKeys.all })')
  })
})
