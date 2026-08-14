import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const schema = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814110000_work_management_requests_queues.sql',
), 'utf8')

const commands = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814111000_work_management_request_commands.sql',
), 'utf8')

const atomicity = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814111100_work_management_request_triage_atomicity.sql',
), 'utf8')

describe('work requests / queues contract', () => {
  it('creates queue, membership, request type and runtime tables with RLS', () => {
    for (const table of ['work_queues', 'work_queue_members', 'work_request_types', 'work_requests']) {
      expect(schema).toContain(`CREATE TABLE public.${table}`)
      expect(schema).toContain(`ALTER TABLE public.${table} ENABLE ROW LEVEL SECURITY;`)
    }
  })

  it('keeps queue access scoped to queue membership rather than branch authority', () => {
    expect(schema).toContain('private.work_user_has_queue_access')
    expect(schema).toContain('private.work_user_is_queue_member')
    expect(schema).not.toContain("work.items.read_branch")
    expect(schema).not.toContain('queue membership grants branch')
  })

  it('keeps triage SLA independent from execution due dates', () => {
    expect(schema).toContain('triage_due_at TIMESTAMPTZ NOT NULL')
    expect(schema).toContain('default_triage_sla_minutes')
    expect(schema).toContain('default_resolution_sla_minutes')
    expect(commands).toContain("'triage_due_at',v_triage_due,'due_at',v_due_at")
  })

  it('validates structured intake payloads without dynamic SQL', () => {
    expect(commands).toContain('private.work_validate_intake_payload')
    expect(commands).toContain("jsonb_array_elements(p_schema->'fields')")
    expect(commands).toContain("'REQUIRED_FIELD_MISSING'")
    expect(commands).not.toContain('EXECUTE ')
  })

  it('provides idempotent request submission and optimistic-concurrency triage', () => {
    expect(commands).toContain("private.work_prepare_operation(")
    expect(commands).toContain("'work_submit_request'")
    expect(atomicity).toContain("'work_triage_request'")
    expect(atomicity).toContain('v_item.state_version<>p_expected_version')
    expect(atomicity).toContain("'VERSION_CONFLICT'")
  })

  it('validates the entire triage transition before writing first-response state', () => {
    const validateAccept = atomicity.indexOf("IF p_decision='needs_information'")
    const firstResponseWrite = atomicity.indexOf('SET first_responded_at=COALESCE(first_responded_at,v_now)')
    expect(validateAccept).toBeGreaterThan(-1)
    expect(firstResponseWrite).toBeGreaterThan(validateAccept)
  })

  it('supports needs-information, rejection and accepted assignment outcomes', () => {
    expect(atomicity).toContain("p_decision='needs_information'")
    expect(atomicity).toContain("p_decision='reject'")
    expect(atomicity).toContain("'work.request.accepted'")
    expect(atomicity).toContain("'work.request.rejected'")
    expect(atomicity).toContain("'work.request.information_required'")
  })

  it('exposes a queue backlog read model and an assignment-route resolver', () => {
    expect(schema).toContain('CREATE OR REPLACE VIEW public.work_queue_backlog')
    expect(commands).toContain('public.work_resolve_assignment_route')
    expect(commands).toContain("'request_required'")
  })
})
