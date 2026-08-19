import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816171000_ai_operations_admin_read_gateway.sql',
), 'utf8')

const service = readFileSync(resolve(
  process.cwd(),
  'src/features/ai-operations/service.ts',
), 'utf8')

describe('AI Operations management read gateway contract', () => {
  it('is design-only and exposes only the two bounded management read RPCs', () => {
    expect(migration).toContain('DESIGN-TIME MIGRATION ONLY')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.ai_ops_get_console_snapshot()')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.ai_ops_get_case_detail(p_case_id UUID)')
    expect(migration.match(/CREATE OR REPLACE FUNCTION public\.ai_ops_/g)).toHaveLength(2)
    expect(migration).not.toMatch(/CREATE\s+TABLE/i)
    expect(migration).not.toMatch(/CREATE\s+TRIGGER/i)
  })

  it('follows the deployed Work admin authentication and permission pattern', () => {
    expect(migration).toContain('v_actor UUID := auth.uid()')
    expect(migration.match(/private\.work_actor_is_active\(v_actor\)/g)?.length).toBeGreaterThanOrEqual(2)
    expect(migration.match(/public\.check_permission\(v_actor, 'work\.policies\.manage'\)/g)?.length).toBeGreaterThanOrEqual(2)
    expect(migration.match(/ERRCODE = '42501'/g)?.length).toBeGreaterThanOrEqual(2)
    expect(migration).toContain("SET search_path = ''")
  })

  it('keeps ai_ops tables private and grants no anonymous execution', () => {
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.ai_ops_get_console_snapshot() FROM anon;')
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.ai_ops_get_case_detail(UUID) FROM anon;')
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.ai_ops_get_console_snapshot() TO authenticated;')
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.ai_ops_get_case_detail(UUID) TO authenticated;')
    expect(migration).not.toMatch(/GRANT\s+(?:SELECT|INSERT|UPDATE|DELETE|ALL)\s+ON\s+(?:TABLE\s+)?ai_ops\./i)
    expect(migration).not.toMatch(/GRANT\s+USAGE\s+ON\s+SCHEMA\s+ai_ops\s+TO\s+(?:anon|authenticated)/i)
  })

  it('is read-only and never becomes a worker or action gateway', () => {
    expect(migration).not.toMatch(/\bINSERT\s+INTO\b/i)
    expect(migration).not.toMatch(/\bUPDATE\s+(?:ai_ops|public|private)\./i)
    expect(migration).not.toMatch(/\bDELETE\s+FROM\b/i)
    expect(migration).not.toMatch(/work_create_task|work_delegate|work_transfer_ownership|work_escalate/i)
    expect(migration).not.toMatch(/claim_run|stage_decision|commit_decision|worker_token|api_key/i)
  })

  it('keeps normal console reads bounded', () => {
    expect(migration).toContain('LIMIT 10')
    expect(migration).toContain('LIMIT 30')
    expect(migration).toContain('LIMIT v_settings.max_cases_per_snapshot')
    expect(migration).toContain('WHERE sc.snapshot_id = v_snapshot.id')
    expect(migration).toContain('ORDER BY sc.snapshot_rank ASC')
  })

  it('returns a safe not-ready payload when foundation exists but no snapshot has been generated', () => {
    expect(migration).toContain("'integration_state', 'database_not_ready'")
    expect(migration).toContain("'attention', '[]'::JSONB")
    expect(migration).toContain("'trust', '[]'::JSONB")
    expect(migration).toContain("'pulse', '[]'::JSONB")
  })

  it('reads planner evidence from immutable snapshot_cases rather than mutable current case facts', () => {
    expect(migration).toContain('FROM ai_ops.snapshot_cases sc')
    expect(migration).toContain('JOIN ai_ops.cases c ON c.id = sc.case_id')
    expect(migration).toContain('v_snapshot_case ai_ops.snapshot_cases%ROWTYPE')
    expect(migration).toContain('v_snapshot_case.responsibility_evidence')
    expect(migration).toContain('v_snapshot_case.facts')
    expect(migration).not.toContain("jsonb_typeof(v_case.facts->'existing_active_work')")
  })

  it('normalizes credit evidence without collapsing causal signals into one routing rule', () => {
    expect(migration).toContain("('credit_override', 'صاحب قرار تجاوز الائتمان', 'direct'")
    expect(migration).toContain("('last_due_date_change', 'آخر من عدّل تاريخ الاستحقاق', 'direct'")
    expect(migration).toContain("('customer_credit_change', 'آخر من عدّل حد ائتمان العميل', 'supporting'")
    expect(migration).toContain("('current_customer_rep', 'مندوب العميل الحالي', 'supporting'")
    expect(migration).toContain("('order_creator', 'منشئ الفاتورة', 'contextual'")
    expect(migration).toContain("left(v_snapshot_case.responsibility_evidence->e.evidence_key->>'reason', 500)")
  })

  it('includes exact existing Work and active operational context in lazy case review', () => {
    expect(migration).toContain("jsonb_typeof(v_snapshot_case.facts->'existing_active_work') = 'object'")
    expect(migration).toContain("c.subject_type = 'sales_order'")
    expect(migration).toContain("c.subject_type = 'customer'")
    expect(migration).toContain("'relevant_context_ids', v_context_ids")
  })

  it('matches the RPC names already used by the guarded TypeScript service adapter', () => {
    expect(service).toContain("supabase.rpc('ai_ops_get_console_snapshot')")
    expect(service).toContain("supabase.rpc('ai_ops_get_case_detail', { p_case_id: caseId })")
  })
})
