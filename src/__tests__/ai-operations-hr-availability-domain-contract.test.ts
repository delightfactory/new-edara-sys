import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const read = (name: string) => readFileSync(resolve(process.cwd(), `supabase/migrations/${name}`), 'utf8')

const caseSql = read('20260817008800_ai_operations_hr_availability_case_engine.sql')
const snapshotSql = read('20260817008900_ai_operations_hr_availability_snapshot_capture.sql')
const budgetSql = read('20260817009000_ai_operations_hr_availability_global_budget_actionability.sql')
const guardSql = read('20260817009100_ai_operations_hr_availability_current_state_guard.sql')
const bridgeSql = read('20260817009200_ai_operations_hr_availability_reviewed_work_bridge.sql')

const executable = [caseSql, snapshotSql, budgetSql, guardSql, bridgeSql]
  .join('\n')
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations HR / Availability domain contract', () => {
  it('uses authoritative HR availability sources and never infers absence from a missing punch', () => {
    expect(caseSql).toContain('public.get_employee_work_schedule')
    expect(caseSql).toContain('public.hr_leave_requests')
    expect(caseSql).toContain("lr.status::TEXT='approved'")
    expect(caseSql).toContain('public.hr_attendance_days')
    expect(caseSql).toContain("attendance_status IN ('on_leave','absent_authorized','absent_unauthorized','weekly_off','public_holiday')")
    expect(caseSql).toContain("'missing_punch_never_infers_absence',true")
    expect(caseSql).toContain("'missing_attendance_row_treated_as_absence',false")
    expect(caseSql).not.toMatch(/punch_in_time\s+IS\s+NULL|punch_out_time\s+IS\s+NULL/i)
  })

  it('detects only allocation/continuity conflicts and carries schedule capacity as context, not a performance score', () => {
    expect(caseSql).toContain("'approved_leave_allocation_conflict'")
    expect(caseSql).toContain("'employee_status_unavailable'")
    expect(caseSql).toContain("'explicit_attendance_unavailable'")
    expect(caseSql).toContain("'nonworking_schedule_allocation_conflict'")
    expect(caseSql).toContain("'scheduled_minutes',s.scheduled_minutes")
    expect(caseSql).toContain("'employee_performance_scoring',false")
    expect(caseSql).toContain("'contact_or_identity_pii_included',false")
  })

  it('routes coverage to an active source owner or direct manager, never automatically back to the unavailable employee', () => {
    expect(caseSql).toContain("a.accountable_owner_user_id<>a.employee_user_id")
    expect(caseSql).toContain("a.manager_user_id<>a.employee_user_id")
    expect(caseSql).toContain("'active_source_owner_else_direct_manager_controls_short_term_coverage'")
    expect(caseSql).toContain("'create_work_owner_user_id',s.routed_owner_user_id")
    expect(caseSql).toContain("'create_work_assignee_user_id',s.routed_owner_user_id")
  })

  it('freezes exact immutable hr-availability-v1 evidence with bounded governed context', () => {
    expect(snapshotSql).toContain('CREATE OR REPLACE FUNCTION ai_ops.refresh_hr_availability_cases')
    expect(snapshotSql).toContain("'hr_availability','hr-availability-v1'")
    expect(snapshotSql).toContain('v_snapshot.data_as_of')
    expect(snapshotSql).toContain('LIMIT 5')
    expect(snapshotSql).toContain("'planning_horizon_days',14")
    expect(snapshotSql).toContain("'hr_mutation_performed',false")
  })

  it('adds HR Availability as the seventh domain under the same global allocator and explicit trusted gate', () => {
    expect(budgetSql).toContain("ARRAY['receivables','sales','customer_health','inventory','field_execution','work_health','hr_availability']::TEXT[]")
    expect(budgetSql).toContain("'hr_availability',v_hr_demand")
    expect(budgetSql).toContain('ai_ops.allocate_domain_case_budget')
    expect(budgetSql).toContain('build_operational_snapshot_six_domain_v1')
    expect(budgetSql).toContain("v_version<>'hr-availability-v1'")
    expect(budgetSql).toContain("v_snapshot_status<>'ready'")
    expect(budgetSql).toContain("v_frozen_count IS DISTINCT FROM v_case_count")
    expect(budgetSql).toContain("(v_meta->>'case_limit')::INTEGER<=0")
    expect(budgetSql).toContain("'global_budget_exhausted',v_hr_has_candidate")
  })

  it('revalidates Work, HR availability evidence, responsibility and cross-domain collisions immediately before action', () => {
    expect(guardSql).toContain('ai_ops.hr_availability_candidates(v_today,v_now,2000)')
    expect(guardSql).toContain("'source_work_execution_state_changed_after_snapshot'")
    expect(guardSql).toContain("'hr_availability_evidence_changed_after_snapshot'")
    expect(guardSql).toContain("'hr_availability_responsibility_changed_after_snapshot'")
    expect(guardSql).toContain("recovery.metadata->>'ai_domain' IN ('hr_availability','work_health')")
    expect(guardSql).toContain('ai_ops.apply_selected_case_capture_actionability')
    expect(guardSql).toContain("WHEN 'hr_availability' THEN RETURN ai_ops.current_hr_availability_decision_issues")
  })

  it('creates only reviewed employee-safe coverage Work and never mutates HR or the source Work', () => {
    expect(bridgeSql).toContain("'ai_domain','hr_availability'")
    expect(bridgeSql).toContain("'coverage_planning_task',true")
    expect(bridgeSql).toContain("'management_rationale_exposed',false")
    expect(bridgeSql).toContain("v_work.id,'work_item',v_source_work_id,'coverage_for'")
    expect(bridgeSql).toContain("v_work.id,'employee',v_employee_id,'availability_for'")
    expect(bridgeSql).toContain('v_issues:=ai_ops.current_decision_issues(p_decision_id)')
    expect(bridgeSql).toContain("PERFORM pg_advisory_xact_lock(hashtextextended('ai_ops:hr-availability-source:'")
    expect(bridgeSql).not.toMatch(/UPDATE\s+public\.hr_|DELETE\s+FROM\s+public\.hr_|INSERT\s+INTO\s+public\.hr_/i)
    expect(bridgeSql).not.toMatch(/work_change_due|work_update_next_action|work_set_waiting|work_resume|work_escalate\s*\(/i)
  })

  it('keeps every new planner helper closed to generic API roles', () => {
    expect(caseSql).toContain('FROM PUBLIC,anon,authenticated,service_role')
    expect(snapshotSql).toContain('FROM PUBLIC,anon,authenticated,service_role')
    expect(budgetSql).toContain('FROM PUBLIC,anon,authenticated,service_role')
    expect(guardSql).toContain('FROM PUBLIC,anon,authenticated,service_role')
    expect(bridgeSql).toContain('FROM PUBLIC,anon,authenticated,service_role')
    expect(executable).not.toMatch(/GRANT\s+EXECUTE[^;]+(?:anon|authenticated|service_role)/i)
  })
})
