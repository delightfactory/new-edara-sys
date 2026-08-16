-- ============================================================================
-- AI Operations Planner — Human Decision Review Gate
--
-- DESIGN-TIME MIGRATION ONLY. Do not apply until explicitly reviewed/approved.
-- Depends on:
--   * 20260816172600_ai_operations_current_state_guard.sql
--
-- Separates two meanings that must never be conflated:
--   validation_state = system says the staged recommendation is still current/safe
--   human review     = an authorised manager accepts/rejects that recommendation
--
-- No operational Work/Sales mutation occurs in this migration.
-- ============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '30s';

CREATE TABLE ai_ops.decision_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  decision_id UUID NOT NULL UNIQUE
    REFERENCES ai_ops.decisions(id) ON DELETE RESTRICT,
  review_state TEXT NOT NULL,
  reviewed_by_user_id UUID NOT NULL,
  reviewed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  review_note TEXT,
  decision_fingerprint TEXT NOT NULL,
  decision_revision INTEGER NOT NULL,
  validation_state_at_review TEXT NOT NULL,
  validation_at_review TIMESTAMPTZ,
  metadata JSONB NOT NULL DEFAULT '{}'::JSONB,

  CONSTRAINT ai_ops_decision_reviews_state_check
    CHECK (review_state IN ('approved','rejected')),
  CONSTRAINT ai_ops_decision_reviews_revision_positive
    CHECK (decision_revision > 0),
  CONSTRAINT ai_ops_decision_reviews_validation_state_check
    CHECK (validation_state_at_review IN ('pending','validated','rejected')),
  CONSTRAINT ai_ops_decision_reviews_note_length
    CHECK (review_note IS NULL OR length(review_note) <= 1000),
  CONSTRAINT ai_ops_decision_reviews_fingerprint_check
    CHECK (decision_fingerprint ~ '^[a-f0-9]{32}$'),
  CONSTRAINT ai_ops_decision_reviews_metadata_object
    CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE INDEX idx_ai_ops_decision_reviews_reviewer_time
  ON ai_ops.decision_reviews(reviewed_by_user_id, reviewed_at DESC);

ALTER TABLE ai_ops.decision_reviews ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE ai_ops.decision_reviews FROM PUBLIC;
REVOKE ALL ON TABLE ai_ops.decision_reviews FROM anon;
REVOKE ALL ON TABLE ai_ops.decision_reviews FROM authenticated;

CREATE OR REPLACE FUNCTION ai_ops.reject_decision_review_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'AI decision review history is immutable';
END;
$$;

REVOKE ALL ON FUNCTION ai_ops.reject_decision_review_mutation() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER trg_ai_ops_decision_reviews_immutable
  BEFORE UPDATE OR DELETE ON ai_ops.decision_reviews
  FOR EACH ROW EXECUTE FUNCTION ai_ops.reject_decision_review_mutation();

