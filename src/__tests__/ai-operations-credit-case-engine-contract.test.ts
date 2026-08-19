import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816165500_ai_operations_credit_case_engine.sql',
), 'utf8')

const sourceMap = readFileSync(resolve(
  process.cwd(),
  'docs/work-management/12_AI_OPERATIONS_CREDIT_SOURCE_MAP.md',
), 'utf8')

const executableSql = migration
  .split('\n')
  .filter(line => !line.trimStart().startsWith('--'))
  .join('\n')

describe('AI Operations credit case engine contract', () => {
  it('is design-only and creates functions only inside the isolated ai_ops boundary', () => {
    expect(migration).toContain('DESIGN-TIME MIGRATION ONLY')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION ai_ops.credit_overdue_candidates')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION ai_ops.refresh_credit_cases')
    expect(migration).not.toMatch(/CREATE\s+TABLE/i)
    expect(migration).not.toMatch(/ALTER\s+TABLE/i)
    expect(migration).not.toMatch(/CREATE\s+(?:UNIQUE\s+)?INDEX/i)
    expect(migration).not.toMatch(/CREATE\s+TRIGGER/i)
  })

  it('uses an explicit planner business date rather than the database UTC current date', () => {
    expect(migration).toContain('p_business_date DATE')
    expect(migration).toContain('so.due_date < p_business_date')
    expect(migration).toContain('(p_business_date - so.due_date)::INTEGER')
    expect(executableSql).not.toMatch(/CURRENT_DATE/i)
    expect(sourceMap).toContain('database timezone is UTC')
  })

  it('preserves the deployed overdue factual definition and remaining-balance formula', () => {
    expect(migration).toContain("'delivered'::public.sales_order_status")
    expect(migration).toContain("'partially_delivered'::public.sales_order_status")
    expect(migration).toContain("so.payment_terms IN ('credit', 'mixed')")
    expect(migration).toContain('COALESCE(so.total_amount, 0)')
    expect(migration).toContain('- COALESCE(so.paid_amount, 0)')
    expect(migration).toContain('- COALESCE(so.returned_amount, 0)')
    expect(migration).toContain("WHEN (p_business_date - so.due_date) >= 60 THEN 'critical'")
    expect(migration).toContain("WHEN (p_business_date - so.due_date) >= 30 THEN 'high'")
    expect(migration).toContain("WHEN (p_business_date - so.due_date) >= 7 THEN 'medium'")
  })

  it('keeps responsibility signals separate instead of inventing a single blame owner', () => {
    expect(migration).toContain('c.assigned_rep_id AS current_customer_rep_id')
    expect(migration).toContain('so.rep_id AS order_rep_id')
    expect(migration).toContain('so.created_by_id AS order_creator_id')
    expect(migration).toContain('order_creator.full_name::TEXT AS order_creator_name')
    expect(migration).toContain('so.credit_override_by')
    expect(migration).toContain('credit_override_actor.full_name::TEXT AS credit_override_by_name')
    expect(migration).toContain('due_hist.changed_by AS last_due_date_changed_by')
    expect(migration).toContain("'order_creator_not_necessarily_accountable'")
    expect(migration).toContain("'explicit_credit_override'")
    expect(migration).toContain("'governed_due_date_change'")
  })

  it('adds customer credit-policy history as evidence without treating it as invoice ownership', () => {
    expect(migration).toContain('FROM public.customer_credit_history h')
    expect(migration).toContain('credit_hist.limit_before AS last_credit_limit_before')
    expect(migration).toContain('credit_hist.limit_after AS last_credit_limit_after')
    expect(migration).toContain("'customer_credit_limit_change'")
    expect(migration).toContain("'limit_before', b.last_credit_limit_before")
    expect(migration).toContain("'limit_after', b.last_credit_limit_after")
  })

  it('bounds human-entered reason text and labels it as untrusted data', () => {
    expect(migration).toContain('left(credit_hist.reason::TEXT, 500)')
    expect(migration).toContain('left(due_hist.reason::TEXT, 500)')
    expect(migration).toContain("'content_trust', 'untrusted_human_text'")
    expect(migration).toContain("'human_text_policy', 'bounded_untrusted_data'")
    expect(migration).toContain("'human_text_max_chars', 500")
  })

  it('reuses the existing Work link mechanism for exact invoice collision detection', () => {
    expect(migration).toContain('FROM public.work_links wl')
    expect(migration).toContain("wl.entity_type = 'sales_order'")
    expect(migration).toContain('wl.entity_id = so.id')
    expect(migration).toContain("wi.status NOT IN ('done'::public.work_item_status, 'cancelled'::public.work_item_status)")
    expect(migration).toContain('wi.title::TEXT AS title')
    expect(migration).toContain('wl.relation_type::TEXT AS relation_type')
    expect(migration).not.toMatch(/CREATE\s+TABLE\s+(?:public\.)?work_(?:entity_)?links/i)
  })

  it('does not mutate Sales, Customers or Work and exposes no browser callable function', () => {
    expect(migration).not.toMatch(/UPDATE\s+public\.(?:sales_orders|customers|work_items|work_links)/i)
    expect(migration).not.toMatch(/INSERT\s+INTO\s+public\.(?:sales_orders|customers|work_items|work_links)/i)
    expect(migration).not.toMatch(/DELETE\s+FROM\s+public\.(?:sales_orders|customers|work_items|work_links)/i)
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.credit_overdue_candidates(DATE, INTEGER) FROM authenticated;')
    expect(migration).toContain('REVOKE ALL ON FUNCTION ai_ops.refresh_credit_cases(UUID, DATE, INTEGER) FROM authenticated;')
    expect(migration).not.toMatch(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\./i)
  })

  it('uses a stable invoice-specific case key and does not auto-resolve a truncated scan', () => {
    expect(migration).toContain("'receivables:overdue_invoice:' || b.order_id::TEXT")
    expect(migration).toContain("'resolution_performed', false")
    expect(migration).toContain('p_limit INTEGER DEFAULT 100')
    expect(migration).toContain('LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500)')
  })
})
