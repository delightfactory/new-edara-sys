import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const read = (name: string) => readFileSync(resolve(process.cwd(), `supabase/migrations/${name}`), 'utf8')

const caseSql = read('20260817008100_ai_operations_work_health_case_engine.sql')
const snapshotSql = read('20260817008200_ai_operations_work_health_snapshot_capture.sql')
const budgetSql = read('20260817008300_ai_operations_work_health_global_budget_actionability.sql')
const guardSql = read('20260817008400_ai_operations_work_health_current_state_guard.sql')
const bridgeSql = read('20260817008500_ai_operations_work_health_reviewed_work_bridge.sql')

const executable = [caseSql, snapshotSql, budgetSql, guardSql, bridgeSql]
  .join('\n')
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations Work Health domain contract', () => {
  it('uses the deployed Work health semantics and does not invent a second SLA', () => {
    expect(caseSql).toContain('public.work_operational_settings')
    expect(caseSql).toContain('private.work_operational_item_is_blocked(w.id)')
    expect(caseSql).toContain("b.status IN ('open','in_progress','pending_approval')")
    expect(caseSql).toContain("b.status='waiting'")
    expect(caseSql).toContain("'missing_next_action'")
    expect(caseSql).toContain("'stale_after_hours',s.stale_after_hours")
    expect(caseSql).not.toMatch(/max_pending_days|max_blocked_days|overdue_escalation_hours/i)
  })

  it('keeps one dominant Case per source Work and excludes recursive recovery Work', () => {
    expect(caseSql).toContain("'work_health:'||s.id::TEXT AS case_key")
    expect(caseSql).toContain("COALESCE(w.metadata->>'ai_domain','')<>'work_health'")
    expect(caseSql).toContain("WHEN e.is_overdue THEN 'overdue_work'")
    expect(caseSql).toContain("WHEN e.is_blocked THEN 'blocked_work'")
    expect(caseSql).toContain("WHEN e.is_follow_up_due THEN 'waiting_follow_up_due'")
    expect(caseSql).toContain("WHEN e.is_stale THEN 'stale_work'")
  })

  it('excludes private Work and freezes the source Work itself as the ESCALATE contract', () => {
    expect(caseSql).toContain("w.visibility='standard'")
    expect(caseSql).toContain("'existing_active_work',jsonb_build_object(")
    expect(caseSql).toContain("'work_item_id',s.id")
    expect(caseSql).not.toMatch(/work_comments|work_proofs|work_attachments/i)
  })

  it('freezes immutable Work Health evidence with bounded governed context', () => {
    expect(snapshotSql).toContain('CREATE OR REPLACE FUNCTION ai_ops.refresh_work_health_cases')
    expect(snapshotSql).toContain("'work_health','work-health-v1'")
    expect(snapshotSql).toContain('LIMIT 5')
    expect(snapshotSql).toContain("'source_work_mutation_performed',false")
    expect(snapshotSql).toContain("case_type=EXCLUDED.case_type")
  })

  it('adds Work Health as the sixth domain under the same hard global allocator', () => {
    expect(budgetSql).toContain("ARRAY['receivables','sales','customer_health','inventory','field_execution','work_health']::TEXT[]")
    expect(budgetSql).toContain("'work_health',v_work_demand")
    expect(budgetSql).toContain('ai_ops.allocate_domain_case_budget')
    expect(budgetSql).toContain('build_operational_snapshot_five_domain_v1')
    expect(budgetSql).toContain("'global_budget_exhausted',v_work_has_candidate")
  })

  it('updates the shared required-domain registry and trusted bounded-partial gate', () => {
    expect(budgetSql).toContain('CREATE OR REPLACE FUNCTION ai_ops.required_operational_domains()')
    expect(budgetSql).toContain("'work_health'")
    expect(budgetSql).toContain("v_capture_version<>'work-health-v1'")
    expect(budgetSql).toContain("v_snapshot_status<>'ready'")
    expect(budgetSql).toContain("v_frozen_domain_case_count IS DISTINCT FROM v_capture_case_count")
    expect(budgetSql).toContain("(v_metadata->>'case_limit')::INTEGER<=0")
  })

  it('revalidates source state/version/signals/settings and routing before action', () => {
    expect(guardSql).toContain('FROM ai_ops.work_health_candidates(v_now,2000) c')
    expect(guardSql).toContain("'source_work_state_version_changed_after_snapshot'")
    expect(guardSql).toContain("'work_health_signals_changed_after_snapshot'")
    expect(guardSql).toContain("'work_operational_settings_changed_after_snapshot'")
    expect(guardSql).toContain("'recommended_work_health_assignee_not_source_owner'")
    expect(guardSql).toContain("'active_work_health_recovery_collision_now'")
    expect(guardSql).toContain('ai_ops.apply_selected_case_capture_actionability')
  })

  it('creates only a separate reviewed recovery Work and never mutates the unhealthy source Work', () => {
    expect(bridgeSql).toContain("WHEN 'work_item' THEN 'public.work_items'")
    expect(bridgeSql).toContain("'work_health_recovery_task',true")
    expect(bridgeSql).toContain("'source_work_mutation_performed',false")
    expect(bridgeSql).toContain("v_work.id,'work_item',v_source_work_id,'recovery_for'")
    expect(bridgeSql).toContain('v_issues:=ai_ops.current_decision_issues(p_decision_id)')
    expect(bridgeSql).toContain("v_decision.decision_type<>'CREATE_WORK'")
    expect(bridgeSql).not.toMatch(/work_change_due|work_update_next_action|work_set_waiting|work_resume|work_escalate\s*\(/i)
  })

  it('keeps source Work reads internal and planner helpers closed to generic API roles', () => {
    expect(executable).not.toMatch(/(?:DELETE\s+FROM)\s+public\.work_items/i)
    expect(caseSql).toContain('FROM PUBLIC,anon,authenticated,service_role')
    expect(snapshotSql).toContain('FROM PUBLIC,anon,authenticated,service_role')
    expect(budgetSql).toContain('FROM PUBLIC,anon,authenticated,service_role')
    expect(guardSql).toContain('FROM PUBLIC,anon,authenticated,service_role')
    expect(bridgeSql).toContain('FROM PUBLIC,anon,authenticated,service_role')
  })
})
