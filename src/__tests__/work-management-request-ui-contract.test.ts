import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const read = (path: string) => readFileSync(resolve(process.cwd(), path), 'utf8')

const app = read('src/App.tsx')
const hub = read('src/pages/work/WorkHubPage.tsx')
const requestPanel = read('src/pages/work/SubmitRequestPanel.tsx')
const runtimeApi = read('src/features/work/runtime-api.ts')
const permissions = read('src/lib/permissions/work.ts')
const requestSchema = read('supabase/migrations/20260814110000_work_management_requests_queues.sql')
const requestCommands = read('supabase/migrations/20260814111000_work_management_request_commands.sql')

describe('Work request submission UI contract', () => {
  it('gates request submission in the hub with the dedicated permission', () => {
    expect(permissions).toContain("REQUESTS_CREATE: 'work.requests.create'")
    expect(hub).toContain("const canSubmitRequest = can('work.requests.create')")
    expect(hub).toContain("searchParams.get('request') === 'new'")
    expect(hub).toContain('<SubmitRequestPanel')
    expect(hub).toContain('إرسال طلب')
  })

  it('keeps supervisor and management workspaces behind their permission families', () => {
    expect(app).toContain('path="work/team"')
    expect(app).toContain("'work.items.read_team', 'work.items.read_all', 'work.items.manage_team'")
    expect(app).toContain('path="work/manage"')
    expect(app).toContain("'work.queues.manage', 'work.templates.manage', 'work.workflows.manage', 'work.recurrence.manage', 'work.policies.manage'")
  })

  it('loads only active request types and queues allowed by RLS', () => {
    expect(runtimeApi).toContain(".from('work_queues')")
    expect(runtimeApi).toContain(".from('work_request_types')")
    expect(runtimeApi).toContain(".eq('is_active', true)")
    expect(requestSchema).toContain('CREATE POLICY work_request_types_select_visible')
    expect(requestSchema).toContain("public.check_permission(auth.uid(),'work.requests.create')")
    expect(requestSchema).toContain('CREATE POLICY work_queues_select_visible')
  })

  it('submits through the atomic request RPC without direct Work table mutations', () => {
    expect(requestPanel).not.toContain("@/lib/supabase/client")
    expect(requestPanel).not.toContain(".from('work_items')")
    expect(runtimeApi).toContain("executeAtomic<SubmitWorkRequestResult>('work_submit_request'")
    expect(runtimeApi).toContain('p_operation_id: input.operationId')
    expect(runtimeApi).toContain('p_expected_outcome: null')
    expect(runtimeApi).toContain('p_priority: null')
    expect(runtimeApi).toContain('p_visibility: null')
    expect(requestCommands).toContain('CREATE OR REPLACE FUNCTION public.work_submit_request(')
    expect(requestCommands).toContain("public.check_permission(v_actor,'work.requests.create')")
    expect(requestCommands).toContain('private.work_validate_intake_payload')
  })

  it('preserves an operation id across ambiguous retries and resets it when the form changes', () => {
    expect(requestPanel).toContain('operationIdRef')
    expect(requestPanel).toContain('operationIdRef.current ?? crypto.randomUUID()')
    expect(requestPanel).toContain('operationIdRef.current = operationId')
    expect(requestPanel).toContain('operationIdRef.current = null')
  })

  it('renders and validates every intake field type supported by the server schema', () => {
    expect(requestPanel).toContain("field.type === 'boolean'")
    expect(requestPanel).toContain("field.type === 'number'")
    expect(requestPanel).toContain("field.type === 'array'")
    expect(requestPanel).toContain("field.type === 'object'")
    expect(requestPanel).toContain('JSON.parse(text)')
    expect(requestPanel).toContain('field.required')
    expect(requestPanel).toContain('expected_outcome_template')
  })

  it('supports direct links to a preselected request type by id or code', () => {
    expect(hub).toContain("searchParams.get('type')")
    expect(requestPanel).toContain('type.id === initialTypeKey || type.code === initialTypeKey')
  })
})
