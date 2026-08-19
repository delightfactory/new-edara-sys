import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260817011800_ai_operations_feedback_asof_guard.sql',
), 'utf8')

describe('AI Operations feedback/outcome snapshot causality', () => {
  it('binds every learning collection to the immutable snapshot data_as_of', () => {
    expect(migration).toContain('f.created_at<=v_snapshot.data_as_of')
    expect(migration).toContain("f.created_at>=v_snapshot.data_as_of-interval '30 days'")
    expect(migration).toContain('o.observed_at<=v_snapshot.data_as_of')
    expect(migration).toContain("o.observed_at>=v_snapshot.data_as_of-interval '30 days'")
    expect(migration).toContain('dr.reviewed_at<=v_snapshot.data_as_of')
    expect(migration).toContain("dr.reviewed_at>=v_snapshot.data_as_of-interval '30 days'")
  })

  it('overrides all three prior-learning collections with as-of-safe evidence', () => {
    expect(migration).toContain("'recent_human_feedback',v_feedback")
    expect(migration).toContain("'recent_outcome_observations',v_outcomes")
    expect(migration).toContain("'recent_human_reviews',v_reviews")
    expect(migration).toContain("'learning_evidence_as_of',v_snapshot.data_as_of")
    expect(migration).toContain("'future_feedback_excluded',true")
    expect(migration).toContain("'future_outcomes_excluded',true")
    expect(migration).toContain("'future_reviews_excluded',true")
  })

  it('keeps learning evidence bounded and non-punitive', () => {
    expect(migration).toContain('LIMIT 12')
    expect(migration).toContain('left(f.feedback_note,300)')
    expect(migration).toContain('left(dr.review_note,300)')
    expect(migration).toContain("'does_not_self_modify_policy',true")
    expect(migration).toContain("'does_not_score_employees',true")
    expect(migration).toContain("'employee_performance_signal',false")
  })
})
