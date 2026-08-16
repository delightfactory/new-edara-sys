import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816170500_ai_operations_credit_snapshot_builder.sql',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations atomic Credit snapshot builder contract', () => {
  it('is planner-internal, design-only and adds no browser or worker grants', () => {
    expect(migration).toContain('DESIGN-TIME MIGRATION ONLY')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION ai_ops.build_credit_snapshot')
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.build_credit_snapshot(UUID, INTEGER) FROM authenticated;')
    expect(migration).not.toMatch(/GRANT\s+EXECUTE/i)
    expect(migration).not.toMatch(/CREATE\s+TABLE|CREATE\s+TRIGGER|ALTER\s+TABLE/i)
  })

  it('serializes competing retries and reuses an existing run snapshot before operational rereads', () => {
    expect(migration).toContain("pg_advisory_xact_lock(hashtextextended('ai_ops:credit_snapshot:' || p_run_id::TEXT, 0))")
    expect(migration).toContain('FROM ai_ops.snapshots')
    expect(migration).toContain('WHERE run_id = p_run_id')
    expect(migration).toContain("'idempotent_reuse', true")
    expect(migration.indexOf("'idempotent_reuse', true")).toBeLessThan(migration.indexOf('FROM public.sales_orders so'))
  })

  it('accepts only buildable run states and derives all date logic from the durable Cairo business date', () => {
    expect(migration).toContain("v_run.status NOT IN ('pending', 'claimed', 'reasoning')")
    expect(migration).toContain('so.due_date < v_run.business_date')
    expect(migration).toContain('(v_run.business_date - so.due_date)::INTEGER')
    expect(migration).toContain("'business_date', v_run.business_date")
    expect(executableSql).not.toMatch(/CURRENT_DATE/i)
  })

  it('preserves the deployed overdue definition and does not invent a new receivables KPI', () => {
    expect(migration).toContain("'delivered'::public.sales_order_status")
    expect(migration).toContain("'partially_delivered'::public.sales_order_status")
    expect(migration).toContain("so.payment_terms IN ('credit', 'mixed')")
    expect(migration).toContain('COALESCE(so.total_amount, 0)')
    expect(migration).toContain('- COALESCE(so.paid_amount, 0)')
    expect(migration).toContain('- COALESCE(so.returned_amount, 0)')
  })

  it('bounds cases and trips a circuit breaker instead of flooding the planner', () => {
    expect(migration).toContain('v_settings.max_cases_per_snapshot')
    expect(migration).toContain('v_case_limit := LEAST(')
    expect(migration).toContain('GREATEST(v_settings.max_cases_per_snapshot * 10, 100)')
    expect(migration).toContain("'circuit_breaker', v_circuit_breaker")
    expect(migration).toContain("v_snapshot_status := 'partial'")
  })

  it('keeps operational overdue trust conservative even when supporting AR analytics is healthy', () => {
    expect(migration).toContain("t.component_name = 'fact_ar_collections_attributed_to_origin_sale_date'")
    expect(migration).toContain("'state', 'partial'")
    expect(migration).toContain("COALESCE(v_ar_stale, true)")
    expect(migration).toContain("COALESCE(v_ar_status, 'UNKNOWN')")
    expect(migration).toContain('القيمة ليست إقفالًا محاسبيًا نهائيًا')
  })

  it('creates the immutable snapshot and captures case evidence in one function-level transaction path', () => {
    const snapshotInsert = migration.indexOf('INSERT INTO ai_ops.snapshots(')
    const snapshotId = migration.indexOf('RETURNING id INTO v_snapshot_id')
    const capture = migration.indexOf('ai_ops.refresh_credit_cases(v_snapshot_id, v_run.business_date, v_case_limit)')

    expect(snapshotInsert).toBeGreaterThan(-1)
    expect(snapshotId).toBeGreaterThan(snapshotInsert)
    expect(capture).toBeGreaterThan(snapshotId)
    expect(migration).toContain('if evidence capture fails, the snapshot insert rolls back')
  })

  it('accounts for header plus frozen-case bytes as the estimated AI context budget', () => {
    expect(migration).toContain("'header_payload_bytes', v_payload_bytes")
    expect(migration).toContain("'snapshot_evidence_bytes', v_evidence_bytes")
    expect(migration).toContain('v_estimated_context_bytes := v_payload_bytes::BIGINT + v_evidence_bytes')
    expect(migration).toContain("'estimated_context_bytes', v_estimated_context_bytes")
    expect(migration).toContain('COALESCE(sum(sc.payload_bytes), 0)::BIGINT')
  })

  it('never mutates operational Sales, Customer or Work data', () => {
    expect(migration).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:sales_orders|customers|customer_credit_history|sales_order_due_date_history|work_items|work_links)/i)
    expect(migration).not.toMatch(/work_create_task|work_delegate|work_transfer_ownership|work_escalate/i)
  })
})
