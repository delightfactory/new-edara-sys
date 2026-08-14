import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const read = (path: string) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8')

describe('work management functional closure contract', () => {
  it('keeps the proven detail page intact and composes the closure extensions', () => {
    const wrapper = read('pages/work/WorkDetailPage.tsx')
    const extensions = read('pages/work/WorkDetailExtensions.tsx')

    expect(wrapper).toContain("import WorkDetailCorePage from './WorkDetailCorePage'")
    expect(wrapper).toContain('<WorkDetailCorePage />')
    expect(wrapper).toContain('<WorkDetailExtensions item={itemQuery.data} />')
    expect(extensions).toContain("setModal('cancel')")
    expect(extensions).toContain("setModal('reopen')")
    expect(extensions).toContain("setModal('checklist')")
    expect(extensions).toContain("setModal('dependency')")
    expect(extensions).toContain("setModal('link')")
  })

  it('uses atomic server commands for lifecycle, collaboration and links', () => {
    const api = read('features/work/extensions-api.ts')

    expect(api).toContain("executeAtomic<WorkItemMutationResult>('work_cancel'")
    expect(api).toContain("executeAtomic<WorkItemMutationResult>('work_reopen'")
    expect(api).toContain("'work_add_checklist_item'")
    expect(api).toContain("'work_add_dependency'")
    expect(api).toContain("'work_resolve_dependency'")
    expect(api).toContain("'work_add_link'")
    expect(api).toContain("'work_remove_link'")
    expect(api).not.toContain(".from('work_links').insert")
    expect(api).not.toContain(".from('work_links').delete")
  })

  it('closes entity links server-side without granting linked-entity access', () => {
    const migration = read('../supabase/migrations/20260814135000_work_management_functional_closure.sql')

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

  it('publishes only the work runtime tables required by detail realtime refresh', () => {
    const migration = read('../supabase/migrations/20260814135000_work_management_functional_closure.sql')
    const ui = read('pages/work/WorkDetailExtensions.tsx')

    for (const table of ['work_items', 'work_events', 'work_comments', 'work_checklist_items', 'work_attachments', 'work_links', 'work_dependencies']) {
      expect(migration).toContain(`'${table}'`)
      expect(ui).toContain(`table: '${table}'`)
    }
    expect(migration).toContain("pubname='supabase_realtime'")
  })
})
