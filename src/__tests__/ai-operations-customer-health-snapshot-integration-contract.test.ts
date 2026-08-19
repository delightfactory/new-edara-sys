import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const capture = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817006500_ai_operations_customer_health_snapshot_capture.sql',
), 'utf8')
const orchestration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817006600_ai_operations_generic_domain_budget_customer_health.sql',
), 'utf8')
const executable = `${capture}\n${orchestration}`
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations Customer Health snapshot integration contract', () => {
  it('freezes both Customer Health case families into the shared immutable snapshot', () => {
    expect(capture).toContain('CREATE OR REPLACE FUNCTION ai_ops.refresh_customer_health_cases')
    expect(capture).toContain("'reactivation_gap'")
    expect(capture).toContain("'high_value_reactivation_opportunity'")
    expect(capture).toContain('INSERT INTO ai_ops.snapshot_cases')
    expect(capture).toContain('INSERT INTO ai_ops.snapshot_domain_captures')
    expect(capture).toContain("'customer_health','customer-health-v1'")
  })

  it('preserves globally unique deterministic snapshot ranks and bounded governed context', () => {
    expect(capture).toContain('SELECT COALESCE(MAX(sc.snapshot_rank),0)')
    expect(capture).toContain('v_rank_offset+v_count')
    expect(capture).toContain('LIMIT 5')
    expect(capture).toContain("'max_per_case',5")
    expect(capture).toContain("'content_trust','governed_untrusted_text'")
  })

  it('records partial coverage instead of pretending truncated evidence is complete', () => {
    expect(capture).toContain('v_has_more')
    expect(capture).toContain("v_capture_status:='partial'")
    expect(orchestration).toContain("CASE WHEN v_customer_has_candidate THEN 'partial' ELSE 'completed' END")
    expect(orchestration).toContain("'global_budget_exhausted',v_customer_has_candidate")
  })

  it('uses a generic deterministic allocator for three domains without cross-domain severity ranking', () => {
    expect(orchestration).toContain('CREATE OR REPLACE FUNCTION ai_ops.allocate_domain_case_budget')
    expect(orchestration).toContain("ARRAY['receivables','sales','customer_health']::TEXT[]")
    expect(orchestration).toContain("'receivables',v_credit_demand")
    expect(orchestration).toContain("'sales',v_sales_demand")
    expect(orchestration).toContain("'customer_health',v_customer_demand")
    expect(orchestration).not.toMatch(/ORDER BY[\s\S]{0,300}severity/i)
  })

  it('reuses the audited Receivables/Sales builder rather than duplicating those domain implementations', () => {
    expect(orchestration).toContain('RENAME TO build_operational_snapshot_two_domain_v1')
    expect(orchestration).toContain('ai_ops.build_operational_snapshot_two_domain_v1(')
    expect(orchestration).toContain('preserved two-domain builder')
  })

  it('requires all three immutable domain capture markers and enforces the one global hard cap', () => {
    expect(orchestration).toContain("dc.domain='receivables'")
    expect(orchestration).toContain("dc.domain='sales'")
    expect(orchestration).toContain("dc.domain='customer_health'")
    expect(orchestration).toContain('v_total_cases>v_limit')
    expect(orchestration).toContain('operational snapshot did not produce all three immutable domain capture markers')
  })

  it('refuses to add Customer Health after a worker context identity has already been bound', () => {
    expect(orchestration).toContain("NULLIF(v_run.result_summary->>'worker_context_hash','') IS NOT NULL")
    expect(orchestration).toContain('existing snapshot is already bound to a worker context and cannot add Customer Health')
  })

  it('keeps all operational business sources read-only during capture/orchestration', () => {
    expect(executable).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:customers|sales_orders|sales_order_items|targets|target_customers|target_progress|activities|visit_plans|visit_plan_items|call_plans|call_plan_items|customer_ledger|work_items|work_links)/i)
    expect(executable).not.toMatch(/recalculate_target_progress\s*\(/i)
  })
})