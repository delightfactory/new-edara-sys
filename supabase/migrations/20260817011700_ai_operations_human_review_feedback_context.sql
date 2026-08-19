-- ============================================================================
-- AI Operations — human review outcomes as bounded future planning context
--
-- Approve/Reject is authoritative management feedback. It must be visible to
-- later planner runs as evidence of prior human judgement, without becoming a
-- self-modifying policy or employee-performance signal.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '30s';

ALTER FUNCTION ai_ops.build_global_operational_context(UUID,UUID)
  RENAME TO build_global_operational_context_pre_human_review_feedback_v1;
REVOKE ALL ON FUNCTION ai_ops.build_global_operational_context_pre_human_review_feedback_v1(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ai_ops.build_global_operational_context(
  p_snapshot_id UUID,
  p_run_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_base JSONB;
  v_reviews JSONB:='[]'::JSONB;
BEGIN
  v_base:=ai_ops.build_global_operational_context_pre_human_review_feedback_v1(
    p_snapshot_id,p_run_id
  );

  SELECT COALESCE(jsonb_agg(review_row ORDER BY reviewed_at DESC),'[]'::JSONB)
  INTO v_reviews
  FROM (
    SELECT
      dr.reviewed_at,
      jsonb_build_object(
        'review_id',dr.id,
        'decision_id',d.id,
        'case_id',d.case_id,
        'domain',c.domain,
        'case_type',c.case_type,
        'decision_type',d.decision_type,
        'review_state',dr.review_state,
        'reviewed_at',dr.reviewed_at,
        'review_note',CASE
          WHEN dr.review_note IS NULL THEN NULL
          ELSE left(dr.review_note,300)
        END,
        'decision_revision',dr.decision_revision,
        'human_override_authoritative',true,
        'feedback_is_policy_change',false,
        'employee_performance_signal',false,
        'content_trust',CASE WHEN dr.review_note IS NULL THEN 'structured_human_decision' ELSE 'bounded_untrusted_human_text' END
      ) AS review_row
    FROM ai_ops.decision_reviews dr
    JOIN ai_ops.decisions d ON d.id=dr.decision_id
    JOIN ai_ops.cases c ON c.id=d.case_id
    JOIN ai_ops.planner_runs r ON r.id=d.run_id
    WHERE r.id<>p_run_id
      AND dr.reviewed_at>=clock_timestamp()-interval '30 days'
    ORDER BY dr.reviewed_at DESC,dr.id DESC
    LIMIT 12
  ) q;

  RETURN v_base||jsonb_build_object(
    'recent_human_reviews',v_reviews,
    'human_review_feedback_semantics',jsonb_build_object(
      'authoritative_human_judgement',true,
      'used_as_future_planning_evidence',true,
      'does_not_self_modify_policy',true,
      'does_not_score_employees',true,
      'bounded_review_note_chars',300,
      'max_review_rows',12
    )
  );
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.build_global_operational_context(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.build_global_operational_context(UUID,UUID) IS
  'Frozen global planning frame enriched with bounded prior management Approve/Reject outcomes. Human judgement is authoritative evidence, never self-modifying policy or employee scoring.';

RESET lock_timeout;
RESET statement_timeout;
