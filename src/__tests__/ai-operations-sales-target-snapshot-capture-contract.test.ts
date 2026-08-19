import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817004000_ai_operations_sales_target_snapshot_capture.sql',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations Sales & Targets snapshot capture contract', () => {
  it('freezes Sales evidence into existing ai_ops snapshot structures only', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION ai_ops.refresh_sales_target_cases')
    expect(migration).toContain('INSERT INTO ai_ops.cases')
    expect(migration).toContain('INSERT INTO ai_ops.snapshot_cases')
    expect(migration).toContain('INSERT INTO ai_ops.snapshot_domain_captures')
    expect(migration).not.toMatch(/CREATE\s+TABLE/i)
    expect(migration).not.toMatch(/ALTER\s+TABLE/i)
    expect(migration).not.toMatch(/CREATE\s+TRIGGER/i)
  })

  it('keeps snapshot rank unique when multiple domains share one snapshot', () => {
    expect(migration).toContain('SELECT COALESCE(MAX(sc.snapshot_rank), 0)')
    expect(migration).toContain('v_rank_offset + v_count')
    expect(migration).toContain("dc.domain = 'sales'")
    expect(migration).toContain("sc.domain = 'sales'")
  })

  it('writes an immutable zero-case-capable domain capture marker', () => {
    expect(migration).toContain("'sales-target-gap-v1'")
    expect(migration).toContain("'capture_marker_written', true")
    expect(migration).toContain("'case_type', 'target_trajectory_gap'")
    expect(migration).toContain("'supported_target_types', jsonb_build_array('sales_value', 'product_qty')")
  })

  it('freezes bounded governed context without promoting unapproved AI inference', () => {
    expect(migration).toContain("oc.visibility IN ('management', 'standard')")
    expect(migration).toContain("oc.confidence_class <> 'ai_inference' OR oc.approved_by_user_id IS NOT NULL")
    expect(migration).toContain("oc.subject_type = 'target'")
    expect(migration).toContain("oc.subject_type = 'product'")
    expect(migration).toContain("oc.subject_type = 'product_category'")
    expect(migration).toContain("oc.subject_type = 'department'")
    expect(migration).toContain("'content_trust', 'governed_untrusted_text'")
    expect(migration).toContain('LIMIT 5')
    expect(migration).toContain('left(COALESCE(NULLIF(oc.context_payload->>\'summary\', \'\'), oc.context_type), 500)')
  })

  it('records contribution parity failures instead of hiding them', () => {
    expect(migration).toContain("v_candidate.contribution_evidence->>'parity_ok'")
    expect(migration).toContain('v_parity_failed_cases := v_parity_failed_cases + 1')
    expect(migration).toContain("'contribution_parity_failed_cases', v_parity_failed_cases")
  })

  it('detects domain truncation and does not pretend coverage is complete', () => {
    expect(migration).toContain('v_effective_limit + 1')
    expect(migration).toContain('v_has_more')
    expect(migration).toContain("v_capture_status := 'partial'")
    expect(migration).toContain("'has_more', v_has_more")
  })

  it('does not recalculate or mutate operational sources while capturing', () => {
    const sourceTables = '(?:targets|target_progress|sales_orders|sales_order_items|activities|visit_plans|hr_employees|work_items|work_links)'
    expect(executableSql).not.toMatch(/recalculate_target_progress\s*\(/i)
    expect(executableSql).not.toMatch(new RegExp(`UPDATE\\s+public\\.${sourceTables}`, 'i'))
    expect(executableSql).not.toMatch(new RegExp(`INSERT\\s+INTO\\s+public\\.${sourceTables}`, 'i'))
    expect(executableSql).not.toMatch(new RegExp(`DELETE\\s+FROM\\s+public\\.${sourceTables}`, 'i'))
    expect(migration).toContain("'target_recalculation_performed', false")
  })

  it('keeps the capture function private from all generic API roles', () => {
    const signature = 'ai_ops.refresh_sales_target_cases(UUID, DATE, INTEGER)'
    expect(migration).toContain(`REVOKE ALL ON FUNCTION ${signature} FROM PUBLIC;`)
    expect(migration).toContain(`REVOKE ALL ON FUNCTION ${signature} FROM anon;`)
    expect(migration).toContain(`REVOKE ALL ON FUNCTION ${signature} FROM authenticated;`)
    expect(migration).toContain(`REVOKE ALL ON FUNCTION ${signature} FROM service_role;`)
  })
})
