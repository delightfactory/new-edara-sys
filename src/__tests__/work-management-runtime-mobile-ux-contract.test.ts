import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const read = (path: string) => readFileSync(resolve(process.cwd(), path), 'utf8')

const recurrenceApi = read('src/features/work/recurrence-read-api.ts')
const managementHooks = read('src/features/work/management-hooks.ts')
const recurrenceMigration = read('supabase/migrations/20260815004000_work_management_recurrence_admin_read.sql')
const hub = read('src/pages/work/WorkHubPage.tsx')
const baseWorkCss = read('src/pages/work/work.css')
const polishCss = read('src/pages/work/work-polish.css')
const managementCss = read('src/pages/work/management/work-management.css')
const main = read('src/main.tsx')

describe('work management runtime and mobile UX closure', () => {
  it('loads recurrence management through a permission-gated RPC instead of opening the table', () => {
    expect(recurrenceApi).toContain("supabase.rpc('work_list_recurrence_definitions_admin')")
    expect(recurrenceApi).not.toContain(".from('work_recurrence_definitions')")
    expect(managementHooks).toContain("import { listRecurrenceDefinitionsSecure } from './recurrence-read-api'")
    expect(managementHooks).toContain('queryFn: listRecurrenceDefinitionsSecure')

    expect(recurrenceMigration).toContain('SECURITY DEFINER')
    expect(recurrenceMigration).toContain("public.check_permission(v_actor, 'work.recurrence.manage')")
    expect(recurrenceMigration).toContain('private.work_actor_is_active(v_actor)')
    expect(recurrenceMigration).toContain('REVOKE ALL ON FUNCTION public.work_list_recurrence_definitions_admin() FROM PUBLIC')
    expect(recurrenceMigration).toContain('GRANT EXECUTE ON FUNCTION public.work_list_recurrence_definitions_admin() TO authenticated')
  })

  it('restores all permission-authorized Work entry points on phones', () => {
    expect(hub).toContain("navigate('/work/team')")
    expect(hub).toContain("navigate('/work/manage')")
    expect(hub).toContain('openRequestForm')
    expect(hub).toContain("navigate('/work/new')")
    expect(hub).toContain("can('work.requests.create')")
    expect(hub).toContain("can('work.items.create')")

    // The legacy rule is deliberately overridden by the final mobile polish.
    expect(baseWorkCss).toContain('.work-hero-actions')
    expect(baseWorkCss).toContain('display: none')
    expect(polishCss).toContain('.work-page .work-hero-actions')
    expect(polishCss).toContain('display: grid !important')
    expect(polishCss).toContain('grid-template-columns: repeat(2, minmax(0, 1fr))')
    expect(polishCss).toContain('.work-page .work-mobile-create')
    expect(polishCss).toContain('display: none !important')
  })

  it('keeps the management navigation compact and horizontally reachable on mobile', () => {
    expect(managementCss).toContain('.work-management-tabs')
    expect(polishCss).toContain('.work-management-page .work-management-tabs')
    expect(polishCss).toContain('flex-wrap: nowrap !important')
    expect(polishCss).toContain('overflow-x: auto')
    expect(polishCss).toContain('scroll-snap-type: inline proximity')
    expect(polishCss).toContain('flex-basis: auto !important')
  })

  it('applies Work-specific responsive polish from every direct Work route', () => {
    expect(main).toContain("import './pages/work/work-polish.css'")
    expect(polishCss).toContain('.work-page .work-detail-actions')
    expect(polishCss).toContain('.work-page .work-form-card')
    expect(polishCss).toContain('.work-page .work-responsibility-row')
    expect(polishCss).toContain('.work-management-page .work-management-grid')
  })
})
