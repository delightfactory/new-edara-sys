import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const read = (path: string) => readFileSync(resolve(process.cwd(), path), 'utf8')

const app = read('src/App.tsx')
const bottomNav = read('src/components/layout/BottomNav.tsx')
const hub = read('src/pages/work/WorkHubPage.tsx')
const createTask = read('src/pages/work/CreateTaskPage.tsx')
const detail = read('src/pages/work/WorkDetailPage.tsx')
const runtimeApi = read('src/features/work/runtime-api.ts')
const runtimeHooks = read('src/features/work/runtime-hooks.ts')
const permissions = read('src/lib/permissions/work.ts')
const assignmentMigration = read('supabase/migrations/20260814133100_work_management_assignment_candidates.sql')
const responsibilityMigration = read('supabase/migrations/20260814133200_work_management_responsibility_snapshot.sql')
const vercelConfig = read('vercel.json')

describe('operational Work UI architecture', () => {
  it('wires Work routes behind the correct permission families', () => {
    expect(app).toContain("const WorkHubPage = lazy(() => import('@/pages/work/WorkHubPage'))")
    expect(app).toContain('path="work"')
    expect(app).toContain("'work.items.read_own', 'work.items.read_team', 'work.items.read_all'")
    expect(app).toContain('path="work/new"')
    expect(app).toContain('permission="work.items.create"')
    expect(app).toContain('path="work/:id"')
  })

  it('makes Work a primary mobile destination without bypassing permissions', () => {
    expect(bottomNav).toContain("id: 'work'")
    expect(bottomNav).toContain("path: '/work'")
    expect(bottomNav).toContain("'work.items.read_own', 'work.items.read_team', 'work.items.read_all'")
  })

  it('keeps page components free from direct Supabase workflow mutations', () => {
    for (const source of [hub, createTask, detail]) {
      expect(source).not.toContain("from('@/lib/supabase/client')")
      expect(source).not.toContain(".from('work_items').update")
      expect(source).not.toContain(".from('work_items').insert")
      expect(source).not.toContain(".from('work_items').delete")
    }
    expect(detail).toContain('useStartWork')
    expect(detail).toContain('useSetWorkWaiting')
    expect(detail).toContain('useCompleteWork')
    expect(detail).toContain('useDecideApproval')
    expect(detail).toContain('useTriageRequest')
  })

  it('uses server-filtered assignment candidates rather than exposing the profile directory', () => {
    expect(createTask).toContain('useAssignmentCandidates')
    expect(runtimeApi).toContain("supabase.rpc('work_list_assignment_candidates'")
    expect(assignmentMigration).toContain('private.work_user_can_assign_target(v_actor,p.id)')
    expect(assignmentMigration).toContain("public.check_permission(v_actor,'work.items.create')")
    expect(assignmentMigration).toContain('LIMIT v_limit')
  })

  it('keeps responsibility names scoped to an already-visible Work Item', () => {
    expect(responsibilityMigration).toContain('private.work_user_can_view_row(')
    expect(responsibilityMigration).toContain("'owner',CASE")
    expect(responsibilityMigration).toContain("'assignee',CASE")
    expect(responsibilityMigration).toContain("'waiting_on',CASE")
    expect(detail).toContain('useWorkResponsibility')
  })

  it('centres the Work Hub on current action rather than dashboard-only analytics', () => {
    expect(hub).toContain('useMyActionInbox(100)')
    expect(hub).toContain('مطلوب مني الآن')
    expect(hub).toContain('يحتاج انتباه')
    expect(hub).toContain("navigate(action.deep_link || `/work/${action.work_item_id}`)")
    expect(hub).toContain("import './work-interactions.css'")
  })

  it('keeps task creation outcome-driven and distinguishes accountability from execution', () => {
    expect(createTask).toContain('النتيجة المتوقعة *')
    expect(createTask).toContain('المسؤول النهائي *')
    expect(createTask).toContain('المكلف الحالي *')
    expect(createTask).toContain('الإجراء التالي *')
    expect(createTask).toContain('acknowledgementRequired: acknowledgementRequired && !assigneeIsSelf')
  })

  it('centralises all Work permissions in a typed frontend registry', () => {
    expect(permissions).toContain("ITEMS_READ_OWN: 'work.items.read_own'")
    expect(permissions).toContain("ITEMS_MANAGE_TEAM: 'work.items.manage_team'")
    expect(permissions).toContain("APPROVALS_DECIDE: 'work.approvals.decide'")
    expect(permissions).toContain("RECURRENCE_MANAGE: 'work.recurrence.manage'")
    expect(permissions).toContain('WORK_PERMISSION_GROUP')
  })

  it('invalidates Work queries after atomic mutations', () => {
    expect(runtimeHooks).toContain("queryClient.invalidateQueries({ queryKey: workKeys.all })")
    expect(runtimeApi).toContain('crypto.randomUUID()')
    expect(runtimeApi).toContain('executeAtomic')
  })

  it('prevents automatic Vercel deployments from the feature branch', () => {
    expect(vercelConfig).toContain('"feature/work-management": false')
  })
})
