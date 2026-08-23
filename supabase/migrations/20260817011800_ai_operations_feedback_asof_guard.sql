-- ============================================================================
-- AI Operations — snapshot as-of guard for learning / feedback evidence
--
-- A recovery attempt may happen after new reviews, dispositions or outcomes were
-- recorded. Those later facts did not exist when the immutable snapshot was
-- taken and must never leak backwards into that historical model input. This
-- final global-context wrapper replaces all recent feedback/outcome collections
-- with rows bounded by the snapshot's exact data_as_of timestamp.
-- ============================================================================
SET lock_timeout = '5s';
SET statement_timeout = '30s';

ALTER FUNCTION ai_ops.build_global_operational_context(UUID,UUID)
  RENAME TO build_global_operational_context_pre_feedback_asof_v1;
REVOKE ALL ON FUNCTION ai_ops.build_global_operational_context_pre_feedback_asof_v1(UUID,UUID)
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
  v_snapshot ai_ops.snapshots%ROWTYPE;
  v_base JSONB;
  v_feedback JSONB := '[]'::JSONB;
  v_outcomes JSONB := '[]'::JSONB;
  v_reviews JSONB := '[]'::JSONB;
BEGIN
  SELECT * INTO v_snapshot
  FROM ai_ops.snapshots s
  WHERE s.id=p_snapshot_id AND s.run_id=p_run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'snapshot/run binding is invalid for feedback as-of context';
  END IF;

  v_base:=ai_ops.build_global_operational_context_pre_feedback_asof_v1(
    p_snapshot_id,p_run_id
  );

  SELECT COALESCE(jsonb_agg(row_payload ORDER BY created_at DESC,feedback_id DESC),'[]'::JSONB)
  INTO v_feedback
  FROM (
    SELECT
      f.id AS feedback_id,
      f.created_at,
      jsonb_build_object(
        'feedback_id',f.id,
        'decision_id',d.id,
        'case_id',d.case_id,
        'domain',c.domain,
        'case_type',c.case_type,
        'decision_type',d.decision_type,
        'feedback_reason',f.feedback_reason,
        'feedback_note',CASE WHEN f.feedback_note IS NULL THEN NULL ELSE left(f.feedback_note,300) END,
        'created_at',f.created_at,
        'as_of_snapshot',v_snapshot.data_as_of,
        'human_feedback_is_planning_evidence',true,
        'feedback_is_policy_change',false,
        'employee_performance_signal',false,
        'content_trust',CASE
          WHEN f.feedback_note IS NULL THEN 'structured_feedback'
          ELSE 'bounded_untrusted_human_text'
        END
      ) AS row_payload
    FROM ai_ops.decision_feedback f
    JOIN ai_ops.decisions d ON d.id=f.decision_id
    JOIN ai_ops.cases c ON c.id=d.case_id
    WHERE f.created_at<=v_snapshot.data_as_of
      AND f.created_at>=v_snapshot.data_as_of-interval '30 days'
      AND d.run_id<>p_run_id
    ORDER BY f.created_at DESC,f.id DESC
    LIMIT 12
  ) q;

  SELECT COALESCE(jsonb_agg(row_payload ORDER BY observed_at DESC,outcome_id DESC),'[]'::JSONB)
  INTO v_outcomes
  FROM (
    SELECT
      o.id AS outcome_id,
      o.observed_at,
      jsonb_build_object(
        'outcome_id',o.id,
        'case_id',o.case_id,
        'decision_id',o.decision_id,
        'work_item_id',o.work_item_id,
        'domain',c.domain,
        'case_type',c.case_type,
        'outcome_type',o.outcome_type,
        'observed_at',o.observed_at,
        'as_of_snapshot',v_snapshot.data_as_of,
        'completion_is_not_automatically_success',true,
        'employee_performance_signal',false
      ) AS row_payload
    FROM ai_ops.case_outcomes o
    JOIN ai_ops.cases c ON c.id=o.case_id
    WHERE o.observed_at<=v_snapshot.data_as_of
      AND o.observed_at>=v_snapshot.data_as_of-interval '30 days'
    ORDER BY o.observed_at DESC,o.id DESC
    LIMIT 12
  ) q;

  SELECT COALESCE(jsonb_agg(row_payload ORDER BY reviewed_at DESC,review_id DESC),'[]'::JSONB)
  INTO v_reviews
  FROM (
    SELECT
      dr.id AS review_id,
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
        'review_note',CASE WHEN dr.review_note IS NULL THEN NULL ELSE left(dr.review_note,300) END,
        'decision_revision',dr.decision_revision,
        'as_of_snapshot',v_snapshot.data_as_of,
        'human_override_authoritative',true,
        'feedback_is_policy_change',false,
        'employee_performance_signal',false,
        'content_trust',CASE
          WHEN dr.review_note IS NULL THEN 'structured_human_decision'
          ELSE 'bounded_untrusted_human_text'
        END
      ) AS row_payload
    FROM ai_ops.decision_reviews dr
    JOIN ai_ops.decisions d ON d.id=dr.decision_id
    JOIN ai_ops.cases c ON c.id=d.case_id
    WHERE dr.reviewed_at<=v_snapshot.data_as_of
      AND dr.reviewed_at>=v_snapshot.data_as_of-interval '30 days'
      AND d.run_id<>p_run_id
    ORDER BY dr.reviewed_at DESC,dr.id DESC
    LIMIT 12
  ) q;

  RETURN v_base||jsonb_build_object(
    'recent_human_feedback',v_feedback,
    'recent_outcome_observations',v_outcomes,
    'recent_human_reviews',v_reviews,
    'learning_evidence_as_of',v_snapshot.data_as_of,
    'learning_evidence_semantics',jsonb_build_object(
      'strict_snapshot_as_of',true,
      'future_feedback_excluded',true,
      'future_outcomes_excluded',true,
      'future_reviews_excluded',true,
      'window_days',30,
      'max_rows_per_collection',12,
      'does_not_self_modify_policy',true,
      'does_not_score_employees',true
    )
  );
END;
$$;
REVOKE ALL ON FUNCTION ai_ops.build_global_operational_context(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION ai_ops.build_global_operational_context(UUID,UUID) IS
  'Final frozen global planning builder. Prior feedback, management review and outcomes are bounded by the immutable snapshot data_as_of so later facts cannot leak backwards into historical reasoning.';

RESET lock_timeout;
RESET statement_timeout;
