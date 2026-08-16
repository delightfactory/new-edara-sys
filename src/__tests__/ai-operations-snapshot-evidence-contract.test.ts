import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const evidenceMigration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816164500_ai_operations_snapshot_case_evidence.sql',
), 'utf8')

const domainCaptureMigration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816164700_ai_operations_snapshot_domain_captures.sql',
), 'utf8')

const captureMigration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260816170000_ai_operations_credit_snapshot_capture.sql',
), 'utf8')

describe('AI Operations immutable snapshot evidence contract', () => {
  it('adds only planner-local immutable snapshot evidence structures', () => {
    expect(evidenceMigration).toContain('DESIGN-TIME MIGRATION ONLY')
    expect(evidenceMigration).toContain('CREATE TABLE ai_ops.snapshot_cases')
    expect(domainCaptureMigration).toContain('CREATE TABLE ai_ops.snapshot_domain_captures')
    for (const migration of [evidenceMigration, domainCaptureMigration]) {
      expect(migration).not.toMatch(/CREATE\s+TABLE\s+public\./i)
      expect(migration).not.toMatch(/ALTER\s+TABLE\s+public\./i)
      expect(migration).not.toMatch(/CREATE\s+TRIGGER[\s\S]*?ON\s+public\./i)
    }
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

  it('records immutable domain completion independently from case count', () => {
    expect(domainCaptureMigration).toContain('PRIMARY KEY (snapshot_id, domain)')
    expect(domainCaptureMigration).toContain('case_count INTEGER NOT NULL DEFAULT 0')
    expect(domainCaptureMigration).toContain('evidence_bytes BIGINT NOT NULL DEFAULT 0')
    expect(domainCaptureMigration).toContain("capture_status IN ('completed','partial','blocked')")
    expect(domainCaptureMigration).toContain('business_date DATE NOT NULL')
    expect(domainCaptureMigration).toContain('capture_version VARCHAR(60) NOT NULL')
  })

  it('protects both evidence rows and domain completion markers from mutation', () => {
    expect(evidenceMigration).toContain('CREATE TRIGGER trg_ai_ops_snapshot_cases_immutable')
    expect(evidenceMigration).toContain('BEFORE UPDATE OR DELETE ON ai_ops.snapshot_cases')
    expect(domainCaptureMigration).toContain('CREATE TRIGGER trg_ai_ops_snapshot_domain_captures_immutable')
    expect(domainCaptureMigration).toContain('BEFORE UPDATE OR DELETE ON ai_ops.snapshot_domain_captures')
    expect(domainCaptureMigration).toContain('EXECUTE FUNCTION ai_ops.reject_snapshot_mutation()')
  })

  it('keeps immutable snapshot structures closed to browser roles', () => {
    for (const [migration, table] of [
      [evidenceMigration, 'snapshot_cases'],
      [domainCaptureMigration, 'snapshot_domain_captures'],
    ] as const) {
      expect(migration).toContain(`ALTER TABLE ai_ops.${table} ENABLE ROW LEVEL SECURITY;`)
      expect(migration).toContain(`REVOKE ALL ON TABLE ai_ops.${table} FROM PUBLIC;`)
      expect(migration).toContain(`REVOKE ALL ON TABLE ai_ops.${table} FROM anon;`)
      expect(migration).toContain(`REVOKE ALL ON TABLE ai_ops.${table} FROM authenticated;`)
    }
  })

  it('captures immutable case evidence and writes a domain marker in the same planner-local refresh', () => {
    expect(captureMigration).toContain('INSERT INTO ai_ops.cases(')
    expect(captureMigration).toContain('RETURNING id, status INTO v_case_id, v_case_status')
    expect(captureMigration).toContain('INSERT INTO ai_ops.snapshot_cases(')
    expect(captureMigration).toContain('INSERT INTO ai_ops.snapshot_domain_captures(')
    expect(captureMigration).toContain('v_candidate.facts')
    expect(captureMigration).toContain('v_candidate.responsibility_evidence')
    expect(captureMigration).toContain('v_candidate.trust')
  })

  it('uses the domain marker as the single-shot invariant and detects inconsistent partial capture', () => {
    expect(captureMigration).toContain("dc.domain = 'receivables'")
    expect(captureMigration).toContain('ai_ops receivables domain already captured')
    expect(captureMigration).toContain('ai_ops receivables evidence exists without capture marker')
    expect(captureMigration).toContain("sc.domain = 'receivables'")
    expect(captureMigration).toContain('Retry through build_credit_snapshot()')
  })

  it('writes the completion marker even when no candidate loop rows exist', () => {
    const loopStart = captureMigration.indexOf('FOR v_candidate IN')
    const loopEnd = captureMigration.indexOf('END LOOP;', loopStart)
    const markerInsert = captureMigration.indexOf('INSERT INTO ai_ops.snapshot_domain_captures(')

    expect(loopStart).toBeGreaterThan(-1)
    expect(loopEnd).toBeGreaterThan(loopStart)
    expect(markerInsert).toBeGreaterThan(loopEnd)
    expect(captureMigration).toContain("'capture_marker_written', true")
    expect(captureMigration).toContain('v_count')
  })

  it('computes and persists a conservative byte budget per frozen case and domain', () => {
    expect(captureMigration).toContain('v_case_payload_bytes := octet_length(convert_to(')
    expect(captureMigration).toContain("'responsibility_evidence', v_candidate.responsibility_evidence")
    expect(captureMigration).toContain('v_evidence_bytes := v_evidence_bytes + v_case_payload_bytes')
    expect(captureMigration).toContain('evidence_bytes')
    expect(captureMigration).toContain("'snapshot_evidence_bytes', v_evidence_bytes")
  })

  it('does not mutate any operational source or Work table', () => {
    for (const migration of [evidenceMigration, domainCaptureMigration, captureMigration]) {
      expect(migration).not.toMatch(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.(?:sales_orders|customers|customer_credit_history|sales_order_due_date_history|work_items|work_links)/i)
    }
  })
})
