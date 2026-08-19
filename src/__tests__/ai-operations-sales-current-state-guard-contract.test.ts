import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817006100_ai_operations_sales_current_state_guard.sql',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations Sales current-state guard contract', () => {
  it('preserves the audited credit guard and dispatches by frozen case domain', () => {
    expect(migration).toContain('ALTER FUNCTION ai_ops.current_decision_issues(UUID)')
    expect(migration).toContain('RENAME TO current_decision_issues_credit_v1')
    expect(migration).toContain("WHEN 'receivables' THEN")
    expect(migration).toContain('ai_ops.current_decision_issues_credit_v1(p_decision_id)')
    expect(migration).toContain("WHEN 'sales' THEN")
    expect(migration).toContain('ai_ops.current_sales_target_decision_issues(p_decision_id)')
    expect(migration).toContain("'unsupported_validation_domain'")
  })

  it('anchors sales validation to the current Cairo business date', () => {
    expect(migration).toContain("AT TIME ZONE 'Africa/Cairo'")
    expect(migration).toContain('v_business_date NOT BETWEEN v_target.period_start AND v_target.period_end')
    expect(migration).toContain('tp.snapshot_date <= v_business_date')
  })

  it('fails closed when the target definition or canonical progress changed after the snapshot', () => {
    expect(migration).toContain("'target_missing'")
    expect(migration).toContain("'target_no_longer_actionable'")
    expect(migration).toContain("'target_definition_changed_after_snapshot'")
    expect(migration).toContain("'target_progress_missing_now'")
    expect(migration).toContain("'target_progress_changed_after_snapshot'")
    expect(migration).toContain("'target_no_longer_gap_candidate'")
    expect(migration).toContain('ORDER BY tp.snapshot_date DESC, tp.last_calc_at DESC NULLS LAST, tp.id DESC')
  })

  it('blocks stale progress or contribution mismatch only from consequential action', () => {
    expect(migration).toMatch(/IF v_decision\.decision_type IN \('CREATE_WORK','ESCALATE'\)\s+AND COALESCE\(\(v_sc\.trust->>'requires_progress_refresh_for_current_action'\)::BOOLEAN, true\)/)
    expect(migration).toContain("'sales_progress_stale_for_action'")
    expect(migration).toMatch(/IF v_decision\.decision_type IN \('CREATE_WORK','ESCALATE'\)\s+AND COALESCE\(\(v_sc\.trust->>'contribution_parity_ok'\)::BOOLEAN, false\) = false/)
    expect(migration).toContain("'sales_contribution_parity_failed'")
    expect(migration).toContain('A parity failure is useful evidence for INVESTIGATE/MONITOR')
  })

  it('rechecks governed target context and exact target-linked Work continuity', () => {
    expect(migration).toContain("oc.subject_type = 'target'")
    expect(migration).toContain("oc.subject_type = 'product'")
    expect(migration).toContain("oc.subject_type = 'product_category'")
    expect(migration).toContain("oc.subject_type = 'department'")
    expect(migration).toContain("'new_governed_context_after_snapshot'")
    expect(migration).toContain("wl.entity_type = 'target'")
    expect(migration).toContain('wl.entity_id = v_target_id')
    expect(migration).toContain("'active_work_collision_now'")
    expect(migration).toContain("'linked_work_no_longer_active'")
  })

  it('requires active owner and assignee and a complete sales capture for consequential action', () => {
    expect(migration).toContain("'recommended_owner_unavailable'")
    expect(migration).toContain("'recommended_assignee_unavailable'")
    expect(migration).toContain("v_domain_capture.capture_status <> 'completed'")
    expect(migration).toContain("'snapshot_not_complete_for_action'")
  })

  it('is read-only against operational targets, progress, work and context', () => {
    for (const table of ['targets','target_progress','work_items','work_links']) {
      expect(executableSql).not.toMatch(new RegExp(`UPDATE\\s+public\\.${table}`, 'i'))
      expect(executableSql).not.toMatch(new RegExp(`INSERT\\s+INTO\\s+public\\.${table}`, 'i'))
      expect(executableSql).not.toMatch(new RegExp(`DELETE\\s+FROM\\s+public\\.${table}`, 'i'))
    }
    expect(executableSql).not.toMatch(/recalculate_target_progress\s*\(/i)
  })

  it('keeps all guard primitives private from generic API roles', () => {
    for (const signature of [
      'ai_ops.current_decision_issues_credit_v1(UUID)',
      'ai_ops.current_sales_target_decision_issues(UUID)',
      'ai_ops.current_decision_issues(UUID)',
    ]) {
      expect(migration).toContain(`REVOKE ALL ON FUNCTION ${signature}`)
    }
  })
})
