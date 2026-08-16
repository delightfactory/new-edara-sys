import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817005000_ai_operations_sales_target_progress_freshness.sql',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations Sales target progress freshness contract', () => {
  it('is a narrow internal follow-up with no operational schema or data mutation', () => {
    expect(migration).toContain('DESIGN-TIME MIGRATION ONLY')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION ai_ops.sales_target_contribution_evidence')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION ai_ops.sales_target_candidates')
    expect(migration).not.toMatch(/CREATE\s+TABLE/i)
    expect(migration).not.toMatch(/ALTER\s+TABLE/i)
    expect(migration).not.toMatch(/CREATE\s+TRIGGER/i)
    expect(migration).not.toMatch(/CREATE\s+(?:UNIQUE\s+)?INDEX/i)

    const sourceTables = '(?:targets|target_progress|sales_orders|sales_order_items|activities|visit_plans|hr_employees|work_items|work_links)'
    expect(executableSql).not.toMatch(new RegExp(`UPDATE\\s+public\\.${sourceTables}`, 'i'))
    expect(executableSql).not.toMatch(new RegExp(`INSERT\\s+INTO\\s+public\\.${sourceTables}`, 'i'))
    expect(executableSql).not.toMatch(new RegExp(`DELETE\\s+FROM\\s+public\\.${sourceTables}`, 'i'))
    expect(executableSql).not.toMatch(/recalculate_target_progress\s*\(/i)
  })

  it('selects the latest canonical progress at or before the planner business date', () => {
    expect(migration).toContain('tp.snapshot_date <= p_business_date')
    expect(migration).toContain('ORDER BY tp.snapshot_date DESC, tp.last_calc_at DESC NULLS LAST, tp.id DESC')
    expect(migration).not.toContain('tp.snapshot_date = p_business_date\n')
  })

  it('aligns contribution parity to the same official metrics date', () => {
    expect(migration).toContain('c.progress_snapshot_date AS metrics_date')
    expect(migration).toContain('so.delivered_at::DATE BETWEEN t.period_start AND t.metrics_date')
    expect(migration).toContain("'official_achieved_value'")
    expect(migration).toContain("'parity_ok'")
    expect(migration).toContain('<= 0.01')
    expect(migration).toContain("'metrics_as_of', (SELECT progress_snapshot_date FROM canonical)")
  })

  it('does not mix stale achieved values with a newer-date pace window', () => {
    expect(migration).toContain('GREATEST(e.period_end - e.progress_snapshot_date, 0)::INTEGER AS remaining_days')
    expect(migration).toContain('WHEN (e.period_end - e.progress_snapshot_date) > 0')
    expect(migration).toContain('/ (e.period_end - e.progress_snapshot_date)')
    expect(migration).toContain('a.activity_date BETWEEN b.period_start AND b.progress_snapshot_date')
    expect(migration).toContain('vp.plan_date BETWEEN b.period_start AND b.progress_snapshot_date')
    expect(migration).toContain("'activity_window_end', b.progress_snapshot_date")
  })

  it('surfaces snapshot age and blocks current-state actionability without hiding the case', () => {
    expect(migration).toContain("'progress_snapshot_date', b.progress_snapshot_date")
    expect(migration).toContain("'progress_snapshot_age_days', p_business_date - b.progress_snapshot_date")
    expect(migration).toContain("'progress_snapshot_exact_business_date', b.progress_snapshot_date = p_business_date")
    expect(migration).toContain("'stale_for_current_business_date'")
    expect(migration).toContain("'requires_progress_refresh_for_current_action', b.progress_snapshot_date < p_business_date")
    expect(migration).toContain("'evidence_only_until_progress_refresh'")
    expect(migration).toContain("tp.trend::TEXT IN ('behind', 'at_risk')")
  })

  it('keeps the replaced routines closed to browser and generic service roles', () => {
    const signatures = [
      'ai_ops.sales_target_contribution_evidence(UUID, DATE, INTEGER)',
      'ai_ops.sales_target_candidates(DATE, INTEGER)',
    ]

    for (const signature of signatures) {
      expect(migration).toContain(`REVOKE ALL ON FUNCTION ${signature} FROM PUBLIC;`)
      expect(migration).toContain(`REVOKE ALL ON FUNCTION ${signature} FROM anon;`)
      expect(migration).toContain(`REVOKE ALL ON FUNCTION ${signature} FROM authenticated;`)
      expect(migration).toContain(`REVOKE ALL ON FUNCTION ${signature} FROM service_role;`)
    }
  })
})