CREATE OR REPLACE FUNCTION public.ai_ops_review_decision(
  p_decision_id UUID,
  p_review_state TEXT,
  p_review_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_decision ai_ops.decisions%ROWTYPE;
  v_run ai_ops.planner_runs%ROWTYPE;
  v_existing ai_ops.decision_reviews%ROWTYPE;
  v_issues JSONB;
  v_now TIMESTAMPTZ := clock_timestamp();
  v_fingerprint TEXT;
  v_note TEXT := NULLIF(btrim(COALESCE(p_review_note, '')), '');
BEGIN
  IF v_actor IS NULL OR NOT private.work_actor_is_active(v_actor) THEN
    RAISE EXCEPTION 'المستخدم غير متاح لمراجعة قرار AI Operations'
      USING ERRCODE = '42501';
  END IF;

  IF NOT COALESCE(public.check_permission(v_actor, 'work.policies.manage'), false) THEN
    RAISE EXCEPTION 'لا تملك صلاحية مراجعة قرارات التشغيل الذكي'
      USING ERRCODE = '42501';
  END IF;

  IF p_review_state NOT IN ('approved','rejected') THEN
    RAISE EXCEPTION 'حالة المراجعة غير صحيحة';
  END IF;

  IF v_note IS NOT NULL AND length(v_note) > 1000 THEN
    RAISE EXCEPTION 'ملاحظة المراجعة تتجاوز الحد المسموح';
  END IF;

  SELECT * INTO v_decision
  FROM ai_ops.decisions
  WHERE id = p_decision_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'AI Operations decision not found'; END IF;

  SELECT * INTO v_run
  FROM ai_ops.planner_runs
  WHERE id = v_decision.run_id
  FOR UPDATE;

  IF NOT FOUND OR v_run.status <> 'staged' THEN
    RAISE EXCEPTION 'القرار ليس ضمن Run قابلة للمراجعة';
  END IF;

  v_fingerprint := md5(jsonb_build_object(
    'id', v_decision.id,
    'run_id', v_decision.run_id,
    'case_id', v_decision.case_id,
    'revision', v_decision.revision,
    'decision_type', v_decision.decision_type,
    'recommended_owner_user_id', v_decision.recommended_owner_user_id,
    'recommended_assignee_user_id', v_decision.recommended_assignee_user_id,
    'responsibility_basis', v_decision.responsibility_basis,
    'concise_rationale', v_decision.concise_rationale,
    'confidence', v_decision.confidence,
    'expected_outcome', v_decision.expected_outcome,
    'next_action_text', v_decision.next_action_text,
    'due_at', v_decision.due_at,
    'review_after', v_decision.review_after,
    'linked_work_item_id', v_decision.linked_work_item_id
  )::TEXT);

  SELECT * INTO v_existing
  FROM ai_ops.decision_reviews
  WHERE decision_id = p_decision_id;

  IF FOUND THEN
    IF v_existing.review_state = p_review_state
       AND v_existing.reviewed_by_user_id = v_actor
       AND v_existing.decision_fingerprint = v_fingerprint
       AND COALESCE(v_existing.review_note, '') = COALESCE(v_note, '') THEN
      RETURN jsonb_build_object(
        'reviewed', true,
        'idempotent_reuse', true,
        'review_id', v_existing.id,
        'decision_id', p_decision_id,
        'review_state', v_existing.review_state
      );
    END IF;

    RAISE EXCEPTION 'القرار تمت مراجعته بالفعل ولا يمكن استبدال سجل المراجعة';
  END IF;

  IF p_review_state = 'approved' THEN
    -- Approval always performs a fresh guard check. Previous validation may be
    -- minutes/hours old and is not execution authority.
    v_issues := ai_ops.current_decision_issues(p_decision_id);

    IF jsonb_array_length(v_issues) > 0 THEN
      UPDATE ai_ops.decisions
      SET
        validation_state = 'rejected',
        validation_detail = validation_detail || jsonb_build_object(
          'approval_revalidation_failed', true,
          'approval_revalidation_codes', v_issues,
          'approval_revalidation_at', v_now,
          'requires_human_review', true,
          'stage_only', true
        ),
        validated_at = v_now,
        validated_by_user_id = NULL
      WHERE id = p_decision_id;

      RAISE EXCEPTION 'الواقع التشغيلي تغير؛ راجع الحالة قبل الموافقة';
    END IF;

    UPDATE ai_ops.decisions
    SET
      validation_state = 'validated',
      validation_detail = validation_detail || jsonb_build_object(
        'approval_revalidated_against_current_state', true,
        'approval_revalidated_at', v_now,
        'requires_human_review', true,
        'stage_only', true
      ),
      validated_at = v_now,
      validated_by_user_id = NULL
    WHERE id = p_decision_id
    RETURNING * INTO v_decision;
  END IF;

  INSERT INTO ai_ops.decision_reviews(
    decision_id,
    review_state,
    reviewed_by_user_id,
    reviewed_at,
    review_note,
    decision_fingerprint,
    decision_revision,
    validation_state_at_review,
    validation_at_review,
    metadata
  ) VALUES (
    p_decision_id,
    p_review_state,
    v_actor,
    v_now,
    v_note,
    v_fingerprint,
    v_decision.revision,
    v_decision.validation_state,
    v_decision.validated_at,
    jsonb_build_object(
      'human_review', true,
      'execution_performed', false,
      'auto_commit_enabled_at_review', false
    )
  )
  RETURNING * INTO v_existing;

  RETURN jsonb_build_object(
    'reviewed', true,
    'idempotent_reuse', false,
    'review_id', v_existing.id,
    'decision_id', p_decision_id,
    'review_state', p_review_state,
    'validation_state', v_decision.validation_state,
    'execution_performed', false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.ai_ops_review_decision(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ai_ops_review_decision(UUID, TEXT, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.ai_ops_review_decision(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ai_ops_review_decision(UUID, TEXT, TEXT) TO service_role;

COMMENT ON FUNCTION public.ai_ops_review_decision(UUID, TEXT, TEXT) IS
  'Management human review gate for AI decisions. Approval freshly revalidates current reality but performs no operational execution.';

RESET lock_timeout;
RESET statement_timeout;
