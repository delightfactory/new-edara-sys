import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const read = (path: string) => readFileSync(resolve(process.cwd(), path), 'utf8')
const normalizeWhitespace = (value: string) => value.replace(/\s+/g, ' ').trim()

const migrationPath = 'supabase/migrations/20260815001000_work_management_governance_continuity.sql'

describe('work management governance and continuity closure', () => {
  it('enforces due-date extensions through Approval Engine on the server', () => {
    const migration = read(migrationPath)
    const api = read('src/features/work/due-governance-api.ts')
    const ui = read('src/pages/work/WorkDueGovernance.tsx')

    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.work_change_due')
    expect(migration).toContain("'APPROVAL_REQUIRED'")
    expect(migration).toContain("'DUE_CHANGE_APPROVAL_PENDING'")
    expect(migration).toContain('p_new_due_at>v_item.due_at')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.work_request_due_change')
    expect(migration).toContain("'NOT_DUE_EXTENSION'")
    expect(api).toContain("executeAtomic<WorkDueExtensionResult>('work_request_due_change'")
    expect(api).toContain('p_approval_template_id: input.approvalTemplateId')
    expect(ui).toContain('طلب تمديد الموعد')
    expect(ui).toContain('الموعد الحالي لم يتغير بعد')
    expect(ui).toContain('new Date(iso).getTime() <= new Date(item.due_at!).getTime()')
  })

  it('fails closed for deactivated HR employees while preserving non-HR system users', () => {
    const migration = read(migrationPath)
    const compact = normalizeWhitespace(migration)

    expect(migration).toContain('CREATE OR REPLACE FUNCTION private.work_user_is_available_for_work')
    expect(migration).toContain("e.status::TEXT='active'")
    expect(compact).toContain('NOT EXISTS ( SELECT 1 FROM public.hr_employees e WHERE e.user_id=p_user_id')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION private.work_actor_is_active')
    expect(migration).toContain('OR NOT private.work_user_is_available_for_work(p_target_user_id)')
  })

  it('surfaces orphaned live responsibilities and bulk reassigns them atomically', () => {
    const migration = read(migrationPath)
    const api = read('src/features/work/continuity-api.ts')
    const ui = read('src/pages/work/management/WorkContinuityPanel.tsx')
    const management = read('src/pages/work/management/WorkManagementPage.tsx')

    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.work_list_orphaned_assignments')
    expect(migration).toContain("public.check_permission(v_actor,'work.items.manage')")
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.work_bulk_reassign_orphaned')
    expect(migration).toContain("'SOURCE_STILL_ACTIVE'")
    expect(migration).toContain("'INVALID_REPLACEMENT'")
    expect(migration).toContain('state_version=state_version+1')
    expect(migration).toContain("'work.ownership_transferred'")
    expect(migration).toContain("'work.delegated'")
    expect(migration).toContain("'source','inactive_user_continuity'")
    expect(api).toContain("supabase.rpc('work_list_orphaned_assignments')")
    expect(api).toContain("executeAtomic<WorkContinuityResult>('work_bulk_reassign_orphaned'")
    expect(ui).toContain('استمرارية الأعمال')
    expect(ui).toContain('إعادة إسناد كل الأعمال المفتوحة')
    expect(management).toContain("id: 'continuity' as const")
    expect(management).toContain("permission: 'work.items.manage'")
    expect(management).toContain("activeTab === 'continuity'")
  })

  it('keeps historical identity immutable during continuity repair', () => {
    const migration = read(migrationPath)
    const bulkStart = migration.indexOf('CREATE OR REPLACE FUNCTION public.work_bulk_reassign_orphaned')
    const bulkBody = normalizeWhitespace(migration.slice(bulkStart))

    expect(bulkBody).toContain('accountable_owner_user_id=CASE WHEN v_changed_owner')
    expect(bulkBody).toContain('current_assignee_user_id=CASE WHEN v_changed_assignee')
    expect(bulkBody).not.toContain('creator_user_id=')
    expect(bulkBody).not.toContain('requester_user_id=')
  })
})
