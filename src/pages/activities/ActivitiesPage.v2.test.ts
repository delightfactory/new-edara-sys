import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const sourcePath = fileURLToPath(new URL('./ActivitiesPage.tsx', import.meta.url))
const source = readFileSync(sourcePath, 'utf8')
const stylesheetPath = fileURLToPath(new URL('../../styles/field-activities-v2.css', import.meta.url))
const stylesheet = readFileSync(stylesheetPath, 'utf8')

describe('ActivitiesPage V2 representative list contract', () => {
  it('uses one responsive collection with deliberate Desktop, Tablet and Mobile composition', () => {
    expect(source).toContain("import ResponsiveCollection from '@/components/patterns/ResponsiveCollection'")
    expect(source).toContain('<ResponsiveCollection<ActivityRow>')
    expect(source).toContain('renderDesktop={items => (')
    expect(source).toContain("renderTablet={items => renderActivityCards(items, 'tablet')}")
    expect(source).toContain("renderMobile={items => renderActivityCards(items, 'mobile')}")
    expect(source).not.toContain('dataCardMapping=')
    expect(source).not.toContain('system-mobile-cards')
  })

  it('preserves field query inputs and client-side search semantics exactly at the page boundary', () => {
    expect(source).toContain('typeCategory: categoryFilter || undefined')
    expect(source).toContain('outcomeType: outcomeFilter || undefined')
    expect(source).toContain('dateFrom: dateFrom || undefined')
    expect(source).toContain('dateTo: dateTo || undefined')
    expect(source).toContain('employeeId: employeeFilter || undefined')
    expect(source).toContain('customerId: customerFilter || undefined')
    expect(source).toContain('pageSize: 25')
    expect(source).toContain('useActivities(queryParams)')
    expect(source).toContain('const filtered = useMemo(() => {')
    expect(source).toContain('a.outcome_notes?.toLowerCase().includes(q)')
  })

  it('keeps create/delete authority and backend time-window truth outside presentation components', () => {
    expect(source).toContain('can(PERMISSIONS.ACTIVITIES_CREATE)')
    expect(source).toContain('can(PERMISSIONS.ACTIVITIES_UPDATE_OWN)')
    expect(source).toContain('can(PERMISSIONS.ACTIVITIES_READ_TEAM)')
    expect(source).toContain('can(PERMISSIONS.ACTIVITIES_READ_ALL)')
    expect(source).toContain('useSoftDeleteActivity()')
    expect(source).toContain('deleteActivity.mutate(deleteTarget.id')
    expect(source).not.toContain('24h')
    expect(source).not.toContain('48h')
  })

  it('uses semantic outcome status and canonical page-owned action declarations', () => {
    expect(source).toContain('<ActivityOutcomeBadge outcome={activity.outcome_type} />')
    expect(source).toContain('const activityActions = (activity: ActivityRow): AppAction[] => [')
    expect(source).toContain("id: 'view'")
    expect(source).toContain("id: 'delete'")
    expect(source).not.toContain("ActivityStatusBadge")
  })

  it('uses shared Pagination once outside the device renderer without moving page truth', () => {
    expect(source).toContain("import Pagination from '@/components/patterns/Pagination'")
    expect(source).toContain('page={page}')
    expect(source).toContain('onPageChange={setPage}')
    expect(source).not.toContain('page={page}\n              totalPages={totalPages}')
  })

  it('keeps field card touch targets deliberate through Tablet and Mobile grids distinct', () => {
    expect(stylesheet).toContain('.ds-field-activity-grid--tablet')
    expect(stylesheet).toContain('grid-template-columns: repeat(2, minmax(0, 1fr))')
    expect(stylesheet).toContain('.ds-field-activity-grid--mobile')
    expect(stylesheet).toContain('@media (max-width: 1024px)')
    expect(stylesheet).toContain('min-height: var(--ds-icon-hit-target)')
  })
})
