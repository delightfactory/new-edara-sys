import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const evidenceMigration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816164500_ai_operations_snapshot_case_evidence.sql',
), 'utf8')

const captureMigration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816170000_ai_operations_credit_snapshot_capture.sql',
), 'utf8')

describe('AI Operations immutable snapshot evidence contract', () => {
  it('adds only a planner-local immutable snapshot evidence table', () => {
    expect(evidenceMigration).toContain('DESIGN-TIME MIGRATION ONLY')
    expect(evidenceMigration).toContain('CREATE TABLE ai_ops.snapshot_cases')
    expect(evidenceMigration).not.toMatch(/CREATE\s+TABLE\s+public\./i)
    expect(evidenceMigration).not.toMatch(/ALTER\s+TABLE\s+public\./i)
    expect(evidenceMigration).not.toMatch(/CREATE\s+TRIGGER[\s\S]*?ON\s+public\./i)
  })

  it('freezes exact per-snapshot facts, responsibility evidence, trust and serialized size', () => {
    expect(evidenceMigration).toContain('snapshot_id UUID NOT NULL')
    expect(evidenceMigration).toContain('case_id UUID NOT NULL')
    expect(evidenceMigration).toContain('snapshot_rank INTEGER NOT NULL')
    expect(evidenceMigration).toContain("facts JSONB NOT NULL DEFAULT '{}'::JSONB")
    expect(evidenceMigration).toContain("responsibility_evidence JSONB NOT NULL DEFAULT '{}'::JSONB")
    expect(evidenceMigration).toContain("trust JSONB NOT NULL DEFAULT '{}'::JSONB")
    expect(evidenceMigration).toContain('payload_bytes INTEGER NOT NULL')
    expect(evidenceMigration).toContain('ai_ops_snapshot_cases_payload_bytes_nonnegative')
    expect(evidenceMigration).toContain('UNIQUE (snapshot_id, case_key)')
    expect(evidenceMigration).toContain('UNIQUE (snapshot_id, snapshot_rank)')
  })

  it('reuses the snapshot immutability guard for update and delete protection', () => {
    expect(evidenceMigration).toContain('CREATE TRIGGER trg_ai_ops_snapshot_cases_immutable')
    expect(evidenceMigration).toContain('BEFORE UPDATE OR DELETE ON ai_ops.snapshot_cases')
    expect(evidenceMigration).toContain('EXECUTE FUNCTION ai_ops.reject_snapshot_mutation()')
  })

  it('keeps snapshot evidence closed to browser roles', () => {
    expect(evidenceMigration).toContain('ALTER TABLE ai_ops.snapshot_cases ENABLE ROW LEVEL SECURITY;')
    expect(evidenceMigration).toContain('REVOKE ALL ON TABLE ai_ops.snapshot_cases FROM PUBLIC;')
    expect(evidenceMigration).toContain('REVOKE ALL ON TABLE ai_ops.snapshot_cases FROM anon;')
    expect(evidenceMigration).toContain('REVOKE ALL ON TABLE ai_ops.snapshot_cases FROM authenticated;')
    expect(evidenceMigration).not.toMatch(/GRANT\s+(?:SELECT|INSERT|UPDATE|DELETE|ALL).*ai_ops\.snapshot_cases/i)
  })

  it('captures immutable evidence in the same planner-local refresh operation that updates current case state', () => {
    expect(captureMigration).toContain('INSERT INTO ai_ops.cases(')
    expect(captureMigration).toContain('RETURNING id, status INTO v_case_id, v_case_status')
    expect(captureMigration).toContain('INSERT INTO ai_ops.snapshot_cases(')
    expect(captureMigration).toContain('v_candidate.facts')
    expect(captureMigration).toContain('v_candidate.responsibility_evidence')
    expect(captureMigration).toContain('v_candidate.trust')
    expect(captureMigration).toContain('snapshot_rank')
  })

  it('treats evidence capture as single-shot and pushes retry to the idempotent builder', () => {
    expect(captureMigration).toContain('ai_ops snapshot evidence already captured')
    expect(captureMigration).toContain('FROM ai_ops.snapshot_cases sc')
    expect(captureMigration).toContain('WHERE sc.snapshot_id = p_snapshot_id')
    expect(captureMigration).not.toContain('ON CONFLICT (snapshot_id, case_id) DO NOTHING')
    expect(captureMigration).toContain('Retry through build_credit_snapshot()')
  })

  it('computes and persists a conservative byte budget per frozen case', () => {
    expect(captureMigration).toContain('v_case_payload_bytes := octet_length(convert_to(')
    expect(captureMigration).toContain("'responsibility_evidence', v_candidate.responsibility_evidence")
    expect(captureMigration).toContain('v_case_payload_bytes')
    expect(captureMigration).toContain('v_evidence_bytes := v_evidence_bytes + v_case_payload_bytes')
    expect(captureMigration).toContain("'snapshot_evidence_bytes', v_evidence_bytes")
  })

  it('does not mutate any operational source or Work table', () => {
    for (const migration of [evidenceMigration, captureMigration]) {
      expect(migration).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:sales_orders|customers|customer_credit_history|sales_order_due_date_history|work_items|work_links)/i)
    }
  })
})
