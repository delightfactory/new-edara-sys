import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const operational = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814130000_work_management_operational_state.sql',
), 'utf8')
const inbox = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814130500_work_management_action_inbox.sql',
), 'utf8')

describe('work operational state and action inbox contract', () => {
  it('keeps operational conditions out of the lifecycle enum', () => {
    expect(operational).toContain('CREATE OR REPLACE VIEW public.work_operational_flags')
    expect(operational).toContain('is_blocked')
    expect(operational).toContain('is_overdue')
    expect(operational).toContain('is_stale')
    expect(operational).toContain('is_at_risk')
    expect(operational).toContain('is_escalated')
    expect(operational).not.toContain("ALTER TYPE public.work_item_status ADD VALUE 'blocked'")
    expect(operational).not.toContain("ALTER TYPE public.work_item_status ADD VALUE 'overdue'")
  })

  it('uses a deterministic configurable stale and due-soon rule', () => {
    expect(operational).toContain('due_soon_hours INTEGER NOT NULL DEFAULT 24')
    expect(operational).toContain('stale_after_hours INTEGER NOT NULL DEFAULT 72')
    expect(operational).toContain('last_meaningful_activity_at')
    expect(operational).toContain('make_interval(hours=>b.stale_after_hours)')
  })

  it('fails closed for automatic manager escalation until hierarchy validation', () => {
    expect(operational).toContain('manager_escalation_enabled BOOLEAN NOT NULL DEFAULT false')
    expect(operational).toContain('work_operational_settings_escalation_gate')
    expect(operational).toContain("'HIERARCHY_NOT_VALIDATED'")
    expect(operational).toContain('private.work_manager_escalation_ready()')
  })

  it('requires an atomic expected-version command for explicit escalation', () => {
    expect(operational).toContain('CREATE OR REPLACE FUNCTION public.work_escalate(')
    expect(operational).toContain('p_expected_version BIGINT')
    expect(operational).toContain("'VERSION_CONFLICT'")
    expect(operational).toContain("'work.escalated'")
    expect(operational).toContain('CREATE UNIQUE INDEX work_escalations_one_active_per_item')
  })

  it('uses RLS-aware security-invoker read models', () => {
    expect(operational).toContain('WITH (security_invoker=true)')
    expect(inbox).toContain('WITH (security_invoker=true)')
    expect(inbox).toContain('SECURITY INVOKER')
  })

  it('unifies execution, owner review, approval and request triage actions', () => {
    expect(inbox).toContain("'execute_next_action'")
    expect(inbox).toContain("'follow_up'")
    expect(inbox).toContain("'completion_review'")
    expect(inbox).toContain("'approval_decision'")
    expect(inbox).toContain("'triage_request'")
  })

  it('does not treat queue membership alone as triage authority', () => {
    expect(inbox).toContain("public.check_permission((select auth.uid()),'work.requests.triage')")
    expect(inbox).toContain('m.can_triage=true')
    expect(inbox).toContain("m.member_role IN ('triager','manager')")
  })

  it('carries optimistic-lock versions in quick-action payloads', () => {
    expect(inbox).toContain("'expected_version',w.state_version")
    expect(inbox).toContain("'expected_approval_version',ar.state_version")
  })
})
