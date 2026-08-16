import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const read = (path: string) => readFileSync(resolve(process.cwd(), path), 'utf8')

describe('work management functional closure contract', () => {
  it('keeps the proven detail page intact and composes closure capabilities', () => {
    const wrapper = read('src/pages/work/WorkDetailPage.tsx')
    const extensions = read('src/pages/work/WorkDetailExtensions.tsx')
    const administration = read('src/pages/work/WorkDetailAdministration.tsx')

    expect(wrapper).toContain("import WorkDetailCorePage from './WorkDetailCorePage'")
    expect(wrapper).toContain('<WorkDetailCorePage />')
    expect(wrapper).toContain('<WorkDetailExtensions item={itemQuery.data} />')
    expect(wrapper).toContain('<WorkDetailAdministration item={itemQuery.data} />')
    expect(extensions).toContain("setModal('cancel')")
    expect(extensions).toContain("setModal('reopen')")
    expect(extensions).toContain("setModal('checklist')")
    expect(extensions).toContain("setModal('dependency')")
    expect(extensions).toContain("setModal('link')")
    expect(administration).toContain("setModal('delegate')")
    expect(administration).toContain("setModal('transfer')")
    expect(administration).toContain("setModal('due')")
    expect(administration).toContain("setModal('subtask')")
    expect(administration).toContain("setModal('participant')")
  })

  it('uses atomic server commands for lifecycle, collaboration, assignment and links', () => {
    const extensionApi = read('src/features/work/extensions-api.ts')
    const administrationApi = read('src/features/work/administration-api.ts')

    expect(extensionApi).toContain("executeAtomic<WorkItemMutationResult>('work_cancel'")
    expect(extensionApi).toContain("executeAtomic<WorkItemMutationResult>('work_reopen'")
    expect(extensionApi).toContain("'work_add_checklist_item'")
    expect(extensionApi).toContain("'work_add_dependency'")
    expect(extensionApi).toContain("'work_resolve_dependency'")
    expect(extensionApi).toContain("'work_add_link'")
    expect(extensionApi).toContain("'work_remove_link'")
    expect(administrationApi).toContain("'work_delegate'")
    expect(administrationApi).toContain("'work_transfer_ownership'")
    expect(administrationApi).toContain("'work_change_due'")
    expect(administrationApi).toContain("'work_create_subtask'")
    expect(administrationApi).toContain("'work_set_participant'")
    expect(administrationApi).toContain("'work_escalate'")
    expect(administrationApi).toContain("'work_resolve_escalation'")
    expect(extensionApi).not.toContain(".from('work_links').insert")
    expect(extensionApi).not.toContain(".from('work_links').delete")
  })

  it('closes entity links server-side without granting linked-entity access', () => {
    const migration = read('supabase/migrations/20260814135000_work_management_functional_closure.sql')

    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.work_add_link')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.work_remove_link')
    expect(migration).toContain('private.work_link_entity_exists')
    expect(migration).toContain("'public.customers'")
    expect(migration).toContain("'public.sales_orders'")
    expect(migration).toContain("'public.payment_receipts'")
    expect(migration).toContain("'public.purchase_invoices'")
    expect(migration).toContain("'public.activities'")
    expect(migration).toContain("'public.targets'")
    expect(migration).not.toContain('GRANT SELECT ON public.customers')
  })

  it('uses a server-filtered people directory for participants and responsibility changes', () => {
    const migration = read('supabase/migrations/20260814135500_work_management_item_people_directory.sql')
    const api = read('src/features/work/administration-api.ts')

    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.work_list_item_people_candidates')
    expect(migration).toContain('private.work_user_can_assign_target(v_actor,p.id)')
    expect(migration).toContain("v_purpose='delegate'")
    expect(migration).toContain("v_purpose='transfer_owner'")
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.work_list_participants')
    expect(api).toContain("supabase.rpc('work_list_item_people_candidates'")
    expect(api).toContain("supabase.rpc('work_list_participants'")
  })

  it('publishes only the Work runtime tables required by detail realtime refresh', () => {
    const migration = read('supabase/migrations/20260814135000_work_management_functional_closure.sql')
    const ui = read('src/pages/work/WorkDetailExtensions.tsx')

    for (const table of ['work_items', 'work_events', 'work_comments', 'work_checklist_items', 'work_attachments', 'work_links', 'work_dependencies']) {
      expect(migration).toContain(`'${table}'`)
      expect(ui).toContain(`table: '${table}'`)
    }
    expect(migration).toContain("pubname='supabase_realtime'")
  })
})
